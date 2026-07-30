import Foundation

/// Swift port of `utils/cipher/PlayerJsFetcher.kt`: fetches and disk-caches
/// YouTube's current `player.js` (the file containing the signature-decipher
/// and n-throttle-transform functions), with the same iframe_api → hash →
/// base.js flow and 6-hour cache TTL.
actor PlayerJsFetcher {
    static let shared = PlayerJsFetcher()

    private static let iframeAPIURL = URL(string: "https://www.youtube.com/iframe_api")!
    private static let cacheTTL: TimeInterval = 6 * 60 * 60
    private static let playerHashRegex = try! NSRegularExpression(pattern: #"\\?/s\\?/player\\?/([a-zA-Z0-9_-]+)\\?/"#)

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cipher_cache", isDirectory: true)
    }

    struct PlayerJs {
        var content: String
        var hash: String
    }

    func getPlayerJs(forceRefresh: Bool = false) async -> PlayerJs? {
        let dir = cacheDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if !forceRefresh, let cached = readFromCache(dir: dir) {
            return cached
        }

        guard let hash = await fetchPlayerHash() else { return nil }
        guard let content = await downloadPlayerJs(hash: hash) else { return nil }
        writeToCache(dir: dir, hash: hash, content: content)
        return PlayerJs(content: content, hash: hash)
    }

    func invalidateCache() {
        let dir = cacheDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("player_") || file.lastPathComponent == "current_hash.txt" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func readFromCache(dir: URL) -> PlayerJs? {
        let hashFile = dir.appendingPathComponent("current_hash.txt")
        guard
            let hashData = try? String(contentsOf: hashFile, encoding: .utf8),
            case let lines = hashData.split(separator: "\n", omittingEmptySubsequences: false),
            lines.count >= 2,
            let timestamp = Double(lines[1])
        else { return nil }

        let hash = String(lines[0])
        guard Date().timeIntervalSince1970 - timestamp < Self.cacheTTL else { return nil }

        let jsFile = dir.appendingPathComponent("player_\(hash).js")
        guard let content = try? String(contentsOf: jsFile, encoding: .utf8) else { return nil }
        return PlayerJs(content: content, hash: hash)
    }

    private func writeToCache(dir: URL, hash: String, content: String) {
        let jsFile = dir.appendingPathComponent("player_\(hash).js")
        let hashFile = dir.appendingPathComponent("current_hash.txt")
        try? content.write(to: jsFile, atomically: true, encoding: .utf8)
        try? "\(hash)\n\(Date().timeIntervalSince1970)".write(to: hashFile, atomically: true, encoding: .utf8)
    }

    private func fetchPlayerHash() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: Self.iframeAPIURL) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let full = NSRange(text.startIndex..., in: text)
        guard let match = Self.playerHashRegex.firstMatch(in: text, range: full), match.numberOfRanges > 1 else { return nil }
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func downloadPlayerJs(hash: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/s/player/\(hash)/player_ias.vflset/en_GB/base.js") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
