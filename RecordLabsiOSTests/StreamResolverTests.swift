import XCTest
@testable import RecordLabsiOS

final class StreamResolverTests: XCTestCase {
    func testUnsupportedFormatInOneClientContinuesToNextClient() async throws {
        let client = MockStreamResolverClient { identity in
            identity.clientName == "VISIONOS" ? Self.response(mimeType: "audio/webm; codecs=\"opus\"") : Self.response(mimeType: "audio/mp4; codecs=\"mp4a.40.2\"")
        }

        let resolved = try await StreamResolver.resolveStreamURL(videoId: "v1", client: client, signatureTimestampProvider: { nil })

        XCTAssertEqual(resolved.diagnostics.selectedClient, "ANDROID_VR")
    }

    func testDecodeFailureContinuesToNextClient() async throws {
        let client = MockStreamResolverClient { identity in
            identity.clientName == "VISIONOS" ? Data("bad json".utf8) : Self.response(mimeType: "audio/mp4; codecs=\"mp4a.40.2\"")
        }

        let resolved = try await StreamResolver.resolveStreamURL(videoId: "v1", client: client, signatureTimestampProvider: { nil })

        XCTAssertEqual(resolved.diagnostics.selectedClient, "ANDROID_VR")
    }

    func testAllClientsFailProducesStreamResolutionFailure() async {
        let client = MockStreamResolverClient { _ in Data("bad json".utf8) }

        do {
            _ = try await StreamResolver.resolveStreamURL(videoId: "v1", client: client, signatureTimestampProvider: { nil })
            XCTFail("Expected resolution failure")
        } catch let error as PlayerError {
            guard case .streamResolutionFailure = error else { XCTFail("Unexpected PlayerError: \(error)"); return }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIOSFallbackIsTriedAfterEarlierClientsFail() async throws {
        let client = MockStreamResolverClient { identity in
            identity.clientName == "IOS"
                ? Self.response(mimeType: "audio/mp4; codecs=\"mp4a.40.2\"")
                : Self.response(mimeType: "audio/webm; codecs=\"opus\"")
        }

        let resolved = try await StreamResolver.resolveStreamURL(videoId: "v1", client: client, signatureTimestampProvider: { nil })

        XCTAssertEqual(resolved.diagnostics.selectedClient, "IOS")
        XCTAssertEqual(resolved.diagnostics.pathType, .direct)
    }

    private static func response(mimeType: String) -> Data {
        let json = """
        {"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"itag":140,"url":"https://example.invalid/audio","mimeType":"\(mimeType)","bitrate":128000,"audioQuality":"AUDIO_QUALITY_MEDIUM"}]}}
        """
        return Data(json.utf8)
    }
}

private actor MockStreamResolverClient: StreamResolverClient {
    private let responseForIdentity: (YouTubeClientIdentity) -> Data

    init(responseForIdentity: @escaping (YouTubeClientIdentity) -> Data) {
        self.responseForIdentity = responseForIdentity
    }

    func player(videoId: String, identity: YouTubeClientIdentity, signatureTimestamp: Int?) async throws -> Data {
        responseForIdentity(identity)
    }
}
