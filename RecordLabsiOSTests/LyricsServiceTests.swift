import XCTest
@testable import RecordLabsiOS

@MainActor
final class LyricsServiceTests: XCTestCase {
    private let query = LyricsQuery(videoId: "v1", title: "Neon Tide", artist: "Aurora Bay", album: nil, duration: 200)

    func testBetterLyricsSuccessPreventsLRCLIBCall() async {
        let better = MockLyricsProvider(name: "BetterLyrics", result: .syncedLines([], provider: "BetterLyrics"))
        let lrc = MockLyricsProvider(name: "LRCLIB", result: .syncedLines([], provider: "LRCLIB"))
        let service = LyricsService(providers: [better, lrc])

        await service.load(for: query)

        XCTAssertEqual(better.calls, 1)
        XCTAssertEqual(lrc.calls, 0)
    }

    func testBetterLyricsNoMatchFallsBackToLRCLIB() async {
        let better = MockLyricsProvider(name: "BetterLyrics", result: .noMatch)
        let lrc = MockLyricsProvider(name: "LRCLIB", result: .plain("lyrics", provider: "LRCLIB"))
        let service = LyricsService(providers: [better, lrc])

        await service.load(for: query)

        XCTAssertEqual(better.calls, 1)
        XCTAssertEqual(lrc.calls, 1)
        XCTAssertEqual(service.result, .plain("lyrics", provider: "LRCLIB"))
    }

    func testBetterLyricsProviderFailureFallsBackToLRCLIB() async {
        let better = MockLyricsProvider(name: "BetterLyrics", error: .network("offline"))
        let lrc = MockLyricsProvider(name: "LRCLIB", result: .plain("lyrics", provider: "LRCLIB"))
        let service = LyricsService(providers: [better, lrc])

        await service.load(for: query)

        XCTAssertEqual(lrc.calls, 1)
        XCTAssertEqual(service.result, .plain("lyrics", provider: "LRCLIB"))
    }

    func testPerProviderTimeoutFallsBackCorrectly() async {
        let better = MockLyricsProvider(name: "BetterLyrics", delayNanoseconds: 100_000_000)
        let lrc = MockLyricsProvider(name: "LRCLIB", result: .plain("lyrics", provider: "LRCLIB"))
        let service = LyricsService(providers: [better, lrc], overallTimeout: 1, perProviderTimeout: 0.01)

        await service.load(for: query)

        XCTAssertEqual(lrc.calls, 1)
        XCTAssertEqual(service.result, .plain("lyrics", provider: "LRCLIB"))
    }

    func testOverallTimeoutReturnsControlledResult() async {
        let slow = MockLyricsProvider(name: "BetterLyrics", delayNanoseconds: 200_000_000)
        let service = LyricsService(providers: [slow], overallTimeout: 0.01, perProviderTimeout: 1)

        await service.load(for: query)

        if case .providerFailure = service.result { } else { XCTFail("Expected controlled provider failure") }
    }

    func testCancellingLoadPreventsResultPublication() async {
        let slow = MockLyricsProvider(name: "BetterLyrics", delayNanoseconds: 200_000_000)
        let service = LyricsService(providers: [slow], overallTimeout: 1, perProviderTimeout: 1)
        let task = Task { await service.load(for: query) }

        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        await task.value

        XCTAssertEqual(service.result, .noMatch)
    }

    func testStaleResponseCannotOverwriteNewerTrack() async {
        let provider = MockLyricsProvider(name: "BetterLyrics", delayedVideoId: "old", delayNanoseconds: 100_000_000, result: .plain("old", provider: "BetterLyrics"))
        let service = LyricsService(providers: [provider], overallTimeout: 1, perProviderTimeout: 1)
        let oldQuery = LyricsQuery(videoId: "old", title: "Old", artist: "Artist", album: nil, duration: nil)
        let newQuery = LyricsQuery(videoId: "new", title: "New", artist: "Artist", album: nil, duration: nil)

        let oldTask = Task { await service.load(for: oldQuery) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await service.load(for: newQuery)
        await oldTask.value

        XCTAssertEqual(service.result, .noMatch)
    }

    func testPositiveCacheIsReused() async {
        let provider = MockLyricsProvider(name: "BetterLyrics", result: .plain("lyrics", provider: "BetterLyrics"))
        let service = LyricsService(providers: [provider])

        await service.load(for: query)
        await service.load(for: query)

        XCTAssertEqual(provider.calls, 1)
    }

    func testNegativeCacheCanBeBypassedByForceRefresh() async {
        let provider = MockLyricsProvider(name: "BetterLyrics", result: .noMatch)
        let service = LyricsService(providers: [provider])

        await service.load(for: query)
        provider.result = .plain("lyrics", provider: "BetterLyrics")
        await service.load(for: query, forceRefresh: true)

        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(service.result, .plain("lyrics", provider: "BetterLyrics"))
    }

    func testProviderOutageIsNotNegativeCached() async {
        let provider = MockLyricsProvider(name: "BetterLyrics", error: .network("offline"))
        let service = LyricsService(providers: [provider])

        await service.load(for: query)
        provider.error = nil
        provider.result = .plain("lyrics", provider: "BetterLyrics")
        await service.load(for: query)

        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(service.result, .plain("lyrics", provider: "BetterLyrics"))
    }
}

private final class MockLyricsProvider: LyricsProvider {
    let name: String
    var result: LyricsResult = .noMatch
    var error: LyricsProviderError?
    var delayNanoseconds: UInt64 = 0
    var delayedVideoId: String?
    private(set) var calls = 0

    init(name: String, result: LyricsResult = .noMatch, error: LyricsProviderError? = nil, delayNanoseconds: UInt64 = 0, delayedVideoId: String? = nil) {
        self.name = name
        self.result = result
        self.error = error
        self.delayNanoseconds = delayNanoseconds
        self.delayedVideoId = delayedVideoId
    }

    func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult {
        calls += 1
        if delayedVideoId == nil || delayedVideoId == query.videoId {
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        }
        if let delayedVideoId, delayedVideoId != query.videoId { return .noMatch }
        if let error { throw error }
        return result
    }
}
