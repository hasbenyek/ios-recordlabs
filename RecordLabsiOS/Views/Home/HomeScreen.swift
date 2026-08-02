import SwiftUI

/// Real `/browse` (`FEmusic_home`) call, rendered as a "Quick Picks" section
/// plus a "Recently Played" section sourced from this device's own actual
/// playback history (`PlayerConnection.recentlyPlayed`). No sample-data
/// fallback of any kind — a failed or empty load shows a real error/empty
/// state with Retry, per the "never fake a success state" rule.
///
/// Still not a faithful port of Android's many independent home sections
/// (QuickPicks/DailyDiscover/KeepListening/ForgottenFavorites/
/// AccountPlaylists/FromTheCommunity/MoodAndGenres) — see
/// `SearchResponseParser`'s doc comment for why.
struct HomeScreen: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @State private var state: LoadState<[Song]> = .idle

    private let cardSize: CGFloat = 140

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Home")
                .task { await loadHome() }
                .refreshable { await loadHome() }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ScrollView {
                if !playerConnection.recentlyPlayed.isEmpty {
                    section(title: "Recently Played", songs: playerConnection.recentlyPlayed)
                }
            }
            .overlay { ProgressView() }
        case .error(let error):
            ErrorStateView(title: "Couldn't load your feed", message: error.message) {
                Task { await loadHome() }
            }
        case .empty:
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !playerConnection.recentlyPlayed.isEmpty {
                        section(title: "Recently Played", songs: playerConnection.recentlyPlayed)
                    }
                    EmptyStateView(
                        title: "Nothing to show",
                        systemImage: "house",
                        message: "YouTube Music didn't return any recognizable songs for your home feed right now."
                    )
                    .frame(height: 240)
                }
                .padding(.vertical, 12)
            }
        case .loaded(let songs):
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !playerConnection.recentlyPlayed.isEmpty {
                        section(title: "Recently Played", songs: playerConnection.recentlyPlayed)
                    }
                    section(title: "Quick Picks", songs: songs)
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func section(title: String, songs: [Song]) -> some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.bold())
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(songs) { song in
                            Button {
                                playerConnection.playQueue(songs, startIndex: songs.firstIndex(of: song) ?? 0)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(url: song.thumbnailURL, cornerRadius: 10)
                                        .frame(width: cardSize, height: cardSize)

                                    Text(song.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(song.artistNames)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: cardSize)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func loadHome() async {
        state = .loading
        do {
            let data = try await InnerTubeClient.shared.browse(browseId: "FEmusic_home")
            let parsed = SearchResponseParser.parseSongs(from: data)
            state = parsed.songs.isEmpty ? .empty : .loaded(parsed.songs)
        } catch {
            state = .error(.network(error.localizedDescription))
        }
    }
}

#Preview {
    HomeScreen().environmentObject(PlayerConnection())
}
