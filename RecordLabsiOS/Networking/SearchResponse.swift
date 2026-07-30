import Foundation

/// Best-effort parser for YouTube Music's `/search` AND `/browse` responses
/// (both use the same `musicResponsiveListItemRenderer` shape for song rows,
/// so `HomeScreen` reuses this too — see its doc comment for what that
/// means for fidelity).
///
/// The real response is a deeply nested "renderer tree"
/// (`SectionListRenderer` → `MusicShelfRenderer`/`MusicCardShelfRenderer` →
/// `MusicResponsiveListItemRenderer`, etc) — the Android `innertube` module
/// models this faithfully across dozens of files
/// (`models/MusicResponsiveListItemRenderer.kt` and friends) with typed
/// `isSong`/`isAlbum`/`isArtist`/`isPodcast` detection.
///
/// Reproducing that whole tree is out of scope for this pass, so this parser
/// instead recursively scans the raw JSON for any
/// `musicResponsiveListItemRenderer` object (the shape used for song rows in
/// both quick picks and search results) and pulls out just enough fields to
/// play something: title, a best-guess artist string, and the video id. It
/// will misclassify or skip renderer shapes the real client distinguishes
/// (albums, artists, playlists, podcast episodes) — treat results as
/// "songs found", not a faithful reproduction of YouTube Music's UI.
enum SearchResponseParser {
    static func parseSongs(from data: Data) -> [Song] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var results: [Song] = []
        walk(root) { node in
            guard
                let renderer = node["musicResponsiveListItemRenderer"] as? [String: Any],
                let videoId = extractVideoId(renderer),
                let title = extractRuns(renderer, flexColumnIndex: 0).first
            else { return }

            let subtitleRuns = extractRuns(renderer, flexColumnIndex: 1)
            let artistName = subtitleRuns.first { !$0.contains("•") && !isDurationLike($0) } ?? "Unknown Artist"

            results.append(
                Song(
                    id: videoId,
                    title: title,
                    artists: [ArtistRef(id: artistName, name: artistName)],
                    album: nil,
                    duration: 0,
                    thumbnailURL: extractThumbnail(renderer)
                )
            )
        }
        return results
    }

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

    private static func extractRuns(_ renderer: [String: Any], flexColumnIndex: Int) -> [String] {
        guard
            let flexColumns = renderer["flexColumns"] as? [[String: Any]],
            flexColumnIndex < flexColumns.count,
            let column = flexColumns[flexColumnIndex]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
            let text = column["text"] as? [String: Any],
            let runs = text["runs"] as? [[String: Any]]
        else { return [] }
        return runs.compactMap { $0["text"] as? String }
    }

    private static func isDurationLike(_ text: String) -> Bool {
        text.allSatisfy { $0.isNumber || $0 == ":" }
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
