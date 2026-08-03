# Record Labs Android → iOS Migration Audit

**Date:** 2026-08-02
**Scope:** Read-only audit. Android app at `../3` (package `com.recordlabs.music`, a rebranded fork of the open-source **Metrolist** project — proof: `PlayerConfigStore.kt` fetches cipher config from `raw.githubusercontent.com/MetrolistGroup/Metrolist/...`, and root-level `patch_controls.py`/`patch_queue.py`/`temp_controls.txt`/`Player_backup.kt` are leftover dev-scratch files from the `com.metrolist.music` → `com.recordlabs.music` rename). iOS app at `RecordLabsiOS/` (SwiftUI, ~25 files, iOS 15+, XcodeGen-generated project).
**Classification legend:** Confirmed from source · Partially confirmed · Inferred · Missing · Dummy · Broken · Technically unstable.
**Context:** private, non-commercial, personally-sideloaded app. Unofficial integrations are evaluated on "can this function when sideloaded," not App Store eligibility.

---

## Table of Contents
1. Complete Android feature inventory
2. Screen and navigation inventory
3. Player architecture and exact playback flow
4. Search and streaming request flow
5. InnerTube client context, headers, endpoints, parsers, stream URL resolution
6. Authentication and cookie handling
7. Audio format selection logic
8. Expiring URL handling
9. Queue, radio, autoplay, repeat, shuffle behavior
10. Background playback and media controls
11. Lyrics retrieval and provider priority
12. LRC, enhanced LRC, and TTML parsing
13. Translation and romanization flow
14. Database entities and migrations
15. Last.fm, Discord, recognition, and other integrations
16. Settings and persistence
17. Error, loading, offline, cancellation, retry behavior
18. Security-sensitive values / hardcoded secrets
19. Features currently implemented in iOS
20. Features that are only visual or dummy in iOS
21. Incorrect architectural decisions in the iOS project
22. Reusable iOS code vs. code that should be replaced
23. Native iOS equivalents for Android-specific components
24. Missing information and blockers
25. Recommended iOS architecture
26. Feature-by-feature migration order
27. Dependency map
28. Files to retain or discard in the current iOS project
29. Acceptance criteria per phase
30. Open questions requiring your decision

---

## 1. Complete Android Feature Inventory

**Confirmed from source.** Everything a user can do, by area:

- **Browse/discover**: personalized Home feed (quick picks, keep listening, forgotten favorites, similar-artist recs, daily discover, community playlists, mood/genre shortcuts, speed-dial pins, official podcast rows, YTM home sections, pull-to-refresh, randomize order), Explore/Charts (partially orphaned — see §2.3), New Release albums.
- **Search**: on-device library search + online YTM search with autocomplete.
- **Library**: Playlists/Songs/Albums/Artists/Podcasts tabs; sync liked/uploaded/library songs with account.
- **Detail pages**: Album/Artist/Playlist/Podcast, with play/shuffle/queue/add-to-playlist/download/share, explicit/video-song hiding.
- **Local playlists**: create, rename, drag-reorder, cropped custom thumbnail, delete, CSV/M3U import.
- **Auto-playlists**: Liked Songs, Downloaded Songs, Cached Songs, Top-N Most Played.
- **History & Stats**: listen history (search/filter/multi-select delete), stats screen (top playlists, song-stat merge tool), Wrapped year-in-review (full animated story flow + generated playlist).
- **Account**: WebView-based YouTube Music login (cookie capture), account content browser.
- **Deep links**: YT/YTM URLs (playlist/browse/channel/search/watch), `listen://` room-join links, widget-target links, recognition links.
- **Playback**: full player + mini player, queue management, radio/autoplay, shuffle, repeat, crossfade, gapless, loudness normalization, custom parametric equalizer (+ AutoEQ community-preset wizard), sleep timer (manual + scheduled), music alarm ("wake with playlist"), background playback, lock-screen/notification controls, Android Auto media-browser tree, Chromecast (GMS flavor only).
- **Lyrics**: multi-provider fetch with fallback chain, word-level karaoke sync, on-device romanization, AI-powered translation.
- **Downloads/offline**: ExoPlayer-based download manager, separate streaming vs. offline caches.
- **Integrations**: Last.fm scrobbling/now-playing, Discord Rich Presence, Shazam-style music recognition, Listen Together (synced group listening).
- **Widgets**: playback-control widget, "turntable" widget, playlist-target widget, recognition widget.
- **Quick Settings tile**: recognition trigger (not playback — confirmed no playback QS tile exists).
- **Settings**: appearance/theming, content/language, AI translation config, player/audio, stream-source toggles, Android Auto, privacy, storage, backup/restore, per-integration settings, about.
- **Crash reporting UX**: dedicated crash screen with copy/share stack trace.
- **Build flavors**: `gms` (real Chromecast), `foss`/`izzy` (Cast stubbed out) — the *only* flavor divergence in the whole app.

---

## 2. Screen and Navigation Inventory

**Confirmed from source.** Single-Activity app (`MainActivity`) hosting one Compose `NavHost`; only `CrashActivity` and `RecognitionLaunchActivity` are separate Activities.

**Bottom nav (4 tabs, `Screens.kt`):** Home (`home`) · Search (`search_input`) · Listen Together (`listen_together`, or moved to a top-bar icon via `ListenTogetherInTopBarKey`) · Library (`library`).

**Full route table** (registered in `NavigationBuilder.kt`): `home`, `search_input`, `library`, `listen_together[_from_topbar]`, `history`, `stats`, `mood_and_genres`, `account`, `new_release`, `charts_screen`, `browse/{browseId}`, `search/{query}`, `album/{albumId}`, `artist/{artistId}?isPodcastChannel=`, `artist/{artistId}/songs|albums|items`, `online_playlist/{id}`, `online_podcast/{id}`, `local_playlist/{id}`, `auto_playlist/{playlist}` (liked/downloaded), `cache_playlist/{playlist}`, `top_playlist/{top}`, `youtube_browse/{browseId}?params=`, `settings` + 15 sub-routes (appearance, appearance/theme, content, content/romanization, ai, player, stream_sources, storage, privacy, backup_restore, integrations[+discord/lastfm/listen_together], about, android_auto), `login`, `wrapped`, `equalizer`, `eq_wizard`, `recognition?autoStart=`, `recognition_history`.

**Dead/orphaned routes (Confirmed):** `ExploreScreen.kt` is never invoked and not registered as a destination; it's the *only* caller of `navigate("new_release")`, and nothing calls `navigate("charts_screen")`. Both routes exist but have no live UI entry point — Home appears to have absorbed the equivalent content. **Don't port `ExploreScreen` as-is** without a product decision.

**Deep links** are hand-parsed in `MainActivity.handleDeepLinkIntent` (not `navDeepLink{}` DSL): YT/YTM playlist/browse/channel/search/watch URL patterns, `listen://` room-join, widget-target intent, recognition intent. Fully documented, directly portable rules — just needs Swift reimplementation via Universal Links / custom URL scheme.

**Back-stack:** standard multi-back-stack bottom-nav semantics (`popUpTo(start){saveState} + launchSingleTop + restoreState`); double-tap-active-tab scrolls to top instead of navigating. `wrapped` route hides all chrome (immersive). Per-tab slide+fade transitions; `search/{query}}` has its own fade/slide (with same-route chaining special-cased).

**DI (Hilt, 5 files total in `di/`):** `AppModule` (app-scope CoroutineScope, Room DB, ExoPlayer cache providers, ListenTogether client/manager), `NetworkModule` (connectivity observer), `Qualifiers`, `WrappedModule`, `LyricsHelperEntryPoint`. Minimal — maps cleanly onto a lightweight iOS DI approach (small container / `@Environment`), no need to replicate Hilt's module structure.

**~35 ViewModels**, one per screen (or a handful grouped per file, e.g. `LibraryViewModels.kt`), all `@HiltViewModel`. `WrappedViewModel` (in `ui/screens/wrapped/`) is an **unreferenced empty stub** — Wrapped state actually flows through `WrappedManager` via `LocalWrappedManager`. Flag as dead code, don't port.

---

## 3. Player Architecture and Exact Playback Flow

**Confirmed from source.** Core: `playback/MusicService.kt` (4,780 lines) — `MediaLibraryService` + `Player.Listener` + `PlaybackStatsListener.Callback`, wrapping a single `lateinit var player: ExoPlayer`. `PlayerConnection.kt` is the UI-facing façade, bound **in-process** via a `Binder` (not `MediaController` IPC) — UI and playback engine share one process, so there's no "remote" indirection to replicate on iOS.

