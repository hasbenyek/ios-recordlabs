import Foundation

/// Trimmed Swift mirror of `innertube/models/response/PlayerResponse.kt` —
/// only the fields needed to pick a playable audio format.
struct PlayerResponse: Decodable {
    struct PlayabilityStatus: Decodable {
        var status: String
        var reason: String?
    }

    struct StreamingData: Decodable {
        struct Format: Decodable {
            var itag: Int
            var url: String?
            var mimeType: String
            var bitrate: Int
            var audioQuality: String?
            var approxDurationMs: String?
            /// Present when YouTube requires deciphering the stream URL via
            /// obfuscated player JS. `StreamResolver` treats any format with
            /// a non-nil cipher as unusable rather than guessing at it.
            var signatureCipher: String?
        }

        var adaptiveFormats: [Format]
    }

    struct VideoDetails: Decodable {
        var videoId: String
        var title: String?
        var author: String?
        var lengthSeconds: String
    }

    var playabilityStatus: PlayabilityStatus
    var streamingData: StreamingData?
    var videoDetails: VideoDetails?
}
