import SwiftUI

/// Mirrors `MiniPlayer.kt`: the collapsed bar sitting above the tab bar —
/// artwork, title/artist, play/pause, skip-next, and a thin progress line
/// along the bottom edge. Tapping it expands to `FullPlayerView` (like
/// tapping the collapsed `BottomSheetPlayer` on Android). Not ported from
/// the Android version: the horizontal swipe-to-skip gesture and the
/// album-art-driven background color extraction — real, but lower-value
/// polish on top of this.
struct MiniPlayerView: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @Binding var isExpanded: Bool

    private var progress: Double {
        guard let duration = playerConnection.currentSong?.duration, duration > 0 else { return 0 }
        return (playerConnection.position / duration).clamped(to: 0...1)
    }

    var body: some View {
        if let song = playerConnection.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ArtworkView(url: song.thumbnailURL, cornerRadius: 6)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.subheadline).lineLimit(1)
                        Text(song.artistNames).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }

                    Spacer()

                    if playerConnection.isBusy {
                        ProgressView()
                            .frame(width: 24, height: 24)
                    } else if playerConnection.state.isFailure {
                        Button {
                            playerConnection.retryCurrentTrack()
                        } label: {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.title3)
                        }
                        .foregroundStyle(.red)
                    } else {
                        Button {
                            playerConnection.togglePlayPause()
                        } label: {
                            Image(systemName: playerConnection.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                        }
                        .tint(Theme.accent)
                    }

                    Button {
                        playerConnection.seekToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .disabled(!playerConnection.canSkipNext)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                // Thin progress line along the bottom edge, matching the
                // slim indicator Android's mini player shows under the row.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(height: 2)
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * progress, height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded = true }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    return VStack {
        Spacer()
        MiniPlayerView(isExpanded: .constant(false))
            .environmentObject(PlayerConnection())
    }
}
