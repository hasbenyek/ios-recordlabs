import XCTest
@testable import RecordLabsiOS

final class LyricsMatcherTests: XCTestCase {
    private let query = LyricsQuery(videoId: "v1", title: "Neon Tide", artist: "Aurora Bay", album: nil, duration: 200)

    func testExactTitleArtistMatch() {
        let score = LyricsMatcher.confidence(query: query, candidate: .init(title: "Neon Tide", artist: "Aurora Bay", duration: 200))
        XCTAssertGreaterThanOrEqual(score, LyricsMatcher.minimumAcceptableConfidence)
    }

    func testNormalizedTitleMatch() {
        let score = LyricsMatcher.confidence(query: query, candidate: .init(title: "Neon Tide (Official Video)", artist: "Aurora Bay", duration: 200))
        XCTAssertGreaterThanOrEqual(score, LyricsMatcher.minimumAcceptableConfidence)
    }

    func testWrongArtistRejected() {
        let score = LyricsMatcher.confidence(query: query, candidate: .init(title: "Neon Tide", artist: "Different Artist", duration: 200))
        XCTAssertLessThan(score, LyricsMatcher.minimumAcceptableConfidence)
    }

    func testExcessiveDurationDifferenceRejected() {
        let score = LyricsMatcher.confidence(query: query, candidate: .init(title: "Neon Tide", artist: "Aurora Bay", duration: 260))
        XCTAssertLessThan(score, LyricsMatcher.minimumAcceptableConfidence)
    }

    func testCloseDurationMatchAccepted() {
        let score = LyricsMatcher.confidence(query: query, candidate: .init(title: "Neon Tide", artist: "Aurora Bay", duration: 201))
        XCTAssertGreaterThanOrEqual(score, LyricsMatcher.minimumAcceptableConfidence)
    }
}