**MediaItem construction** (`extensions/MediaItemExt.kt`): a cheap placeholder — `setUri(videoId)` (not a playable URL yet!), app's own `MediaMetadata` stashed as the item's `tag`. **The real stream URL is resolved lazily**, only when ExoPlayer's data source actually requests bytes. This two-phase design (placeholder item → lazy async resolve) is the single most important thing to replicate in an `AVPlayer`/`AVAssetResourceLoader` port.

**Stream resolution** (`ResolvingDataSource.Factory` callback, `MusicService.kt:3650`): cache chain (quality-bypass flag → download cache → streaming cache → 500-entry in-memory `songUrlCache` LRU) → on miss, `YTPlayerUtils.playerResponseForPlayback()` (the InnerTube network call, runs `runBlocking(Dispatchers.IO)` on the loading thread) → persists `FormatEntity` → caches URL+expiry → rewrites the `DataSpec` URI.

**Exact flow, tap-to-audio:**
1. `PlayerConnection.togglePlayPause()` → `player.togglePlayPause()` (or `prepare()` first if `STATE_IDLE`).
2. `prepare()` → ExoPlayer builds a `MediaSource`, opens the custom `DataSource` chain.
3. `ResolvingDataSource` callback resolves the real CDN URL as above (cache or fresh InnerTube `/player` call + format selection, §7).
4. `DefaultMediaSourceFactory`'s extractors (Matroska/WebM or Fragmented-MP4) demux; ExoPlayer decodes.
5. `playWhenReady=true`; once buffered ~750ms (custom `LoadControl`), state → `STATE_READY`.
6. `onEvents` requests audio focus, opens the audio-effect session.
7. **Audio processor chain runs on every PCM buffer**, in order: `VolumeNormalizationAudioProcessor` (manual ReplayGain-style gain, computed from `FormatEntity.perceptualLoudnessDb`/`loudnessDb`) → `CustomEqualizerAudioProcessor` (manual biquad cascade + preamp) → `SilenceDetectorAudioProcessor` (instant-skip trigger) → media3's `SilenceSkippingAudioProcessor` → `SonicAudioProcessor` (speed/pitch).
8. `AudioTrack` writes to the active OS audio route.
9. `MediaSession` reflects state to system (notification/lock-screen/Auto/Wear).
10. Side effects fire: scrobble start (Last.fm), widget refresh, Discord RPC sync, crossfade scheduling, EQ-instant-apply seek nudge.

**Audio focus** (`MusicService.kt:1375-1483`): ExoPlayer's own focus handling is disabled; manual `AudioFocusRequest` — GAIN resumes after a 300ms debounce, LOSS pauses+abandons, LOSS_TRANSIENT pauses, LOSS_TRANSIENT_CAN_DUCK sets a 20% volume multiplier (no pause). Effective volume = `user_volume × mute × sleepTimerFade × focusDuck`. **iOS: `AVAudioSession` category `.playback` + `interruptionNotification`, manual ducking via `AVPlayer.volume`** (no native "duck" concept on iOS — must reimplement this exact multiplier chain). Bluetooth-connect auto-resume via `AudioDeviceCallback` → iOS: `routeChangeNotification` reason `.newDeviceAvailable`. Becoming-noisy is delegated to ExoPlayer's built-in handling → iOS: `routeChangeNotification` reason `.oldDeviceUnavailable`.

**Seek-to-previous UX detail**: if `currentPosition > 3000ms` OR no previous item, restarts the current track instead of going back — this 3-second threshold must be replicated exactly. Note: **widget skip-previous bypasses this** (calls `player.seekToPrevious()` directly, not through `PlayerConnection`) — a possible existing inconsistency, worth deciding whether to preserve or fix in the port.

**Error/retry** (`MusicService.kt:1477-3353`): typed error classification (expired URL/403, range-not-satisfiable/416, YouTube "page reload," network, renderer, file-not-found, remote) each with dedicated handlers; per-song retry cap 3 (`MAX_RETRY_PER_SONG`), exponential backoff 3s→30s cap (`MAX_RETRY_COUNT=10`), hard-stops auto-advance after 5 consecutive errors.

**Crossfade/gapless** (`MusicService.kt:4546-4740`) — **not** native ExoPlayer transitions; a **dual-ExoPlayer-instance** architecture: a `secondaryPlayer` is created, seeked to the next track, started at volume 0 in parallel, then a 20-step quadratic-ease coroutine ramps volumes and promotes it to be the new `player` (re-attaching `MediaSession`, manually re-firing `onMediaItemTransition`). Gapless detection is a heuristic (same non-null `albumTitle` on current+next ⇒ skip crossfade). **This is one of the highest-effort ports** — no `AVQueuePlayer` equivalent; would need two `AVPlayer`s + manual volume ramping (`CADisplayLink`/`Timer`) or `AVAudioEngine` mixing.

**Equalizer DSP** (`eq/audio/CustomEqualizerAudioProcessor.kt` + `BiquadFilter.kt`): pure manual biquad math over raw PCM `ByteBuffer`s, **no Android-specific dependency** (not `android.media.audiofx.Equalizer`) — good news: it's portable algorithmically to `AVAudioEngine`/`AVAudioUnitEQ` or a custom `AVAudioSourceNode` tap. AutoEQ-format parametric bands (PK/LSC/HSC filter types), ≤20 bands, preamp gain. `BiquadFilter.kt` internals and `EQProfileRepository`/`GitHubAutoEqSearch`/`ParametricEQParser` were **not read in this pass — flagged as follow-up** if exact persistence/AutoEQ-parsing needs porting.

**Sleep timer** (`playback/SleepTimer.kt`): manual start (minutes, or -1 = "stop after current song"), 60-second linear fade-out window, plus a fully separate **scheduled/automatic** sleep timer (day-of-week + time-window driven, `PlayerConnection.checkAndStartAutomaticSleepTimer()`), auto-arming on every paused→playing transition if the current time matches the configured window.

**Music Alarm** ("wake me with this playlist"): `AlarmManager.setExactAndAllowWhileIdle` + device-protected-storage `SharedPreferences` (survives pre-unlock/Direct Boot) + `MusicAlarmRescheduleReceiver` re-arming on boot/clock-change. **`handleAlarmTrigger`'s body was not read in this pass** (Partially confirmed). **Major iOS platform-gap**: there is no iOS equivalent of "wake device and autonomously start audio playback from a suspended app" — `UNUserNotificationCenter` triggers can only post a notification, not start playback. This needs explicit design discussion, not a straight port.

**Background playback & media controls**: standard media3 `MediaSession`/notification/lock-screen integration; full Android Auto media-browser tree (`MediaLibrarySessionCallback.onGetLibraryRoot/onGetChildren`, configurable section order); headset buttons delegated to `MediaButtonReceiver` (default media3 handling, not independently verified); foreground-service lifecycle hardened against Android 12+/14+ background-start restrictions.

**Widgets** (`widget/`): main music widget (2×2/4×1/full, `RemoteViews`, thin intent-forwarder — real logic lives in `MusicService.onStartCommand`), "turntable" widget, playlist-target widget, recognition widget (separate, not playback). **iOS: WidgetKit + App Intents / Live Activities** — no code-level port, behavioral parity only.

**Quick Settings tile**: recognition-only (launches `RecognitionLaunchActivity`) — **there is no playback QS tile**; correct any assumption otherwise.

**Chromecast**: `gms` flavor has a full `CastConnectionHandler` (779 lines, real `com.google.android.gms.cast.*`, bidirectional sync guards, lookahead queue building); `foss`/`izzy` flavors carry byte-for-byte-identical **57-line stubs** with the same public API surface (`initialize()→false`, no-op methods). Clean precedent for how to gate Cast on iOS too (protocol + no-op default vs. a real Google Cast iOS SDK integration).

**`Player_backup.kt` (repo root)**: confirmed git-ignored (`.gitignore:122`), never committed, an older uncommitted developer scratch snapshot of `ui/player/Player.kt` missing several current features (Listen Together guest gating, lyrics-page header, etc.). **Not part of the build. Ignore for migration purposes.**

---

## 4-6. Search/Streaming Flow, InnerTube Client, Auth & Cookies

**Confirmed from source. Technically unstable by nature** (reverse-engineered private API, no SLA, breaks silently on Google changes).

