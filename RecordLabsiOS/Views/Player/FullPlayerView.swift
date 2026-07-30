import SwiftUI

/// Mirrors `Player.kt`'s `BottomSheetPlayer` in its expanded state: artwork,
/// transport controls, scrubber, and a button through to the queue sheet.
/// Lyrics (`InlineLyricsView` on Android) are left as a TODO placeholder —
/// wiring that up needs a lyrics provider (LrcLib/KuGou/etc equivalent).
struct FullPlayerView: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @Binding var isExpanded: Bool
    @State private var showQueue = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(.secondary))
                    .padding(.horizontal, 24)

                if let song = playerConnection.currentSong {
                    VStack(spacing: 4) {
                        Text(song.title).font(.title2.bold()).lineLimit(1)
                        Text(song.artistNames).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                if playerConnection.isResolvingStream {
                    ProgressView("Resolving stream…")
                        .font(.caption)
                } else if let playbackError = playerConnection.playbackError {
                    Text(playbackError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Slider(value: Binding(
                    get: { playerConnection.position },
                    set: { playerConnection.seek(to: $0) }
                ), in: 0...(playerConnection.currentSong?.duration ?? 1))
                .padding(.horizontal, 24)

                HStack(spacing: 36) {
                    Button { playerConnection.seekToPrevious() } label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    .disabled(!playerConnection.canSkipPrevious)

                    Button { playerConnection.togglePlayPause() } label: {
                        Image(systemName: playerConnection.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }

                    Button { playerConnection.seekToNext() } label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                    .disabled(!playerConnection.canSkipNext)
                }

                HStack(spacing: 32) {
                    Button { playerConnection.toggleLike() } label: {
                        Image(systemName: playerConnection.currentSong?.isLiked == true ? "heart.fill" : "heart")
                    }
                    Button { showQueue = true } label: {
                        Image(systemName: "list.bullet")
                    }
                }
                .font(.title3)

                Spacer()
            }
            .padding(.top, 24)
            .toolbar {
                // .topBarLeading needs iOS 16+; .navigationBarLeading is the
                // iOS 15-compatible placement (same visual result here).
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { isExpanded = false }
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
            }
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    let connection = PlayerConnection()
    connection.playQueue(SampleData.songs)
    return FullPlayerView(isExpanded: .constant(true))
        .environmentObject(connection)
}
