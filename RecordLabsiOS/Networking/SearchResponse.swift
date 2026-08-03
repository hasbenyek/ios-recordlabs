import Foundation
import os

private let searchParserLog = Logger(subsystem: "com.recordlabs.music.ios", category: "SearchResponseParser")

struct SearchParseDiagnostics: Equatable {
    var topLevelKeys: [String] = []
    var rendererNodesVisited = 0
    var candidateSongRenderersFound = 0
    var rejectedMissingVideoId = 0
    var rejectedMissingTitle = 0
    var rejectedMissingArtist = 0
    var songsEmitted = 0
    var finalErrorCategory: String?
}

/// Conservative parser for the renderer tree returned by YouTube Music.
/// It emits only rows containing a real watchEndpoint videoId, title and artist.
enum SearchResponseParser {
    struct ParseResult {
        var songs: [Song]
        /// Kept as strings for the existing UI/tests; `metrics` is the safe
        /// structured form used by the runtime diagnostics panel.
        var diagnostics: [String]
        var metrics: SearchParseDiagnostics
    }

    static func parseSongs(from data: Data) -> ParseResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            let metrics = SearchParseDiagnostics(finalErrorCategory: "invalidJSON")
            return ParseResult(songs: [], diagnostics: ["Response body was not valid JSON"], metrics: metrics)
        }

        var metrics = SearchParseDiagnostics()
        if let rootDictionary = root as? [String: Any] {
            metrics.topLevelKeys = rootDictionary.keys.sorted()
        }

        var songs: [Song] = []
        var messages: [String] = []
        var seenVideoIds = Set<String>()

        walk(root) { node in
            metrics.rendererNodesVisited += 1
            guard let candidate = candidate(in: node) else { return }
            metrics.candidateSongRenderersFound += 1

            guard let videoId = extractVideoId(candidate.renderer) else {
                metrics.rejectedMissingVideoId += 1
                return
            }
            guard let title = extractTitle(candidate.renderer), !title.isEmpty else {
                metrics.rejectedMissingTitle += 1
                return
            }
            let subtitle = extractSubtitleParts(candidate.renderer)
            guard let artist = subtitle.artist, !artist.isEmpty else {
                metrics.rejectedMissingArtist += 1
                return
            }
            guard seenVideoIds.insert(videoId).inserted else { return }

            songs.append(Song(
                id: videoId,
                title: title,
                artists: [ArtistRef(id: subtitle.artistId ?? artist, name: artist)],
                album: subtitle.album.map { AlbumRef(id: subtitle.albumId ?? $0, title: $0) },
                duration: subtitle.duration.flatMap(parseDuration) ?? 0,
                thumbnailURL: extractThumbnail(candidate.renderer),
                isExplicit: hasExplicitBadge(candidate.renderer)
            ))
        }

        metrics.songsEmitted = songs.count
        if metrics.candidateSongRenderersFound == 0 {
            metrics.finalErrorCategory = "parserIncompatible"
            messages.append("Search response received, but no supported song renderer was parsed.")
        } else if songs.isEmpty {
            metrics.finalErrorCategory = "noUsableSongs"
        }
        if metrics.rejectedMissingVideoId > 0 { messages.append("Rejected (metrics.rejectedMissingVideoId) candidate(s) without videoId") }
        if metrics.rejectedMissingTitle > 0 { messages.append("Rejected (metrics.rejectedMissingTitle) candidate(s) without title") }
        if metrics.rejectedMissingArtist > 0 { messages.append("Rejected (metrics.rejectedMissingArtist) candidate(s) without artist") }
        if !messages.isEmpty { searchParserLog.warning("\(messages.joined(separator: "; "), privacy: .public)") }
        return ParseResult(songs: songs, diagnostics: messages, metrics: metrics)
    }

    private struct Candidate {
        let renderer: [String: Any]
    }

    private static func candidate(in node: [String: Any]) -> Candidate? {
        if let renderer = node["musicResponsiveListItemRenderer"] as? [String: Any] { return Candidate(renderer: renderer) }
        if let renderer = node["musicTwoRowItemRenderer"] as? [String: Any] { return Candidate(renderer: renderer) }
        return nil
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dictionary = node as? [String: Any] {
            visit(dictionary)
            for value in dictionary.values { walk(value, visit: visit) }
        } else if let array = node as? [Any] {
            for value in array { walk(value, visit: visit) }
        }
    }

    private static func extractVideoId(_ renderer: [String: Any]) -> String? {
        if let endpointVideoId = findString(in: renderer, key: "videoId", under: "watchEndpoint") {
            return endpointVideoId
        }
        // Android's parser also accepts playlistItemData.videoId for search
        // rows whose play endpoint is carried by the row metadata/overlay.
        if let playlistItemData = renderer["playlistItemData"] as? [String: Any],
           let videoId = playlistItemData["videoId"] as? String,
           !videoId.isEmpty {
            return videoId
        }
        return nil
    }

    private static func extractTitle(_ renderer: [String: Any]) -> String? {
        if let title = textValue(renderer["title"]) { return title }
        if let flexColumns = renderer["flexColumns"] as? [[String: Any]],
           let first = flexColumns.first,
           let flex = first["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] {
            return textValue(flex["text"])
        }
        return nil
    }

    private static func extractSubtitleParts(_ renderer: [String: Any]) -> (artist: String?, artistId: String?, album: String?, albumId: String?, duration: String?) {
        let textObject: Any?
        if let flexColumns = renderer["flexColumns"] as? [[String: Any]], flexColumns.count > 1,
           let flex = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] {
            textObject = flex["text"]
        } else {
            textObject = renderer["subtitle"]
        }
        guard let text = textObject as? [String: Any], let runs = text["runs"] as? [[String: Any]] else {
            return (nil, nil, nil, nil, nil)
        }

        var segments: [[(String, String?)]] = [[]]
        for run in runs {
            guard let raw = run["text"] as? String else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || ["•", "-", "–", "·"].contains(value) {
                segments.append([])
                continue
            }
            let browseId = ((run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
            segments[segments.count - 1].append((value, browseId))
        }
        segments.removeAll { $0.isEmpty }
        var artist: String?
        var artistId: String?
        var album: String?
        var albumId: String?
        var duration: String?
        for segment in segments {
            let value = segment.map(\.0).joined(separator: " ")
            if duration == nil, isDurationLike(value) { duration = value }
            else if artist == nil { artist = value; artistId = segment.first?.1 }
            else if album == nil { album = value; albumId = segment.first?.1 }
        }
        return (artist, artistId, album, albumId, duration)
    }

    private static func textValue(_ value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let simple = object["simpleText"] as? String { return simple }
        if let runs = object["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func findString(in value: Any, key: String, under parentKey: String) -> String? {
        if let object = value as? [String: Any] {
            if let parent = object[parentKey] as? [String: Any], let found = parent[key] as? String, !found.isEmpty { return found }
            for child in object.values { if let found = findString(in: child, key: key, under: parentKey) { return found } }
        } else if let array = value as? [Any] {
            for child in array { if let found = findString(in: child, key: key, under: parentKey) { return found } }
        }
        return nil
    }

    private static func isDurationLike(_ text: String) -> Bool {
        text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil
    }

    private static func parseDuration(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return TimeInterval(parts.reduce(0) { $0 * 60 + $1 })
    }

    private static func hasExplicitBadge(_ renderer: [String: Any]) -> Bool {
        guard let badges = renderer["badges"] as? [[String: Any]] else { return false }
        return badges.contains { badge in
            guard let inline = badge["musicInlineBadgeRenderer"] as? [String: Any],
                  let icon = inline["icon"] as? [String: Any],
                  let type = icon["iconType"] as? String else { return false }
            return type.contains("EXPLICIT")
        }
    }

    private static func extractThumbnail(_ renderer: [String: Any]) -> URL? {
        var urls: [String] = []
        walk(renderer) { node in
            if let thumbnails = (node["thumbnails"] as? [[String: Any]])?.compactMap({ $0["url"] as? String }) { urls.append(contentsOf: thumbnails) }
        }
        return urls.last.flatMap(URL.init(string:))
    }
}
