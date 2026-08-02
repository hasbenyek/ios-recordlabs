import SwiftUI

struct SearchDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    let report: SearchDiagnosticsReport?

    var body: some View {
        NavigationView {
            List {
                if let report {
                    row("Query", report.query)
                    row("Clients tried", report.attemptedClients.joined(separator: " → "))
                    row("Succeeded", report.successfulClient ?? "none")
                    row("Endpoint", report.endpointPath)
                    row("HTTP", report.statusCode.map(String.init) ?? "not received")
                    row("Content-Type", report.contentType ?? "not received")
                    row("Response bytes", String(report.responseBytes))
                    row("Top-level keys", report.topLevelKeys.joined(separator: ", "))
                    row("Renderer nodes", String(report.rendererNodesVisited))
                    row("Song candidates", String(report.candidateSongRenderersFound))
                    row("Rejected: videoId", String(report.rejectedMissingVideoId))
                    row("Rejected: title", String(report.rejectedMissingTitle))
                    row("Rejected: artist", String(report.rejectedMissingArtist))
                    row("Songs emitted", String(report.songsEmitted))
                    row("Final category", report.finalErrorCategory ?? "none")
                    row("Message", report.safeMessage ?? "none")
                } else {
                    Text("No search diagnostics yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Search diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
