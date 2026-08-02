import SwiftUI

/// Mirrors `MainActivity.kt`: a tab scaffold with a persistent player sheet
/// overlaid above the bottom tab bar (mini player collapsed / full player
/// expanded), rather than the player being its own tab or pushed screen.
struct RootView: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @State private var selectedTab: Tab = .home
    @State private var isPlayerExpanded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    tabContent(for: tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }

            if playerConnection.currentSong != nil {
                MiniPlayerView(isExpanded: $isPlayerExpanded)
                    .padding(.bottom, 49) // sits just above the tab bar
            }
        }
        // Same brand color as Android's `DefaultThemeColor` (see Theme.swift)
        // - applied once here so every default-tinted control (tab bar
        // selection, nav bar buttons, etc.) picks it up app-wide.
        .tint(Theme.accent)
        .fullScreenCover(isPresented: $isPlayerExpanded) {
            FullPlayerView(isExpanded: $isPlayerExpanded)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        switch tab {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .listenTogether: ListenTogetherScreen()
        case .library: LibraryScreen()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(PlayerConnection())
}
