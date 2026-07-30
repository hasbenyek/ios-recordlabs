import Foundation

/// Swift port of `utils/cipher/PlayerConfigParser.kt` + the *bundled* half of
/// `PlayerConfigStore.kt`. This is the "known player.js hash → validated
/// sig/n expression" fast path: `Resources/player_configs.json` is a 1:1
/// copy of the Android app's own bundled `assets/player_configs.json`
/// (pure data — hash, a `name(int,int,INPUT)` signature-decipher call, and
/// an n-transform class name — already validated by that project against
/// the live CDN). When the current player.js hash isn't in this table,
/// `FunctionNameExtractor`'s regex heuristics are the fallback.
///
/// NOT ported: `PlayerConfigStore`'s remote-refresh/ETag machinery that
/// keeps the Android table updated over time without an app update. This
/// bundled copy will gradually go stale as YouTube ships new player
/// versions; the regex fallback is what keeps things working in between.
struct PlayerConfig {
    var sigFuncName: String
    var sigJsExpression: String?
    var nFuncName: String
    var nJsExpression: String?
    var signatureTimestamp: Int
}

enum PlayerConfigParser {
    private static let sigPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9$_]{1,8}\(\d+,\d+,INPUT\)$"#)
    private static let nClassPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9$_]{1,8}$"#)
    private static let hashPattern = try! NSRegularExpression(pattern: #"^[a-f0-9]{8}$"#)

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    /// Mirrors `PlayerConfigParser.buildNJsExpression` — builds a self-contained
    /// n-transform by instantiating the player's own throttle-parameter class
    /// (`nClass`) against a dummy URL and reading its "n" getter back out.
    static func buildNJsExpression(nClass: String) -> String {
        "(function(n){try{var u=new g.\(nClass)('https://x.googlevideo.com/videoplayback?n='+n,true);" +
            "var t=u.get('n');return(t&&t!==n)?t:n;}catch(e){return n;}})(INPUT)"
    }

    /// Loads and validates `player_configs.json` from the app bundle. Returns
    /// an empty table (not a crash) if the bundle resource is missing or the
    /// JSON is malformed — callers fall back entirely to regex extraction.
    static func loadBundledConfigs() -> [String: PlayerConfig] {
        guard
            let url = Bundle.main.url(forResource: "player_configs", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let schemaVersion = root["schemaVersion"] as? Int,
            schemaVersion == 1,
            let players = root["players"] as? [String: Any]
        else { return [:] }

        var configs: [String: PlayerConfig] = [:]
        for (hash, value) in players {
            guard let (config, aliases) = parseEntry(hash: hash, obj: value as? [String: Any]) else { continue }
            configs[hash] = config
            for alias in aliases { configs[alias] = config }
        }
        return configs
    }

    private static func parseEntry(hash: String, obj: [String: Any]?) -> (PlayerConfig, [String])? {
        guard let obj, matches(hashPattern, hash) else { return nil }
        guard let sig = obj["sig"] as? String, matches(sigPattern, sig) else { return nil }
        guard let nClass = obj["nClass"] as? String, matches(nClassPattern, nClass) else { return nil }
        guard let sts = obj["sts"] as? Int, sts > 0 else { return nil }

        let aliases: [String]
        if let aliasArray = obj["aliases"] as? [String] {
            guard aliasArray.allSatisfy({ matches(hashPattern, $0) }) else { return nil }
            aliases = aliasArray
        } else {
            aliases = []
        }

        let config = PlayerConfig(
            sigFuncName: "_expr_sig",
            sigJsExpression: sig,
            nFuncName: "_expr_n",
            nJsExpression: buildNJsExpression(nClass: nClass),
            signatureTimestamp: sts
        )
        return (config, aliases)
    }
}
