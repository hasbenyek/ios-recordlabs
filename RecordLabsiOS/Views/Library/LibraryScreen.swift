import SwiftUI

/// Library has no real backing store yet (no persistence layer — see
/// README "known limitations"). Rather than show fabricated content, this
/// screen says so explicitly until real persistence is added.
struct LibraryScreen: View {
    @State private var section: LibrarySection = .playlists

    enum LibrarySection: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums", artists = "Artists", playlists = "Playlists"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(LibrarySection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                EmptyStateView(
                    title: "Library persistence is not implemented yet",
                    systemImage: "tray",
                    message: "Liked songs, saved albums/artists, and playlists need a local database (SwiftData/GRDB), which hasn't been built for iOS yet. This tab intentionally shows nothing rather than sample content."
                )
            }
            .navigationTitle("Library")
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    LibraryScreen()
}
