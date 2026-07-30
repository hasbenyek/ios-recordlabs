import SwiftUI

/// Mirrors `MiniPlayer.kt`: the collapsed bar sitting above the tab bar.
/// Tapping it expands to `FullPlayerView` (like tapping the collapsed
/// `BottomSheetPlayer` on Android).
struct MiniPlayerView: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @Binding var isExpanded: Bool

    var body: some View {
        if let song = playerConnection.currentSong {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.subheadline).lineLimit(1)
                    Text(song.artistNames).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                if playerConnection.isResolvingStream {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Button {
                        playerConnection.togglePlayPause()
                    } label: {
                        Image(systemName: playerConnection.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
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
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded = true }
        }
    }
}

#Preview {
    let connection = PlayerConnection()
    connection.playQueue(SampleData.songs)
    return VStack {
        Spacer()
        MiniPlayerView(isExpanded: .constant(false))
            .environmentObject(connection)
    }
}
