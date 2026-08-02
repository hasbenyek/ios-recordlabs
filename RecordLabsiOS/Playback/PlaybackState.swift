import Foundation

/// Every state the player can visibly be in. Replaces the old
/// `isResolvingStream: Bool` + `playbackError: String?` pair with a single
/// source of truth so the UI can never show a stale/ambiguous combination.
enum PlaybackState: Equatable {
    case idle
    case resolving
    case buffering
    case playing
    case paused
    case unsupportedFormat(availableFormats: [String])
    case networkFailure(String)
    case cipherFailure(String)
    case streamResolutionFailure(String)
    case playbackFailure(String)

    var isFailure: Bool {
        switch self {
        case .unsupportedFormat, .networkFailure, .cipherFailure, .streamResolutionFailure, .playbackFailure:
            return true
        default:
            return false
        }
    }

    /// User-facing summary. Never includes a URL, token, or credential —
    /// see `StreamDiagnostics` for the rule this enforces project-wide.
    var displayMessage: String? {
        switch self {
        case .idle, .resolving, .buffering, .playing, .paused:
            return nil
        case .unsupportedFormat(let formats):
            let list = formats.isEmpty ? "no audio formats were offered" : formats.joined(separator: ", ")
            return "None of the available streams (\(list)) can be played on this device (AAC/MP4 required)."
        case .networkFailure(let detail):
            return "Network error while resolving this track: \(detail)"
        case .cipherFailure(let detail):
            return "Couldn't decode this track's stream signature: \(detail)"
        case .streamResolutionFailure(let detail):
            return "Couldn't find a playable stream for this track: \(detail)"
        case .playbackFailure(let detail):
            return "Playback failed: \(detail)"
        }
    }
}

/// Errors thrown by `StreamResolver`. Kept separate from `PlaybackState` so
/// non-UI callers (e.g. tests) can pattern-match on the error itself.
enum PlayerError: Error, Equatable {
    case unsupportedFormat(availableFormats: [String])
    case network(String)
    case cipherFailure(String)
    case streamResolutionFailure(String)
}
