import Foundation

/// Title/artist normalization + match-confidence scoring, in the spirit of
/// Android's `lrclib/.../LrcLib.kt` (`cleanTitle`/`cleanArtist`/
/// `bestMatchingForRelaxed`), generalized so both `LrcLibProvider` and
/// `BetterLyricsProvider` share one implementation instead of each
/// reinventing it (unlike Android, where `LyricsPlusProvider.convertToLrc`
/// and `TTMLParser.toLRC` independently duplicate similar logic — the
/// migration audit flagged that duplication as something to avoid porting
/// forward).
enum LyricsMatcher {
    struct Candidate {
        var title: String
        var artist: String
        var duration: TimeInterval?
    }

    /// A match below this is rejected outright rather than accepted as
    /// "close enough" — obviously-wrong results must not be shown.
    static let minimumAcceptableConfidence: Double = 0.55

    /// Removes common "(Official Video)"/"(Lyric Video)"/"[HD]"-style
    /// bracketed suffixes and trailing "- Official Audio" text, then
    /// collapses whitespace. Only strips tags that look safely
    /// video/promo-related — never strips arbitrary parenthetical content
    /// (e.g. "(Remix)" or "(feat. X)" survive, since those usually *are*
    /// part of the real title).
    static func cleanTitle(_ title: String) -> String {
        var result = title
        result = result.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*\b(official|video|audio|lyric|visualizer|remaster(ed)?|hd|4k)\b[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s*[-|]\s*(official\s*(video|audio|lyric\s*video)?)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return normalizeWhitespace(result)
    }

    /// Reduces a multi-artist credit string to its first/primary artist,
    /// splitting on common separators (&, and, comma, x, feat./ft.).
    static func cleanArtist(_ artist: String) -> String {
        let separators = [" & ", " and ", ", ", " x ", " feat. ", " feat ", " ft. ", " ft ", " featuring "]
        var shortest = artist
        for separator in separators {
            if let range = shortest.range(of: separator, options: .caseInsensitive) {
                shortest = String(shortest[shortest.startIndex..<range.lowerBound])
            }
        }
        return normalizeWhitespace(shortest)
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 0...1 confidence that `candidate` really is the requested song.
    /// Title similarity dominates, artist similarity is secondary, and
    /// duration proximity (when both are known) nudges the score up when
    /// close and sharply down when very far apart.
    static func confidence(query: LyricsQuery, candidate: Candidate) -> Double {
        let titleSimilarity = similarity(cleanTitle(query.title).lowercased(), cleanTitle(candidate.title).lowercased())
        let artistSimilarity = similarity(cleanArtist(query.artist).lowercased(), cleanArtist(candidate.artist).lowercased())

        // An exact title is not enough to identify a song: unrelated artists
        // commonly share titles. Reject a clearly unrelated artist before
        // applying the weighted score.
        guard artistSimilarity >= 0.25 else { return 0 }

        var score = titleSimilarity * 0.6 + artistSimilarity * 0.4

        if let queryDuration = query.duration, queryDuration > 0,
           let candidateDuration = candidate.duration, candidateDuration > 0 {
            let delta = abs(queryDuration - candidateDuration)
            if delta <= 2 {
                score += 0.1
            } else if delta > 10 {
                return 0
            }
        }

        return min(1, max(0, score))
    }

    // MARK: - String similarity (normalized Levenshtein, with a substring shortcut)

    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        if a.contains(b) || b.contains(a) { return 0.85 }
        let distance = levenshtein(a, b)
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 1 }
        return max(0, 1 - Double(distance) / Double(maxLength))
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var dist = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { dist[i][0] = i }
        for j in 0...bChars.count { dist[0][j] = j }
        guard aChars.count > 0, bChars.count > 0 else { return max(aChars.count, bChars.count) }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                if aChars[i - 1] == bChars[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = 1 + min(dist[i - 1][j - 1], dist[i - 1][j], dist[i][j - 1])
                }
            }
        }
        return dist[aChars.count][bChars.count]
    }
}
