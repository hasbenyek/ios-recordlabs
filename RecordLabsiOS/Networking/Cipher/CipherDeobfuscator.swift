import Foundation

/// Swift port of `utils/cipher/CipherDeobfuscator.kt`: the orchestrator that
/// ties `PlayerJsFetcher` (get player.js) + `FunctionNameExtractor`/
/// `PlayerConfig` (locate the cipher/n-transform entry points) +
/// `CipherWebView` (actually run them) into two operations —
/// deciphering a `signatureCipher` and transforming a throttling `n` param.
///
/// Being an `actor` gives this the same "only one decipher/transform call
/// touches the shared WebView at a time" guarantee Android's
/// `deobfuscateMutex` provides, for free.
///
/// Not ported: `RendererRecoveryPolicy` (backoff after repeated WebView
/// renderer deaths) and `PlayerConfigStore`'s remote-refresh/self-heal loop
/// (re-fetching the config table mid-session when an unknown player hash
/// shows up). Both are real-world reliability hardening the Android app
/// earned over time in production; this port has the core mechanism but not
/// that additional hardening yet.
actor CipherDeobfuscator {
    static let shared = CipherDeobfuscator()

    private lazy var configs: [String: PlayerConfig] = PlayerConfigParser.loadBundledConfigs()
    private var webView: CipherWebView?
    private(set) var lastUsedPlayerHash: String?

    /// The signatureTimestamp callers must send in their `/player` request's
    /// `playbackContext` — a sig minted for one player generation but
    /// deciphered by a different one produces a URL the CDN rejects.
    func signatureTimestamp() async -> Int? {
        guard let playerJs = await PlayerJsFetcher.shared.getPlayerJs(forceRefresh: false) else { return nil }
        return FunctionNameExtractor.extractSignatureTimestamp(playerJs.content, knownHash: playerJs.hash, configs: configs)
    }

    /// Deciphers a `signatureCipher` query string (`s`, `sp`, `url` params)
    /// into a final playable URL. Retries once with a forced player.js
    /// refresh if the first attempt throws (mirrors Android's retry-with-
    /// fresh-JS behavior for a rotated player).
    func deobfuscateStreamURL(signatureCipher: String) async throws -> URL {
        do {
            return try await deobfuscateInternal(signatureCipher: signatureCipher, forceRefresh: false)
        } catch {
            await PlayerJsFetcher.shared.invalidateCache()
            closeWebView()
            return try await deobfuscateInternal(signatureCipher: signatureCipher, forceRefresh: true)
        }
    }

    /// Transforms the `n` query param YouTube uses to throttle streams that
    /// weren't fetched through a "real" player. Best-effort: returns the
    /// original URL unchanged on any failure, same as the Android version,
    /// since a wrong/missing n-transform degrades to throttling rather than
    /// an outright broken URL.
    func transformNParam(in url: URL) async -> URL {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            var items = components.queryItems,
            let nIndex = items.firstIndex(where: { $0.name == "n" }),
            let nValue = items[nIndex].value
        else { return url }

        do {
            let webView = try await getOrCreateWebView(forceRefresh: false)
            guard await webView.nFunctionAvailable else { return url }
            let transformed = try await webView.transformN(nValue)
            items[nIndex] = URLQueryItem(name: "n", value: transformed)
            components.queryItems = items
            return components.url ?? url
        } catch {
            return url
        }
    }

    private func deobfuscateInternal(signatureCipher: String, forceRefresh: Bool) async throws -> URL {
        let params = Self.parseQueryParams(signatureCipher)
        guard let obfuscatedSig = params["s"], let baseURLString = params["url"] else {
            throw CipherError.jsError("could not parse signatureCipher params (s/url)")
        }
        let sigParam = params["sp"] ?? "signature"

        let webView = try await getOrCreateWebView(forceRefresh: forceRefresh)
        let deciphered = try await webView.deobfuscateSignature(obfuscatedSig)

        guard var components = URLComponents(string: baseURLString) else {
            throw CipherError.jsError("could not parse base url")
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: sigParam, value: deciphered))
        components.queryItems = items
        guard let url = components.url else {
            throw CipherError.jsError("could not build final url")
        }
        return url
    }

    private func getOrCreateWebView(forceRefresh: Bool) async throws -> CipherWebView {
        if !forceRefresh, let webView { return webView }

        guard let playerJs = await PlayerJsFetcher.shared.getPlayerJs(forceRefresh: forceRefresh) else {
            throw CipherError.playerJsLoadFailed("could not fetch player.js")
        }

        let analysis = FunctionNameExtractor.analyzePlayerJs(playerJs.content, knownHash: playerJs.hash, configs: configs)
        guard analysis.sigInfo != nil else {
            throw CipherError.sigFunctionUnavailable
        }

        let newWebView = try await CipherWebView.create(playerJs: playerJs.content, sigInfo: analysis.sigInfo, nFuncInfo: analysis.nFuncInfo)
        webView = newWebView
        lastUsedPlayerHash = playerJs.hash
        return newWebView
    }

    private func closeWebView() {
        let toClose = webView
        webView = nil
        lastUsedPlayerHash = nil
        Task { @MainActor in toClose?.close() }
    }

    private static func parseQueryParams(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            guard let eqIndex = pair.firstIndex(of: "=") else { continue }
            let rawKey = String(pair[pair.startIndex..<eqIndex])
            let rawValue = String(pair[pair.index(after: eqIndex)...])
            result[rawKey.removingPercentEncoding ?? rawKey] = rawValue.removingPercentEncoding ?? rawValue
        }
        return result
    }
}
