import Foundation
import WebKit

/// Swift port of `utils/cipher/CipherWebView.kt`'s core idea: load YouTube's
/// REAL, unmodified `player.js` into a real WebKit engine and let it execute
/// verbatim — so the hard part (YouTube's obfuscated cipher algorithm
/// itself) is never reimplemented, only *located* (which function to call,
/// with what wrapper args), via `FunctionNameExtractor`/`PlayerConfig`. This
/// is what makes the technique survive YouTube's periodic obfuscation
/// changes far better than a hand-rewritten JS interpreter would.
///
/// Simplifications vs. the Android version: no render-process-death
/// recovery/backoff policy (`RendererRecoveryPolicy`) and no per-request-id
/// stale-callback guarding — `CipherDeobfuscator` (an `actor`) already
/// serializes every call into this class to one-at-a-time, so unlike the
/// Android code (which added request ids defensively on top of its own
/// mutex), there is no concurrent-call case here to guard against.
// @unchecked Sendable: instances are handed off to and stored by the
// `CipherDeobfuscator` actor, but every method that touches WKWebView state
// stays @MainActor-isolated, and CipherDeobfuscator's own actor isolation
// means only one call into a given instance is ever in flight at a time.
@MainActor
final class CipherWebView: NSObject, @unchecked Sendable {
    private let webView: WKWebView
    private var contentController: WKUserContentController!
    private(set) var sigFunctionAvailable = false
    private(set) var nFunctionAvailable = false

    private var initContinuation: CheckedContinuation<Void, Error>?
    private var sigContinuation: CheckedContinuation<String, Error>?
    private var nContinuation: CheckedContinuation<String, Error>?

    private static let messageNames = ["logDebug", "onDiscoveryDone", "onPlayerJsLoaded", "onPlayerJsError", "onSigResult", "onSigError", "onNResult", "onNError"]

    private init(sigInfo: FunctionNameExtractor.SigFunctionInfo?, nFuncInfo: FunctionNameExtractor.NFunctionInfo?) {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.limitsNavigationsToAppBoundDomains = false
        webView = WKWebView(frame: .zero, configuration: config)
        contentController = controller
        super.init()
        for name in Self.messageNames {
            controller.add(self, name: name)
        }
    }

    static func create(playerJs: String, sigInfo: FunctionNameExtractor.SigFunctionInfo?, nFuncInfo: FunctionNameExtractor.NFunctionInfo?) async throws -> CipherWebView {
        let instance = CipherWebView(sigInfo: sigInfo, nFuncInfo: nFuncInfo)
        try await instance.load(playerJs: playerJs, sigInfo: sigInfo, nFuncInfo: nFuncInfo)
        return instance
    }

