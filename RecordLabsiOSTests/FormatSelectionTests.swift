import XCTest
@testable import RecordLabsiOS

final class FormatSelectionTests: XCTestCase {
    private func format(
        itag: Int,
        mimeType: String,
        bitrate: Int,
        audioQuality: String? = nil,
        width: Int? = nil,
        url: String? = "https://example.invalid/stream"
    ) -> PlayerResponse.StreamingData.Format {
        PlayerResponse.StreamingData.Format(
            itag: itag,
            url: url,
            mimeType: mimeType,
            bitrate: bitrate,
            audioQuality: audioQuality,
            approxDurationMs: nil,
            width: width,
            signatureCipher: nil
        )
    }

    func testAACPreferredOverWebM() {
        let aac = format(itag: 140, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 128_000, audioQuality: "AUDIO_QUALITY_MEDIUM")
        let webm = format(itag: 251, mimeType: #"audio/webm; codecs="opus""#, bitrate: 160_000, audioQuality: "AUDIO_QUALITY_HIGH")

        let best = AudioFormatSelector.selectBest(from: [aac, webm])

        XCTAssertEqual(best?.itag, 140, "WebM/Opus must never be selected, even at a higher bitrate/quality label")
    }

    func testOnlyWebMIsUnsupported() {
        let webm = format(itag: 251, mimeType: #"audio/webm; codecs="opus""#, bitrate: 160_000, audioQuality: "AUDIO_QUALITY_HIGH")

        XCTAssertNil(AudioFormatSelector.selectBest(from: [webm]), "With only WebM/Opus available there is no AVPlayer-compatible format")
    }

    func testVideoOnlyEntriesAreExcluded() {
        let video = format(itag: 137, mimeType: #"video/mp4; codecs="avc1.640028""#, bitrate: 5_000_000, width: 1920)
        let aac = format(itag: 140, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 128_000, audioQuality: "AUDIO_QUALITY_MEDIUM")

        let best = AudioFormatSelector.selectBest(from: [video, aac])

        XCTAssertEqual(best?.itag, 140)
        XCTAssertFalse(AudioFormatSelector.describeAudioFormats([video, aac]).contains { $0.hasPrefix("video/") })
    }

    func testAACRemainsAudioWhenResponseIncludesWidthField() {
        let aac = format(
            itag: 140,
            mimeType: #"audio/mp4; codecs="mp4a.40.2""#,
            bitrate: 128_000,
            audioQuality: "AUDIO_QUALITY_MEDIUM",
            width: 0
        )

        XCTAssertEqual(AudioFormatSelector.selectBest(from: [aac])?.itag, 140)
    }

    func testPlainAACTokenInMIMEIsPlayable() {
        let aac = format(
            itag: 140,
            mimeType: "audio/mp4 mp4a.40.2",
            bitrate: 128_000,
            audioQuality: "AUDIO_QUALITY_MEDIUM"
        )

        XCTAssertEqual(AudioFormatSelector.selectBest(from: [aac])?.itag, 140)
    }

    func testMalformedMimeTypeIsRejectedSafely() {
        let malformed = format(itag: 999, mimeType: "not-a-real-mime-type", bitrate: 999_000, audioQuality: "AUDIO_QUALITY_HIGH")
        let aac = format(itag: 140, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 128_000, audioQuality: "AUDIO_QUALITY_MEDIUM")

        let best = AudioFormatSelector.selectBest(from: [malformed, aac])

        XCTAssertEqual(best?.itag, 140, "A malformed mimeType must never crash the selector and must never be chosen")
    }

    func testHigherQualityTierBeatsHigherBitrateInLowerTier() {
        let mediumHighBitrate = format(itag: 141, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 256_000, audioQuality: "AUDIO_QUALITY_MEDIUM")
        let highLowerBitrate = format(itag: 140, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 128_000, audioQuality: "AUDIO_QUALITY_HIGH")

        let best = AudioFormatSelector.selectBest(from: [mediumHighBitrate, highLowerBitrate])

        XCTAssertEqual(best?.itag, 140, "Quality label must win over raw bitrate — a format is never chosen purely for having a higher bitrate")
    }

    func testBitrateBreaksTiesWithinSameQualityTier() {
        let lowerBitrate = format(itag: 140, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 128_000, audioQuality: "AUDIO_QUALITY_HIGH")
        let higherBitrate = format(itag: 141, mimeType: #"audio/mp4; codecs="mp4a.40.2""#, bitrate: 192_000, audioQuality: "AUDIO_QUALITY_HIGH")

        let best = AudioFormatSelector.selectBest(from: [lowerBitrate, higherBitrate])

        XCTAssertEqual(best?.itag, 141, "Within the same quality tier, higher bitrate should win")
    }
}
