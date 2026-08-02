import SwiftUI

/// Reused across Home/Search/Library lists — analogous to the shared
/// `SongListItem` composable on the Android side.
struct SongRow: View {
    let song: Song
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkView(url: song.thumbnailURL)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(song.artistNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if song.isLiked {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
