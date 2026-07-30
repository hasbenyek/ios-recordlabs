import SwiftUI

/// Real network search against YouTube Music's `/search` endpoint (see
/// `Networking/InnerTubeClient.swift` + `SearchResponse.swift`). Parsing is
/// best-effort/heuristic, not a faithful port of the Android renderer tree —
/// see `SearchResponseParser`'s doc comment for exactly what that means.
struct SearchScreen: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            List(results) { song in
                SongRow(song: song) {
                    playerConnection.playQueue(results, startIndex: results.firstIndex(of: song) ?? 0)
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if let errorMessage {
                    EmptyStateView(title: "Search failed", systemImage: "wifi.exclamationmark", message: errorMessage)
                } else if query.isEmpty {
                    EmptyStateView(title: "Search songs", systemImage: "magnifyingglass")
                } else if results.isEmpty {
                    EmptyStateView(title: "No results for \"\(query)\"", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Search")
        }
        .navigationViewStyle(.stack)
        .searchable(text: $query)
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            guard !newValue.isEmpty else {
                results = []
                errorMessage = nil
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000) // debounce
                guard !Task.isCancelled else { return }
                await runSearch(newValue)
            }
        }
    }

    private func runSearch(_ text: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let data = try await InnerTubeClient.shared.search(query: text)
            guard !Task.isCancelled else { return }
            results = SearchResponseParser.parseSongs(from: data)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SearchScreen().environmentObject(PlayerConnection())
}
