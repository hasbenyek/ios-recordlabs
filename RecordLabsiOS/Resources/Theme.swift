import SwiftUI

/// Mirrors `ui/theme/Theme.kt`'s `DefaultThemeColor` (`Color(0xFFFF2D55)`) and
/// the general Material 3 look the Android app builds from it.
///
/// Android derives its *entire* color scheme (surfaces, containers, on-colors
/// for both light/dark) from that single seed using Material You's HCT tonal
/// palette algorithm (`materialKolor`/`dynamicDarkColorScheme`), and on
/// Android 12+ can instead seed from the user's wallpaper. Reimplementing
/// that whole algorithm in SwiftUI is out of scope here — there's also no
/// iOS equivalent to "seed from wallpaper" (apps can't read wallpaper
/// colors), so this instead applies the same seed color as a flat accent
/// tint plus a small set of hand-picked surface shades, which gets most of
/// the way to the same *feel* (same brand color, proper light/dark support)
/// without the full tonal-palette machinery.
enum Theme {
    /// Same literal value as Android's `DefaultThemeColor` (0xFFFF2D55).
    static let accent = Color(red: 0xFF / 255, green: 0x2D / 255, blue: 0x55 / 255)

    /// Rough stand-in for Material 3's `surfaceContainer`/`surfaceVariant`
    /// tones used for cards (song rows, grid cells, chips) - `secondarySystemBackground`
    /// is the closest built-in iOS equivalent to that "one step up from the
    /// screen background" card surface.
    static let cardBackground = Color(uiColor: .secondarySystemBackground)

    /// Placeholder tile shown behind artwork before/instead of a loaded
    /// thumbnail - mirrors Android's `.quaternary`-filled boxes with a music
    /// note glyph, used consistently instead of every screen re-inventing
    /// its own placeholder style.
    static let placeholderTile = Color(uiColor: .tertiarySystemFill)
}

/// A thumbnail image that mirrors the rounded-square artwork used throughout
/// the Android app (`ThumbnailCornerRadius`) - real image when a URL is
/// available and loads, a music-note placeholder otherwise/while loading.
/// Centralizing this (instead of each screen building its own
/// `RoundedRectangle` + `Image(systemName:)` stand-in) is what actually
/// makes artwork show up consistently across Home/Search/Library/Player.
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 6

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle()
                    .fill(Theme.placeholderTile)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
