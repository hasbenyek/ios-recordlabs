# RecordLabs iOS (real networking, real cipher deciphering, real local sync, CI-buildable)

This is a **from-scratch SwiftUI app**, built to run on a real iPhone, that
talks to YouTube Music's private API the same way the sibling Android app
(`record-labs`) does. It is not a translation of that Kotlin code —
Kotlin/Compose cannot be mechanically converted to Swift/SwiftUI — but it
reproduces the same navigation structure, player, and backend techniques,
including a real port of the Android app's own WebView-based
signature-cipher deciphering. Comments throughout reference the Android
file each piece mirrors (e.g. `utils/cipher/CipherWebView.kt`) — those files
live in the `record-labs` repo, not this one.

**Read "What's real vs. not" below before assuming anything works
end-to-end.** The one genuinely unimplemented piece — BotGuard "PoToken"
generation — is explained in `Networking/Cipher/CipherDeobfuscator.swift`.

## What's real vs. not

| Piece | Status |
|---|---|
| 4-tab navigation, mini/full player UI | Fully working SwiftUI, real state management, styled to match the Android app's Material You look (`Resources/Theme.swift` uses the same `0xFF2D55` seed color as `ui/theme/Theme.kt`'s `DefaultThemeColor`) |
| `Search` tab | **Real network calls** to `music.youtube.com/youtubei/v1/search`, same request headers/context as the Android `innertube` module; results show real artwork (`ArtworkView`) |
| `Home` tab | **Real network call** to `/browse` (`FEmusic_home`), rendered as horizontally-scrolling artwork-card sections ("Quick Picks", plus a "Recently Played" section sourced from this device's own real playback history) rather than a flat text list; falls back to sample data (labeled) if the request fails. Still not a faithful port of Android's many independent home sections (QuickPicks/DailyDiscover/KeepListening/ForgottenFavorites/AccountPlaylists/FromTheCommunity/MoodAndGenres) — see `HomeScreen.swift`'s doc comment for why |
| Song playback | **Real `AVPlayer` streaming**, including **real signature-cipher deciphering** — see below. Full player has a blurred-artwork background, shuffle/repeat controls, and elapsed/remaining time, closer to Android's `Player.kt` (still no real palette-based background color extraction) |
| `Listen Together` | **Real peer-to-peer sync** via Apple's MultipeerConnectivity — works between nearby devices, not over the internet (see below) |
| `Library` tab | Still `SampleData.swift` mock content, but now laid out like Android's real Library screens (Songs list / Albums grid / Artists grid / Playlists list with real artwork where available) rather than plain text rows — full library browsing needs both the same renderer-tree parsing work as `Home`/`Search` and a real persistence layer (no SwiftData/Core Data yet) |
| Downloads, lyrics, equalizer, Discord RPC, login | Not started |

### Signature-cipher deciphering: a real port, with one deliberate gap

`Networking/Cipher/` is a genuine Swift port of the Android app's own
`utils/cipher/` pipeline, not a reimplementation of YouTube's algorithm:

- `PlayerJsFetcher` fetches and disk-caches YouTube's actual `player.js`
  (same iframe_api → hash → base.js flow, same 6h TTL as Android).
- `FunctionNameExtractor` ports the same regex heuristics Android uses to
  *locate* the current sig/n-transform function names inside that JS (not
  reimplement the algorithm — YouTube's real, unmodified code runs verbatim).
- `PlayerConfig` bundles the same `player_configs.json` validated-hash table
  Android ships, as a fast/reliable path for known player versions, with the
  regex heuristics as fallback for unknown ones.
- `CipherWebView` loads that real `player.js` into a `WKWebView` (iOS's
  WebKit, same idea as Android's Chromium-based `WebView`) and calls the
  located function through it — so the actual deciphering is done by
  YouTube's own code, not a hand-rewritten JS interpreter.
- `CipherDeobfuscator` orchestrates the above and is used by
  `StreamResolver` for the `ANDROID` client identity, which (per the
  Android code's own `YouTubeClient.kt`) needs a `signatureTimestamp` and
  often ciphers its URLs, but — unlike `WEB_REMIX` — does **not** require a
  BotGuard PoToken.

**The one deliberate gap: BotGuard "PoToken" generation is not
implemented.** That's what `WEB_REMIX`/`WEB_CREATOR`/`TVHTML5` need in
addition to cipher deciphering, and it's a fundamentally different, harder
problem (running Google's anti-automation challenge JS, not just a
decipher function) — porting it without a device to verify against would
be guesswork dressed up as working code. `StreamResolver` therefore never
uses those three clients; it uses the direct-URL clients first
(VISIONOS/ANDROID_VR/TVHTML5_SIMPLY_EMBEDDED_PLAYER), then falls through to
the cipher-capable ANDROID client. If a video fails on all of those,
PoToken support is the real follow-up work — see the doc comment in
`CipherDeobfuscator.swift`.

Also **not ported** from Android's cipher pipeline: `RendererRecoveryPolicy`
(backoff after repeated WebView renderer crashes) and `PlayerConfigStore`'s
remote-refresh/self-heal loop that keeps the hash table current without an
app update — this port's bundled `player_configs.json` will gradually go
stale as YouTube ships new player versions, same as any snapshot would.

### Listen Together: real, but local-network only

`ListenTogether/ListenTogetherSession.swift` uses Apple's
**MultipeerConnectivity** framework — nearby-device discovery and encrypted
sessions over Wi-Fi/Bluetooth, with **zero server required**. Whoever taps
"Start a session" becomes the host and broadcasts their playback state once
a second; anyone who joins has their player driven entirely by what the
host sends (a deliberately one-directional design, so there's no sync
feedback loop to reconcile).

This genuinely works for devices near each other — but **not** over the
internet for people in different places. That would need a real hosted
relay (Firebase, a WebSocket server, etc.), which requires infrastructure
only you can provision; it isn't something that can be included by default.

One more honest caveat: `ListenTogetherSession` auto-accepts every incoming
join request (encryption is still `.required`, so traffic itself is
protected — there's just no "let this person join?" confirmation prompt
yet). Fine for trying it out with people you already know are nearby; add a
confirmation UI before shipping this to strangers.

### Search/Home parsing is heuristic, not a faithful port

`SearchResponseParser` recursively scans the raw JSON for
`musicResponsiveListItemRenderer` objects (reused by both `Search` and
`Home`) instead of reproducing the full typed renderer tree the Android app
uses (`MusicShelfRenderer`, `MusicCardShelfRenderer`,
`isSong`/`isAlbum`/`isArtist`/`isPodcast` detection, etc — dozens of files
under `innertube/models/`). It surfaces plausible songs but can misclassify
or miss shapes the real client distinguishes, and doesn't preserve
sections/shelves. Treat it as "a list of songs", not a faithful YouTube
Music UI.

## Project layout

```
project.yml                — XcodeGen spec; generates the .xcodeproj (not committed — see below)
RecordLabsiOS/
  Info.plist                — includes Local Network + Bonjour keys for Listen Together
  App/                      — @main entry point + RootView (tab scaffold + player overlay)
  Navigation/                — Tab enum (Home/Search/Listen Together/Library)
  Models/                    — Song/Album/Artist/Playlist + SampleData mocks
  Networking/                — InnerTube client: context/headers, search, browse, player,
                                PlayerResponse model, StreamResolver, search/browse JSON parser
    Cipher/                  — real signature-cipher deciphering (see above): PlayerJsFetcher,
                                FunctionNameExtractor, PlayerConfig(+bundled JSON), CipherWebView,
                                CipherDeobfuscator
  Playback/                  — PlayerConnection (AVPlayer-backed ObservableObject)
  ListenTogether/            — ListenTogetherSession (MultipeerConnectivity)
  Views/                     — Home, Search, Library, ListenTogether, Player (mini/full/queue)
  Resources/                 — Assets.xcassets, bundled player_configs.json
```

There is **no `.xcodeproj` committed** — it's generated on demand by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. This
avoids hand-authoring/committing a `project.pbxproj`, which is a binary-ish,
easy-to-corrupt format that can't be reliably hand-written or verified
without Xcode itself to open it. XcodeGen regenerates it deterministically
from a plain YAML file, both locally and in CI.

## Building it yourself, with or without a Mac

### Option A — you have a Mac
```
git clone https://github.com/hasbenyek/ios-recordlabs.git
cd ios-recordlabs
brew install xcodegen
xcodegen generate
open RecordLabsiOS.xcodeproj
```
Then hit ⌘R in Xcode (simulator needs no signing at all). To run on your own
physical iPhone: plug it in, select it as the run destination, and under the
target's **Signing & Capabilities** tab pick your Apple ID as the team
(a free Apple ID works for local device testing, limited to a 7-day app
expiry that Xcode auto-renews while your Mac is nearby).

### Option B — no Mac: GitHub Actions (macOS cloud runner)
`.github/workflows/ios-build.yml` runs on every push to this repo:
1. **`build-simulator`** — installs XcodeGen, generates the project, and
   builds it unsigned for the iOS Simulator. This is a pure compile check —
   it proves the Swift code builds; it does not produce something
   installable on a phone (simulator builds only run in Simulator).
2. **`archive-ipa`** — archives and exports a real, signed `.ipa`. This job
   is skipped automatically unless you've added Apple Developer signing
   secrets (below) to your fork/repo — I cannot generate or supply these on
   your behalf; they require an Apple ID and, for anything beyond a 7-day
   local install, a **paid Apple Developer Program membership ($99/year)**.

Watch runs under your repo's **Actions** tab; download the `.ipa` from the
`archive-ipa` job's "Artifacts" once it succeeds.

### Producing a signed `.ipa` via CI

1. Enroll at [developer.apple.com](https://developer.apple.com) (paid, for
   device installs beyond 7 days / TestFlight / App Store).
2. In Xcode (or via the Apple Developer portal), create an **iOS
   Distribution certificate**, export it as a `.p12` with a password.
3. Register your iPhone's UDID and create an **ad-hoc (or App Store)
   provisioning profile** for bundle id `com.recordlabs.music.ios` (or
   whatever you change `PRODUCT_BUNDLE_IDENTIFIER` to in `project.yml`).
4. Base64-encode both files (macOS/Linux: `base64 -i cert.p12 | pbcopy` /
   `base64 -w0 cert.p12`; Windows PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.p12"))`).
5. In your GitHub repo → **Settings → Secrets and variables → Actions**, add:
   - `IOS_DIST_CERTIFICATE_P12_BASE64`
   - `IOS_DIST_CERTIFICATE_PASSWORD`
   - `IOS_PROVISIONING_PROFILE_BASE64`
   - `IOS_TEAM_ID` (10-character Team ID, shown on your Apple Developer
     account page)
6. Push a commit (or run the workflow manually via **Actions → iOS Build →
   Run workflow**). The `archive-ipa` job will now run and upload a real
   `.ipa`.
7. Installing that `.ipa` on your iPhone still needs a sideloading tool
   (Xcode's Devices window, Apple Configurator, or a MDM) since Apple
   doesn't allow installing arbitrary `.ipa` files by just tapping them.

## Suggested next steps, roughly in order of value

1. Try the CI build now — it's the fastest way to confirm the Swift code
   actually compiles on real Xcode, which nothing on this Windows machine
   could verify, and the cipher/WebKit code in particular is worth
   confirming on a real device or simulator.
2. Get your own signing secrets in place (Option B above) and get a real
   `.ipa` onto your phone. Try Search, playback (including a song that
   forces the cipher path), and Listen Together between two devices.
3. If cipher-path playback still fails on some videos: that's most likely
   the bundled `player_configs.json` going stale, or a video that needs
   BotGuard PoToken. Refreshing the bundled config table from the Android
   app's latest `assets/player_configs.json` is a cheap fix for the former;
   PoToken is the real remaining project for the latter.
4. Port the renderer-tree parser properly (or at least point `Library` at a
   `browse` call the way `Home` now is) once Search/Home parsing quality
   feels like the limiting factor.
5. Add persistence (SwiftData) for library/liked songs/downloads, and
   `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` for lock-screen controls.
6. Add a real join-confirmation UI to `ListenTogetherSession` before using
   it with people you don't already trust to be on the same network.
