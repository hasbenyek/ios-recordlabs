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

    var client: Client

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
        YouTubeLocale(
            gl: Locale.current.region?.identifier ?? "US",
            hl: Locale.current.language.languageCode?.identifier ?? "en"
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
