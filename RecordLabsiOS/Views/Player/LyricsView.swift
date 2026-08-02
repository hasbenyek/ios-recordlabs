import SwiftUI

/// Real synchronized lyrics for the currently playing song.
///
/// Fetches via `LyricsService` (BetterLyrics → LRCLIB) using a
/// `.task(id: song?.id)` — SwiftUI cancels the previous fetch automatically
/// when the track changes, before this view even asks `LyricsService` to
/// start a new one. Highlighting is driven by `currentTime`, which comes
/// from `PlayerConnection.position` (already updated on a fixed ~0.5s
/// timer) — this view adds no extra high-frequency timer of its own.
struct LyricsView: View {
    var song: Song?
    var currentTime: TimeInterval

    @StateObject private var service = LyricsService()
    @State private var userScrolledAt: Date?
    @State private var showOffsetControl = false

    /// How long to leave the list alone after the user manually scrolls
    /// before auto-scroll-to-active-line resumes.
    private let resumeAutoScrollDelay: TimeInterval = 3

    var body: some View {
        VStack(spacing: 12) {
            header

            Group {
                if service.isLoading {
                    ProgressView("Finding lyrics…")
                        .tint(.white)
                } else {
                    switch service.result {
                    case .syncedLines(let lines, _), .syncedWords(let lines, _):
                        syncedList(lines)
                    case .plain(let text, _):
                        plainView(text)
                    case .instrumental:
                        EmptyStateView(title: "Instrumental", systemImage: "music.note", message: "This track has no lyrics.")
                            .colorScheme(.dark)
                    case .noMatch:
                        EmptyStateView(title: "Lyrics not found", systemImage: "quote.bubble", message: "Neither BetterLyrics nor LRCLIB had a confident match for this track.")
                            .colorScheme(.dark)
                    case .providerFailure(let message):
                        ErrorStateView(title: "Lyrics unavailable", message: message) {
                            Task { await refresh() }
                        }
                        .colorScheme(.dark)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .foregroundStyle(.white)
        .task(id: song?.id) {
            await load()
        }
    }

    @ViewBuilder
    private var header: some View {
        if let song {
            VStack(spacing: 2) {
                Text(song.title).font(.headline).lineLimit(1)
                Text(song.artistNames).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
    }

    private var providerName: String? {
        switch service.result {
        case .syncedLines(_, let provider), .syncedWords(_, let provider), .plain(_, let provider):
            return provider
        default:
            return nil
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                if let providerName {
                    Text("via \(providerName)")
                }
                Spacer()
                Button { showOffsetControl.toggle() } label: {
                    Image(systemName: "timer")
                }
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))

            if showOffsetControl {
                HStack {
                    Text("Offset: \(String(format: "%.1f", service.timingOffsetSeconds))s")
                    Slider(value: $service.timingOffsetSeconds, in: -5...5, step: 0.1)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func plainView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func syncedList(_ lines: [LyricsLine]) -> some View {
        let adjustedTime = currentTime + service.timingOffsetSeconds
        let activeIndex = activeLineIndex(lines, time: adjustedTime)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lineView(line, isActive: index == activeIndex, time: adjustedTime)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 40)
            }
            .simultaneousGesture(DragGesture().onChanged { _ in userScrolledAt = Date() })
            .onChange(of: activeIndex) { newIndex in
                guard let newIndex, shouldAutoScroll else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lines[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private var shouldAutoScroll: Bool {
        guard let userScrolledAt else { return true }
        return Date().timeIntervalSince(userScrolledAt) > resumeAutoScrollDelay
    }

    private func lineView(_ line: LyricsLine, isActive: Bool, time: TimeInterval) -> some View {
        Group {
            if let words = line.words, !words.isEmpty {
                wordHighlightedText(words, time: time, isActive: isActive)
            } else {
                Text(line.text)
            }
        }
        .font(isActive ? .title3.bold() : .body)
        .foregroundStyle(isActive ? .white : .white.opacity(line.isBackground ? 0.35 : 0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    /// Per-word highlighting: a word already sung (its `startTime` has
    /// passed) renders full-white, one not yet reached stays dim. Falls
    /// back to whole-line highlighting (`lineView`'s plain `Text(line.text)`
    /// branch) whenever a line has no word timestamps.
    private func wordHighlightedText(_ words: [LyricsWord], time: TimeInterval, isActive: Bool) -> some View {
        var attributed = AttributedString()
        for (index, word) in words.enumerated() {
            var run = AttributedString(word.text + (index < words.count - 1 ? " " : ""))
            let sung = isActive && time >= word.startTime
            run.foregroundColor = sung ? .white : .white.opacity(0.4)
            attributed += run
        }
        return Text(attributed)
    }

    private func activeLineIndex(_ lines: [LyricsLine], time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int?
        for (index, line) in lines.enumerated() {
            if line.startTime <= time {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func load() async {
        guard let song else { return }
        await service.load(for: query(for: song))
    }

    private func refresh() async {
        guard let song else { return }
        await service.load(for: query(for: song), forceRefresh: true)
    }

    private func query(for song: Song) -> LyricsQuery {
        LyricsQuery(
            videoId: song.id,
            title: song.title,
            artist: song.artistNames,
            album: song.album?.title,
            duration: song.duration > 0 ? song.duration : nil
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LyricsView(song: nil, currentTime: 0)
    }
}
