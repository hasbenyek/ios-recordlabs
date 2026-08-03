import Foundation

/// Swift TTML parser for BetterLyrics/Binimum-shaped lyrics documents —
/// same source format as Android's `betterlyrics/.../TTMLParser.kt`, built
/// on `Foundation.XMLParser` (SAX-based; Foundation has no DOM API, so this
/// file first builds a minimal tree via `TTMLTreeBuilder` and then walks it
/// the same way the Android DOM-based parser does).
///
/// Deliberately fixes two behaviors the migration audit found in the
/// Android parser, rather than reproducing them:
/// - A `<p>` with **no timing anywhere** (no `begin`, no `ttp:begin`, no
///   timed child `<span>`) is **kept**, not silently dropped — its
///   `startTime` is inferred from the previous timed line and
///   `isTimingInferred` is set, exactly like `LRCParser`'s equivalent fix.
///   Android's `findFirstSpanBegin` fallback returns `nil` and the whole
///   `<p>` vanishes with no diagnostic.
/// - Agent identifiers are kept **raw** (whatever the source used —
///   `"v1"`, `"v2"`, `"v3"`, a named voice, anything), never remapped into
///   a fixed two-slot `v1`/`v2` namespace. Android's `toLRC` collapses any
///   3rd+ distinct agent into `v1`, silently merging a third singer's
///   lines into the primary vocalist's. Keeping the raw identifier means a
///   3rd agent can never collide with the 1st.
enum TTMLParser {
    struct ParseOutcome {
        var lines: [LyricsLine]
        var warnings: [String]
    }

    private static let beginAttrNames = ["begin", "ttp:begin"]
    private static let endAttrNames = ["end", "ttp:end"]
    private static let agentAttrNames = ["ttm:agent", "agent"]
    private static let roleAttrNames = ["ttm:role", "role"]

