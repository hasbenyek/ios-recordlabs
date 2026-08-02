import XCTest
@testable import RecordLabsiOS

final class SearchResponseParserTests: XCTestCase {
    func testValidSongRendererIsAccepted() {
        let result = SearchResponseParser.parseSongs(from: fixture(videoId: "v1", title: "Song", artist: "Artist"))
        XCTAssertEqual(result.songs.map(\.id), ["v1"])
    }

    func testMissingVideoIdIsRejected() {
        let result = SearchResponseParser.parseSongs(from: fixture(videoId: nil, title: "Song", artist: "Artist"))
        XCTAssertTrue(result.songs.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.contains("videoId") })
    }

    func testMissingTitleIsRejected() {
        let result = SearchResponseParser.parseSongs(from: fixture(videoId: "v1", title: nil, artist: "Artist"))
        XCTAssertTrue(result.songs.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.contains("title") })
    }

    func testMissingArtistIsRejected() {
        let result = SearchResponseParser.parseSongs(from: fixture(videoId: "v1", title: "Song", artist: nil))
        XCTAssertTrue(result.songs.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.contains("artist") })
    }

    func testMalformedJSONReturnsControlledParseFailure() {
        let result = SearchResponseParser.parseSongs(from: Data("not json".utf8))
        XCTAssertTrue(result.songs.isEmpty)
        XCTAssertFalse(result.diagnostics.isEmpty)
    }

    func testDuplicateVideoIdsAreDeduplicated() {
        let first = fixtureObject(videoId: "v1", title: "Song", artist: "Artist")
        let second = fixtureObject(videoId: "v1", title: "Song", artist: "Artist")
        let data = try! JSONSerialization.data(withJSONObject: [first, second])
        let result = SearchResponseParser.parseSongs(from: data)
        XCTAssertEqual(result.songs.count, 1)
    }

    func testClearlyNonSongRendererIsNotEmittedAsSong() {
        let object: [String: Any] = ["musicResponsiveListItemRenderer": ["navigationEndpoint": ["watchEndpoint": ["videoId": "v1"]]]]
        let data = try! JSONSerialization.data(withJSONObject: object)
        let result = SearchResponseParser.parseSongs(from: data)
        XCTAssertTrue(result.songs.isEmpty)
    }

    private func fixture(videoId: String?, title: String?, artist: String?) -> Data {
        try! JSONSerialization.data(withJSONObject: fixtureObject(videoId: videoId, title: title, artist: artist))
    }

    private func fixtureObject(videoId: String?, title: String?, artist: String?) -> [String: Any] {
        var watch: [String: Any] = [:]
        if let videoId { watch["videoId"] = videoId }
        var firstRun: [String: Any] = [:]
        if let title { firstRun["text"] = title }
        var subtitleRuns: [[String: Any]] = []
        if let artist { subtitleRuns.append(["text": artist]) }
        subtitleRuns.append(["text": " - "])
        subtitleRuns.append(["text": "3:20"])
        return [
            "musicResponsiveListItemRenderer": [
                "navigationEndpoint": ["watchEndpoint": watch],
                "flexColumns": [
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [firstRun]]]],
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": subtitleRuns]]]
                ]
            ]
        ]
    }
}
