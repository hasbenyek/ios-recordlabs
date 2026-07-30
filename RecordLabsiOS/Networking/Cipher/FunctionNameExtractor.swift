import Foundation
import CryptoKit

/// Swift port of `utils/cipher/FunctionNameExtractor.kt`'s regex patterns —
/// same intent, same pattern strings (NSRegularExpression's ICU regex engine
/// accepts the same syntax as Kotlin's `java.util.regex`-backed `Regex`, so
/// these translate close to verbatim). These are unanchored heuristics that
/// scan YouTube's ~2-2.8MB obfuscated `player.js` for the current
/// signature-decipher / n-throttle-transform entry points; see
/// `PlayerConfig.swift` for the validated-hash-table fast path these
/// heuristics fall back to when a hash isn't in that table.
enum FunctionNameExtractor {
    struct SigFunctionInfo {
        var name: String
        var constantArg: Int?
        var jsExpression: String?
        var isHardcoded: Bool = false
    }

    struct NFunctionInfo {
        var name: String
        var arrayIndex: Int?
        var jsExpression: String?
        var isHardcoded: Bool = false
    }

    struct PlayerAnalysis {
        var playerHash: String?
        var sigInfo: SigFunctionInfo?
        var nFuncInfo: NFunctionInfo?
        var signatureTimestamp: Int?
    }

