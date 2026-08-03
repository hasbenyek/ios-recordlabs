import Foundation

/// Pure format-selection logic, split out of `StreamResolver` so it can be
/// unit-tested without any networking (`StreamResolver` itself only does
/// I/O + calls into this type).
///
/// `AVFoundation`/`AVPlayer` cannot decode WebM containers or Opus audio —
/// unlike Android's ExoPlayer, which plays them natively and actually
/// *prefers* Opus when available (`YTPlayerUtils.kt findFormat`'s codec
/// scoring: opus=2 > mp4a=1). This selector requires `audio/mp4` + AAC
/// (`mp4a*`) and rejects every other audio format outright, and rejects
/// video-only formats regardless of bitrate — a format is never chosen
/// purely because it has a higher bitrate than a rival in a different
/// (rejected or lower) quality tier.
enum AudioFormatSelector {
    /// Quality label is the primary sort key; bitrate only breaks ties
    /// *within* the same quality tier.
    static func selectBest(from formats: [PlayerResponse.StreamingData.Format]) -> PlayerResponse.StreamingData.Format? {
        formats
            // The MIME type is the authoritative container signal. Some
            // current InnerTube responses attach an incidental width field
            // to adaptive audio, so requiring isAudioOnly here can reject a
            // valid AAC stream even though it is clearly audio/mp4.
            .filter { $0.isAACCompatible }
            .sorted { lhs, rhs in
                let lRank = qualityRank(lhs.audioQuality)
                let rRank = qualityRank(rhs.audioQuality)
                if lRank != rRank { return lRank > rRank }
                return lhs.bitrate > rhs.bitrate
            }
            .first
    }

    /// Every audio-only format's `"container codec"` label, for building an
    /// "available but unsupported" diagnostic message.
    static func describeAudioFormats(_ formats: [PlayerResponse.StreamingData.Format]) -> [String] {
        formats
            .filter { $0.isAudioOnly }
            .map { "\($0.container) \($0.codec ?? "unknown")" }
    }

    static func qualityRank(_ audioQuality: String?) -> Int {
        switch audioQuality {
        case "AUDIO_QUALITY_HIGH": return 3
        case "AUDIO_QUALITY_MEDIUM": return 2
        case "AUDIO_QUALITY_LOW": return 1
        default: return 0
        }
    }
}
