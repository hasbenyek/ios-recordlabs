import SwiftUI

/// Safe-to-show diagnostics for the currently resolved (or failed-to-resolve)
/// stream. Never displays the resolved URL, cookies, or any credential —
/// see `StreamDiagnostics`'s doc comment for the rule this enforces.
struct PlayerDiagnosticsView: View {
    var diagnostics: StreamDiagnostics?
    var state: PlaybackState

    var body: some View {
        NavigationView {
            List {
                if let diagnostics {
                    Section("Stream") {
                        row("Client", diagnostics.selectedClient)
                        row("Path", diagnostics.pathType.rawValue)
                        row("MIME type", diagnostics.mimeType)
                        row("Codec", diagnostics.codec)
                        row("Bitrate", diagnostics.bitrateKbps > 0 ? "\(diagnostics.bitrateKbps) kbps" : "—")
                        if let expires = diagnostics.expiresInSeconds {
                            row("URL expires in", "\(expires / 60) min")
                        }
                    }
                    if !diagnostics.fallbackClientsAttempted.isEmpty {
                        Section("Clients attempted") {
                            ForEach(diagnostics.fallbackClientsAttempted, id: \.self) { client in
                                Text(client)
                            }
                        }
                    }
                    if let category = diagnostics.finalErrorCategory {
                        Section("Error") {
                            row("Category", category)
                        }
                    }
                } else {
                    Text("No stream has been resolved yet for this track.")
                        .foregroundStyle(.secondary)
                }
                Section("Player state") {
                    row("State", String(describing: state))
                }
            }
            .navigationTitle("Playback Diagnostics")
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