    private func load(playerJs: String, sigInfo: FunctionNameExtractor.SigFunctionInfo?, nFuncInfo: FunctionNameExtractor.NFunctionInfo?) async throws {
        let modifiedJs = Self.buildModifiedPlayerJs(playerJs: playerJs, sigInfo: sigInfo, nFuncInfo: nFuncInfo)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cipher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let jsFile = dir.appendingPathComponent("player.js")
        let htmlFile = dir.appendingPathComponent("discovery.html")
        try modifiedJs.write(to: jsFile, atomically: true, encoding: .utf8)
        try Self.discoveryHTML.write(to: htmlFile, atomically: true, encoding: .utf8)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.initContinuation = continuation
            webView.loadFileURL(htmlFile, allowingReadAccessTo: dir)
        }
    }

    func deobfuscateSignature(_ obfuscatedSig: String) async throws -> String {
        let escaped = Self.escapeJSString(obfuscatedSig)
        let jsCall = "deobfuscateSig('\(escaped)')"
        return try await withCheckedThrowingContinuation { continuation in
            self.sigContinuation = continuation
            webView.evaluateJavaScript(jsCall, completionHandler: nil)
        }
    }

    func transformN(_ nValue: String) async throws -> String {
        let escaped = Self.escapeJSString(nValue)
        let jsCall = "transformN('\(escaped)')"
        return try await withCheckedThrowingContinuation { continuation in
            self.nContinuation = continuation
            webView.evaluateJavaScript(jsCall, completionHandler: nil)
        }
    }

    func close() {
        for name in Self.messageNames {
            contentController.removeScriptMessageHandler(forName: name)
        }
        webView.loadHTMLString("", baseURL: nil)
    }

    private static func escapeJSString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// Mirrors `CipherWebView.buildModifiedPlayerJsImpl`: appends `window._cipherSigFunc` /
    /// `window._nTransformFunc` export statements into player.js's closing IIFE so the
    /// discovery script (below) can find and call them without needing to know YouTube's
    /// actual (obfuscated, ever-changing) internal names ahead of time.
    /// Not ported: Android's rarer `preprocessFunc`-wrapped sig case (e.g.
    /// `FUNC(argsA..., PREPROCESS(argsB..., sig))`) — none of the current
    /// regex patterns in `FunctionNameExtractor` populate it, so it would be
    /// dead code here too; only the plain-name and single-leading-constant
    /// forms are wrapped below.
    private static func buildModifiedPlayerJs(playerJs: String, sigInfo: FunctionNameExtractor.SigFunctionInfo?, nFuncInfo: FunctionNameExtractor.NFunctionInfo?) -> String {
        var exports: [String] = []

        if let expr = sigInfo?.jsExpression {
            let replaced = expr.replacingOccurrences(of: "INPUT", with: "sig")
            exports.append("window._cipherSigFunc = function(sig) { try { return \(replaced); } catch(e) { return null; } };")
        } else if let name = sigInfo?.name {
            // Patterns that captured a leading numeric constant (e.g. `FUNC(48, decodeURIComponent(...))`)
            // need it re-supplied as the function's first argument on every call.
            if let constantArg = sigInfo?.constantArg {
                exports.append("window._cipherSigFunc = function(sig) { return \(name)(\(constantArg), sig); };")
            } else {
                exports.append("window._cipherSigFunc = typeof \(name) !== 'undefined' ? \(name) : null;")
            }
        }

        if let expr = nFuncInfo?.jsExpression {
            let replaced = expr.replacingOccurrences(of: "INPUT", with: "n")
            exports.append("window._nTransformFunc = function(n) { try { return \(replaced); } catch(e) { return n; } };")
        } else if let name = nFuncInfo?.name {
            let expr = nFuncInfo?.arrayIndex.map { "\(name)[\($0)]" } ?? name
            exports.append("window._nTransformFunc = typeof \(name) !== 'undefined' ? \(expr) : null;")
        }

        guard !exports.isEmpty else { return playerJs }
        let exportCode = "; " + exports.joined(separator: " ")
        let marker = "})(_yt_player);"
        if let range = playerJs.range(of: marker) {
            var modified = playerJs
            modified.replaceSubrange(range, with: "\(exportCode) \(marker)")
            return modified
        }
        return playerJs + "\n" + exportCode
    }

    /// Mirrors `CipherWebView.buildDiscoveryHtml`, minus the window-property
    /// brute-force n-function scan (kept in Android as a last resort when
    /// export injection itself finds nothing — a reasonable follow-up here
    /// too, but skipped for this pass since it's a pure bonus-effort fallback
    /// on top of the injected exports, not the primary mechanism).
    private static let discoveryHTML = """
    <!DOCTYPE html><html><head><script>
    function deobfuscateSig(obfuscatedSig) {
        try {
            var func = window._cipherSigFunc;
            if (typeof func !== 'function') { window.webkit.messageHandlers.onSigError.postMessage("Sig func not found (type: " + typeof func + ")"); return; }
            var result = func(obfuscatedSig);
            if (result === undefined || result === null) { window.webkit.messageHandlers.onSigError.postMessage("Function returned null/undefined"); return; }
            window.webkit.messageHandlers.onSigResult.postMessage(String(result));
        } catch (error) {
            window.webkit.messageHandlers.onSigError.postMessage(String(error) + "\\n" + (error.stack || ""));
        }
    }
    function transformN(nValue) {
        try {
            var func = window._nTransformFunc;
            if (typeof func !== 'function') { window.webkit.messageHandlers.onNError.postMessage("N-transform func not available (type: " + typeof func + ")"); return; }
            var result = func(nValue);
            if (result === undefined || result === null) { window.webkit.messageHandlers.onNError.postMessage("N-transform returned null/undefined"); return; }
            window.webkit.messageHandlers.onNResult.postMessage(String(result));
        } catch (error) {
            window.webkit.messageHandlers.onNError.postMessage(String(error) + "\\n" + (error.stack || ""));
        }
    }
    function discoverAndInit() {
        var sigOk = (typeof window._cipherSigFunc === 'function');
        var nOk = (typeof window._nTransformFunc === 'function');
        window.webkit.messageHandlers.onDiscoveryDone.postMessage(JSON.stringify({sig: sigOk, n: nOk}));
        window.webkit.messageHandlers.onPlayerJsLoaded.postMessage("");
    }
    </script>
    <script src="player.js" onload="discoverAndInit()" onerror="window.webkit.messageHandlers.onPlayerJsError.postMessage('Failed to load player.js')"></script>
    </head><body></body></html>
    """
}

enum CipherError: Error {
    case playerJsLoadFailed(String)
    case sigFunctionUnavailable
    case nFunctionUnavailable
    case jsError(String)
}

extension CipherWebView: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "onDiscoveryDone":
            if let json = message.body as? String, let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
                sigFunctionAvailable = obj["sig"] ?? false
                nFunctionAvailable = obj["n"] ?? false
            }
        case "onPlayerJsLoaded":
            initContinuation?.resume(returning: ())
            initContinuation = nil
        case "onPlayerJsError":
            let error = (message.body as? String) ?? "unknown error"
            initContinuation?.resume(throwing: CipherError.playerJsLoadFailed(error))
            initContinuation = nil
        case "onSigResult":
            if let result = message.body as? String {
                sigContinuation?.resume(returning: result)
            } else {
                sigContinuation?.resume(throwing: CipherError.jsError("non-string sig result"))
            }
            sigContinuation = nil
        case "onSigError":
            sigContinuation?.resume(throwing: CipherError.jsError((message.body as? String) ?? "sig error"))
            sigContinuation = nil
        case "onNResult":
            if let result = message.body as? String {
                nContinuation?.resume(returning: result)
            } else {
                nContinuation?.resume(throwing: CipherError.jsError("non-string n result"))
            }
            nContinuation = nil
        case "onNError":
            nContinuation?.resume(throwing: CipherError.jsError((message.body as? String) ?? "n-transform error"))
            nContinuation = nil
        default:
            break // "logDebug" — intentionally ignored (Android forwards these to Timber only)
        }
    }
}
