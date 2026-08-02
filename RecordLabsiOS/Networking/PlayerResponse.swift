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
            /// Non-nil only for video/combined formats; always nil for
            /// genuine audio-only adaptive formats. Mirrors Android's
            /// `PlayerResponse.Format.isAudio` check
            /// (`mimeType.startsWith("audio/") || width == null`,
            /// `innertube/models/response/PlayerResponse.kt`).
            var width: Int?
            /// Present when YouTube requires deciphering the stream URL via
            /// obfuscated player JS.
            var signatureCipher: String?

            /// `"audio/mp4"` / `"audio/webm"` — the part of `mimeType`
            /// before the `codecs=` parameter.
            var container: String {
                String(mimeType.split(separator: ";").first ?? "").trimmingCharacters(in: .whitespaces)
            }

            /// The `codecs="..."` value, e.g. `"mp4a.40.2"` or `"opus"`.
            var codec: String? {
                guard let range = mimeType.range(of: #"codecs="([^"]+)""#, options: .regularExpression) else { return nil }
                let match = mimeType[range]
                guard let inner = match.range(of: #"(?<=")[^"]+(?=")"#, options: .regularExpression) else { return nil }
                return String(match[inner])
            }

            var isAudioOnly: Bool {
                mimeType.hasPrefix("audio/") && width == nil
            }

            /// `AVPlayer`/AVFoundation does not decode WebM containers or
            /// Opus audio (a platform limitation, not something InnerTube
            /// reports) — unlike Android's ExoPlayer, which plays Opus/WebM
            /// natively and actually *prefers* it
            /// (`YTPlayerUtils.kt findFormat`'s codec scoring: opus=2 >
            /// mp4a=1). iOS must instead require AAC-in-MP4 and explicitly
            /// reject WebM/Opus rather than picking "whatever has the
            /// highest bitrate".
            var isAACCompatible: Bool {
                container == "audio/mp4" && (codec?.hasPrefix("mp4a") ?? false)
            }
        }

        var adaptiveFormats: [Format]
        /// Raw TTL for the resolved stream URL(s), seconds. Surfaced in
        /// `StreamDiagnostics` — not currently used to drive a refetch
        /// cache in this phase (see README "known limitations").
        var expiresInSeconds: String?
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
