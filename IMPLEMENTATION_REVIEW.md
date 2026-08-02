# Implementation Completion Review

This review is based on the current repository contents. No source file was changed while producing this document.

## 1. SampleData removal

The placeholder source file was deleted:

- `RecordLabsiOS/Models/SampleData.swift` — deleted; it previously defined `enum SampleData` with fabricated artists, songs, albums, and playlists.

The remaining preview locations now use empty or `nil` state instead of fixture data:

- `RecordLabsiOS/Views/Player/QueueView.swift`
  - Modified function/body context: `#Preview`.
  - Evidence:

    ```swift
    #Preview {
        QueueView().environmentObject(PlayerConnection())
    }
    ```

- `RecordLabsiOS/Views/Player/MiniPlayerView.swift`
  - Modified function/body context: `#Preview`.
  - Evidence:

    ```swift
    #Preview {
        return VStack {
            Spacer()
            MiniPlayerView(isExpanded: .constant(false))
                .environmentObject(PlayerConnection())
        }
    }
    ```

- `RecordLabsiOS/Views/Player/FullPlayerView.swift`
  - Modified function/body context: `#Preview`.
  - Evidence:

    ```swift
    #Preview {
        return FullPlayerView(isExpanded: .constant(true))
            .environmentObject(PlayerConnection())
    }
    ```

- `RecordLabsiOS/Views/Player/LyricsView.swift`
  - Modified function/body context: `#Preview`.
  - Evidence:

    ```swift
    #Preview {
        ZStack {
            Color.black.ignoresSafeArea()
            LyricsView(song: nil, currentTime: 0)
        }
    }
    ```

Repository evidence: searching `RecordLabsiOS` and `RecordLabsiOSTests` for `SampleData` returns no matches. No production runtime reference remains.

## 2. Search

### Endpoint and request

- `RecordLabsiOS/Views/Search/SearchScreen.swift`
  - Modified function: `runSearch(_:)`.
  - Evidence:

    ```swift
    let data = try await InnerTubeClient.shared.search(query: text)
    let parsed = SearchResponseParser.parseSongs(from: data)
    ```

- `RecordLabsiOS/Networking/InnerTubeClient.swift`
  - Modified function: `search(query:identity:)`.
  - Evidence:

    ```swift
    func search(query: String, identity: YouTubeClientIdentity = .webRemix) async throws -> Data {
        let body = SearchRequestBody(..., query: query, params: nil)
        return try await request(path: "search", identity: identity, body: body)
    }
    ```

  - `request(path:identity:body:)` sends a POST to `YouTubeClientIdentity.apiURL.appendingPathComponent(path)` with YouTube Music headers and JSON body.

### Parser and Song mapping

- `RecordLabsiOS/Networking/SearchResponse.swift`
  - Modified function: `SearchResponseParser.parseSongs(from:)`.
  - The parser recursively walks the JSON renderer tree using `walk(_:,visit:)` and reads `musicResponsiveListItemRenderer`.
  - Evidence:

    ```swift
    guard let renderer = node["musicResponsiveListItemRenderer"] as? [String: Any] else { return }
    guard let videoId = extractVideoId(renderer) else {
        skippedNoVideoId += 1
        return
    }
    guard let title = extractTitle(renderer), !title.isEmpty else {
        skippedNoTitle += 1
        return
    }
    ```

  - Song construction maps actual parsed values:

    ```swift
    Song(
        id: videoId,
        title: title,
        artists: [ArtistRef(id: subtitle.artistId ?? artistName, name: artistName)],
        album: subtitle.album.map { AlbumRef(id: subtitle.albumId ?? $0, title: $0) },
        duration: duration,
        thumbnailURL: extractThumbnail(renderer),
        isExplicit: hasExplicitBadge(renderer)
    )
    ```

  - Artist filtering is also explicit:

    ```swift
    guard let artistName = subtitle.artist, !artistName.isEmpty else {
        skippedNoArtist += 1
        return
    }
    ```

Songs without a real `navigationEndpoint.watchEndpoint.videoId` are rejected before `Song` creation. The parser records the count in `ParseResult.diagnostics`.

## 3. Playback

### StreamResolver

- `RecordLabsiOS/Networking/StreamResolver.swift`
  - Modified functions: `resolveStreamURL(videoId:)`, `resolveDirect(videoId:identity:attempted:formatsSeen:)`, and `resolveViaCipher(videoId:attempted:formatsSeen:)`.
  - The resolver returns `ResolvedStream`, containing the playable URL and non-sensitive `StreamDiagnostics`.