    private static let anchoredSTS = try! NSRegularExpression(pattern: #"signatureTimestamp['":\s]+(\d+)"#)
    private static let looseSTS = try! NSRegularExpression(pattern: #"sts['":\s]+(\d+)"#)

    private static let playerHashPatterns = [
        try! NSRegularExpression(pattern: #"jsUrl['":\s]+[^"']*?/player/([a-f0-9]{8})/"#),
        try! NSRegularExpression(pattern: #"player_ias\.vflset/[^/]+/([a-f0-9]{8})/"#),
        try! NSRegularExpression(pattern: #"/s/player/([a-f0-9]{8})/"#),
    ]

    // Index 0/1 capture (name, constantArg); the rest capture only (name).
    private static let sigFunctionPatterns = [
        try! NSRegularExpression(pattern: #"&&\s*\(\s*[a-zA-Z0-9$]+\s*=\s*([a-zA-Z0-9$]+)\s*\(\s*(\d+)\s*,\s*decodeURIComponent\s*\(\s*[a-zA-Z0-9$]+\s*\)"#),
        try! NSRegularExpression(pattern: #"&&\s*\(\s*[a-zA-Z0-9$]+\s*=\s*([a-zA-Z0-9$]+)\s*\(\s*(\d+)\s*,\s*decodeURIComponent\s*\(\s*[a-zA-Z0-9$]+\s*\.\s*[a-z]\s*\)"#),
        try! NSRegularExpression(pattern: #"\b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\("#),
        try! NSRegularExpression(pattern: #"\b[a-zA-Z0-9]+\s*&&\s*[a-zA-Z0-9]+\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\("#),
        try! NSRegularExpression(pattern: #"\bm=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(h\.s\)\)"#),
        try! NSRegularExpression(pattern: #"\bc\s*&&\s*d\.set\([^,]+\s*,\s*(?:encodeURIComponent\s*\()([a-zA-Z0-9$]+)\("#),
        try! NSRegularExpression(pattern: #"\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\("#),
    ]

    private static let nFunctionPatterns = [
        try! NSRegularExpression(pattern: #"\.get\("n"\)\)&&\(b=([a-zA-Z0-9$]+)(?:\[(\d+)\])?\(([a-zA-Z0-9])\)"#),
        try! NSRegularExpression(pattern: #"\.get\("n"\)\)\s*&&\s*\(([a-zA-Z0-9$]+)\s*=\s*([a-zA-Z0-9$]+)(?:\[(\d+)\])?\(\1\)"#),
        try! NSRegularExpression(pattern: #"\.get\("n"\);if\([a-zA-Z0-9$]+\)\s*\{[^}]*match"#),
        try! NSRegularExpression(pattern: #"\(\s*([a-zA-Z0-9$]+)\s*=\s*String\.fromCharCode\(110\)"#),
        try! NSRegularExpression(pattern: #"([a-zA-Z0-9$]+)\s*=\s*function\([a-zA-Z0-9]\)\s*\{[^}]*?enhanced_except_"#),
    ]

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in string: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }

    static func extractPlayerHash(_ playerJs: String) -> String? {
        let full = NSRange(playerJs.startIndex..., in: playerJs)
        for pattern in playerHashPatterns {
            if let match = pattern.firstMatch(in: playerJs, range: full), let hash = group(match, 1, in: playerJs) {
                return hash
            }
        }
        // Fallback: hash the first 10KB, mirroring the Android MD5-of-prefix fallback
        // (used only as a cache key when no URL-embedded hash is found — never looked
        // up in the config table, since it won't match any real player hash there).
        let prefix = String(playerJs.prefix(10_000))
        let digest = Insecure.MD5.hash(data: Data(prefix.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func extractSigFunctionInfo(_ playerJs: String, knownHash: String?, configs: [String: PlayerConfig]) -> SigFunctionInfo? {
        let hash = knownHash ?? extractPlayerHash(playerJs)
        if let hash, let config = configs[hash] {
            return SigFunctionInfo(name: config.sigFuncName, constantArg: nil, jsExpression: config.sigJsExpression, isHardcoded: true)
        }

        let full = NSRange(playerJs.startIndex..., in: playerJs)
        for pattern in sigFunctionPatterns {
            guard let match = pattern.firstMatch(in: playerJs, range: full), let name = group(match, 1, in: playerJs) else { continue }
            let constantArg = group(match, 2, in: playerJs).flatMap { Int($0) }
            return SigFunctionInfo(name: name, constantArg: constantArg, jsExpression: nil, isHardcoded: false)
        }
        return nil
    }

    static func extractNFunctionInfo(_ playerJs: String, knownHash: String?, configs: [String: PlayerConfig]) -> NFunctionInfo? {
        let hash = knownHash ?? extractPlayerHash(playerJs)
        if let hash, let config = configs[hash] {
            return NFunctionInfo(name: config.nFuncName, arrayIndex: nil, jsExpression: config.nJsExpression, isHardcoded: true)
        }

        let full = NSRange(playerJs.startIndex..., in: playerJs)
        for (index, pattern) in nFunctionPatterns.enumerated() {
            guard let match = pattern.firstMatch(in: playerJs, range: full) else { continue }
            switch index {
            case 0:
                guard let name = group(match, 1, in: playerJs) else { continue }
                let arrayIdx = group(match, 2, in: playerJs).flatMap { Int($0) }
                return NFunctionInfo(name: name, arrayIndex: arrayIdx, isHardcoded: false)
            case 1:
                guard let name = group(match, 2, in: playerJs) else { continue }
                let arrayIdx = group(match, 3, in: playerJs).flatMap { Int($0) }
                return NFunctionInfo(name: name, arrayIndex: arrayIdx, isHardcoded: false)
            case 2:
                continue // matches but exposes no usable function name (see Kotlin's comment)
            default:
                guard let name = group(match, 1, in: playerJs) else { continue }
                return NFunctionInfo(name: name, arrayIndex: nil, isHardcoded: false)
            }
        }
        return nil
    }

    static func extractSignatureTimestamp(_ playerJs: String, knownHash: String?, configs: [String: PlayerConfig]) -> Int? {
        let full = NSRange(playerJs.startIndex..., in: playerJs)
        if let match = anchoredSTS.firstMatch(in: playerJs, range: full), let value = group(match, 1, in: playerJs) {
            return Int(value)
        }
        let hash = knownHash ?? extractPlayerHash(playerJs)
        if let hash, let config = configs[hash] {
            return config.signatureTimestamp
        }
        if let match = looseSTS.firstMatch(in: playerJs, range: full), let value = group(match, 1, in: playerJs) {
            return Int(value)
        }
        return nil
    }

    static func analyzePlayerJs(_ playerJs: String, knownHash: String?, configs: [String: PlayerConfig]) -> PlayerAnalysis {
        let hash = knownHash ?? extractPlayerHash(playerJs)
        return PlayerAnalysis(
            playerHash: hash,
            sigInfo: extractSigFunctionInfo(playerJs, knownHash: hash, configs: configs),
            nFuncInfo: extractNFunctionInfo(playerJs, knownHash: hash, configs: configs),
            signatureTimestamp: extractSignatureTimestamp(playerJs, knownHash: hash, configs: configs)
        )
    }
}
