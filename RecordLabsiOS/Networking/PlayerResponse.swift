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
            /// Some Innertube client responses use this legacy alias instead
            /// of `signatureCipher`. Android accepts either field.
            var cipher: String? = nil
            /// Snake-case key used by some YouTube client responses.
            var signature_cipher: String? = nil

            var streamCipher: String? {
                signatureCipher ?? cipher ?? signature_cipher
            }

            /// `"audio/mp4"` / `"audio/webm"` — the part of `mimeType`
            /// before the `codecs=` parameter.
            var container: String {
                String(mimeType.split(separator: ";").first ?? "").trimmingCharacters(in: .whitespaces)
            }

            /// The `codecs="..."` value, e.g. `"mp4a.40.2"` or `"opus"`.
            var codec: String? {
                if let range = mimeType.range(of: #"codecs\s*=\s*["']?([^"',;\s]+)["']?"#, options: .regularExpression) {
                    let match = String(mimeType[range])
                    if let innerRange = match.range(of: #"(?<=codecs\s*=\s*["']?)[^"',;\s]+(?=["']?)"#, options: .regularExpression) {
                        return String(match[innerRange])
                    }
                }

                // Some InnerTube responses omit the codecs= parameter and
                // append the codec as a plain token, e.g. "audio/mp4 mp4a.40.2".
                return mimeType
                    .split { $0 == ";" || $0 == "," || $0.isWhitespace }
                    .dropFirst()
                    .first { token in
                        let lower = token.lowercased()
                        return lower.hasPrefix("mp4a.") || lower == "opus" || lower.hasPrefix("codecs=")
                    }
                    .map { token -> String in
                        let lower = token.lowercased()
                        if lower.hasPrefix("codecs=") {
                            return String(token.dropFirst(7).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                        }
                        return String(token)
                    }
            }

            var isAudioOnly: Bool {
                // YouTube may include a non-nil/zero width field even on
                // adaptive audio formats. Android treats an audio MIME type
                // as audio regardless of that optional field.
                mimeType.lowercased().hasPrefix("audio/") || width == nil
            }

            /// `AVPlayer`/AVFoundation does not decode WebM containers or
            /// Opus audio (a platform limitation, not something InnerTube
            /// reports) — unlike Android's ExoPlayer, which plays Opus/WebM
            /// natively. iOS requires AAC-in-MP4.
            var isAACCompatible: Bool {
                let lowerContainer = container.lowercased()
                let isMp4 = lowerContainer == "audio/mp4" || lowerContainer.hasPrefix("audio/mp4")
                let codecLower = codec?.lowercased() ?? ""
                return isMp4 && (codecLower.hasPrefix("mp4a") || mimeType.lowercased().contains("mp4a"))
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
