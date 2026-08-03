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
        client: StreamResolverClient = InnerTubeClient.shared,
        signatureTimestampProvider: @escaping @Sendable () async -> Int? = {
            await CipherDeobfuscator.shared.signatureTimestamp()
        }
    ) async throws -> ResolvedStream {
        var attemptedClients: [String] = []
        var formatsSeen: Set<String> = []
        var lastCipherError: PlayerError?

        for identity in YouTubeClientIdentity.playbackFallbackOrder {
            try Task.checkCancellation()
            attemptedClients.append(identity.clientName)
            do {
                if let resolved = try await resolveFromClient(videoId: videoId, identity: identity, client: client, attempted: attemptedClients, formatsSeen: &formatsSeen, signatureTimestampProvider: signatureTimestampProvider) {
                    return resolved
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as PlayerError {
                if case .cipherFailure = error { lastCipherError = error }
            } catch {
                // A client-specific HTTP/decode failure must not prevent a
                // later client from supplying a playable stream.
                continue
            }
        }

        if formatsSeen.isEmpty {
            throw PlayerError.streamResolutionFailure("No audio formats were returned by any client")
        }
        if let lastCipherError { throw lastCipherError }
        if formatsSeen.contains(where: { $0.hasPrefix("audio/mp4") }) {
            throw PlayerError.streamResolutionFailure("AAC/MP4 was returned, but none of the attempted clients supplied a usable stream URL or cipher")
        }
        throw PlayerError.unsupportedFormat(availableFormats: Array(formatsSeen).sorted())
    }

    private static func resolveFromClient(
        videoId: String,
        identity: YouTubeClientIdentity,
        client: StreamResolverClient,
        attempted: [String],
        formatsSeen: inout Set<String>,
        signatureTimestampProvider: @escaping @Sendable () async -> Int?
    ) async throws -> ResolvedStream? {
        let signatureTimestamp = identity.usesSignatureTimestamp
            ? await signatureTimestampProvider()
            : nil
        let data = try await client.player(videoId: videoId, identity: identity, signatureTimestamp: signatureTimestamp)
        let response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        guard response.playabilityStatus.status == "OK" else { return nil }

        let allAudio = response.streamingData?.adaptiveFormats ?? []
        formatsSeen.formUnion(AudioFormatSelector.describeAudioFormats(allAudio))

        guard let best = AudioFormatSelector.selectBest(from: allAudio) else {
            return nil
        }

        let resolvedURL: URL
        if let urlString = best.url, let url = URL(string: urlString) {
            resolvedURL = await CipherDeobfuscator.shared.transformNParam(in: url)
        } else if let cipher = best.streamCipher {
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
                pathType: best.streamCipher != nil ? .cipher : .direct,
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