    static func parse(_ ttml: String) -> ParseOutcome {
        let builder = TTMLTreeBuilder()
        let parser = XMLParser(data: Data(ttml.utf8))
        parser.delegate = builder
        guard parser.parse(), let root = builder.root, !builder.hadError else {
            return ParseOutcome(lines: [], warnings: ["Malformed TTML: XML could not be parsed"])
        }

        var globalOffset: TimeInterval = 0
        if let audio = findAll(root, named: "audio").first,
           let offsetString = audio.attr(["lyricOffset"]),
           let parsed = parseTime(offsetString) {
            globalOffset = parsed
        }

        var lines: [LyricsLine] = []
        var warnings: [String] = []
        var nextId = 0
        var lastTimestamp: TimeInterval = 0

        for p in findAll(root, named: "p") {
            appendLines(for: p, offset: globalOffset, lines: &lines, warnings: &warnings, nextId: &nextId, lastTimestamp: &lastTimestamp)
        }

        lines.sort { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        return ParseOutcome(lines: lines, warnings: warnings)
    }

    private static func appendLines(
        for p: XMLNode,
        offset: TimeInterval,
        lines: inout [LyricsLine],
        warnings: inout [String],
        nextId: inout Int,
        lastTimestamp: inout TimeInterval
    ) {
        let agent = p.attr(agentAttrNames) ?? enclosingDivAgent(p)
        let isPBackground = (p.attr(roleAttrNames)?.contains("x-bg") ?? false)

        var mainWords: [LyricsWord] = []
        var bgLines: [(startTime: TimeInterval, words: [LyricsWord], text: String)] = []
        var mainTextFallback = ""

        let childSpans = p.children.filter { localName($0.name) == "span" }
        if childSpans.isEmpty {
            mainTextFallback = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for span in childSpans {
            let role = span.attr(roleAttrNames) ?? ""
            if role.contains("x-translation") || role.contains("x-roman") { continue }

            if role.contains("x-bg") && !isPBackground {
                let (words, text) = wordsAndText(from: span, offset: offset, warnings: &warnings)
                let start = words.map(\.startTime).min() ?? (parseTime(span.attr(beginAttrNames) ?? "").map { $0 + offset } ?? lastTimestamp)
                bgLines.append((startTime: start, words: words, text: text))
                continue
            }

            let word = wordSpan(from: span, offset: offset, warnings: &warnings)
            if let word { mainWords.append(word) }
        }

        // Line-level begin: p's own attribute, else earliest timed direct
        // child span, else "no timing anywhere" — the fixed case.
        let explicitBegin = p.attr(beginAttrNames).flatMap { parseTime($0) }.map { $0 + offset }
        let earliestSpanBegin = childSpans.compactMap { $0.attr(beginAttrNames).flatMap(parseTime) }.min().map { $0 + offset }
        let mainStart = explicitBegin ?? earliestSpanBegin ?? mainWords.map(\.startTime).min()

        let mainText = mainWords.isEmpty ? mainTextFallback : mainWords.map(\.text).joined(separator: " ")
        if !mainText.isEmpty {
            let isInferred = mainStart == nil
            let startTime = mainStart ?? lastTimestamp
            lines.append(LyricsLine(
                id: nextId,
                startTime: startTime,
                text: mainText,
                words: mainWords.isEmpty ? nil : mainWords,
                agent: agent,
                isBackground: isPBackground,
                isTimingInferred: isInferred
            ))
            nextId += 1
            lastTimestamp = startTime
        }

        for bg in bgLines {
            let text = bg.words.isEmpty ? bg.text : bg.words.map(\.text).joined(separator: " ")
            guard !text.isEmpty else { continue }
            lines.append(LyricsLine(
                id: nextId,
                startTime: bg.startTime,
                text: text,
                words: bg.words.isEmpty ? nil : bg.words,
                agent: agent,
                isBackground: true,
                isTimingInferred: false
            ))
            nextId += 1
            lastTimestamp = max(lastTimestamp, bg.startTime)
        }
    }

    /// A background `<span role="x-bg">` can itself contain word-level
    /// child spans; if it doesn't, its own text is the whole background
    /// line.
    private static func wordsAndText(from bgSpan: XMLNode, offset: TimeInterval, warnings: inout [String]) -> (words: [LyricsWord], text: String) {
        let children = bgSpan.children.filter { localName($0.name) == "span" }
        guard !children.isEmpty else {
            return ([], bgSpan.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let words = children.compactMap { wordSpan(from: $0, offset: offset, warnings: &warnings) }
        return (words, "")
    }

    private static func wordSpan(from span: XMLNode, offset: TimeInterval, warnings: inout [String]) -> LyricsWord? {
        let text = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        guard
            let beginString = span.attr(beginAttrNames),
            let begin = parseTime(beginString)
        else {
            // No/invalid timing on this specific span — its text still
            // matters for the line, so it's folded into the fallback text
            // path by the caller rather than becoming a dangling word.
            if span.attr(beginAttrNames) != nil {
                warnings.append("Invalid <span begin> value, ignoring word timing for: \(text)")
            }
            return nil
        }
        let end = span.attr(endAttrNames).flatMap(parseTime) ?? begin
        return LyricsWord(text: text, startTime: begin + offset, endTime: end + offset)
    }

    private static func enclosingDivAgent(_ p: XMLNode) -> String? {
        var node: XMLNode? = p.parent
        while let current = node {
            if localName(current.name) == "div", let agent = current.attr(agentAttrNames) {
                return agent
            }
            node = current.parent
        }
        return nil
    }

    private static func findAll(_ node: XMLNode, named name: String) -> [XMLNode] {
        var result: [XMLNode] = []
        func visit(_ n: XMLNode) {
            if localName(n.name) == name { result.append(n) }
            for child in n.children { visit(child) }
        }
        visit(node)
        return result
    }

    private static func localName(_ name: String) -> String {
        guard let idx = name.firstIndex(of: ":") else { return name }
        return String(name[name.index(after: idx)...])
    }

    /// Parses `hh:mm:ss.fff`, `mm:ss.fff`, or a bare offset value with a
    /// `ms`/`s`/`m`/`h` suffix. Returns `nil` (never a silently-defaulted
    /// `0`) if the string doesn't match a recognized shape or its numeric
    /// part isn't parseable — callers treat `nil` as "no valid timing"
    /// exactly like a missing attribute, which is what feeds the
    /// untimed-line fix above.
    static func parseTime(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        if value.contains(":") {
            let parts = value.split(separator: ":").map(String.init)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            let numericParts = parts.map { Double($0) }
            guard numericParts.allSatisfy({ $0 != nil }) else { return nil }
            let doubles = numericParts.compactMap { $0 }
            if doubles.count == 3 {
                return doubles[0] * 3600 + doubles[1] * 60 + doubles[2]
            } else {
                return doubles[0] * 60 + doubles[1]
            }
        }

        let suffixes: [(String, Double)] = [("ms", 0.001), ("s", 1), ("m", 60), ("h", 3600)]
        for (suffix, multiplier) in suffixes where value.hasSuffix(suffix) {
            let numberPart = String(value.dropLast(suffix.count))
            guard let number = Double(numberPart) else { return nil }
            return number * multiplier
        }

        // Bare number with no unit at all — TTML technically requires a
        // unit, but be lenient and treat it as seconds rather than reject
        // outright, since some sources omit it.
        return Double(value)
    }
}

// MARK: - Minimal tree, built via XMLParser's SAX delegate

final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text: String = ""
    weak var parent: XMLNode?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Looks up an attribute by any of the given names (to accept both
    /// `ttm:agent`-prefixed and bare `agent` forms, mirroring Android's
    /// `getAttr`).
    func attr(_ names: [String]) -> String? {
        for name in names {
            if let value = attributes[name], !value.isEmpty { return value }
        }
        return nil
    }
}

private final class TTMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    var hadError = false
    private var current: XMLNode?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLNode(name: elementName, attributes: attributeDict)
        node.parent = current
        if let current {
            current.children.append(node)
        } else {
            root = node
        }
        current = node
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        current = current?.parent
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        hadError = true
    }
}
