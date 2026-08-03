import Foundation

/// Real client for the same BetterLyrics community server Android's
/// `betterlyrics/.../BetterLyrics.kt` uses (`lyrics-api.boidu.dev`).
/// Returns TTML (word/line-synced, with background-vocal and agent
/// support), parsed by the shared `TTMLParser`.
///
/// Matches Android's actual behavior: title/artist are sent as-is with no
/// client-side confidence scoring — matching happens server-side. (LRCLIB,
/// by contrast, returns a candidate *list* the client must score itself —
/// see `LrcLibProvider`.)
struct BetterLyricsProvider: LyricsProvider {
    let name = "BetterLyrics"

    private let baseURL = URL(string: "https://lyrics-api.boidu.dev/getLyrics")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private struct Response: Decodable {
        var ttml: String?
    }

    func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw LyricsProviderError.malformedResponse("Bad base URL")
        }
        var items = [
            URLQueryItem(name: "s", value: query.title),
            URLQueryItem(name: "a", value: query.artist),
        ]
        if let duration = query.duration, duration > 0 {
            items.append(URLQueryItem(name: "d", value: String(Int(duration))))
        }
        if let album = query.album, !album.isEmpty {
            items.append(URLQueryItem(name: "al", value: album))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw LyricsProviderError.malformedResponse("Bad request URL")
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LyricsProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LyricsProviderError.network("No HTTP response")
        }
        if http.statusCode == 404 {
            return .noMatch
        }
        guard 200..<300 ~= http.statusCode else {
            throw LyricsProviderError.network("HTTP \(http.statusCode)")
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LyricsProviderError.malformedResponse("Couldn't decode BetterLyrics response")
        }
        guard let ttml = decoded.ttml, !ttml.isEmpty else {
            return .noMatch
        }

        let outcome = TTMLParser.parse(ttml)
        guard !outcome.lines.isEmpty else {
            throw LyricsProviderError.malformedResponse("BetterLyrics returned TTML with no usable lines")
        }

        let hasWordTiming = outcome.lines.contains { $0.isWordSynced }
        return hasWordTiming ? .syncedWords(outcome.lines, provider: name) : .syncedLines(outcome.lines, provider: name)
    }
}