### Format, MIME, and codec filtering

- `RecordLabsiOS/Networking/AudioFormatSelector.swift`
  - Modified function: `selectBest(from:)`.
  - Evidence:

    ```swift
    formats
        .filter { $0.isAudioOnly && $0.isAACCompatible }
        .sorted { lhs, rhs in
            let lRank = qualityRank(lhs.audioQuality)
            let rRank = qualityRank(rhs.audioQuality)
            if lRank != rRank { return lRank > rRank }
            return lhs.bitrate > rhs.bitrate
        }
        .first
    ```

- `RecordLabsiOS/Networking/PlayerResponse.swift`
  - Modified properties: `Format.container`, `Format.codec`, `Format.isAudioOnly`, and `Format.isAACCompatible`.
  - Evidence:

    ```swift
    var isAudioOnly: Bool {
        mimeType.hasPrefix("audio/") && width == nil
    }

    var isAACCompatible: Bool {
        container == "audio/mp4" && (codec?.hasPrefix("mp4a") ?? false)
    }
    ```

This rejects video-only formats, WebM, Opus, malformed MIME values, and non-AAC codecs. Quality rank is primary; bitrate only breaks ties.

### Fallback order

- `RecordLabsiOS/Networking/YouTubeClientIdentity.swift`
  - Modified property: `directURLFallbackOrder`.
  - Evidence:

    ```swift
    static let directURLFallbackOrder: [YouTubeClientIdentity] = [
        .visionOS, .androidVR, .tvEmbedded,
    ]
    ```

- `RecordLabsiOS/Networking/StreamResolver.swift`
  - The resolver tries those direct clients in order, then `.androidMobile` through cipher handling:

    ```swift
    for identity in YouTubeClientIdentity.directURLFallbackOrder { ... }
    attemptedClients.append(YouTubeClientIdentity.androidMobile.clientName)
    if let resolved = try await resolveViaCipher(...) { return resolved }
    ```

Direct clients only accept formats with a direct URL and no `signatureCipher`. Android formats may use either a direct URL or cipher URL.

### Error classification

- `RecordLabsiOS/Playback/PlaybackState.swift`
  - Modified enum: `PlayerError`.
  - Cases: `.unsupportedFormat`, `.network`, `.cipherFailure`, and `.streamResolutionFailure`.
- `RecordLabsiOS/Playback/PlayerConnection.swift`
  - Modified function: `applyResolutionFailure(_:for:)`.
  - It maps each `PlayerError` to the matching visible `PlaybackState` and diagnostic category (`unsupported_format`, `network`, `cipher`, or `resolution`).

## 4. Lyrics

### Protocol and models

- `RecordLabsiOS/Lyrics/LyricsModels.swift`
  - Modified protocol: `LyricsProvider`.
  - Evidence:

    ```swift
    protocol LyricsProvider {
        var name: String { get }
        func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult
    }
    ```

  - `LyricsResult` distinguishes synced lines, word-synced lines, plain text, instrumental, provider failure, and no match.

### BetterLyrics

- `RecordLabsiOS/Lyrics/Providers/BetterLyricsProvider.swift`
  - Modified function: `fetchLyrics(for:)`.
  - Endpoint: `https://lyrics-api.boidu.dev/getLyrics`.
  - It sends title (`s`), artist (`a`), optional duration (`d`), and album (`al`), decodes `ttml`, then calls `TTMLParser.parse(ttml)`.
  - It returns `.syncedWords` when parsed lines contain word timing, otherwise `.syncedLines`; 404/empty TTML returns `.noMatch`.

### LRCLIB

- `RecordLabsiOS/Lyrics/Providers/LrcLibProvider.swift`
  - Modified functions: `fetchLyrics(for:)`, `search(_:)`, `pickBest(_:query:)`, and `result(for:)`.
  - Endpoint: `https://lrclib.net/api/search`.
  - It tries track+artist, free-text, then title-only searches. Candidates are scored by `LyricsMatcher`; candidates below `minimumAcceptableConfidence` are rejected. Synced lyrics use `LRCParser`; plain lyrics use `.plain`; instrumental results use `.instrumental`.

### Fallback, timeout, cancellation, and cache

