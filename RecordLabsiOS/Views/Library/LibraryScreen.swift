import SwiftUI

/// Placeholder for `library/` (Songs/Albums/Artists/Playlists/Podcasts/Mix
/// tabs). Collapsed into a single segmented view here as a starting point.
struct LibraryScreen: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @State private var section: Section = .playlists

    enum Section: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums", artists = "Artists", playlists = "Playlists"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            VStack {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                List {
                    switch section {
                    case .songs:
                        ForEach(SampleData.songs) { song in
                            SongRow(song: song) {
                                playerConnection.playQueue(SampleData.songs, startIndex: SampleData.songs.firstIndex(of: song) ?? 0)
                            }
                        }
                    case .albums:
                        ForEach(SampleData.albums) { album in
                            Text(album.title)
                        }
                    case .artists:
                        ForEach(SampleData.artists) { artist in
                            Text(artist.name)
                        }
                    case .playlists:
                        ForEach(SampleData.playlists) { playlist in
                            HStack {
                                Text(playlist.name)
                                Spacer()
                                Text("\(playlist.songCount)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Library")
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    LibraryScreen().environmentObject(PlayerConnection())
}