### Client contexts (`innertube/models/YouTubeClient.kt`)
13 distinct spoofed client identities, each with `clientName`/`clientId`/`clientVersion`/`userAgent` and capability flags (`loginSupported`, `useSignatureTimestamp`, `useWebPoTokens`). Key ones: **`WEB_REMIX`** (`clientId=67`, main client for search/browse/primary playback, needs sig-timestamp + PoToken), **`VISIONOS`** (`clientId=101`, internal/unreleased Apple client — "no spc throttle gate," first-choice fallback because it needs *no* cipher/PoToken), **`ANDROID`/MOBILE** (needs sig-timestamp, no PoToken), plus `TVHTML5_SIMPLY_EMBEDDED_PLAYER`, `ANDROID_VR` (3 variants), `IOS`/`IPADOS`, `WEB_CREATOR`, `ANDROID_CREATOR`, `TVHTML5`. All defined `https://music.youtube.com/youtubei/v1/`-scoped.

### Headers (every request, `InnerTube.kt:ytClient()`)
`X-Goog-Api-Format-Version: 1`, `X-YouTube-Client-Name: <clientId>`, `X-YouTube-Client-Version`, `X-Origin: https://music.youtube.com`, `Referer: https://music.youtube.com/`, `X-Goog-Visitor-Id` (if set), `User-Agent`, `Content-Type: application/json`, `?prettyPrint=false`; when logged in + client supports login: `cookie` + `Authorization: SAPISIDHASH <ts>_<sha1>`.

### Endpoints (all under `/youtubei/v1/`)
`search`, `player`, `browse`, `next`, `feedback`, `music/get_search_suggestions`, `music/get_queue`, `get_transcript` (full URL, public key auth not header auth), `account/account_menu`, `like/like[+removelike]`, `subscription/subscribe[+unsubscribe]`, `browse/edit_playlist`, `playlist/create[+delete]`, upload endpoints, `music/delete_privately_owned_entity`, plus non-InnerTube: `videostatsPlaybackUrl` telemetry ping, `returnyoutubedislikeapi.com` (3rd-party community service), `youtube.com/iframe_api` + `/s/player/<hash>/.../base.js` (player.js scraping), `youtube.com/api/jnn/v1/{Create,GenerateIT}` (BotGuard).

### Auth / cookies (Confirmed)
**Not OAuth.** Login = embedded `WebView` pointed at Google's real login page; on reaching `music.youtube.com` with a cookie set, reads the full cookie string via `CookieManager`, plus `visitorData`/`dataSyncId` scraped from `window.yt.config_` via a JS bridge. Persisted to DataStore, restarts app process. **SAPISIDHASH** (implemented identically 4×, `InnerTube.kt`): `sha1("$unixTime $SAPISID https://music.youtube.com")` → `Authorization: SAPISIDHASH <unixTime>_<hash>`. Only the plain `SAPISID` cookie key is read — no explicit handling of `__Secure-3PAPISID` variants was found. **iOS: `WKWebView` + `WKHTTPCookieStore`** to replicate cookie capture; SHA-1 signing trivial via CryptoKit/CommonCrypto. The cookie-scrape-via-embedded-browser pattern itself is inherently fragile against Google UI changes and carries ToS exposure regardless of platform.

### Stream URL resolution — full fallback chain (`YTPlayerUtils.playerResponseForPlayback`)
1. Resolve signature timestamp (prefers app's own cipher engine's extraction, falls back to bundled NewPipeExtractor).
2. If `WEB_REMIX`: generate PoToken via BotGuard (§7 below).
3. Primary `/player` call with `WEB_REMIX`.
4. Age-restriction retry with `WEB_CREATOR` if needed.
5. **Client fallback loop**, in order: `VISIONOS → WEB_CREATOR → TVHTML5 → ANDROID_VR(1.43.32) → ANDROID_VR(1.61.48) → TVHTML5_SIMPLY_EMBEDDED_PLAYER → IOS → IPADOS → ANDROID_CREATOR → ANDROID_VR_NO_AUTH → MOBILE(ANDROID) → WEB`. Each candidate: format-select (§7 below) → resolve URL (direct `url` field, or `CipherDeobfuscator.deobfuscateStreamUrl()`, or NewPipeExtractor's independent decipher engine as redundancy) → n-param throttle-transform for web-family clients → HEAD-validate (except WEB_REMIX, which skips validation and lets ExoPlayer try directly unless previously 403'd).
6. Quality-upgrade logic keeps searching subsequent clients even after a "good enough" one validates, if HIGH quality was requested but not yet achieved.

**This entire pipeline has no legitimate iOS equivalent already implemented in the current iOS project** and depends on Android `WebView` (Chromium) for JS execution — a port needs `WKWebView`/`JavaScriptCore` at minimum.

**Signature cipher / n-param** (`app/utils/cipher/`): real `WebView` executing YouTube's **actual unmodified player.js** (not reimplemented — only *located*). 3-tier function-name discovery: (1) remote crowd-sourced config table (bundled JSON + live refresh from `raw.githubusercontent.com/MetrolistGroup/Metrolist/...`, **no cryptographic verification beyond TLS** — flag as a supply-chain consideration), (2) regex heuristics, (3) in-WebView brute-force property scan. Self-heals on CDN 403 by re-fetching the config table. The iOS project (`Networking/Cipher/*.swift`) is **already a faithful, working Swift port of exactly this pipeline** (see §19) — the best-ported subsystem in the entire iOS project.

**PoToken/BotGuard** (`app/utils/potoken/PoTokenWebView.kt`): a from-scratch, entirely on-device (no external PoToken server) re-implementation of Google's BotGuard anti-bot challenge/response, executed in a dedicated `WebView` loading a bundled `po_token.html` asset (contents not read in this pass). Uses the same public BotGuard bootstrap key/request-key every unofficial client uses (not a private secret). **This is the single hardest piece to port** — the iOS project explicitly does not implement it (see §20) and none of the `WEB_REMIX`/`WEB_CREATOR`/`TVHTML5` clients (the ones requiring it) are used by iOS's `StreamResolver` as a result.

---

## 7. Audio Format Selection Logic

**Confirmed from source** (`YTPlayerUtils.findFormat`, `YTPlayerUtils.kt:582-663`). Filters `adaptiveFormats` to audio (`mimeType.startsWith("audio/")`). User preference `AudioQuality` = AUTO/LOW/HIGH:
- **HIGH**: max by (audioQuality label rank → channel count → codec score [opus=2, mp4a=1] → bitrate).
- **LOW**: cap ≤128kbps, prefer non-dubbed ("original") track.
- **AUTO**: target 128kbps if network metered, else max bitrate; same original-track preference.

Cross-client upgrade logic keeps a running "best fallback format" across fallback clients even after a lesser one already validated, swapping in a better HIGH match if found later.

iOS's `PlayerResponse.Format`/`StreamResolver` (see §19) implements a **much simpler** version: sort by bitrate only, no codec/channel/quality-label scoring, no cross-client upgrade search — straightforward to extend to match Android's scoring exactly.

---

## 8. Expiring URL Handling

**Confirmed from source, with one caveat.** `StreamingData.expiresInSeconds` (raw `/player` field, ~6h typical) drives a 500-entry LRU (`songUrlCache` in `MusicService.kt`) keyed by mediaId, only reused while `expiry > now`. On HTTP 403 detection (`isExpiredUrlError`): evict cache entry, mark WEB_REMIX failed for that videoId (skip straight to fallback next time), fire `CipherDeobfuscator.onStreamRejected()` (async config refresh), re-seek/re-prepare to trigger fresh resolution. Per-song retry cap 3, global retry cap 10 with backoff.

**Caveat**: `YTPlayerUtils.forceRefreshForVideo()` is a **dead no-op stub** (just logs) — actual invalidation happens via `songUrlCache.remove()` + `markWebRemixFailed()` directly in `MusicService.kt`, not via this named function. Worth flagging as vestigial/incomplete refactor when porting — don't port the stub's apparent contract, port the actual behavior.

iOS has **no expiry-aware caching at all** — `StreamResolver.resolveStreamURL` re-resolves from scratch on every `loadTrack()` call (see §20), which is simpler but wastes a network round-trip per song and has no 403-triggered fallback/refresh logic.

---

## 9. Queue, Radio, Autoplay, Repeat, Shuffle Behavior

**Confirmed from source.** `Queue` interface (`playback/queues/Queue.kt`) with 6 implementations: `EmptyQueue`, `ListQueue` (fixed list, no pagination), `YouTubeQueue` (radio via InnerTube `YouTube.next`/`related`, radio-ID detection `RDAMVM{videoId}`, 3 retries, empty-first-page fallback to `related`), `YouTubePlaylistQueue` (paginated via `YouTube.playlist`/`playlistContinuation`), `LocalAlbumRadio` (local album → seamlessly continues into YouTube album-radio), `YouTubeAlbumRadio`.

