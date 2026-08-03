import Foundation

/// Standard LRC parser (also used for LRCLIB's `syncedLyrics` field).
///
/// Deliberately fixes two behaviors found in the Android app's
/// `LyricsUtils.kt`/`TTMLParser.kt` during the migration audit, rather than
/// reproducing them:
/// - A malformed timestamp (non-numeric minute/second/fraction inside a
///   `[..:..]`-shaped tag) is **skipped and recorded in `warnings`**, never
///   silently treated as `00:00` — Android's `parseTime` does
///   `.toIntOrNull() ?: 0` / `.toDoubleOrNull() ?: 0.0`, which can collide
///   unrelated lines at the start of the song with no diagnostic trail.
/// - A textual line with no valid timestamp at all is **kept**, not
///   silently dropped — `isTimingInferred` is set to `true` and its
///   `startTime` is inherited from the previous valid line, so the UI can
///   render it without treating it as a real sync anchor. Android's
///   `TTMLParser.findFirstSpanBegin` fallback silently discards a
///   completely untimed `<p>` line; this documents and tests the opposite
///   choice for the LRC path.
enum LRCParser {
    struct Result {
        var lines: [LyricsLine]
        var offsetMs: Int
        var warnings: [String]

        /// False only when every line came back `isTimingInferred` — i.e.
        /// there was no real timing anywhere in the file.
        var isSynced: Bool { lines.contains { !$0.isTimingInferred } }
    }

    /// Loosely matches ANY `[left:right]` or `[left:right.frac]` bracket
    /// shape (not just digits) so a corrupted timestamp like `[xx:yy]` is
    /// recognized as "this was meant to be a timestamp" and routed through
    /// the malformed-timestamp warning path, rather than being invisible to
    /// the parser entirely.
    private static let timestampBracketPattern = #"\[([^:\]]+):([^\].]+)(?:[.:]([^\]]+))?\]"#
    private static let metadataTagPattern = #"^\[[a-zA-Z]+:.*\]$"#
    private static let offsetTagPattern = #"^\[offset:\s*([+-]?\d+)\]$"#

    static func parse(_ text: String) -> Result {
        var warnings: [String] = []
        let offsetMs = extractOffset(from: text, warnings: &warnings)

        var lines: [LyricsLine] = []
        var nextId = 0
        var lastTimestamp: TimeInterval = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.range(of: offsetTagPattern, options: .regularExpression) != nil { continue }
            if trimmed.range(of: metadataTagPattern, options: .regularExpression) != nil { continue }

            let timestamps = extractTimestamps(from: trimmed, offsetMs: offsetMs, warnings: &warnings)
            let textPart = stripTimestamps(from: trimmed)
            guard !textPart.isEmpty else { continue }

            if timestamps.isEmpty {
                lines.append(LyricsLine(id: nextId, startTime: lastTimestamp, text: textPart, isTimingInferred: true))
                nextId += 1
                continue
            }

            for time in timestamps {
                lastTimestamp = time
                lines.append(LyricsLine(id: nextId, startTime: time, text: textPart, isTimingInferred: false))
                nextId += 1
            }
        }

        lines.sort { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        return Result(lines: lines, offsetMs: offsetMs, warnings: warnings)
    }

    private static func extractOffset(from text: String, warnings: inout [String]) -> Int {
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.range(of: offsetTagPattern, options: .regularExpression) else { continue }
            let inner = trimmed[match]
                .replacingOccurrences(of: "[offset:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let value = Int(inner) {
                return value
            }
            warnings.append("Malformed [offset:] tag: \(trimmed)")
        }
        return 0
    }

    /// Extracts every timestamp tag on a line. A tag whose bracket shape
    /// matches but whose numeric components don't parse is skipped (not
    /// defaulted to 0) and recorded in `warnings`.
    private static func extractTimestamps(from line: String, offsetMs: Int, warnings: inout [String]) -> [TimeInterval] {
        var results: [TimeInterval] = []
        guard let regex = try? NSRegularExpression(pattern: timestampBracketPattern) else { return results }
        let nsrange = NSRange(line.startIndex..., in: line)

        for match in regex.matches(in: line, range: nsrange) {
            guard
                let minuteRange = Range(match.range(at: 1), in: line),
                let secondRange = Range(match.range(at: 2), in: line)
            else { continue }

            guard let minutes = Int(line[minuteRange]), let seconds = Int(line[secondRange]) else {
                warnings.append("Malformed timestamp in line: \(line)")
                continue
            }

            var fraction: Double = 0
            if match.range(at: 3).location != NSNotFound, let fractionRange = Range(match.range(at: 3), in: line) {
                let raw = String(line[fractionRange])
                guard let fractionValue = Int(raw), !raw.isEmpty else {
                    warnings.append("Malformed timestamp fraction in line: \(line)")
                    continue
                }
                fraction = Double(fractionValue) / pow(10, Double(raw.count))
            }

            // Convention used here: a positive [offset:] advances lyrics
            // (subtracted from each timestamp); a negative offset delays
            // them. Documented explicitly because real-world LRC files are
            // inconsistent about this — this is the one this app uses.
            let adjusted = TimeInterval(minutes * 60 + seconds) + fraction - (Double(offsetMs) / 1000)
            results.append(max(0, adjusted))
        }
        return results
    }

    private static func stripTimestamps(from line: String) -> String {
        (try? NSRegularExpression(pattern: timestampBracketPattern))
            .map { regex -> String in
                let nsrange = NSRange(line.startIndex..., in: line)
                return regex.stringByReplacingMatches(in: line, range: nsrange, withTemplate: "")
            }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? line
    }
}
