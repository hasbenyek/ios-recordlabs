import Foundation

/// Mirrors `Screens.MainScreens` from the Android app (Home, Search,
/// ListenTogether, Library) — the four bottom-nav tabs.
enum Tab: String, CaseIterable, Identifiable {
    case home
    case search
    case listenTogether
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .listenTogether: return "Listen Together"
        case .library: return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .listenTogether: return "person.2.wave.2.fill"
        case .library: return "music.note.list"
        }
    }
}
