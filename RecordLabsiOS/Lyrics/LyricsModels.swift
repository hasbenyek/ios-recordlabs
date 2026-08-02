import Foundation

/// One word inside a word-synced lyrics line.
struct LyricsWord: Equatable {
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
}

/// One lyrics line, optionally with word-level timing, agent (duet-voice),
/// and background-vocal information — mirrors what Android's
/// `LyricsEntry`/TTML pipeline carries, minus the two bugs documented on
/// `LRCParser`/`TTMLParser`.
struct LyricsLine: Identifiable, Equatable {
    var id: Int
    var startTime: TimeInterval
    var text: String
    var words: [LyricsWord]? = nil
    /// Raw agent identifier as found in the source (e.g. `"v1"`, `"v2"`,
    /// `"v3"`, or a named voice) — kept as-is rather than remapped into a
    /// fixed two-slot namespace. See `TTMLParser`'s doc comment for why
    /// this differs from Android.
    var agent: String? = nil
    var isBackground: Bool = false
    /// `true` when this line had no parseable timestamp of its own and
    /// `startTime` was inferred rather than actually present in the
    /// source. See `LRCParser`/`TTMLParser` doc comments.
    var isTimingInferred: Bool = false

    var isWordSynced: Bool { (words?.isEmpty == false) }
}

/// What a lyrics fetch produced. Distinguishes every case a caller needs to
/// render correctly — in particular "no lyrics exist for this song"
/// (`.instrumental`) is a different, legitimate outcome from "we couldn't
/// find a confident match" (`.noMatch`) or "the provider itself failed"
/// (`.providerFailure`).
enum LyricsResult: Equatable {
    case syncedLines([LyricsLine], provider: String)
    case syncedWords([LyricsLine], provider: String)
    case plain(String, provider: String)
    case instrumental(provider: String)
    case providerFailure(String)
    case noMatch
}

/// Real, already-known song metadata used to look lyrics up. Never
/// fabricated — every field here comes from the actual playing `Song`.
struct LyricsQuery: Equatable {
    var videoId: String
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval?
}

enum LyricsProviderError: Error, Equatable {
    case timeout
    case network(String)
    case malformedResponse(String)
}

protocol LyricsProvider {
    var name: String { get }
    func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult
}
