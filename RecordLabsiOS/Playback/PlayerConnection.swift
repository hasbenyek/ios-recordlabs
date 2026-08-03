import Foundation
import AVFoundation
import Combine

/// iOS counterpart to the Android app's `PlayerConnection.kt` /
/// `MusicService.kt`.
///
/// Resolves a playable URL via `StreamResolver` on each track change and
/// hands it to a single `AVPlayer`, tracking real engine state (`state`)
/// via KVO on `timeControlStatus`/`AVPlayerItem.status` rather than
/// imperative booleans, so the UI can never show "playing" while the
/// engine is actually buffering or failed.
///
/// Still not implemented (see README "known limitations"): background audio
/// session configuration, lock-screen controls (`MPNowPlayingInfoCenter`/
/// `MPRemoteCommandCenter`), downloads, crossfade.
@MainActor
final class PlayerConnection: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var diagnostics: StreamDiagnostics?
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    /// Real (not sample/fabricated) local playback history, most-recent
    /// first — resets when the app relaunches (no persistence layer yet).
    @Published private(set) var recentlyPlayed: [Song] = []

    enum RepeatMode {
        case off, one, all
    }

    /// Convenience for view code that only cares about the play/pause glyph.
    var isPlaying: Bool { state == .playing }
    /// True while a spinner (not a play/pause glyph or error) should show.
    var isBusy: Bool { state == .resolving || state == .buffering }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var resolveTask: Task<Void, Never>?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    /// Same threshold Android's `PlayerConnection.seekToPrevious` uses:
    /// tapping "previous" restarts the current track instead of skipping
    /// back once you're more than a few seconds in.
    private static let restartInsteadOfPreviousThreshold: TimeInterval = 3

    var canSkipPrevious: Bool { currentIndex > 0 }
    var canSkipNext: Bool { currentIndex < queue.count - 1 }

    init() {
        configureAudioSession()

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard time.isNumeric else { return }
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in self?.handleTimeControlStatusChange(player.timeControlStatus) }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackFinished() }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Non-fatal if session setup fails (e.g. unit tests or simulator environment)
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

    func applyRemoteSync(songId: String, title: String, artist: String, position remotePosition: TimeInterval, isPlaying remoteIsPlaying: Bool) {
        if currentSong?.id != songId {
            let song = Song(id: songId, title: title, artists: [ArtistRef(id: artist, name: artist)], album: nil, duration: 0, thumbnailURL: nil)
            playQueue([song], autoplay: remoteIsPlaying)
        } else {
            if abs(remotePosition - position) > 2 { seek(to: remotePosition) }
            let currentlyPlaying = player.rate > 0
            if remoteIsPlaying != currentlyPlaying { remoteIsPlaying ? play() : pause() }
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayPause() {
        if player.rate > 0 { pause() } else { play() }
    }

    /// Re-attempts stream resolution for the current track without moving
    /// the queue position — the Retry action for `.unsupportedFormat` /
    /// `.networkFailure` / `.cipherFailure` / `.streamResolutionFailure`.
    func retryCurrentTrack() {
        loadTrack(at: currentIndex, autoplay: true)
    }

    func seek(to time: TimeInterval) {
        position = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    func seekToNext() {
        guard canSkipNext else { return }
        loadTrack(at: currentIndex + 1, autoplay: player.rate > 0)
    }

    /// Mirrors Android: restart the current track if more than
    /// `restartInsteadOfPreviousThreshold` seconds in (or there's no
    /// previous track), otherwise actually go back one.
    func seekToPrevious() {
        if position > Self.restartInsteadOfPreviousThreshold || !canSkipPrevious {
            seek(to: 0)
            return
        }
        loadTrack(at: currentIndex - 1, autoplay: player.rate > 0)
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

    private func recordRecentlyPlayed(_ song: Song) {
        recentlyPlayed.removeAll { $0.id == song.id }
        recentlyPlayed.insert(song, at: 0)
        if recentlyPlayed.count > 20 {
            recentlyPlayed.removeLast(recentlyPlayed.count - 20)
        }
    }

    /// Only KVO-driven transport states (buffering/playing/paused) are
    /// touched here — resolution-phase and failure states are exclusively
    /// set by `loadTrack`/item-status-observation, so a stray
    /// `timeControlStatus` change can never mask an in-flight resolve or a
    /// reported failure.
    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        switch state {
        case .idle, .resolving, .unsupportedFormat, .networkFailure, .cipherFailure, .streamResolutionFailure, .playbackFailure:
            return
        case .buffering, .playing, .paused:
            break
        }
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
        case .playing:
            state = .playing
        case .paused:
            state = .paused
        @unknown default:
            break
        }
    }

    private func handleItemStatusChange(_ item: AVPlayerItem) {
        guard item === player.currentItem, item.status == .failed else { return }
        let message = item.error?.localizedDescription ?? "Unknown playback error"
        state = .playbackFailure(message)
    }

    private func loadTrack(at index: Int, autoplay: Bool) {
        guard queue.indices.contains(index) else { return }
        resolveTask?.cancel()
        itemStatusObservation = nil

        currentIndex = index
        currentSong = queue[index]
        position = 0
        diagnostics = nil
        player.replaceCurrentItem(with: nil)
        state = .resolving
        recordRecentlyPlayed(queue[index])

        let song = queue[index]
        resolveTask = Task { @MainActor in
            do {
                let resolved = try await StreamResolver.resolveStreamURL(videoId: song.id)
                guard !Task.isCancelled, song.id == self.currentSong?.id else { return }

                let item = AVPlayerItem(url: resolved.url)
                self.itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in self?.handleItemStatusChange(item) }
                }
                self.player.replaceCurrentItem(with: item)
                self.diagnostics = resolved.diagnostics
                self.state = autoplay ? .buffering : .paused
                if autoplay { self.play() }
            } catch {
                guard !Task.isCancelled, song.id == self.currentSong?.id else { return }
                self.applyResolutionFailure(error, for: song)
            }
        }
    }

    private func applyResolutionFailure(_ error: Error, for song: Song) {
        let category: String
        switch error {
        case PlayerError.unsupportedFormat(let formats):
            state = .unsupportedFormat(availableFormats: formats)
            category = "unsupported_format"
        case PlayerError.network(let detail):
            state = .networkFailure(detail)
            category = "network"
        case PlayerError.cipherFailure(let detail):
            state = .cipherFailure(detail)
            category = "cipher"
        case PlayerError.streamResolutionFailure(let detail):
            state = .streamResolutionFailure(detail)
            category = "resolution"
        default:
            state = .streamResolutionFailure(error.localizedDescription)
            category = "unknown"
        }
        diagnostics = .failure(attempted: [], category: category)
    }
}
