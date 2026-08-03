# Final Pre-CI Completion Report

Date: 2026-08-02

## Status

The implementation is committed and pushed, but the latest GitHub Actions run is not green. The application target compiled successfully in the earlier CI run `30741968092`; the latest run failed before XCTest while resolving an eligible iOS Simulator destination. No IPA was built.

- Branch: `phase-0-real-data-lyrics`
- Latest commit: `c5f5e879f06aafdfe62e891b564c98df956669eb`
- Latest push CI run: [30743023057](https://github.com/hasbenyek/ios-recordlabs/actions/runs/30743023057)
- Latest push CI conclusion: failure, `Build (iOS Simulator, unsigned)` exit code 1 before XCTest
- Earlier application-build result: run `30741968092` built the application successfully; its XCTest command failed with destination exit code 70

## Changed files

The cumulative migration changes from the initial iOS port through the latest commit include:

`.github/workflows/ios-build.yml`, `IMPLEMENTATION_REVIEW.md`, `MIGRATION_AUDIT.md`, `MIGRATION_AUDIT_V2.md`, `README.md`, `project.yml`,

`RecordLabsiOS/App/RootView.swift`, `RecordLabsiOS/Core/LoadState.swift`, `RecordLabsiOS/Info.plist`,

`RecordLabsiOS/Lyrics/LRCParser.swift`, `RecordLabsiOS/Lyrics/LyricsMatcher.swift`, `RecordLabsiOS/Lyrics/LyricsModels.swift`, `RecordLabsiOS/Lyrics/LyricsService.swift`, `RecordLabsiOS/Lyrics/Providers/BetterLyricsProvider.swift`, `RecordLabsiOS/Lyrics/Providers/LrcLibProvider.swift`, `RecordLabsiOS/Lyrics/TTMLParser.swift`,

`RecordLabsiOS/Models/MediaModels.swift`, deleted `RecordLabsiOS/Models/SampleData.swift`,

`RecordLabsiOS/Networking/AudioFormatSelector.swift`, `RecordLabsiOS/Networking/Cipher/CipherDeobfuscator.swift`, `RecordLabsiOS/Networking/InnerTubeClient.swift`, `RecordLabsiOS/Networking/InnerTubeContext.swift`, `RecordLabsiOS/Networking/PlayerResponse.swift`, `RecordLabsiOS/Networking/SearchResponse.swift`, `RecordLabsiOS/Networking/StreamResolver.swift`,

`RecordLabsiOS/Playback/PlaybackState.swift`, `RecordLabsiOS/Playback/PlayerConnection.swift`, `RecordLabsiOS/Playback/PlayerDiagnostics.swift`, `RecordLabsiOS/Resources/Theme.swift`,

`RecordLabsiOS/Views/Home/HomeScreen.swift`, `RecordLabsiOS/Views/Library/LibraryScreen.swift`, `RecordLabsiOS/Views/ListenTogether/ListenTogetherScreen.swift`, `RecordLabsiOS/Views/Player/FullPlayerView.swift`, `RecordLabsiOS/Views/Player/LyricsView.swift`, `RecordLabsiOS/Views/Player/MiniPlayerView.swift`, `RecordLabsiOS/Views/Player/PlayerDiagnosticsView.swift`, `RecordLabsiOS/Views/Player/QueueView.swift`, `RecordLabsiOS/Views/Search/SearchScreen.swift`, `RecordLabsiOS/Views/Shared/EmptyStateView.swift`, `RecordLabsiOS/Views/Shared/ErrorStateView.swift`, `RecordLabsiOS/Views/Shared/SongRow.swift`,

`RecordLabsiOSTests/FormatSelectionTests.swift`, `RecordLabsiOSTests/LRCParserTests.swift`, `RecordLabsiOSTests/LyricsMatcherTests.swift`, `RecordLabsiOSTests/LyricsServiceTests.swift`, `RecordLabsiOSTests/SearchResponseParserTests.swift`, `RecordLabsiOSTests/StreamResolverTests.swift`, `RecordLabsiOSTests/TTMLParserTests.swift`.

## LyricsView integration evidence

- `RecordLabsiOS/Views/Player/FullPlayerView.swift` renders `LyricsView` when `showLyrics` is true:

  ```swift
  if showLyrics {
      LyricsView(song: playerConnection.currentSong,
                 currentTime: playerConnection.position)
  }
  ```

- The lyrics button toggles `showLyrics` in the same view.
- `PlayerConnection.position` is `@Published` and is updated by `AVPlayer.addPeriodicTimeObserver` every 0.5 seconds.
- `LyricsView` owns `LyricsService` with `@StateObject`, so the service is stable across body evaluations.
- `LyricsView` uses `.task(id: song?.id)`, and `LyricsService.resolveWithOverallTimeout` now cancels its internal provider task through `withTaskCancellationHandler`.
- The refresh button calls `refresh()` with `forceRefresh: true`.
- The offset slider binds to `service.timingOffsetSeconds`; active-line calculation uses `currentTime + timingOffsetSeconds`, and word highlighting uses the same adjusted time.

## Tests

Current source contains 47 XCTest methods. The 25 newly added tests are:

### LyricsMatcherTests.swift

- `testExactTitleArtistMatch`
- `testNormalizedTitleMatch`
- `testWrongArtistRejected`
- `testExcessiveDurationDifferenceRejected`
- `testCloseDurationMatchAccepted`

### LyricsServiceTests.swift

- `testBetterLyricsSuccessPreventsLRCLIBCall`
- `testBetterLyricsNoMatchFallsBackToLRCLIB`
- `testBetterLyricsProviderFailureFallsBackToLRCLIB`
- `testPerProviderTimeoutFallsBackCorrectly`
- `testOverallTimeoutReturnsControlledResult`
- `testCancellingLoadPreventsResultPublication`
- `testStaleResponseCannotOverwriteNewerTrack`
- `testPositiveCacheIsReused`
- `testNegativeCacheCanBeBypassedByForceRefresh`
- `testProviderOutageIsNotNegativeCached`

### SearchResponseParserTests.swift

- `testValidSongRendererIsAccepted`
- `testMissingVideoIdIsRejected`
- `testMissingTitleIsRejected`
- `testMissingArtistIsRejected`
- `testMalformedJSONReturnsControlledParseFailure`
- `testDuplicateVideoIdsAreDeduplicated`
- `testClearlyNonSongRendererIsNotEmittedAsSong`

### StreamResolverTests.swift

- `testUnsupportedFormatInOneClientContinuesToNextClient`
- `testDecodeFailureContinuesToNextClient`
- `testAllClientsFailProducesStreamResolutionFailure`

The existing 22 tests remain in `FormatSelectionTests.swift`, `LRCParserTests.swift`, and `TTMLParserTests.swift`. All new network-facing tests use local mock providers, fixtures, or an injected `StreamResolverClient`; XCTest does not call BetterLyrics, LRCLIB, YouTube, or any other live service.

## CI results and warnings

- XcodeGen completed successfully in the earlier runs.
- The application target compiled successfully in run `30741968092`.
- XCTest did not produce a pass result. Run `30741968092` and subsequent destination attempts failed in the CI test step with simulator destination/setup errors (exit 70 or exit 1), before a trustworthy XCTest result was available.
- No compiler warnings were reported by the available CI annotations.
- Non-compiler warnings reported by GitHub: Homebrew tap trust warnings and `actions/checkout@v4` Node 20 deprecation warning.

## Remaining blockers

1. GitHub Actions `macos-latest` is not exposing a destination that the current Xcode-generated scheme accepts for `xcodebuild test`. The final attempted selector was `xcodebuild -showdestinations` plus an Xcode-eligible simulator UUID; the latest run still failed before XCTest.
2. Because XCTest has not completed in CI, the 47-test suite is source-complete but not CI-verified.
3. Real stream resolution, provider availability, signed URL expiry, YouTube client behavior, and synchronized lyrics behavior on an actual iPhone remain runtime-only uncertainties.

Playback and real lyrics are not claimed as verified on iPhone. Device validation still requires the user’s sideloaded build and real-device testing.
