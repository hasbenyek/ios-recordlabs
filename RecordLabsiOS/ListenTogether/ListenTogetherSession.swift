import Foundation
import MultipeerConnectivity
import UIKit

/// Real (not stubbed) implementation of "Listen Together" — but honestly
/// scoped: this uses Apple's `MultipeerConnectivity` framework, which finds
/// and connects to nearby devices over Wi-Fi/Bluetooth peer-to-peer with no
/// server of any kind. That means it genuinely works, with zero backend to
/// stand up, for devices near each other (same room/building) — which is
/// what "listen together" usually means in practice — but NOT for two
/// people in different places over the internet. That would need a real
/// hosted relay (e.g. Firebase, a WebSocket server), which requires an
/// account/infrastructure only you can provision — not something this can
/// include.
///
/// Design: whoever taps "Start a session" is the host and periodically
/// broadcasts their `PlayerConnection`'s state; everyone who joins is a
/// participant whose `PlayerConnection` is driven entirely by what the host
/// sends. This one-directional flow sidesteps sync feedback loops/echo
/// entirely rather than needing timestamp/vector-clock reconciliation.
@MainActor
final class ListenTogetherSession: NSObject, ObservableObject {
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var availablePeers: [MCPeerID] = []
    @Published private(set) var isHosting = false
    @Published private(set) var isParticipant = false

    weak var playerConnection: PlayerConnection?

    /// MultipeerConnectivity service types must be 1-15 chars, lowercase
    /// alphanumeric + hyphen.
    private static let serviceType = "recordlabs-lt"

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session: MCSession = {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var broadcastTimer: Timer?

    struct SyncPayload: Codable {
        var songId: String
        var title: String
        var artist: String
        var position: TimeInterval
        var isPlaying: Bool
    }

    /// Starts advertising this device as joinable and begins periodically
    /// broadcasting `playerConnection`'s state to whoever connects.
    func startHosting() {
        stop()
        isHosting = true

        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.broadcastState() }
        }
    }

    /// Starts scanning for nearby hosts. Discovered peers show up in
    /// `availablePeers`; call `join(_:)` to connect to one.
    func startBrowsing() {
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func join(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        session.disconnect()
        isHosting = false
        isParticipant = false
        connectedPeers = []
        availablePeers = []
    }

    private func broadcastState() {
        guard let playerConnection, let song = playerConnection.currentSong, !session.connectedPeers.isEmpty else { return }
        let payload = SyncPayload(
            songId: song.id,
            title: song.title,
            artist: song.artistNames,
            position: playerConnection.position,
            isPlaying: playerConnection.isPlaying
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }
}

extension ListenTogetherSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeers = session.connectedPeers
            if state == .connected, !self.isHosting { self.isParticipant = true }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else { return }
        Task { @MainActor in
            self.playerConnection?.applyRemoteSync(
                songId: payload.songId,
                title: payload.title,
                artist: payload.artist,
                position: payload.position,
                isPlaying: payload.isPlaying
            )
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension ListenTogetherSession: MCNearbyServiceAdvertiserDelegate {
    /// Auto-accepts every invitation — a deliberate scaffold simplification
    /// (encryption is still `.required`, so traffic is protected; the gap is
    /// no "do you want to let X join?" prompt before that). Swap this for a
    /// real confirmation UI before shipping.
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}

extension ListenTogetherSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !self.availablePeers.contains(peerID) { self.availablePeers.append(peerID) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.availablePeers.removeAll { $0 == peerID }
        }
    }
}
