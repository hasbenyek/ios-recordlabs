import Foundation

/// Resolves a playable audio URL for a YouTube video id.
///
/// Two tiers, in order:
/// 1. **Direct-URL clients** (`YouTubeClientIdentity.directURLFallbackOrder`)
///    — VISIONOS/ANDROID_VR/TVHTML5_SIMPLY_EMBEDDED_PLAYER historically
///    return a `url` with no `signatureCipher` at all, so no deciphering is
///    needed. Cheapest and fastest when it works.
/// 2. **Cipher-capable client** (`YouTubeClientIdentity.androidMobile`) — if
///    every direct-URL client came back cipher-only or failed, this tries
///    the ANDROID client and, if its format has a `signatureCipher`, runs it
///    through `CipherDeobfuscator` (a real WebView executing YouTube's own
///    player.js — see that file for exactly what it does and doesn't
///    handle) to produce a playable URL.
///
/// Deliberately still NOT implemented: BotGuard "PoToken" generation, which
/// only `WEB_REMIX`/`WEB_CREATOR`/`TVHTML5` require (not the ANDROID
/// client used here). That remains the one genuinely unimplemented piece —
/// see `CipherDeobfuscator.swift`'s doc comment. If both tiers here fail,
/// that's most likely YouTube having tightened the ANDROID client too,
/// which would require PoToken support to work around.
enum StreamResolver {
    static func resolveStreamURL(videoId: String) async throws -> URL {
        for identity in YouTubeClientIdentity.directURLFallbackOrder {
            if let url = try? await resolveDirect(videoId: videoId, identity: identity) {
                return url
            }
        }

        if let url = try? await resolveViaCipher(videoId: videoId) {
            return url
        }

        throw InnerTubeError.noPlayableFormat
    }

    private static func resolveDirect(videoId: String, identity: YouTubeClientIdentity) async throws -> URL {
        let data = try await InnerTubeClient.shared.player(videoId: videoId, identity: identity)
        let response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        guard response.playabilityStatus.status == "OK" else { throw InnerTubeError.noPlayableFormat }

        let playableAudioFormats = (response.streamingData?.adaptiveFormats ?? [])
            .filter { $0.mimeType.hasPrefix("audio/") && $0.signatureCipher == nil && $0.url != nil }
            .sorted { $0.bitrate > $1.bitrate }

        guard let best = playableAudioFormats.first, let urlString = best.url, let url = URL(string: urlString) else {
            throw InnerTubeError.noPlayableFormat
        }
        return url
    }

    private static func resolveViaCipher(videoId: String) async throws -> URL {
        let identity = YouTubeClientIdentity.androidMobile
        let signatureTimestamp = await CipherDeobfuscator.shared.signatureTimestamp()

        let data = try await InnerTubeClient.shared.player(videoId: videoId, identity: identity, signatureTimestamp: signatureTimestamp)
        let response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        guard response.playabilityStatus.status == "OK" else { throw InnerTubeError.noPlayableFormat }

        let audioFormats = (response.streamingData?.adaptiveFormats ?? [])
            .filter { $0.mimeType.hasPrefix("audio/") }
            .sorted { $0.bitrate > $1.bitrate }

        for format in audioFormats {
            if let urlString = format.url, let url = URL(string: urlString) {
                return await CipherDeobfuscator.shared.transformNParam(in: url)
            }
            if let cipher = format.signatureCipher {
                let url = try await CipherDeobfuscator.shared.deobfuscateStreamURL(signatureCipher: cipher)
                return await CipherDeobfuscator.shared.transformNParam(in: url)
            }
        }
        throw InnerTubeError.noPlayableFormat
    }
}
