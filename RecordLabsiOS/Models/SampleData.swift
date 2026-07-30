import Foundation

/// Placeholder in-memory catalogue standing in for the real YouTube Music
/// client (Android side: `innertube` module + `YouTubeMusicRepository`-style
/// classes). Wire this up to a real backend before shipping.
enum SampleData {
    static let artists: [Artist] = [
        Artist(id: "a1", name: "Aurora Bay"),
        Artist(id: "a2", name: "Midnight Transit"),
        Artist(id: "a3", name: "Glass Fields")
    ]

    static let songs: [Song] = [
        Song(id: "s1", title: "Neon Tide", artists: [ArtistRef(artists[0])], album: AlbumRef(id: "al1", title: "Coastlines"), duration: 214),
        Song(id: "s2", title: "Static Bloom", artists: [ArtistRef(artists[1])], album: AlbumRef(id: "al2", title: "Departures"), duration: 187),
        Song(id: "s3", title: "Paper Lanterns", artists: [ArtistRef(artists[2])], album: AlbumRef(id: "al3", title: "Glass Fields"), duration: 251),
        Song(id: "s4", title: "Slow Static", artists: [ArtistRef(artists[1])], album: AlbumRef(id: "al2", title: "Departures"), duration: 198)
    ]

    static let albums: [Album] = [
        Album(id: "al1", title: "Coastlines", artists: [ArtistRef(artists[0])], year: 2024, songCount: 9),
        Album(id: "al2", title: "Departures", artists: [ArtistRef(artists[1])], year: 2023, songCount: 11),
        Album(id: "al3", title: "Glass Fields", artists: [ArtistRef(artists[2])], year: 2025, songCount: 8)
    ]

    static let playlists: [Playlist] = [
        Playlist(id: "p1", name: "Liked Songs", songCount: 42, isEditable: false),
        Playlist(id: "p2", name: "Downloaded", songCount: 12, isEditable: false),
        Playlist(id: "p3", name: "Late Night Drive", songCount: 27)
    ]
}
