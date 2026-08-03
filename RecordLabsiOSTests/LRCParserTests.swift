import XCTest
@testable import RecordLabsiOS

final class LRCParserTests: XCTestCase {
    func testStandardTimestamps() {
        let lrc = """
        [00:12.00]First line
        [00:17.50]Second line
        """
        let result = LRCParser.parse(lrc)

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].startTime, 12.0, accuracy: 0.001)
        XCTAssertEqual(result.lines[0].text, "First line")
        XCTAssertEqual(result.lines[1].startTime, 17.5, accuracy: 0.001)
        XCTAssertFalse(result.lines[0].isTimingInferred)
    }

    func testMultipleTimestampsOnOneLine() {
        let result = LRCParser.parse("[00:10.00][00:40.00]Chorus")

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(Set(result.lines.map(\.text)), ["Chorus"])
        XCTAssertEqual(result.lines.map(\.startTime).sorted(), [10.0, 40.0])
    }

    func testMalformedTimestampIsNotDefaultedToZero() {
        let lrc = "[xx:yy]Broken line\n[00:05.00]Good line"
        let result = LRCParser.parse(lrc)

        // Fixed vs. Android: a malformed timestamp must never silently
        // become a "real" 00:00 entry.
        XCTAssertFalse(result.lines.contains { $0.text == "Broken line" && $0.startTime == 0 && !$0.isTimingInferred })
        XCTAssertFalse(result.warnings.isEmpty, "A malformed timestamp must be recorded, not silently ignored")
        // Fixed vs. Android: it's kept (not dropped) as an inferred-timing line.
        XCTAssertTrue(result.lines.contains { $0.text == "Broken line" && $0.isTimingInferred })
        XCTAssertTrue(result.lines.contains { $0.text == "Good line" && !$0.isTimingInferred })
    }

    func testEmptyLyrics() {
        let result = LRCParser.parse("")
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertFalse(result.isSynced)
    }

    func testDuplicateTimestampsAreBothKept() {
        let result = LRCParser.parse("[00:05.00]Voice A\n[00:05.00]Voice B")

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(Set(result.lines.map(\.text)), ["Voice A", "Voice B"])
    }

    func testOffsetHandling() {
        let result = LRCParser.parse("[offset:+1000]\n[00:10.00]Line")

        XCTAssertEqual(result.offsetMs, 1000)
        XCTAssertEqual(result.lines.first?.startTime, 9.0, accuracy: 0.001)
    }

    func testUntimedLineIsKeptNotDropped() {
        let result = LRCParser.parse("[00:05.00]Timed line\nUntimed trailing line")

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertTrue(result.lines.contains { $0.text == "Untimed trailing line" && $0.isTimingInferred })
    }

    func testMetadataTagsAreNotTreatedAsLyrics() {
        let lrc = "[ar:Some Artist]\n[ti:Some Title]\n[00:01.00]Real lyric"
        let result = LRCParser.parse(lrc)

        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines.first?.text, "Real lyric")
    }
}
