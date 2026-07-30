import SwiftUI

/// Mirrors `Queue.kt`: the up-next list, reachable from the full player.
struct QueueView: View {
    @EnvironmentObject private var playerConnection: PlayerConnection

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(playerConnection.queue.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song) {
                        playerConnection.playQueue(playerConnection.queue, startIndex: index)
                    }
                    .listRowBackground(index == playerConnection.currentIndex ? Color.accentColor.opacity(0.12) : nil)
                }
            }
            .navigationTitle("Up next")
        }
    }
}

#Preview {
    let connection = PlayerConnection()
    connection.playQueue(SampleData.songs)
    return QueueView().environmentObject(connection)
}
