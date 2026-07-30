import SwiftUI
import MultipeerConnectivity

/// Real (not UI-only) Listen Together, backed by `ListenTogetherSession`
/// (MultipeerConnectivity — local network only, see that file's doc
/// comment for exactly what that means and doesn't mean).
struct ListenTogetherScreen: View {
    @EnvironmentObject private var playerConnection: PlayerConnection
    @StateObject private var session = ListenTogetherSession()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                if !session.isHosting && !session.isParticipant {
                    Section {
                        Button("Start a session (host)") {
                            session.playerConnection = playerConnection
                            session.startHosting()
                        }
                        Button("Look for nearby sessions") {
                            session.startBrowsing()
                        }
                    }
                }

                if !session.availablePeers.isEmpty {
                    Section("Nearby") {
                        ForEach(session.availablePeers, id: \.self) { peer in
                            Button(peer.displayName) {
                                session.playerConnection = playerConnection
                                session.join(peer)
                            }
                        }
                    }
                }

                if !session.connectedPeers.isEmpty {
                    Section("Connected") {
                        ForEach(session.connectedPeers, id: \.self) { peer in
                            Label(peer.displayName, systemImage: "checkmark.circle.fill")
                        }
                    }
                }

                if session.isHosting || session.isParticipant {
                    Section {
                        Button("Leave session", role: .destructive) {
                            session.stop()
                        }
                    }
                }
            }
            .navigationTitle("Listen Together")
        }
        .onDisappear { session.stop() }
    }

    private var statusText: String {
        if session.isHosting {
            return "Hosting — nearby devices can join. Your playback is being shared."
        } else if session.isParticipant {
            return "Connected — following the host's playback."
        } else {
            return "Start a session, or look for one on the same Wi-Fi/Bluetooth range. This only works with devices physically nearby — there's no internet relay."
        }
    }
}

#Preview {
    ListenTogetherScreen().environmentObject(PlayerConnection())
}
