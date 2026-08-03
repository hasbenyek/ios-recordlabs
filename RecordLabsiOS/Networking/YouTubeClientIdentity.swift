import Foundation

/// Mirrors `innertube/models/YouTubeClient.kt`. Each "client identity" is a
/// combination of headers/UA that makes YouTube's private `/youtubei/v1/*`
/// endpoints treat the request as coming from a specific first-party app
/// (the web player, the Android app, an Android VR headset, etc). Different
/// identities get different `streamingData` in the `/player` response —
/// some include a direct `url`, others require deciphering a
/// `signatureCipher` (see `Cipher/CipherDeobfuscator.swift`).
struct YouTubeClientIdentity {
    let clientName: String
    let clientVersion: String
    let clientId: String
    let userAgent: String
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?
    /// Mirrors `YouTubeClient.useSignatureTimestamp` — whether the `/player`
    /// request body must carry `playbackContext.contentPlaybackContext.signatureTimestamp`.
    let usesSignatureTimestamp: Bool

    static let originYouTubeMusic = "https://music.youtube.com"
    static let refererYouTubeMusic = originYouTubeMusic + "/"
    static let apiURL = URL(string: originYouTubeMusic + "/youtubei/v1/")!
    static let songSearchParams = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"

    init(
        clientName: String,
        clientVersion: String,
        clientId: String,
        userAgent: String,
        osName: String? = nil,
        osVersion: String? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        usesSignatureTimestamp: Bool = false
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.clientId = clientId
        self.userAgent = userAgent
        self.osName = osName
        self.osVersion = osVersion
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.usesSignatureTimestamp = usesSignatureTimestamp
    }

    /// Used for search/browse — the standard YouTube Music web client.
    static let webRemix = YouTubeClientIdentity(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260213.01.00",
        clientId: "67",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    )

    /// Per the Android app's own comment (`YTPlayerUtils.kt`): this client's
    /// CDN URL "has no spc throttle gate" — it returns a directly playable
    /// `url` with no signature cipher, which is why it's tried first among
    /// fallbacks. Internal/unreleased client name; may stop working without
    /// notice since it isn't a real shipped Apple product.
    static let visionOS = YouTubeClientIdentity(
        clientName: "VISIONOS",
        clientVersion: "0.1",
        clientId: "101",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        osName: "visionOS",
        osVersion: "1.3.21O771",
        deviceMake: "Apple",
        deviceModel: "RealityDevice14,1"
    )

    /// Android VR client, non-adaptive-bitrate variant — historically also
    /// tends to return direct (non-ciphered) `url`s.
    static let androidVR = YouTubeClientIdentity(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3"
    )

    /// Embedded TV client — login-free, bypasses age-restriction for
    /// logged-out users. Also generally non-ciphered.
    static let tvEmbedded = YouTubeClientIdentity(
        clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        clientVersion: "2.0",
        clientId: "85",
        userAgent: "Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15"
    )

    /// Order matters: tried top-to-bottom until one yields a directly usable
    /// (non-ciphered) audio format. Mirrors the *shape* of
    /// `YTPlayerUtils.STREAM_FALLBACK_CLIENTS` on Android, restricted to the
    /// subset that doesn't need signature/PoToken deciphering.
    static let directURLFallbackOrder: [YouTubeClientIdentity] = [
        .visionOS, .androidVR, .tvEmbedded,
    ]

    /// The Android ("MOBILE") client — per `YouTubeClient.kt`, it needs a
    /// `signatureTimestamp` and often ciphers its stream URLs, but (unlike
    /// `WEB_REMIX`) does NOT require a BotGuard PoToken. That makes it the
    /// one client where `StreamResolver` will actually invoke
    /// `CipherDeobfuscator` — see that file for why every *other* client
    /// with a cipher is deliberately left unresolved instead.
    static let androidMobile = YouTubeClientIdentity(
        clientName: "ANDROID",
        clientVersion: "21.03.38",
        clientId: "3",
        userAgent: "com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip",
        usesSignatureTimestamp: true
    )
}
