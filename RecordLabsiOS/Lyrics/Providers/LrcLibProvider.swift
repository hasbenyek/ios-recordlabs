import Foundation

/// Real client for LRCLIB's public API (`lrclib.net`) — same service
/// Android's `lrclib/.../LrcLib.kt` uses. Tries a small cascade of search
/// strategies (title+artist, then a combined free-text query, then title
/// alone), scores every candidate with `LyricsMatcher`, and rejects
/// anything below `LyricsMatcher.minimumAcceptableConfidence` rather than
/// returning "the first remotely similar result".
struct LrcLibProvider: LyricsProvider {
    let name = "LRCLIB"

    private let baseURL = URL(string: "https://lrclib.net/api/search")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private struct Track: Decodable {
        var id: Int
        var trackName: String
        var artistName: String
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult {
        let cleanedTitle = LyricsMatcher.cleanTitle(query.title)
        let cleanedArtist = LyricsMatcher.cleanArtist(query.artist)

        let strategies: [[URLQueryItem]] = [
            [URLQueryItem(name: "track_name", value: cleanedTitle), URLQueryItem(name: "artist_name", value: cleanedArtist)],
            [URLQueryItem(name: "q", value: "\(cleanedArtist) \(cleanedTitle)")],
            [URLQueryItem(name: "track_name", value: cleanedTitle)],
        ]

        var lastNetworkError: String?
        for items in strategies {
            try Task.checkCancellation()
            do {
                let tracks = try await search(items)
                if let best = pickBest(tracks, query: query) {
                    return result(for: best)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastNetworkError = error.localizedDescription
            }
        }

        if let lastNetworkError {
            throw LyricsProviderError.network(lastNetworkError)
        }
        return .noMatch
    }

    private func search(_ items: [URLQueryItem]) async throws -> [Track] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw LyricsProviderError.malformedResponse("Bad base URL")
        }
        components.queryItems = items
        guard let url = components.url else {
            throw LyricsProviderError.malformedResponse("Bad search URL")
        }

        var request = URLRequest(url: url)
        request.setValue("RecordLabsiOS/1.0 (+https://github.com/hasbenyek/ios-recordlabs)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LyricsProviderError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let tracks = try? JSONDecoder().decode([Track].self, from: data) else {
            throw LyricsProviderError.malformedResponse("Couldn't decode LRCLIB search response")
        }
        return tracks
    }

    private func pickBest(_ tracks: [Track], query: LyricsQuery) -> Track? {
        let scored = tracks.map { track in
            (track: track, score: LyricsMatcher.confidence(
                query: query,
                candidate: LyricsMatcher.Candidate(title: track.trackName, artist: track.artistName, duration: track.duration)
            ))
        }
        guard let best = scored.max(by: { $0.score < $1.score }),
              best.score >= LyricsMatcher.minimumAcceptableConfidence else {
            return nil
        }
        return best.track
    }

    private func result(for track: Track) -> LyricsResult {
        if track.instrumental == true {
            return .instrumental(provider: name)
        }
        if let synced = track.syncedLyrics, !synced.isEmpty {
            let parsed = LRCParser.parse(synced)
            if parsed.isSynced {
                return .syncedLines(parsed.lines, provider: name)
            }
        }
        if let plain = track.plainLyrics, !plain.isEmpty {
            return .plain(plain, provider: name)
        }
        return .noMatch
    }
}
