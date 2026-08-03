import Foundation

/// In-app diagnostics for the most recently resolved stream.
///
/// Deliberately does NOT hold: the resolved stream URL itself (it's a
/// signed, time-limited YouTube CDN URL), cookies, SAPISID, Authorization
/// headers, PoTokens, or any account identifier. Everything here is safe to
/// display on-screen or include in a bug report.
struct StreamDiagnostics: Equatable {
    var selectedClient: String
    var pathType: PathType
    var mimeType: String
    var codec: String
    var bitrateKbps: Int
    var expiresInSeconds: Int?
    var fallbackClientsAttempted: [String]
    var finalErrorCategory: String?

    enum PathType: String {
        case direct = "Direct URL (no cipher)"
        case cipher = "Signature cipher (WebView-deciphered)"
    }

    static func failure(attempted: [String], category: String) -> StreamDiagnostics {
        StreamDiagnostics(
            selectedClient: "—",
            pathType: .direct,
            mimeType: "—",
            codec: "—",
            bitrateKbps: 0,
            expiresInSeconds: nil,
            fallbackClientsAttempted: attempted,
            finalErrorCategory: category
        )
    }
}
