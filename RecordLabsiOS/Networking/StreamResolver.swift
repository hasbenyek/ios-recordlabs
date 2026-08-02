import Foundation

/// Resolves a playable, `AVPlayer`-compatible audio URL for a YouTube video id.
///
/// Format selection is delegated to `AudioFormatSelector` (kept separate so
/// it's unit-testable without networking) — see that file's doc comment
/// for why iOS requires AAC/MP4 and rejects Opus/WebM, unlike Android.
///
/// Two tiers, in order:
/// 1. **Direct-URL clients** (`YouTubeClientIdentity.directURLFallbackOrder`)
///    — historically return a `url` with no `signatureCipher`, no deciphering needed.
/// 2. **Cipher-capable client** (`YouTubeClientIdentity.androidMobile`) — if
///    every direct-URL client came back cipher-only, unsupported-codec-only,
///    or failed, this tries the ANDROID client and runs any
///    `signatureCipher` format through `CipherDeobfuscator`.
///
/// Every attempt is recorded into a `StreamDiagnostics` value so failures
/// are explainable in-app without ever surfacing the resolved URL itself.
enum StreamResolver {
    static func resolveStreamURL(
        videoId: String,
        client: StreamResolverClient = InnerTubeClient.shared
    ) async throws -> ResolvedStream {
        var attemptedClients: [String] = []
        var formatsSeen: Set<String> = []

        for identity in YouTubeClientIdentity.directURLFallbackOrder {
            try Task.checkCancellation()
            attemptedClients.append(identity.clientName)
            do {
                if let resolved = try await resolveDirect(videoId: videoId, identity: identity, client: client, attempted: attemptedClients, formatsSeen: &formatsSeen) {
                    return resolved
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep the fallback chain alive for HTTP, decoding, and
                // other client-specific failures, not only URLError.
                if attemptedClients.count == YouTubeClientIdentity.directURLFallbackOrder.count,
                   let urlError = error as? URLError {
                    throw PlayerError.network(urlError.localizedDescription)
                }
                continue
            }
        }

        attemptedClients.append(YouTubeClientIdentity.androidMobile.clientName)
        try Task.checkCancellation()
        if let resolved = try await resolveViaCipher(videoId: videoId, client: client, attempted: attemptedClients, formatsSeen: &formatsSeen) {
            return resolved
        }

        if formatsSeen.isEmpty {
            throw PlayerError.streamResolutionFailure("No audio formats were returned by any client")
        }
        throw PlayerError.unsupportedFormat(availableFormats: Array(formatsSeen).sorted())
    }

    private static func resolveDirect(
        videoId: String,
        identity: YouTubeClientIdentity,
        client: StreamResolverClient,
        attempted: [String],
        formatsSeen: inout Set<String>
    ) async throws -> ResolvedStream? {
        let data = try await client.player(videoId: videoId, identity: identity, signatureTimestamp: nil)
        let response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        guard response.playabilityStatus.status == "OK" else { return nil }

        let allAudio = response.streamingData?.adaptiveFormats ?? []
        formatsSeen.formUnion(AudioFormatSelector.describeAudioFormats(allAudio))

        guard let best = AudioFormatSelector.selectBest(from: allAudio.filter { $0.url != nil && $0.signatureCipher == nil }),
              let urlString = best.url, let url = URL(string: urlString) else {
            return nil
        }

        return ResolvedStream(
            url: url,
            diagnostics: StreamDiagnostics(
                selectedClient: identity.clientName,
                pathType: .direct,
                mimeType: best.container,
                codec: best.codec ?? "unknown",
                bitrateKbps: best.bitrate / 1000,
                expiresInSeconds: response.streamingData?.expiresInSeconds.flatMap(Int.init),
                fallbackClientsAttempted: attempted,
                finalErrorCategory: nil
            )
        )
    }

    private static func resolveViaCipher(
        videoId: String,
        client: StreamResolverClient,
        attempted: [String],
        formatsSeen: inout Set<String>
    ) async throws -> ResolvedStream? {
        let identity = YouTubeClientIdentity.androidMobile
        let signatureTimestamp = await CipherDeobfuscator.shared.signatureTimestamp()

        let data: Data
        do {
            data = try await client.player(videoId: videoId, identity: identity, signatureTimestamp: signatureTimestamp)
        } catch {
            throw PlayerError.network(error.localizedDescription)
        }

        let response: PlayerResponse
        do {
            response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        } catch {
            throw PlayerError.streamResolutionFailure("Couldn't parse the player response: \(error.localizedDescription)")
        }
        guard response.playabilityStatus.status == "OK" else {
            throw PlayerError.streamResolutionFailure("YouTube reported this video isn't playable (\(response.playabilityStatus.status))")
        }

        let allAudio = response.streamingData?.adaptiveFormats ?? []
        formatsSeen.formUnion(AudioFormatSelector.describeAudioFormats(allAudio))

        guard let best = AudioFormatSelector.selectBest(from: allAudio) else {
            return nil
        }

        let resolvedURL: URL
        if let urlString = best.url, let url = URL(string: urlString) {
            resolvedURL = await CipherDeobfuscator.shared.transformNParam(in: url)
        } else if let cipher = best.signatureCipher {
            let url: URL
            do {
                url = try await CipherDeobfuscator.shared.deobfuscateStreamURL(signatureCipher: cipher)
            } catch {
                throw PlayerError.cipherFailure(error.localizedDescription)
            }
            resolvedURL = await CipherDeobfuscator.shared.transformNParam(in: url)
        } else {
            return nil
        }

        return ResolvedStream(
            url: resolvedURL,
            diagnostics: StreamDiagnostics(
                selectedClient: identity.clientName,
                pathType: best.signatureCipher != nil ? .cipher : .direct,
                mimeType: best.container,
                codec: best.codec ?? "unknown",
                bitrateKbps: best.bitrate / 1000,
                expiresInSeconds: response.streamingData?.expiresInSeconds.flatMap(Int.init),
                fallbackClientsAttempted: attempted,
                finalErrorCategory: nil
            )
        )
    }
}

struct ResolvedStream {
    var url: URL
    var diagnostics: StreamDiagnostics
}
