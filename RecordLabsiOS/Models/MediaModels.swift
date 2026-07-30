import Foundation

/// Mirrors the shape of `models/MediaMetadata` and the `db/entities` classes
/// from the Android app (Song/Artist/Album/Playlist), simplified for a
/// starting scaffold. Real persistence should later move to SwiftData/Core Data.

struct ArtistRef: Identifiable, Hashable, Codable {
    var id: String
    var name: String
}

struct AlbumRef: Identifiable, Hashable, Codable {
    var id: String
    var title: String
}

struct Song: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var artists: [ArtistRef]
    var album: AlbumRef?
    var duration: TimeInterval
    var thumbnailURL: URL?
    var isExplicit: Bool = false
    var isLiked: Bool = false
    var isDownloaded: Bool = false

    var artistNames: String {
        artists.map(\.name).joined(separator: ", ")
    }
}

struct Album: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var artists: [ArtistRef]
    var year: Int?
    var thumbnailURL: URL?
    var songCount: Int
}

struct Artist: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var thumbnailURL: URL?
    var isBookmarked: Bool = false
}

struct Playlist: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var thumbnailURL: URL?
    var songCount: Int
    var isEditable: Bool = true
}