- `RecordLabsiOS/Lyrics/LyricsService.swift`
  - Modified functions: `load(for:forceRefresh:)`, `resolveWithOverallTimeout(query:)`, `runProviderChain(query:)`, and `withProviderTimeout(_:operation:)`.
  - Provider fallback is sequential in the initializer:

    ```swift
    providers: [LyricsProvider] = [BetterLyricsProvider(), LrcLibProvider()]
    ```

  - `runProviderChain` continues after `.noMatch` and `.providerFailure`, returning the first successful lyrics result.
  - Overall timeout creates provider work and a watchdog; the watchdog cancels work after `overallTimeout`.
  - Each provider call gets its own watchdog using `perProviderTimeout` and `work.cancel()`.
  - Cancellation is checked in the provider loop and caught as `CancellationError`; `load` also guards `!Task.isCancelled`.
  - Positive cache:

    ```swift
    private var cache: [String: LyricsResult] = [:]
    if !forceRefresh, let cached = cache[cacheKey] { result = cached; return }
    ```

  - Negative `.noMatch` results use `negativeCacheTimestamps` with a five-minute TTL. Provider outages are deliberately not cached.
  - Synchronization against stale responses uses `currentQueryKey`, keyed by `LyricsQuery.videoId`; older responses cannot overwrite a newer track.

### Parsers

- `RecordLabsiOS/Lyrics/TTMLParser.swift`
  - Modified function: `parse(_:)`, plus `appendLines`, `wordsAndText`, `wordSpan`, and `parseTime`.
  - Uses `Foundation.XMLParser` and a minimal `XMLNode` tree. It parses line timing, word timing, background vocals, agents, offsets, and warnings. Untimed lines are retained with `isTimingInferred = true`; malformed XML returns empty lines plus a warning.
- `RecordLabsiOS/Lyrics/LRCParser.swift`
  - Modified function: `parse(_:)`, plus timestamp extraction and metadata/offset handling.
  - Parses standard timestamps, multiple timestamps per line, `[offset:]`, malformed timestamps with warnings, and retains untimed text with inferred timing.

## 5. Player UI

- `RecordLabsiOS/Views/Player/LyricsView.swift`
  - Modified functions: `body`, `syncedList(_:)`, `activeLineIndex(_:time:)`, `lineView(_:isActive:time:)`, `wordHighlightedText(_:time:isActive:)`, `load()`, and `refresh()`.
  - Lyrics are loaded from the real current `Song` with `.task(id: song?.id)`:

    ```swift
    .task(id: song?.id) {
        await load()
    }
    ```

  - Active line selection advances to the last line whose `startTime` is at or before playback time:

    ```swift
    if line.startTime <= time {
        result = index
    } else {
        break
    }
    ```

  - Active lines use bold/larger white text; inactive/background lines use reduced opacity. Word-synced lyrics brighten words after their `startTime`.
  - Auto-scroll uses `ScrollViewReader`, `proxy.scrollTo(..., anchor: .center)`, and pauses for three seconds after a drag gesture.
  - Loading state: `ProgressView("Finding lyrics…")`.
  - Error state: `ErrorStateView(title: "Lyrics unavailable", ...)` with a retry action calling `refresh()`.

## 6. Tests

The XCTest target is `RecordLabsiOSTests`, included by `project.yml` and dependent on the application target.

Files and test names:

- `RecordLabsiOSTests/FormatSelectionTests.swift` — 6 tests:
  - `testAACPreferredOverWebM`
  - `testOnlyWebMIsUnsupported`
  - `testVideoOnlyEntriesAreExcluded`
  - `testMalformedMimeTypeIsRejectedSafely`
  - `testHigherQualityTierBeatsHigherBitrateInLowerTier`
  - `testBitrateBreaksTiesWithinSameQualityTier`
- `RecordLabsiOSTests/LRCParserTests.swift` — 8 tests:
  - `testStandardTimestamps`
  - `testMultipleTimestampsOnOneLine`
  - `testMalformedTimestampIsNotDefaultedToZero`
  - `testEmptyLyrics`
  - `testDuplicateTimestampsAreBothKept`
  - `testOffsetHandling`
  - `testUntimedLineIsKeptNotDropped`
  - `testMetadataTagsAreNotTreatedAsLyrics`