**Radio/autoplay is a hard InnerTube dependency baked into the playback layer**, not just search/UI — any iOS port needs InnerTube reachable from the player, not only from search screens.

**"Automix"** — a *separate*, lighter continuation shown as UI suggestions (not inserted into the real queue until the user acts): double-chained `YouTube.next` calls with 3-tier fallback, persisted separately to disk.

**"Start Radio"**: replaces everything *after* the current item with a fresh radio queue seeded on the current song.

**Play next / Add to queue**: honors `PreventDuplicateTracksInQueueKey` (dedup before insert).

**Shuffle**: media3-native `DefaultShuffleOrder` (not queue-item reordering) — Fisher-Yates with current item pinned to shuffle-position 0; optional `shufflePlaylistFirst` mode keeps "original" items ahead of auto-loaded continuation items in two separately-shuffled pools.

**Repeat**: standard OFF/ONE/ALL, persisted, with a specific bug-workaround: ExoPlayer sometimes auto-advances past a REPEAT_MODE_ONE item, detected and corrected in `onMediaItemTransition`.

**Persistence**: queue + automix + player-state all serialized via **raw Java `ObjectOutputStream`** to `filesDir` (10-15s periodic + event-driven). **This binary format cannot be read on iOS** — must be reimplemented as `Codable`/JSON or SQLite from scratch, not ported byte-for-byte.

iOS's `PlayerConnection` (see §19-20) has a flat in-memory `[Song]` queue array with basic next/previous/shuffle-toggle/repeat-mode — **no radio/autoplay, no InnerTube-backed continuation, no persistence at all** (resets on relaunch).

---

## 10. Background Playback and Media Controls

