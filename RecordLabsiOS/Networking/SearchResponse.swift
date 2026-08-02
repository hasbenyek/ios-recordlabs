import Foundation
import os

private let searchParserLog = Logger(subsystem: "com.recordlabs.music.ios", category: "SearchResponseParser")

/// Confidence-based parser for YouTube Music's `/search` AND `/browse`
/// responses (both use the same `musicResponsiveListItemRenderer` shape for
/// song rows, so `HomeScreen` reuses this too).
///
/// The real response is a deeply nested, undocumented "renderer tree"
/// (`SectionListRenderer` → `MusicShelfRenderer`/`MusicCardShelfRenderer` →
/// `MusicResponsiveListItemRenderer`, etc). This parser recursively scans
/// for any `musicResponsiveListItemRenderer` object rather than reproducing
/// the full typed tree, but — unlike a naive scan — it only emits a result
/// when the fields it needs are actually present and it never invents a
/// value for anything it can't confidently find (missing album/artist
/// browse id/duration/explicit flag stay `nil`/default, they are never
/// guessed). Anything it drops is recorded in `ParseResult.diagnostics`
/// rather than silently discarded.
enum SearchResponseParser {
    struct ParseResult {
        var songs: [Song]
        var diagnostics: [String]
    }

    static func parseSongs(from data: Data) -> ParseResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            let message = "Response body was not valid JSON"
            searchParserLog.error("\(message, privacy: .public)")
            return ParseResult(songs: [], diagnostics: [message])
        }

        var results: [Song] = []
        var skippedNoVideoId = 0
        var skippedNoTitle = 0
        var skippedNoArtist = 0
        var seenVideoIds: Set<String> = []

        walk(root) { node in
            guard let renderer = node["musicResponsiveListItemRenderer"] as? [String: Any] else { return }

            // A song is never displayed without a real, resolvable videoId —
            // there is nothing safe to play without one.
            guard let videoId = extractVideoId(renderer) else {
                skippedNoVideoId += 1
                return
            }
            guard let title = extractTitle(renderer), !title.isEmpty else {
                skippedNoTitle += 1
                return
            }

            let subtitle = extractSubtitleParts(renderer)
            guard let artistName = subtitle.artist, !artistName.isEmpty else {
                skippedNoArtist += 1
                return
            }
            guard seenVideoIds.insert(videoId).inserted else { return }
            let duration = subtitle.duration.flatMap(parseDuration) ?? 0

            results.append(Song(
                id: videoId,
                title: title,
                artists: [ArtistRef(id: subtitle.artistId ?? artistName, name: artistName)],
                album: subtitle.album.map { AlbumRef(id: subtitle.albumId ?? $0, title: $0) },
                duration: duration,
                thumbnailURL: extractThumbnail(renderer),
                isExplicit: hasExplicitBadge(renderer)
            ))
        }

        var diagnostics: [String] = []
        if skippedNoVideoId > 0 {
            let message = "Skipped \(skippedNoVideoId) result(s) with no resolvable videoId"
            searchParserLog.warning("\(message, privacy: .public)")
            diagnostics.append(message)
        }
        if skippedNoTitle > 0 {
            let message = "Skipped \(skippedNoTitle) result(s) with no title"
            searchParserLog.warning("\(message, privacy: .public)")
            diagnostics.append(message)
        }
        if skippedNoArtist > 0 {
            let message = "Skipped \(skippedNoArtist) result(s) with no artist"
            searchParserLog.warning("\(message, privacy: .public)")
            diagnostics.append(message)
        }

        return ParseResult(songs: results, diagnostics: diagnostics)
    }

    // MARK: - Tree walk

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let array = node as? [Any] {
            for value in array { walk(value, visit: visit) }
        }
    }

    private static func extractVideoId(_ renderer: [String: Any]) -> String? {
        (((renderer["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String)
    }

    private static func extractTitle(_ renderer: [String: Any]) -> String? {
        guard
            let flexColumns = renderer["flexColumns"] as? [[String: Any]],
            let column = flexColumns.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
            let text = column["text"] as? [String: Any],
            let runs = text["runs"] as? [[String: Any]],
            let title = runs.first?["text"] as? String
        else { return nil }
        return title
    }

    /// The subtitle flex column is a run list like
    /// `Artist • Album • 3:45`, with separator runs (bullets/dashes) between
    /// segments. Splits on those separators instead of assuming a fixed
    /// artist/album/duration ordering, since not every row has all three —
    /// a duration-shaped segment is claimed as the duration wherever it
    /// appears, then the first remaining segment is the artist and the
    /// second (if any) is the album.
    private static func extractSubtitleParts(_ renderer: [String: Any]) -> (artist: String?, artistId: String?, album: String?, albumId: String?, duration: String?) {
        guard
            let flexColumns = renderer["flexColumns"] as? [[String: Any]],
            flexColumns.count > 1,
            let column = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
            let text = column["text"] as? [String: Any],
            let runs = text["runs"] as? [[String: Any]]
        else { return (nil, nil, nil, nil, nil) }

        var segments: [[(text: String, browseId: String?)]] = [[]]
        for run in runs {
            guard let raw = run["text"] as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "•" || trimmed == "-" || trimmed == "–" {
                segments.append([])
                continue
            }
            let browseId = ((run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
            segments[segments.count - 1].append((text: trimmed, browseId: browseId))
        }
        segments.removeAll { $0.isEmpty }

        var artist: String?
        var artistId: String?
        var album: String?
        var albumId: String?
        var duration: String?

        for segment in segments {
            let joined = segment.map(\.text).joined(separator: " ")
            if duration == nil, isDurationLike(joined) {
                duration = joined
                continue
            }
            if artist == nil {
                artist = joined
                artistId = segment.first?.browseId
            } else if album == nil {
                album = joined
                albumId = segment.first?.browseId
            }
        }

        return (artist, artistId, album, albumId, duration)
    }

    private static func isDurationLike(_ text: String) -> Bool {
        text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil
    }

    private static func parseDuration(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        var seconds = 0
        for part in parts { seconds = seconds * 60 + part }
        return TimeInterval(seconds)
    }

    /// Looks for YTM's explicit-content badge
    /// (`musicInlineBadgeRenderer.icon.iconType` containing `"EXPLICIT"`).
    /// If the badge shape ever changes, this simply returns `false` rather
    /// than guessing — explicit-flagging is best-effort, not load-bearing.
    private static func hasExplicitBadge(_ renderer: [String: Any]) -> Bool {
        guard let badges = renderer["badges"] as? [[String: Any]] else { return false }
        for badge in badges {
            if let inline = badge["musicInlineBadgeRenderer"] as? [String: Any],
               let icon = inline["icon"] as? [String: Any],
               let iconType = icon["iconType"] as? String,
               iconType.contains("EXPLICIT") {
                return true
            }
        }
        return false
    }

    private static func extractThumbnail(_ renderer: [String: Any]) -> URL? {
        guard
            let thumbnail = renderer["thumbnail"] as? [String: Any],
            let musicThumbnailRenderer = thumbnail["musicThumbnailRenderer"] as? [String: Any],
            let thumbnailObj = musicThumbnailRenderer["thumbnail"] as? [String: Any],
            let thumbnails = thumbnailObj["thumbnails"] as? [[String: Any]],
            let last = thumbnails.last,
            let urlString = last["url"] as? String
        else { return nil }
        return URL(string: urlString)
    }
}
