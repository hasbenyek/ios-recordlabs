import Foundation

/// Mirrors `innertube/models/Context.kt` — the `context` object every
/// InnerTube POST body includes, describing the calling client.
struct InnerTubeContext: Encodable {
    struct Client: Encodable {
        var clientName: String
        var clientVersion: String
        var osName: String?
        var osVersion: String?
        var deviceMake: String?
        var deviceModel: String?
        var gl: String
        var hl: String
        var visitorData: String?
    }

    struct Request: Encodable {
        var internalExperimentFlags: [String] = []
        var useSsl = true
    }

    struct User: Encodable {
        var lockedSafetyMode = false
        var onBehalfOfUser: String?
    }

    var client: Client
    var request = Request()
    var user = User(onBehalfOfUser: nil)

    init(identity: YouTubeClientIdentity, locale: YouTubeLocale, visitorData: String?) {
        client = Client(
            clientName: identity.clientName,
            clientVersion: identity.clientVersion,
            osName: identity.osName,
            osVersion: identity.osVersion,
            deviceMake: identity.deviceMake,
            deviceModel: identity.deviceModel,
            gl: locale.gl,
            hl: locale.hl,
            visitorData: visitorData
        )
    }
}

struct YouTubeLocale {
    var gl: String
    var hl: String

    static var current: YouTubeLocale {
        // `Locale.current.region`/`.language` (the newer Locale.Region/
        // Locale.Language API) needs iOS 16+; regionCode/languageCode are
        // the iOS 15-compatible equivalents (deprecated on newer OSes, but
        // deprecation warnings don't block compilation or affect behavior).
        YouTubeLocale(
            gl: Locale.current.regionCode ?? "US",
            hl: Locale.current.languageCode ?? "en"
        )
    }
}

struct SearchRequestBody: Encodable {
    var context: InnerTubeContext
    var query: String?
    var params: String?
}

struct BrowseRequestBody: Encodable {
    var context: InnerTubeContext
    var browseId: String?
    var params: String?
}

struct PlayerRequestBody: Encodable {
    struct PlaybackContext: Encodable {
        struct ContentPlaybackContext: Encodable {
            var signatureTimestamp: Int
        }
        var contentPlaybackContext: ContentPlaybackContext
    }

    var context: InnerTubeContext
    var videoId: String
    var playlistId: String?
    var playbackContext: PlaybackContext?
}