Covered in §3 above (MediaSession/notification/Android-Auto/widgets/QS-tile/headset-buttons). iOS currently has **none of this** — no `MPNowPlayingInfoCenter`, no `MPRemoteCommandCenter`, no background audio session configuration, no lock-screen controls (explicitly called out as missing in `PlayerConnection.swift`'s own doc comment and the README).

---

## 11-13. Lyrics: Retrieval, Provider Priority, Parsing, Translation & Romanization

**Confirmed from source.** Orchestrator: `lyrics/LyricsHelper.kt`. Default fallback order (`LyricsProviderRegistry.getDefaultProviderOrder()`, user-reorderable): **BetterLyrics → Paxsenix → LrcLib → KuGou → LyricsPlus → YouTubeSubtitle → YouTube**. Sequential, first-success-wins, each call individually timeout-wrapped (16s per provider, 25s overall), 3-entry in-memory LRU cache, persistent per-song cache in the `lyrics` Room table (raw text + provider name + saved translation).

- **BetterLyrics** (`betterlyrics/`): community server `lyrics-api.boidu.dev`, returns raw **TTML**, converted to the app's internal extended-LRC via a shared `TTMLParser` (also used by LyricsPlus's Binimum sub-source). Supports word-level (karaoke) sync. Has an unused/dead alternate response model (`Track.kt`'s `SearchResponse`).
- **Paxsenix** (`paxsenix/`): scrapes a JWT out of Apple Music's public website JS bundle (**extremely brittle** — breaks on any Apple web-frontend redeploy), then hits Apple Music's private catalog search + a third-party lyrics proxy (`lyrics.paxsenix.org`). *Not* related to music recognition despite the module name overlap with the recognition subsystem.
- **LrcLib** (`lrclib/`): official-ish public API (`lrclib.net`), multi-strategy cascading search with title/artist cleanup, Levenshtein/duration-based best-match scoring. Line-level LRC + plain lyrics only (no word-level from this source).
- **KuGou** (`kugou/`): unofficial Chinese lyrics aggregator (fork of ViMusic's client), 3-hop API (search song → search lyrics by hash/keyword → download Base64-encoded LRC), line-level only. Not language-gated in code — just sits 4th in priority order.
- **LyricsPlus**: not deep-audited by name but referenced as a provider; can source from a "Binimum" TTML sub-source via the shared `TTMLParser`.
- **YouTube/YouTubeSubtitle**: YTM's own lyrics/transcript endpoints (lowest priority, last resort).

**Internal lyrics format** (`lyrics/LyricsUtils.kt`, the one central parser all providers funnel into): a custom extended-LRC dialect supporting standard `[mm:ss.xx]` lines, **two different word-level sync sub-formats** (Paxsenix-native inline `<mm:ss.cc>word` rich-sync, and the app's own trailing `<word:start:end|...>` blocks emitted by the TTML→LRC and LyricsPlus→LRC converters), agent/duet tagging (`{agent:v1}`/`{bg}`), auto-detected and dispatched accordingly. Output model `LyricsEntry` holds **`MutableStateFlow`s for romanized/translated text directly inside the data class** — Compose-idiomatic but needs rethinking for iOS (`@Published` on an `ObservableObject`, or Combine/AsyncStream per-line).

**TTML parser** (`betterlyrics/TTMLParser.kt`): full namespace-aware XML parser (`DocumentBuilderFactory`, XXE-safe), handles line/word/background-vocal spans, multi-voice agents, hyphen-continuation word merging, multiple TTML time-expression formats. Explicitly **skips** `x-translation`/`x-roman` spans even when TTML sources embed them — the app's own separate translation/romanization pipeline is used instead.

**Romanization** (`LyricsUtils.kt`) — **fully on-device, zero network cost**: Japanese via `kuromoji-ipadic` (JVM morphological tokenizer + hand-built kana→romaji tables — **no direct iOS equivalent**, would need `NaturalLanguage`/`NLTokenizer` + a reading dictionary, non-trivial re-implementation not a straight port), Chinese via `tinypinyin` (needs a Swift-side pinyin dictionary equivalent), Korean/Cyrillic(7 languages)/Hindi/Punjabi entirely **hand-built Unicode character-mapping tables in pure Kotlin** — these are a direct, mechanical Swift port target with no platform dependency.

**Translation** (`lyrics/LyricsTranslationHelper.kt`) — external, user-selectable provider: **DeepL** (official REST API), **Mistral**/**OpenRouter**/"Custom" (LLM chat-completion prompt-engineered translation/romanization/transcription, with defensive 4-tier fallback JSON parsing since LLM output formatting is unreliable — **inherently fragile by design**, needs equally defensive parsing on iOS). Whole-song single round-trip (not per-line), in-memory + persistent (Room) caching by content hash, streaming variant for OpenRouter.

iOS currently has **zero lyrics support** — no parser, no provider, no UI (confirmed in `FullPlayerView.swift`'s own doc comment: "lyrics... left as a TODO").

---

## 14. Database Entities and Migrations

**Confirmed from source.** Room DB `song.db`, currently **version 38**, WAL mode + tuned pragmas, custom backup-before-migrate factory (copies `.db`/`-wal`/`-shm` before any upgrade), `fallbackToDestructiveMigration()` as last resort. 29 auto-migrations + 4 hand-written manual migrations (v1→2 full rebuild; later ones mostly additive column changes, several defensively guarded via `PRAGMA table_info` checks — evidence of real-world crash-driven hardening).

**18 tables + 3 views**: `song` (central; ~25 columns incl. `isLocal`/`isDownloaded`/`isCached`/`playbackPosition`/`romanizeLyrics`/`libraryAddToken`), `artist`, `album`, `playlist` (incl. synthetic auto-playlist IDs `LP_LIKED`/`LP_DOWNLOADED`/`LP_WEEKLY_MOST`/`LP_MONTHLY_MOST`), `song_artist_map`/`song_album_map`/`album_artist_map` (ordered many:many joins), `playlist_song_map` (the playlist↔song join, ordered + YTM `setVideoId` edit token), `search_history`, `format` (per-song resolved stream/format cache — bitrate/codec/loudness, **not** the raw URL post-v24), `lyrics` (raw text + provider + translation), `event` (play-history log, distinct from the live queue), `related_song_map` (recommendation graph), `set_video_id`, `playCount` (monthly aggregate), `recognition_history`, `speed_dial_item` (own separate DAO), `podcast`. Views: `sorted_song_artist_map`, `sorted_song_album_map`, `playlist_song_map_preview` (cheap first-3-songs thumbnail preview).

**Not Room tables** (Confirmed missing, by design): live queue/automix/player-state (raw Java-serialized files, §9), EQ presets (`SharedPreferences` JSON blob), Listen Together session-resume tokens (DataStore keys), artist-page cache (`kotlinx.serialization` JSON blob inlined into `artist.cachedPageJson`, not normalized rows).

**One god-DAO** (`DatabaseDao.kt`, ~1938 lines, ~180 methods): reactive `Flow`-first, a repeating "sort-type dispatch to N near-identical queries" pattern (copy-paste-heavy but simple to port to SwiftData `FetchDescriptor`/`SortDescriptor`), plus **hand-written multi-line SQL** for quick-picks/recommendations/stats (`UNION`s, correlated subqueries) that **cannot be expressed directly in SwiftData predicates** — will need raw SQL (GRDB) or in-Swift recomputation over fetched sets. This is the highest-risk porting item in the persistence layer.

**Download/offline storage**: Media3 `DownloadManager`/`SimpleCache`, two separate caches (bounded LRU streaming cache vs. unbounded offline-download cache), both content-addressed by video ID; state tracked as scalar columns on `song` (`isDownloaded`/`dateDownload`/`isCached`), not a separate table (one existed pre-v10, dropped). Maps cleanly to `AVAssetDownloadTask` + FileManager-managed directories + the same scalar columns on a SwiftData Song model.

---

## 15. Last.fm, Discord, Recognition, and Other Integrations

**Confirmed from source.**

**Last.fm** (`lastfm/`) — **official public API**, low risk, trivially portable (REST + MD5 signing via CryptoKit/CommonCrypto). Mobile session auth (username/password → session key, not 3-legged OAuth despite a vestigial unused OAuth code path). Scrobble threshold: **50% of track length OR 180s, whichever comes first**, tracks shorter than 30s never scrobbled — all 3 thresholds user-configurable. Pause/resume-aware elapsed-time bookkeeping. Now-playing + love/unlove sync also implemented. No offline scrobble queue/retry.

**Discord "Rich Presence"** (`discord/`) — **high risk, unofficial.** Not IPC-to-desktop-client, not a 3rd-party RPC proxy: a real OAuth2 PKCE login against Discord's own endpoints, then a **raw WebSocket directly to Discord's production Gateway** (`wss://gateway.discord.gg`), sending `IDENTIFY` with the OAuth **Bearer token** and spoofed `Discord-Android` client metadata (`X-Super-Properties`, fake build/version numbers) — a hand-rolled reimplementation of internal client behavior, not a documented integration surface. Full reconnect/backoff/rate-limit handling. Rich Presence content (name/state/details/timestamps/art/button) built from user-configurable templates. **This pattern resembles what Discord actively polices as unauthorized-client/self-bot behavior** — no SLA, could be blocked or the app's OAuth application revoked at any time, with no legitimate iOS SDK equivalent. Flag as the single highest-risk integration to carry over.

**Music recognition** — **not** Apple's ShazamKit despite the module name. `shazamkit/` module = a from-scratch Kotlin reimplementation (ported from the open-source `vibra`/SongRec project) of Shazam's proprietary audio-fingerprint algorithm, calling Shazam's **private mobile-tagging API** (`amp.shazam.com`) with rotating fake User-Agents, spoofed timezone, and **fabricated random GPS coordinates**. Client-side rate-limiting/retry/caching engineered specifically to work around an API never meant for 3rd-party use. **Only one recognition provider** — Paxsenix is not part of any recognition fallback (it's a lyrics source, see §11). **iOS migration opportunity**: Apple's *real* ShazamKit could replace this entirely with an officially-supported on-device/cloud API — recommended over porting the private endpoint, though it requires a different fingerprint format/API contract, not a language port.

**Listen Together** (`listentogether/`) — custom binary protocol: Protobuf messages wrapped in a GZIP-optional `Envelope`, over WebSocket, to a **single third-party-operated relay server** (`wss://metroserverx.meowery.eu/ws`, community operator, no first-party infrastructure, no configured failover). Host-gated join (explicit approval), full room/host-transfer/kick/block model, latency-compensated position sync, buffer-coordination handshake before new-track playback starts, guest song-suggestion workflow, optional guest remote-control mode. **The actual `.proto` schema is not in this repo** — it lives in an external `relabsproto` sibling directory not present in this checkout; only pre-generated Java/Kotlin sources are committed. **Blocker**: need to source the real `.proto` file to build a correct SwiftProtobuf port; reconstructing it purely from generated code + `Protocol.kt` DTOs is possible but risks subtle mismatches. Protocol design itself (protobuf/WebSocket) is otherwise sound and portable via `URLSessionWebSocketTask` + SwiftProtobuf.

**Equalizer wizard** (`ui/screens/equalizer/wizard/`) — first-party UI + community AutoEQ preset DB, low risk.

---

## 16. Settings and Persistence

**Confirmed from source.** Primary mechanism: **Jetpack Preferences DataStore** (single file `settings.preferences_pb`, ~90 typed keys in `constants/PreferenceKeys.kt`), covering Appearance, Playback (+ sleep timer, + alarm), Lyrics, AI/Translation, Content/Discovery/Privacy, Proxy (**stored in plaintext DataStore — flag for iOS Keychain reconsideration**), Stream Sources, Integrations (Discord/Cast/Listen-Together/Last.fm/Account), sort/filter UI state, sync bookkeeping.

**Secondary mechanism**: raw `SharedPreferences` used only for specific isolated state bypassing DataStore: **EQ profiles** (plaintext JSON blob), **Discord OAuth tokens** (AES-256-GCM encrypted via Android Keystore — the one place with real at-rest encryption; iOS equivalent = Keychain), **Music alarms** (device-protected storage for pre-unlock readability + legacy-migration logic), **widget transient state** (ephemeral).

iOS mapping: DataStore Preferences → `UserDefaults`/`@AppStorage`; the 3 SharedPreferences blob stores → `UserDefaults`/Keychain with `Codable` structs, preserving Keychain-equivalent encryption specifically for the Discord token store.

---

## 17. Error, Loading, Offline, Cancellation, Retry Behavior

Covered in detail in §3 (playback error/retry state machine) and §8 (expiring-URL retry). Additional cross-cutting notes:

- **Lyrics**: per-provider 16s timeout + 25s overall timeout (raised from an original 8s after a real production bug where BetterLyrics/LyricsPlus's own 15s internal ktor timeout was silently causing premature fallthrough — worth replicating the *raised* timeout value, not the original).
- **Network connectivity gating**: `LyricsHelper` bails immediately if `NetworkConnectivityObserver.isCurrentlyConnected()` is false, no network call attempted.
- **Search/streaming**: cascading multi-strategy retries (LrcLib title/artist cleanup cascade; YTPlayerUtils's 12-client fallback loop) are the dominant retry pattern across the app — "try N variations/clients, first success wins" rather than blind retry-same-request backoff (that pattern is reserved for genuine transient/network failures, e.g. `MusicService`'s exponential backoff).
- **Translation**: LLM-backed providers use defensive multi-tier parsing (direct JSON → strip markdown → substring extraction → naive line-split) because LLM output formatting is unreliable by nature — this is a permanent characteristic to replicate, not a bug to fix.

iOS currently has minimal error handling by comparison: `StreamResolver` throws a single `noPlayableFormat` error with no retry/backoff; `SearchScreen`/`HomeScreen` show a generic error/fallback-to-sample-data state; no offline queueing, no cancellation-aware retry beyond basic `Task` cancellation checks (which *are* present and correctly used throughout the Swift code — a good existing pattern to keep).

---

## 18. Security-Sensitive Values / Hardcoded Secrets

**Confirmed from source (full-text scan).**

| Value | Location | Assessment |
|---|---|---|
| `AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3` | `innertube/InnerTube.kt` (2 call sites) | Public InnerTube browser API key — embedded in every YouTube web client, published widely. Not a real secret. |
| `AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw` + `O43z0dpjhgX20SCx4KAo` | `PoTokenWebView.kt` | Public BotGuard bootstrap key/request-key, shared across all unofficial clients (yt-dlp/NewPipe use the same values). Not a real secret. |
| base64 → `raw.githubusercontent.com/MetrolistGroup/Metrolist/.../player_configs.json` | `PlayerConfigStore.kt` | Not a secret, but a **supply-chain trust dependency**: cipher-solving config fetched over HTTPS from a 3rd-party GitHub repo with no payload signature verification beyond TLS. |
| Last.fm `API_KEY`/`SECRET` | injected at runtime from `BuildConfig` (sourced from `local.properties`/CI secrets) | Not hardcoded in source. |
| Discord `DISCORD_APP_ID` | `app/build.gradle.kts` (`1525699798076887183L`) | A public app/client ID, not a secret by nature. |
| Proxy password | DataStore, **plaintext** | Genuine at-rest weakness — recommend Keychain on iOS even though Android leaves it in DataStore. |
| Discord OAuth tokens | SharedPreferences, **AES-256-GCM via Android Keystore** | Correctly encrypted at rest — replicate with iOS Keychain. |
| No matches for `sk-...`, private key blocks, personal cookies/tokens, Sentry DSNs | across `innertube/`, `app/utils/cipher/`, `app/utils/potoken/`, `app/api/`, gradle/manifest/properties files | Clean — no genuinely private/personal credentials found in the scanned scope. |

The iOS project's `README.md` self-reports no committed signing secrets (CI archive job is skipped without user-supplied Apple Developer secrets) — consistent with this scan.

---

## 19. Features Currently Implemented in iOS

**Confirmed from source** (verified by direct read of every file, not just the README's claims):

- **4-tab navigation** (`RootView.swift`, `Tab.swift`) + mini/full player overlay shell — fully working, real `@StateObject`/`@EnvironmentObject` state management.
- **Search** (`SearchScreen.swift`) — real network call to `/search` via `InnerTubeClient`, debounced (350ms), cancellable via `Task`.
- **Home** (`HomeScreen.swift`) — real `/browse` call (`FEmusic_home`), "Quick Picks" (real) + "Recently Played" (real, sourced from in-memory playback history) sections; explicitly labeled sample-data fallback on failure.
- **Playback** (`PlayerConnection.swift`, `StreamResolver.swift`) — real `AVPlayer` streaming, **real signature-cipher deciphering**: a genuine, careful Swift port of the Android app's `utils/cipher/` pipeline (`PlayerJsFetcher` → `FunctionNameExtractor`/`PlayerConfig` → `CipherWebView` executing real unmodified `player.js` in `WKWebView` → `CipherDeobfuscator` orchestration), including the same 3-tier discovery, 6h cache TTL, and retry-with-forced-refresh-on-failure behavior as Android. Two-tier `StreamResolver`: direct-URL clients first (VisionOS/AndroidVR/TVHTML5-embedded, no cipher needed), then the cipher-capable Android client. Play/pause/seek/next/previous/shuffle-toggle/repeat-cycle, basic queue array, "recently played" tracking, resolve-in-progress/error UI states.
- **Listen Together** (`ListenTogetherSession.swift`) — real peer-to-peer sync via Apple's `MultipeerConnectivity` (nearby-device discovery + encrypted session, zero server), one-directional host-broadcasts/guest-follows design, works between physically-nearby devices.
- **Library UI shell** (`LibraryScreen.swift`) — real layout (segmented Songs/Albums/Artists/Playlists with artwork), but backed by `SampleData`, not a real store (see §20).
- **Shared UI infra**: `ArtworkView`/`Theme.swift` (same `0xFF2D55` brand seed color as Android's `DefaultThemeColor`), `SongRow`, `EmptyStateView` (iOS-15-compatible `ContentUnavailableView` stand-in), `QueueView`.
- **Build/CI**: XcodeGen-generated project (no committed `.xcodeproj`), GitHub Actions workflow for simulator build + optional signed `.ipa` archive.

---

## 20. Features That Are Only Visual or Dummy in iOS

**Confirmed from source / Dummy / Missing:**

- **Library tab**: real UI, **`SampleData.swift`-backed content only** — no persistence layer, no real library query.
- **Home**: "Quick Picks"/"Recently Played" are real, but Android's other 5 independent home sections (DailyDiscover/KeepListening/ForgottenFavorites/AccountPlaylists/FromTheCommunity/MoodAndGenres) are **not reproduced** — `SearchResponseParser` is a heuristic recursive-scan for `musicResponsiveListItemRenderer` shapes only, not the typed renderer tree (`MusicShelfRenderer`/`MusicCardShelfRenderer`/`isSong`/`isAlbum`/etc.) Android's `innertube` module implements across dozens of files. Will misclassify or drop albums/artists/playlists/podcast-episode shapes.
- **PoToken/BotGuard**: **deliberately not implemented** (per the code's own doc comments) — `WEB_REMIX`/`WEB_CREATOR`/`TVHTML5` clients are never used by `StreamResolver` as a direct result, relying entirely on the direct-URL-client tier + the cipher-only Android client.
- **Downloads, lyrics, equalizer, Discord RPC, login/auth, Android-Auto-equivalent (CarPlay), background playback/lock-screen controls**: **not started** — confirmed absent from the file tree entirely (no persistence layer, no lyrics parser/UI, no EQ code, no Discord integration, no YouTube Music login flow, no `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`/background audio session config).
- **Queue**: flat in-memory array, no radio/autoplay/continuation (no InnerTube `next`/`related` calls anywhere in the iOS project), no persistence (resets on relaunch).
- **Listen Together**: real for local-network use, but **auto-accepts every join request** (no confirmation UI, despite encryption being enforced) and has no internet-relay path (by design, no server).
- **RendererRecoveryPolicy / PlayerConfigStore self-heal**: explicitly not ported from the cipher pipeline — the bundled `player_configs.json` will gradually go stale with no remote-refresh mechanism (Android re-fetches from GitHub periodically; iOS ships a static snapshot only).
- **Expiring-URL cache**: none — every track re-resolves from scratch, no 403-triggered fallback/refresh logic.

---

## 21. Incorrect Architectural Decisions in the iOS Project

Assessed against the Android source of truth and general iOS platform idiom:

- **No persistence layer at all** (no SwiftData/CoreData) is the most consequential gap — Library, queue, settings, downloads, and lyrics/translation caching all depend on one existing. This should likely be the **first** architectural investment, not deferred, since almost every subsequent feature (Library, downloads, lyrics cache, queue persistence, settings) depends on it.
- **`SearchResponseParser`'s flat recursive-scan approach**, while a pragmatic bootstrap, is a dead end for feature parity — Home's independent sections, album/artist/playlist/podcast distinction, and shelf/section structure all require the typed renderer-tree model Android uses. Continuing to extend the flat-scan approach will accumulate misclassification bugs rather than close the gap; recommend replacing it with a typed renderer-tree parser (mirroring `innertube/models/*.kt`) before investing further in Home/Library fidelity.
- **`PlayerConnection` conflates "queue/transport state" with "everything else"** (recently-played tracking, sync application) in one `ObservableObject` — reasonable at current scale, but Android's separation of `MusicService` (engine) from `PlayerConnection` (façade) from `Queue` (data abstraction) is a cleaner model to converge toward once background playback/persistence are added, so a single view model doesn't grow into a 4,780-line god-object the way `MusicService.kt` did.
- **No abstraction boundary yet for "stream client tiers"** — `StreamResolver`'s two-tier logic is currently hardcoded procedural code; as more clients/PoToken get added this should probably become a strategy-list like Android's `STREAM_FALLBACK_CLIENTS`, to keep the fallback chain declarative and testable.
- **Nothing structurally wrong** was found beyond the above — the existing code is honest about its own scope (extensive, accurate doc comments cross-referencing exact Android file/function names throughout), uses modern Swift concurrency correctly (`actor` isolation for `InnerTubeClient`/`CipherDeobfuscator`/`PlayerJsFetcher`, proper `Task` cancellation, `@MainActor` isolation for UI-touching classes), and the cipher port in particular is architecturally sound and worth using as the template for how to port the remaining Android subsystems (mirror file names/structure, cite the Android source in doc comments, preserve exact numeric constants like timeouts/thresholds).

---

## 22. Reusable iOS Code vs. Code That Should Be Replaced

**Retain and build on:**
- `Networking/Cipher/*.swift` (all 5 files) — working, faithful, well-documented port. Extend, don't replace.
- `Networking/InnerTubeClient.swift`, `InnerTubeContext.swift`, `YouTubeClientIdentity.swift` — correct request-plumbing foundation; extend with more endpoints (`next`, `player` for radio, `browse` variants) rather than rewriting.
- `Playback/PlayerConnection.swift` — correct core transport logic (play/pause/seek/skip, the 3-second restart-previous threshold is *not* yet replicated but the seek/skip skeleton is right); extend rather than replace, but plan to extract a persistence-backed `Queue` abstraction out of it.
- `Views/*` shell (`RootView`, `MiniPlayerView`, `FullPlayerView`, `QueueView`, `Theme.swift`, `ArtworkView`, `SongRow`, `EmptyStateView`) — solid, idiomatic SwiftUI; keep the visual/structural scaffold and wire in real data as backends land.
- `ListenTogether/ListenTogetherSession.swift` — real, working, keep; just add the join-confirmation UI gap noted in §20 before wider use.
- Project tooling (`project.yml`/XcodeGen, GitHub Actions workflow) — sound approach for a no-Mac-required workflow, keep.

**Replace / do not extend as-is:**
- `Networking/SearchResponse.swift` (`SearchResponseParser`) — replace with a typed renderer-tree parser once Home/Library fidelity matters (see §21).
- `Models/SampleData.swift` — delete once a real persistence layer + Library query exists; it's explicitly a placeholder the code itself flags for removal.
- `Networking/PlayerResponse.swift`'s format-selection logic in `StreamResolver` — extend to match Android's full scoring (codec/channel/quality-label), not just bitrate sort.

---

## 23. Native iOS Equivalents for Android-Specific Components

| Android component | iOS equivalent |
|---|---|
| Media3 `MediaLibraryService`/`ExoPlayer` | `AVPlayer`/`AVQueuePlayer` + `AVAudioSession` (background audio mode) |
| `MediaSession` + notification/lock-screen | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` |
| Android Auto media-browser tree | CarPlay (`CPTemplateApplicationSceneDelegate`) — a separate, substantial integration if pursued |
| Home-screen widgets (`RemoteViews`) | WidgetKit (+ interactive widgets/Live Activities on iOS 17+) |
| Quick Settings tile | No direct iOS equivalent (Control Center custom controls, iOS 18+, is the closest analog) |
| `AudioManager` focus/ducking | `AVAudioSession` interruption handling + manual volume ducking |
| `AudioDeviceCallback` (Bluetooth resume) / becoming-noisy | `AVAudioSession.routeChangeNotification` (`.newDeviceAvailable` / `.oldDeviceUnavailable`) |
| Room + DAO | SwiftData (bulk of entities) + GRDB or raw SQL for the stats/quick-picks correlated-subquery/UNION queries SwiftData can't express |
| DataStore Preferences | `UserDefaults`/`@AppStorage` |
| SharedPreferences (EQ/alarms) | `UserDefaults` with `Codable` |
| SharedPreferences + AndroidKeyStore (Discord tokens) | Keychain |
| Java `ObjectOutputStream` queue persistence | `Codable`/JSON to a file, or SwiftData |
| Media3 `DownloadManager`/`SimpleCache` | `AVAssetDownloadTask`/`AVAssetDownloadURLSession` + FileManager-managed cache directories |
| `android.webkit.WebView` (cipher + PoToken + login) | `WKWebView` (already used for cipher in iOS; needed for PoToken and login-cookie-capture too) |
| `AlarmManager` + device-protected storage (Music Alarm) | No clean equivalent — `UNUserNotificationCenter` can only notify, not autonomously resume playback from suspension. Needs a design decision, not a port (see §30). |
| Chromecast (`gms` flavor) | Google Cast iOS SDK, or omit as an optional capability behind a protocol (mirroring the `foss`/`izzy` stub pattern) |
| kuromoji-ipadic (Japanese romanization) | No direct port target — needs `NaturalLanguage`/`NLTokenizer` + a reading dictionary, or a bundled data table, built essentially from scratch |
| tinypinyin (Chinese romanization) | Needs a Swift-side pinyin dictionary/lookup table sourced or rebuilt |
| Korean/Cyrillic/Hindi/Punjabi romanization | Direct mechanical Swift port (pure algorithm/table, no platform dependency) |
| `android.media.audiofx`-independent custom biquad EQ | Direct algorithmic port to `AVAudioEngine`/`AVAudioUnitEQ` or a custom `AVAudioSourceNode` tap |
| Hilt DI | Lightweight custom container or `@Environment`-based injection (5 small modules total — no need for a heavyweight DI framework) |
| NewPipeExtractor (JVM library, cipher redundancy) | No iOS port available — would need a different redundancy strategy or omission |

---

## 24. Missing Information and Blockers

Explicitly flagged as unread/unconfirmed during this pass, or structurally missing from the repo:

- **`listentogether.proto` schema is not in this repository** — lives in an external `relabsproto` sibling directory not present in this checkout. **Blocker for an exact protocol port**; only reconstructable from generated code + `Protocol.kt` DTOs currently.
- `eq/audio/BiquadFilter.kt` internals, `eq/data/{ParametricEQParser,EQProfileRepository,GitHubAutoEqSearch,FilterType}.kt` — not read in this pass (Inferred from usage sites only).
- `playback/DownloadUtil.kt`, `playback/ExoDownloadService.kt` — not read in depth (Inferred from manifest + cross-references).
- `MusicService.kt:4297-4386` (`handleAlarmTrigger` body) and `playback/alarm/MusicAlarmRescheduleReceiver.kt` — not read (Partially confirmed dispatch wiring only).
- `constants/LoudnessLevel.kt` exact LUFS presets, `constants/MediaSessionConstants.kt` — not read directly.
- `po_token.html` bundled asset contents (the actual BotGuard client JS) — not inspected.
- `widget/PlaylistWidgetManager.kt`, `widget/TurntableWidgetReceiver.kt` bodies — not read in depth.
- `LyricsPlus` provider client and `OpenRouterStreamingService.kt` internals — referenced but not fully read.
- `db/entities/LyricsEntity.kt`'s DAO layer — usage sites confirmed, full DAO not opened.
- The exact single/double/triple-press semantics of hardware headset buttons — delegated to media3 defaults, not independently verified.
- Whether `KuGou.useTraditionalChinese` (an unread mutable flag with no read-site found in the scanned file) is dead code or wired elsewhere.

---

## 25. Recommended iOS Architecture

Given the codebase's current shape (a well-started but early scaffold) and Android's proven architecture, recommend converging toward:

1. **Persistence first**: introduce SwiftData for the entity graph in §14 (Song/Artist/Album/Playlist + join tables + Format/Lyrics/Event/RelatedSong caches), mirroring Room's *current* (v38) shape rather than replaying migration history. Use raw SQL (via SQLite directly, or a lightweight query layer) only for the stats/quick-picks correlated-subquery/UNION queries SwiftData's predicate API can't express.
2. **Playback engine as a dedicated layer**, separate from UI state: an `AudioPlaybackEngine` (owns `AVPlayer`/dual-player-for-crossfade, `AVAudioSession`, `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`) analogous to `MusicService`, with `PlayerConnection` staying a thin `ObservableObject` façade over it — don't let one object grow into a god-object.
3. **Queue as its own protocol/type hierarchy** (mirroring Android's `Queue` interface + 6 implementations) rather than a flat array on `PlayerConnection`, so radio/autoplay/pagination can be added without restructuring the player.
4. **InnerTube client layer expanded but architecturally unchanged** — `InnerTubeClient`/`YouTubeClientIdentity` are already the right shape; add the missing endpoints and a typed renderer-tree response layer (mirroring `innertube/models/*.kt` and `pages/*.kt`) to replace `SearchResponseParser`.
5. **Settings** via `UserDefaults`/`@AppStorage` for the bulk, Keychain specifically for anything credential-shaped (Discord tokens, YTM cookie, proxy password).
6. **Feature modules kept optional/pluggable** behind small protocols where Android itself treats them as optional (Cast, lyrics providers, translation providers, recognition) — continuing the pattern iOS's `StreamResolver` client-tier list and Android's `foss`/`gms`/`izzy` split both already demonstrate.
7. **WKWebView-based subsystems consolidated**: cipher (done), PoToken (to build), login cookie-capture (to build) all need a `WKWebView` host — consider one shared, carefully-lifecycle-managed web-view utility rather than three independent ones.

---

## 26. Feature-by-Feature Migration Order

Ordered by (a) unblocking the most downstream work, (b) risk/effort, (c) user-visible value:

1. **Persistence layer (SwiftData)** — unblocks Library, queue persistence, settings-as-Codable-blobs, lyrics/translation caching, downloads. Do this before anything else in this list.
2. **Typed renderer-tree parsing** (replace `SearchResponseParser`) — unblocks faithful Home sections, Library remote sync, Album/Artist/Playlist detail screens.
3. **Background playback & media controls** (`MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`, `AVAudioSession` background mode, interruption/route-change handling) — high user-visible value, moderate effort, no hard blockers.
4. **Real Library** (SwiftData-backed, replacing `SampleData`) — depends on #1.
5. **Queue/radio/autoplay** (port the `Queue` protocol hierarchy, wire `next`/`related` InnerTube calls) — depends on #2 for related/radio parsing quality.
6. **Login/auth** (`WKWebView` cookie capture + SAPISIDHASH) — unblocks account-synced Library/playlists and higher-quality stream access.
7. **PoToken/BotGuard** — unlocks the `WEB_REMIX` client tier for more reliable streaming; can be deferred since the existing direct-URL + cipher-only-Android fallback already works for many videos.
8. **Downloads** (`AVAssetDownloadTask` + two-cache split) — depends on #1.
9. **Lyrics** (LRC/TTML parser port, provider clients, romanization tables first since they're pure-portable, translation providers second) — large but mostly mechanical; Japanese romanization (`kuromoji`) is the one genuinely hard sub-piece.
10. **Equalizer** (biquad DSP port to `AVAudioEngine`) — self-contained, no cross-dependencies, portable algorithm.
11. **Last.fm** — small, low-risk, can slot in anytime after login exists (needs no YTM auth, just its own).
12. **Discord Rich Presence** — do last and only with the risk in §15 explicitly accepted; requires the raw-Gateway reimplementation, no shortcuts.
13. **Music recognition** — recommend building on Apple's real ShazamKit rather than porting the private-API client, as a deliberate architecture change, not a straight port.
14. **Music Alarm** — needs a design decision (see §30) before implementation; not a straight port regardless of order.
15. **Chromecast / CarPlay / widgets / Quick-Settings-equivalent** — treat as optional capability modules, lowest priority, add opportunistically.

---

## 27. Dependency Map

```
SwiftData persistence layer
 ├─→ Real Library (Songs/Albums/Artists/Playlists)
 ├─→ Queue persistence
 ├─→ Downloads (state columns on Song)
 ├─→ Lyrics/translation cache
 └─→ Settings (Codable blob stores: EQ profiles, alarms)

Typed renderer-tree parser
 ├─→ Faithful Home sections
 ├─→ Real Library remote sync
 └─→ Queue radio/autoplay (next/related parsing)

WKWebView-based auth/cipher/PoToken utility
 ├─→ Login (cookie capture)
 │    ├─→ Account-synced Library
 │    └─→ Higher-quality/authenticated streaming
 └─→ PoToken/BotGuard
      └─→ WEB_REMIX/WEB_CREATOR/TVHTML5 client tiers

Background playback & media controls
 └─→ (no hard dependents, but should land early for user value)

Queue protocol hierarchy
 └─→ Radio/autoplay/continuation (needs InnerTube next/related, i.e. typed parser)

Lyrics core (LRC/TTML parser, LyricsEntry model)
 ├─→ Lyrics provider clients (BetterLyrics/LrcLib/KuGou/etc.)
 ├─→ Romanization (mostly independent, Japanese needs NL framework work)
 └─→ Translation providers (independent, needs only network + API keys)

Discord Rich Presence — standalone, no dependents, high risk, do in isolation
Last.fm — standalone, minimal dependencies
Music recognition (ShazamKit-based) — standalone
Music Alarm — blocked on a design decision, not other code
```

---

## 28. Files to Retain or Discard in the Current iOS Project

**Retain (extend in place):**
`App/*`, `Navigation/Tab.swift`, `Networking/InnerTubeClient.swift`, `Networking/InnerTubeContext.swift`, `Networking/YouTubeClientIdentity.swift`, `Networking/Cipher/*` (all 5), `Playback/PlayerConnection.swift` (refactor internals per §25 but keep as the façade), `ListenTogether/ListenTogetherSession.swift`, `Views/Player/*`, `Views/Home/HomeScreen.swift` (keep shell, replace parsing underneath), `Views/Search/SearchScreen.swift` (same), `Views/Shared/*`, `Resources/Theme.swift`, `Resources/player_configs.json` (keep, add a refresh mechanism), `project.yml`, `.github/workflows/ios-build.yml`.

**Discard / replace outright:**
`Models/SampleData.swift` (delete once real data exists), `Networking/SearchResponse.swift`'s `SearchResponseParser` (replace with typed parser), `Views/Library/LibraryScreen.swift`'s data source (keep the view layout, swap `SampleData` calls for real queries).

**Repo-root Android scratch files** (`Player_backup.kt`, `patch_controls.py`, `patch_queue.py`, `temp_controls.txt`, `diff.txt` in the `../3` repo) — confirmed dev leftovers, not build-relevant, irrelevant to iOS; no action needed, just don't treat them as source of truth.

---

## 29. Acceptance Criteria Per Phase

- **Persistence (SwiftData)**: app relaunch preserves Library content, queue, and settings without re-fetching from network; migrations (if schema changes later) don't data-loss on upgrade.
- **Typed parser**: Home renders the distinct sections Android shows (or a documented subset), Search correctly distinguishes songs/albums/artists/playlists (not just "songs found").
- **Background playback**: audio continues with screen locked/app backgrounded; lock-screen shows correct metadata/artwork and responds to play/pause/skip; audio correctly pauses on phone call/Siri interruption and resumes per Android's transient-vs-permanent focus-loss rules; ducks (not pauses) for transient-mixable interruptions.
- **Real Library**: liked/downloaded/synced songs persist and display correctly across relaunch; sort/filter parity with Android's `SongSortType`/`ArtistSortType`/etc. for at least the common cases.
- **Queue/radio**: "Start Radio" produces a continuing queue from InnerTube `next`, not a dead end; shuffle/repeat behave identically to Android's documented semantics (§9), including the REPEAT_MODE_ONE auto-advance correction.
- **Login**: cookie capture succeeds against real accounts.google.com flow; SAPISIDHASH-authenticated requests succeed; account-gated content (playlists, library sync) loads.
- **PoToken**: `WEB_REMIX` client successfully streams videos that previously failed on all direct-URL + cipher-only-Android tiers.
- **Downloads**: a downloaded song plays with no network; storage correctly reflects two-cache split; deleting a download frees space.
- **Lyrics**: at least LRCLIB + one TTML source (BetterLyrics) working end-to-end with line-level sync visible in the player; romanization toggle produces correct output for at least Japanese/Korean/Chinese; translation round-trips through at least one provider.
- **Equalizer**: audible frequency-response change matches the configured bands; preamp doesn't clip.
- **Last.fm**: scrobble fires at the documented 50%/180s threshold; now-playing updates on track change.
- **Discord**: presence appears in a real Discord client for a real connected account, with the explicit understanding this can silently break — acceptance includes a monitoring/fallback plan, not just "works once."
- **Music recognition**: correctly identifies a known playing track via ShazamKit within a few seconds.

---

## 30. Open Questions Requiring Your Decision

1. **Discord Rich Presence**: proceed knowing it reimplements Discord's private Gateway protocol and carries real ToS/blocking risk with no official alternative for what you want (Rich Presence from a 3rd-party mobile client)? Or drop this feature for iOS?
2. **Music recognition**: port the private Shazam-API client (same risk profile as Android), or switch to Apple's real ShazamKit (different fingerprint/API contract, officially supported, likely the better iOS-native choice)?
3. **Music Alarm** ("wake device and autonomously start playback"): iOS has no clean equivalent to Android's `AlarmManager`-triggered foreground-service playback. Acceptable to degrade to "loud notification at the scheduled time, user taps to start playback" instead of true autonomous wake-and-play?
4. **Listen Together over the internet**: the current iOS implementation is local-network-only (MultipeerConnectivity) by design, matching Android's *fallback* mode, but Android also has a real relay-server mode (single 3rd-party-operated server, `.proto` schema not in this repo). Do you want the internet-relay mode ported (blocked on sourcing the actual `.proto` schema), or is local-network-only sufficient for your use?
5. **Chromecast / CarPlay**: worth the investment given this is a personal sideload, not a public release? Both are substantial standalone integrations.
6. **Japanese romanization**: acceptable to invest in building a `NaturalLanguage`-framework-based tokenizer + reading dictionary from scratch (no direct `kuromoji` port target exists for iOS), or is Japanese romanization a droppable feature for v1?
7. **`player_configs.json` staleness**: Android self-heals via a periodic GitHub-hosted refresh; the iOS bundle is currently a static snapshot. Want a matching remote-refresh mechanism, or is manually re-copying Android's latest `assets/player_configs.json` into the iOS bundle occasionally an acceptable substitute?
8. **Proxy password / other plaintext-in-Android values**: Android stores these in plaintext DataStore. Use this as an opportunity to do better on iOS (Keychain) even though it diverges from Android's actual behavior?
9. **`ExploreScreen`/`WrappedViewModel` dead code on Android**: confirm these are genuinely unused before deciding whether their apparent functionality (explore/charts entry point, Wrapped) needs a different real entry point ported, or can be skipped as Android itself effectively skips them today.