- `RecordLabsiOSTests/TTMLParserTests.swift` — 8 tests:
  - `testLineLevelTiming`
  - `testWordLevelTiming`
  - `testBackgroundVocals`
  - `testMultipleAgentsDoNotCollapse`
  - `testMalformedXMLReturnsEmptyWithWarning`
  - `testUntimedLineIsKeptNotDropped`
  - `testInvalidTimingValueIsNotDefaultedToZero`
  - `testNestedWordLevelSpansInsideBackground`

Current test count: **22 XCTest methods**.

## 7. Build readiness

### Working-tree files modified or added by the migration

- `.github/workflows/ios-build.yml`
- `README.md`
- `project.yml`
- `MIGRATION_AUDIT.md`
- `MIGRATION_AUDIT_V2.md`
- `RecordLabsiOS/App/RootView.swift`
- `RecordLabsiOS/Core/LoadState.swift`
- `RecordLabsiOS/Lyrics/LRCParser.swift`
- `RecordLabsiOS/Lyrics/LyricsMatcher.swift`
- `RecordLabsiOS/Lyrics/LyricsModels.swift`
- `RecordLabsiOS/Lyrics/LyricsService.swift`
- `RecordLabsiOS/Lyrics/Providers/BetterLyricsProvider.swift`
- `RecordLabsiOS/Lyrics/Providers/LrcLibProvider.swift`
- `RecordLabsiOS/Lyrics/TTMLParser.swift`
- `RecordLabsiOS/Networking/AudioFormatSelector.swift`
- `RecordLabsiOS/Networking/Cipher/CipherDeobfuscator.swift`
- `RecordLabsiOS/Networking/Cipher/CipherWebView.swift`
- `RecordLabsiOS/Networking/Cipher/FunctionNameExtractor.swift`
- `RecordLabsiOS/Networking/Cipher/PlayerConfig.swift`
- `RecordLabsiOS/Networking/Cipher/PlayerJsFetcher.swift`
- `RecordLabsiOS/Networking/InnerTubeClient.swift`
- `RecordLabsiOS/Networking/PlayerResponse.swift`
- `RecordLabsiOS/Networking/SearchResponse.swift`
- `RecordLabsiOS/Networking/YouTubeClientIdentity.swift`
- `RecordLabsiOS/Playback/PlaybackState.swift`
- `RecordLabsiOS/Playback/PlayerConnection.swift`
- `RecordLabsiOS/Playback/PlayerDiagnostics.swift`
- `RecordLabsiOS/Resources/Theme.swift`
- `RecordLabsiOS/Views/Home/HomeScreen.swift`
- `RecordLabsiOS/Views/Library/LibraryScreen.swift`
- `RecordLabsiOS/Views/Player/FullPlayerView.swift`
- `RecordLabsiOS/Views/Player/LyricsView.swift`
- `RecordLabsiOS/Views/Player/MiniPlayerView.swift`
- `RecordLabsiOS/Views/Player/PlayerDiagnosticsView.swift`
- `RecordLabsiOS/Views/Player/QueueView.swift`
- `RecordLabsiOS/Views/Search/SearchScreen.swift`
- `RecordLabsiOS/Views/Shared/ErrorStateView.swift`
- `RecordLabsiOS/Views/Shared/SongRow.swift`
- `RecordLabsiOSTests/FormatSelectionTests.swift`
- `RecordLabsiOSTests/LRCParserTests.swift`
- `RecordLabsiOSTests/TTMLParserTests.swift`
- `RecordLabsiOS/Models/SampleData.swift` — deleted.

### Remaining TODO/FIXME/placeholder markers

There are no `TODO` or `FIXME` markers in the current `RecordLabsiOS`, `RecordLabsiOSTests`, or `project.yml` source search.

The word `placeholder` still exists in non-runtime UI/documentation contexts:

- `RecordLabsiOS/Core/LoadState.swift` — documentation describing the forbidden fallback behavior.
- `RecordLabsiOS/Lyrics/LyricsService.swift` and `RecordLabsiOS/Views/Shared/ErrorStateView.swift` — documentation stating that placeholder/mock content is not used.
- `RecordLabsiOS/Resources/Theme.swift` — `placeholderTile` is a visual artwork loading fallback, not sample song data.

The iOS build and XCTest commands were not executed in this Windows environment because Xcode/xcodebuild is unavailable. The CI workflow contains both simulator build and XCTest commands for macOS validation.
