import SwiftUI

/// Mirrors `Player.kt`'s `BottomSheetPlayer` in its expanded state: a
/// blurred-artwork background (Android's `PlayerBackgroundStyle.BLUR`),
/// large artwork, transport controls (shuffle/previous/play-pause/next/
/// repeat), scrubber with elapsed/remaining time, like + queue buttons, and
/// a button through to the queue sheet.
///
/// Not ported from Android: real palette-based background color extraction
/// (`PlayerColorExtractor`/`GRADIENT` style) — this always uses the blurred-
/// artwork look; and the `PlayerBackgroundStyle.DEFAULT` (plain-color)
/// option. Lyrics are provided by the native BetterLyrics/LRCLIB view.
struct FullPlayerView: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @Binding var isExpanded: Bool
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showDiagnostics = false

    var body: some View {
        // Plain ZStack rather than NavigationView - the only thing this
        // screen needs from navigation chrome is a close button, and
        // NavigationView's bar would default to an opaque light/dark
        // material that fights with the always-dark blurred-artwork
        // background below. A manually placed button avoids that plus any
        // toolbar-background APIs that need a newer deployment target than
        // this project's (15.0).
        ZStack(alignment: .top) {
            backgroundLayer

            VStack(spacing: 0) {
                HStack {
                    Button {
                        isExpanded = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                VStack(spacing: 20) {
                    if showLyrics {
                        LyricsView(song: playerConnection.currentSong, currentTime: playerConnection.position)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    } else {
                        ArtworkView(url: playerConnection.currentSong?.thumbnailURL, cornerRadius: 16)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(radius: 16, y: 8)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)

                        if let song = playerConnection.currentSong {
                            VStack(spacing: 4) {
                                Text(song.title).font(.title2.bold()).lineLimit(1)
                                Text(song.artistNames).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            }
                            .padding(.horizontal, 24)
                        }

                        statusSection
                    }

                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { playerConnection.position },
                            set: { playerConnection.seek(to: $0) }
                        ), in: 0...max(playerConnection.currentSong?.duration ?? 1, 1))
                        .tint(Theme.accent)

                        HStack {
                            Text(Self.formatted(playerConnection.position))
                            Spacer()
                            Text(Self.formatted(playerConnection.currentSong?.duration ?? 0))
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 24)

                    HStack {
                        Button {
                            playerConnection.shuffleEnabled.toggle()
                        } label: {
                            Image(systemName: "shuffle").font(.body)
                        }
                        .foregroundStyle(playerConnection.shuffleEnabled ? Theme.accent : .white)

                        Spacer()

                        Button { playerConnection.seekToPrevious() } label: {
                            Image(systemName: "backward.fill").font(.title)
                        }
                        .foregroundStyle(.white)
                        .disabled(!playerConnection.canSkipPrevious)
                        .opacity(playerConnection.canSkipPrevious ? 1 : 0.4)

                        Spacer()

                        Button { playerConnection.togglePlayPause() } label: {
                            Image(systemName: playerConnection.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                        }
                        .tint(Theme.accent)

                        Spacer()

                        Button { playerConnection.seekToNext() } label: {
                            Image(systemName: "forward.fill").font(.title)
                        }
                        .foregroundStyle(.white)
                        .disabled(!playerConnection.canSkipNext)
                        .opacity(playerConnection.canSkipNext ? 1 : 0.4)

                        Spacer()

                        Button {
                            playerConnection.repeatMode = Self.nextRepeatMode(after: playerConnection.repeatMode)
                        } label: {
                            Image(systemName: playerConnection.repeatMode == .one ? "repeat.1" : "repeat").font(.body)
                        }
                        .foregroundStyle(playerConnection.repeatMode == .off ? .white : Theme.accent)
                    }
                    .padding(.horizontal, 32)

                    HStack(spacing: 32) {
                        Button { playerConnection.toggleLike() } label: {
                            Image(systemName: playerConnection.currentSong?.isLiked == true ? "heart.fill" : "heart")
                        }
                        .foregroundStyle(playerConnection.currentSong?.isLiked == true ? Theme.accent : .white)

                        Button { showLyrics.toggle() } label: {
                            Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                        }
                        .foregroundStyle(showLyrics ? Theme.accent : .white)

                        Button { showQueue = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .foregroundStyle(.white)

                        Button { showDiagnostics = true } label: {
                            Image(systemName: "info.circle")
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .font(.title3)

                    Spacer()
                }
                .padding(.top, 24)
                .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .sheet(isPresented: $showDiagnostics) {
            PlayerDiagnosticsView(diagnostics: playerConnection.diagnostics, state: playerConnection.state)
        }
        .preferredColorScheme(.dark)
    }

    /// Idle/playing/paused render nothing here (the mini-player/lock-screen
    /// convey that); every other `PlaybackState` gets a message + Retry,
    /// per the "a failed request must never be silently replaced" rule.
    @ViewBuilder
    private var statusSection: some View {
        switch playerConnection.state {
        case .resolving:
            ProgressView("Resolving stream…").tint(.white).font(.caption)
        case .buffering:
            ProgressView("Buffering…").tint(.white).font(.caption)
        case .idle, .playing, .paused:
            EmptyView()
        default:
            if let message = playerConnection.state.displayMessage {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Retry") { playerConnection.retryCurrentTrack() }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
        }
    }

    /// Blurred, darkened artwork filling the background - the cheap
    /// approximation of Android's `PlayerBackgroundStyle.BLUR` that doesn't
    /// need a palette-extraction pass to look right. Falls back to a flat
    /// dark surface (rather than the system background) when there's no
    /// artwork yet, since all the text/icons above are drawn in white and
    /// need a dark backdrop to stay legible in light mode too.
    @ViewBuilder
    private var backgroundLayer: some View {
        if let url = playerConnection.currentSong?.thumbnailURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 40)
                        .overlay(Color.black.opacity(0.55))
                } else {
                    Color(white: 0.12)
                }
            }
            .ignoresSafeArea()
        } else {
            Color(white: 0.12).ignoresSafeArea()
        }
    }

    private static func nextRepeatMode(after mode: PlayerConnection.RepeatMode) -> PlayerConnection.RepeatMode {
        switch mode {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    private static func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    return FullPlayerView(isExpanded: .constant(true))
        .environmentObject(PlayerConnection())
}
