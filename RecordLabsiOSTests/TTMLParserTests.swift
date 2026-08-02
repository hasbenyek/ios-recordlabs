import XCTest
@testable import RecordLabsiOS

final class TTMLParserTests: XCTestCase {
    func testLineLevelTiming() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml">
        <body><div><p begin="00:00:01.000" end="00:00:03.000">Hello world</p></div></body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        XCTAssertEqual(outcome.lines.count, 1)
        XCTAssertEqual(outcome.lines[0].startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(outcome.lines[0].text, "Hello world")
        XCTAssertFalse(outcome.lines[0].isTimingInferred)
    }

    func testWordLevelTiming() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml">
        <body><div><p begin="00:00:01.000">
        <span begin="00:00:01.000" end="00:00:01.500">Hello</span>
        <span begin="00:00:01.500" end="00:00:02.000">world</span>
        </p></div></body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        XCTAssertEqual(outcome.lines.count, 1)
        let line = outcome.lines[0]
        XCTAssertEqual(line.words?.count, 2)
        XCTAssertEqual(line.words?.first?.text, "Hello")
        XCTAssertEqual(line.words?.first?.startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(line.words?.last?.endTime, 2.0, accuracy: 0.001)
        XCTAssertTrue(line.isWordSynced)
    }

    func testBackgroundVocals() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
        <body><div><p begin="00:00:01.000">
        <span begin="00:00:01.000" end="00:00:01.500">Main</span>
        <span ttm:role="x-bg" begin="00:00:01.600" end="00:00:02.000">Background</span>
        </p></div></body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        XCTAssertEqual(outcome.lines.count, 2)
        XCTAssertTrue(outcome.lines.contains { $0.text == "Main" && !$0.isBackground })
        XCTAssertTrue(outcome.lines.contains { $0.text == "Background" && $0.isBackground })
    }

    func testMultipleAgentsDoNotCollapse() {
        // Fixed vs. Android: Android's `TTMLParser.toLRC` remaps every
        // agent into a fixed v1/v2 namespace and a 3rd distinct agent
        // silently collapses into v1. This parser keeps raw agent ids, so
        // a 3rd (or 4th, ...) agent keeps its own identity.
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
        <body>
        <div><p ttm:agent="v1" begin="00:00:01.000">Singer one</p></div>
        <div><p ttm:agent="v2" begin="00:00:02.000">Singer two</p></div>
        <div><p ttm:agent="v3" begin="00:00:03.000">Singer three</p></div>
        </body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        XCTAssertEqual(outcome.lines.count, 3)
        let singerThree = outcome.lines.first { $0.text == "Singer three" }
        XCTAssertEqual(singerThree?.agent, "v3", "A 3rd distinct agent must keep its own identity, not collapse into v1")
        let singerOne = outcome.lines.first { $0.text == "Singer one" }
        XCTAssertEqual(singerOne?.agent, "v1")
    }

    func testMalformedXMLReturnsEmptyWithWarning() {
        let malformed = "<tt><body><div><p begin=\"00:00:01.000\">Unclosed"
        let outcome = TTMLParser.parse(malformed)

        XCTAssertTrue(outcome.lines.isEmpty)
        XCTAssertFalse(outcome.warnings.isEmpty)
    }

    func testUntimedLineIsKeptNotDropped() {
        // Fixed vs. Android: `findFirstSpanBegin` returning nil silently
        // drops the whole <p>. Here it's kept with startTime inherited
        // from the previous line and isTimingInferred = true.
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml">
        <body><div>
        <p begin="00:00:01.000">Timed line</p>
        <p>Untimed line with no begin at all</p>
        </div></body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        XCTAssertEqual(outcome.lines.count, 2)
        let untimed = outcome.lines.first { $0.text == "Untimed line with no begin at all" }
        XCTAssertNotNil(untimed)
        XCTAssertTrue(untimed?.isTimingInferred ?? false)
    }

    func testInvalidTimingValueIsNotDefaultedToZero() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml">
        <body><div><p begin="not-a-time">Invalid begin</p></div></body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        XCTAssertEqual(outcome.lines.count, 1)
        XCTAssertTrue(outcome.lines[0].isTimingInferred, "An unparseable begin value must not silently become 0 as if it were real timing")
    }

    func testNestedWordLevelSpansInsideBackground() {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
        <body><div><p begin="00:00:01.000">
        <span begin="00:00:01.000" end="00:00:01.400">Main</span>
        <span ttm:role="x-bg" begin="00:00:01.500">
        <span begin="00:00:01.500" end="00:00:01.700">bg1</span>
        <span begin="00:00:01.700" end="00:00:01.900">bg2</span>
        </span>
        </p></div></body>
        </tt>
        """
        let outcome = TTMLParser.parse(ttml)

        let bgLine = outcome.lines.first { $0.isBackground }
        XCTAssertNotNil(bgLine)
        XCTAssertEqual(bgLine?.words?.count, 2)
        XCTAssertEqual(bgLine?.words?.map(\.text), ["bg1", "bg2"])
    }
}
