import Foundation

/// Swift port of the request-plumbing half of `innertube/InnerTube.kt`
/// (headers/body only — it does not attempt to replicate the ~100-file
/// response-model tree the Android `innertube` module uses for full
/// browse/library parity; see `SearchResponse.swift` for what's parsed).
protocol StreamResolverClient {
    func player(videoId: String, identity: YouTubeClientIdentity, signatureTimestamp: Int?) async throws -> Data
}

actor InnerTubeClient: StreamResolverClient, SearchRequesting {
    static let shared = InnerTubeClient()

    private let session: URLSession
    var visitorData: String?
    var locale: YouTubeLocale = .current

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func request(
        path: String,
        identity: YouTubeClientIdentity,
        body: Encodable
    ) async throws -> Data {
        let response = try await requestResponse(path: path, identity: identity, body: body)
        return response.data
    }

    private func requestResponse(
        path: String,
        identity: YouTubeClientIdentity,
        body: Encodable
    ) async throws -> SearchHTTPResponse {
        var components = URLComponents(url: YouTubeClientIdentity.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        let isMusicClient = identity.clientName == "WEB_REMIX" || identity.clientName == "ANDROID_MUSIC"
        let origin = isMusicClient ? YouTubeClientIdentity.originYouTubeMusic : "https://www.youtube.com"
        let referer = isMusicClient ? YouTubeClientIdentity.refererYouTubeMusic : "https://www.youtube.com/"
        request.setValue(identity.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(identity.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(origin, forHTTPHeaderField: "X-Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(identity.userAgent, forHTTPHeaderField: "User-Agent")
        if let visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        request.httpBody = try JSONEncoder().encode(AnyEncodable(body))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InnerTubeError.badStatus(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw InnerTubeError.badStatus(http.statusCode)
        }
        return SearchHTTPResponse(
            data: data,
            client: identity,
            endpointPath: request.url?.path ?? "/youtubei/v1/\(path)",
            statusCode: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type") ?? http.mimeType ?? "unknown",
            byteCount: data.count
        )
    }

    func search(query: String, identity: YouTubeClientIdentity = .webRemix) async throws -> Data {
        let body = SearchRequestBody(
            context: InnerTubeContext(identity: identity, locale: locale, visitorData: visitorData),
            query: query,
            params: YouTubeClientIdentity.songSearchParams
        )
        return try await request(path: "search", identity: identity, body: body)
    }

    func searchResponse(query: String, identity: YouTubeClientIdentity) async throws -> SearchHTTPResponse {
        let body = SearchRequestBody(
            context: InnerTubeContext(identity: identity, locale: locale, visitorData: visitorData),
            query: query,
            params: YouTubeClientIdentity.songSearchParams
        )
        return try await requestResponse(path: "search", identity: identity, body: body)
    }

    /// `browseId: "FEmusic_home"` is YouTube Music's own id for the signed-out
    /// home feed (quick picks / recent activity) — the same one the Android
    /// app's `HomeScreen.kt` requests via `YouTube.browse` at startup.
    func browse(
        browseId: String,
        params: String? = nil,
        identity: YouTubeClientIdentity = .webRemix
    ) async throws -> Data {
        let body = BrowseRequestBody(
            context: InnerTubeContext(identity: identity, locale: locale, visitorData: visitorData),
            browseId: browseId,
            params: params
        )
        return try await request(path: "browse", identity: identity, body: body)
    }

    func player(videoId: String, identity: YouTubeClientIdentity, signatureTimestamp: Int? = nil) async throws -> Data {
        let playbackContext = (identity.usesSignatureTimestamp ? signatureTimestamp : nil)
            .map { PlayerRequestBody.PlaybackContext(contentPlaybackContext: .init(signatureTimestamp: $0)) }
        let body = PlayerRequestBody(
            context: InnerTubeContext(identity: identity, locale: locale, visitorData: visitorData),
            videoId: videoId,
            playlistId: nil,
            playbackContext: playbackContext
        )
        return try await request(path: "player", identity: identity, body: body)
    }
}

enum InnerTubeError: Error {
    case badStatus(Int)
    case noPlayableFormat
    case decodingFailed
}

/// Type-erasing wrapper so `request(...)` can accept any `Encodable` body
/// without making the whole client generic.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
