import SwiftUI

/// Real network search against YouTube Music's `/search` endpoint (see
/// `Networking/InnerTubeClient.swift` + `SearchResponse.swift`). No sample
/// data anywhere in this file — a failed or empty request always shows a
/// real state with a Retry action, never fabricated songs.
struct SearchScreen: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @State private var query = ""
    @State private var state: LoadState<[Song]> = .idle
    @State private var diagnostics: [String] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Search")
        }
        .navigationViewStyle(.stack)
        .searchable(text: $query)
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            guard !newValue.isEmpty else {
                state = .idle
                diagnostics = []
                return
            }
            // Debounce: wait for a pause in typing before spending a real
            // network request.
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await runSearch(newValue)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            EmptyStateView(title: "Search songs", systemImage: "magnifyingglass")
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            EmptyStateView(title: "No results for \"\(query)\"", systemImage: "magnifyingglass")
        case .error(let error):
            ErrorStateView(title: "Search failed", message: error.message) {
                let q = query
                searchTask = Task { await runSearch(q) }
            }
        case .loaded(let songs):
            List {
                ForEach(songs) { song in
                    SongRow(song: song) {
                        playerConnection.playQueue(songs, startIndex: songs.firstIndex(of: song) ?? 0)
                    }
                }
                if !diagnostics.isEmpty {
                    Section {
                        Text("\(diagnostics.count) result group(s) couldn't be fully parsed and were skipped.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func runSearch(_ text: String) async {
        state = .loading
        do {
            let data = try await InnerTubeClient.shared.search(query: text)
            guard !Task.isCancelled else { return }
            let parsed = SearchResponseParser.parseSongs(from: data)
            guard !Task.isCancelled else { return }
            diagnostics = parsed.diagnostics
            state = parsed.songs.isEmpty ? .empty : .loaded(parsed.songs)
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.network(error.localizedDescription))
        }
    }
}

#Preview {
    SearchScreen().environmentObject(PlayerConnection())
}
