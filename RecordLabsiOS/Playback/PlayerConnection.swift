import Foundation
import AVFoundation
import Combine

/// iOS counterpart to the Android app's `PlayerConnection.kt`.
///
/// On each track change this resolves a playable URL via `StreamResolver`
/// (see that file for what is/isn't handled — signature deciphering now
/// works for one client tier, BotGuard PoToken still doesn't) and hands it
/// to a single `AVPlayer`. There's no queue-service/session layer like
/// Android's `MediaLibraryService` (`MusicService.kt`) — no lock-screen
/// controls, background audio session config, downloads, or crossfade yet.
@MainActor
final class PlayerConnection: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentSong: Song?
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var isResolvingStream: Bool = false
    @Published private(set) var playbackError: String?
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    enum RepeatMode {
        case off, one, all
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var resolveTask: Task<Void, Never>?

    var canSkipPrevious: Bool { currentIndex > 0 }
    var canSkipNext: Bool { currentIndex < queue.count - 1 }

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, time.isNumeric else { return }
            self.position = time.seconds
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackFinished() }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func playQueue(_ songs: [Song], startIndex: Int = 0, autoplay: Bool = true) {
        queue = songs
        loadTrack(at: startIndex, autoplay: autoplay)
    }

    /// Applies a playback state received from `ListenTogetherSession`. If
    /// it's a different song than what's currently loaded, starts playing it
    /// (as a synthetic single-song queue — the receiving device has no
    /// reason to already have this exact video in its own queue); otherwise
    /// just corrects drift/play-state so both devices stay roughly in sync.
    func applyRemoteSync(songId: String, title: String, artist: String, position remotePosition: TimeInterval, isPlaying remoteIsPlaying: Bool) {
        if currentSong?.id != songId {
            let song = Song(id: songId, title: title, artists: [ArtistRef(id: artist, name: artist)], album: nil, duration: 0, thumbnailURL: nil)
            playQueue([song], autoplay: remoteIsPlaying)
        } else {
            if abs(remotePosition - position) > 2 { seek(to: remotePosition) }
            if remoteIsPlaying != isPlaying { remoteIsPlaying ? play() : pause() }
        }
    }

    func play() {
        isPlaying = true
        player.play()
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        position = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    func seekToNext() {
        guard canSkipNext else { return }
        loadTrack(at: currentIndex + 1, autoplay: isPlaying)
    }

    func seekToPrevious() {
        guard canSkipPrevious else { return }
        loadTrack(at: currentIndex - 1, autoplay: isPlaying)
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
    }

    func playNext(_ song: Song) {
        queue.insert(song, at: min(currentIndex + 1, queue.count))
    }

    func toggleLike() {
        guard var song = currentSong, let idx = queue.firstIndex(where: { $0.id == song.id }) else { return }
        song.isLiked.toggle()
        queue[idx] = song
        currentSong = song
    }

    private func handleTrackFinished() {
        if repeatMode == .one {
            loadTrack(at: currentIndex, autoplay: true)
        } else if canSkipNext {
            loadTrack(at: currentIndex + 1, autoplay: true)
        } else if repeatMode == .all, !queue.isEmpty {
            loadTrack(at: 0, autoplay: true)
        } else {
            pause()
        }
    }

    private func loadTrack(at index: Int, autoplay: Bool) {
        guard queue.indices.contains(index) else { return }
        resolveTask?.cancel()

        currentIndex = index
        currentSong = queue[index]
        position = 0
        playbackError = nil
        player.replaceCurrentItem(with: nil)
        isResolvingStream = true

        let song = queue[index]
        resolveTask = Task { @MainActor in
            do {
                let url = try await StreamResolver.resolveStreamURL(videoId: song.id)
                guard !Task.isCancelled else { return }
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                isResolvingStream = false
                if autoplay { play() }
            } catch {
                guard !Task.isCancelled else { return }
                isResolvingStream = false
                playbackError = "Couldn't get a playable stream for \"\(song.title)\". This scaffold only resolves non-ciphered YouTube clients (see StreamResolver.swift) — YouTube may not be offering one for this video right now."
            }
        }
    }
}
