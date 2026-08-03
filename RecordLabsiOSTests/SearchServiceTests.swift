import XCTest
@testable import RecordLabsiOS

final class SearchServiceTests: XCTestCase {
    func testFirstClientHTTPFailureContinuesToSecond() async throws {
        let mock = MockSearchClient { identity in
            if identity.clientName == "WEB_REMIX" { throw InnerTubeError.badStatus(403) }
            return Self.response(Self.songData(id: "second"), identity: identity)
        }
        let result = try await SearchService(client: mock).search(query: "q")
        XCTAssertEqual(result.songs.map(\.id), ["second"])
        XCTAssertEqual(result.diagnostics.attemptedClients, ["WEB_REMIX", "ANDROID"])
    }

    func testMalformedJSONContinuesToSecond() async throws {
        let mock = MockSearchClient { identity in
            if identity.clientName == "WEB_REMIX" { return Self.response(Data("bad".utf8), identity: identity) }
            return Self.response(Self.songData(id: "valid"), identity: identity)
        }
        let result = try await SearchService(client: mock).search(query: "q")
        XCTAssertEqual(result.songs.map(\.id), ["valid"])
    }

    func testZeroSupportedSongsContinuesToSecond() async throws {
        let mock = MockSearchClient { identity in
            if identity.clientName == "WEB_REMIX" { return Self.response(Self.unsupportedData(), identity: identity) }
            return Self.response(Self.songData(id: "valid"), identity: identity)
        }
        let result = try await SearchService(client: mock).search(query: "q")
        XCTAssertEqual(result.songs.map(\.id), ["valid"])
    }

    func testFirstValidClientStopsTheChain() async throws {
        let mock = MockSearchClient { identity in
            if identity.clientName != "WEB_REMIX" { throw InnerTubeError.badStatus(500) }
            return Self.response(Self.songData(id: "first"), identity: identity)
        }
        let result = try await SearchService(client: mock).search(query: "q")
        XCTAssertEqual(result.songs.map(\.id), ["first"])
    }

    func testAllUnsupportedResponsesExposeParserIncompatibleCategory() async {
        let mock = MockSearchClient { identity in
            Self.response(Self.unsupportedData(), identity: identity)
        }
        do {
            _ = try await SearchService(client: mock).search(query: "q")
            XCTFail("Expected parser incompatibility")
        } catch let error as SearchServiceError {
            XCTAssertEqual(error.report.finalErrorCategory, "parserIncompatible")
            XCTAssertEqual(error.report.songsEmitted, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func response(_ data: Data, identity: YouTubeClientIdentity) -> SearchHTTPResponse {
        SearchHTTPResponse(data: data, client: identity, endpointPath: "/youtubei/v1/search", statusCode: 200, contentType: "application/json", byteCount: data.count)
    }

    private static func songData(id: String) -> Data {
        let object: [String: Any] = ["musicTwoRowItemRenderer": [
            "navigationEndpoint": ["watchEndpoint": ["videoId": id]],
            "title": ["runs": [["text": "Song"]]],
            "subtitle": ["runs": [["text": "Artist"]]]
        ]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private static func unsupportedData() -> Data {
        try! JSONSerialization.data(withJSONObject: ["musicAlbumShelfRenderer": ["title": ["simpleText": "Album"]]])
    }
}

private actor MockSearchClient: SearchRequesting {
    private let action: (YouTubeClientIdentity) throws -> SearchHTTPResponse

    init(action: @escaping (YouTubeClientIdentity) throws -> SearchHTTPResponse) {
        self.action = action
    }

    func searchResponse(query: String, identity: YouTubeClientIdentity) async throws -> SearchHTTPResponse {
        try action(identity)
    }
}
