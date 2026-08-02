import Foundation

/// Orchestrates the real lyrics provider chain: **BetterLyrics → LRCLIB**.
/// If BetterLyrics fails, times out, returns malformed TTML, or has no
/// match, LRCLIB is tried next — mirrors the fallback-chain *shape* of
/// Android's `LyricsHelper.kt` (sequential, first-confident-success-wins,
/// per-provider timeout), generalized to just these two providers for this
/// phase.
///
/// Never uses mock/placeholder lyrics and never shows an unrelated result
/// merely to avoid an empty state — a failed/empty lookup surfaces as
/// `.noMatch`/`.providerFailure`, which the UI renders honestly.
@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var result: LyricsResult = .noMatch
    @Published private(set) var isLoading = false
    /// User-adjustable timing offset (seconds) — added to every line's
    /// `startTime` before comparing against playback position.
    @Published var timingOffsetSeconds: Double = 0

    private let providers: [LyricsProvider]
    private let overallTimeout: TimeInterval
    private let perProviderTimeout: TimeInterval

    private var cache: [String: LyricsResult] = [:]
    private var negativeCacheTimestamps: [String: Date] = [:]
    private let negativeCacheTTL: TimeInterval = 5 * 60

    /// Guards against a response for an *older* query overwriting `result`
    /// after a newer `load(for:)` call has already started — belt-and-
    /// suspenders alongside SwiftUI's own `.task(id:)` cancellation (see
    /// `LyricsView`, which drives this method from a `.task(id: song?.id)`
    /// so the previous in-flight `Task` is cancelled automatically on
    /// track change).
    private var currentQueryKey: String?

    init(
        providers: [LyricsProvider] = [BetterLyricsProvider(), LrcLibProvider()],
        overallTimeout: TimeInterval = 12,
        perProviderTimeout: TimeInterval = 8
    ) {
        self.providers = providers
        self.overallTimeout = overallTimeout
        self.perProviderTimeout = perProviderTimeout
    }

    func load(for query: LyricsQuery, forceRefresh: Bool = false) async {
        let cacheKey = query.videoId
        currentQueryKey = cacheKey
        timingOffsetSeconds = 0

        if !forceRefresh, let cached = cache[cacheKey] {
            result = cached
            return
        }
        if !forceRefresh,
           let negativeTimestamp = negativeCacheTimestamps[cacheKey],
           Date().timeIntervalSince(negativeTimestamp) < negativeCacheTTL {
            result = .noMatch
            return
        }

        isLoading = true
        let outcome = await resolveWithOverallTimeout(query: query)

        guard currentQueryKey == cacheKey, !Task.isCancelled else { return }
        isLoading = false

        switch outcome {
        case .syncedLines, .syncedWords, .plain, .instrumental:
            cache[cacheKey] = outcome
        case .noMatch:
            negativeCacheTimestamps[cacheKey] = Date()
        case .providerFailure:
            break // don't cache outages — a retry a moment later should try again for real
        }
        result = outcome
    }

    private func resolveWithOverallTimeout(query: LyricsQuery) async -> LyricsResult {
        let work = Task { await runProviderChain(query: query) }
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(overallTimeout * 1_000_000_000))
            work.cancel()
        }
        defer { watchdog.cancel() }
        return await withTaskCancellationHandler(
            operation: { await work.value },
            onCancel: { work.cancel() }
        )
    }

    private func runProviderChain(query: LyricsQuery) async -> LyricsResult {
        var lastOutcome: LyricsResult = .noMatch
        for provider in providers {
            if Task.isCancelled { return .providerFailure("Cancelled") }
            do {
                let outcome = try await withProviderTimeout(perProviderTimeout) {
                    try await provider.fetchLyrics(for: query)
                }
                switch outcome {
                case .syncedLines, .syncedWords, .plain, .instrumental:
                    return outcome
                case .noMatch:
                    lastOutcome = outcome
                    continue
                case .providerFailure:
                    lastOutcome = outcome
                    continue
                }
            } catch is CancellationError {
                return .providerFailure("Cancelled")
            } catch let error as LyricsProviderError {
                lastOutcome = .providerFailure("\(provider.name): \(describe(error))")
                continue
            } catch {
                lastOutcome = .providerFailure("\(provider.name): \(error.localizedDescription)")
                continue
            }
        }
        return lastOutcome
    }

    private func describe(_ error: LyricsProviderError) -> String {
        switch error {
        case .timeout: return "timed out"
        case .network(let detail): return detail
        case .malformedResponse(let detail): return detail
        }
    }

    /// Runs `operation` with a hard timeout by racing it against a
    /// cancelling watchdog task, rather than a `TaskGroup` — simpler to
    /// reason about and avoids capturing non-`Sendable` state across a
    /// `@Sendable` closure boundary.
    private func withProviderTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        let work = Task { try await operation() }
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            work.cancel()
        }
        defer { watchdog.cancel() }
        do {
            return try await work.value
        } catch {
            if work.isCancelled { throw LyricsProviderError.timeout }
            throw error
        }
    }
}
