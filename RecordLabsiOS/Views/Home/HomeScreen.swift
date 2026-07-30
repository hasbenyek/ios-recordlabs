import SwiftUI

/// Real network call to YouTube Music's `/browse` (`browseId: FEmusic_home`)
/// via `SearchResponseParser`'s heuristic scan — same caveats as Search (see
/// that file's doc comment): this reads whatever songs it can find in the
/// raw JSON, not a faithful reproduction of the actual home feed's shelves/
/// sections/ordering the way Android's `HomeScreen.kt` renders them. Falls
/// back to `SampleData` if the request fails, labeled as such, rather than
/// showing a dead screen.
struct HomeScreen: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var usingFallbackData = false

    var body: some View {
        NavigationStack {
            List {
                if usingFallbackData {
                    Section {
                        Label("Couldn't load your feed — showing sample songs instead.", systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Quick picks") {
                    ForEach(songs) { song in
                        SongRow(song: song) {
                            playerConnection.playQueue(songs, startIndex: songs.firstIndex(of: song) ?? 0)
                        }
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle("Home")
            .task { await loadHome() }
            .refreshable { await loadHome() }
        }
    }

    private func loadHome() async {
        isLoading = songs.isEmpty
        do {
            let data = try await InnerTubeClient.shared.browse(browseId: "FEmusic_home")
            let parsed = SearchResponseParser.parseSongs(from: data)
            if parsed.isEmpty {
                songs = SampleData.songs
                usingFallbackData = true
            } else {
                songs = parsed
                usingFallbackData = false
            }
        } catch {
            songs = SampleData.songs
            usingFallbackData = true
        }
        isLoading = false
    }
}

#Preview {
    HomeScreen().environmentObject(PlayerConnection())
}
