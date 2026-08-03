import Foundation
import Combine

struct SearchHTTPResponse {
    let data: Data
    let client: YouTubeClientIdentity
    let endpointPath: String
    let statusCode: Int
    let contentType: String
    let byteCount: Int
}

protocol SearchRequesting {
    func searchResponse(query: String, identity: YouTubeClientIdentity) async throws -> SearchHTTPResponse
}

struct SearchDiagnosticsReport: Equatable {
    var query: String
    var attemptedClients: [String] = []
    var successfulClient: String?
    var endpointPath: String = "/youtubei/v1/search"
    var statusCode: Int?
    var contentType: String?
    var responseBytes = 0
    var topLevelKeys: [String] = []
    var rendererNodesVisited = 0
    var candidateSongRenderersFound = 0
    var rejectedMissingVideoId = 0
    var rejectedMissingTitle = 0
    var rejectedMissingArtist = 0
    var songsEmitted = 0
    var finalErrorCategory: String?
    var safeMessage: String?
}

struct SearchExecutionResult {
    let songs: [Song]
    let diagnostics: SearchDiagnosticsReport
}

enum SearchServiceError: Error {
    case failed(SearchDiagnosticsReport)

    var report: SearchDiagnosticsReport {
        switch self {
        case .failed(let report): return report
        }
    }
}

struct SearchService {
    /// These clients are search-capable without a PoToken in this app. The
    /// order is declarative and is also shown in the diagnostics panel.
    static let fallbackOrder: [YouTubeClientIdentity] = [.webRemix, .androidMobile]

    let client: SearchRequesting

    init(client: SearchRequesting = InnerTubeClient.shared) {
        self.client = client
    }

    func search(query: String) async throws -> SearchExecutionResult {
        var report = SearchDiagnosticsReport(query: query)
        for identity in Self.fallbackOrder {
            try Task.checkCancellation()
            report.attemptedClients.append(identity.clientName)
            do {
                let response = try await client.searchResponse(query: query, identity: identity)
                report.endpointPath = response.endpointPath
                report.statusCode = response.statusCode
                report.contentType = response.contentType
                report.responseBytes = response.byteCount
                let parsed = SearchResponseParser.parseSongs(from: response.data)
                merge(parsed.metrics, into: &report)
                try Task.checkCancellation()
                if !parsed.songs.isEmpty {
                    report.successfulClient = identity.clientName
                    report.finalErrorCategory = nil
                    report.safeMessage = "Search succeeded with \(identity.clientName)."
                    return SearchExecutionResult(songs: parsed.songs, diagnostics: report)
                }
                report.finalErrorCategory = parsed.metrics.finalErrorCategory ?? "noUsableSongs"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let inner = error as? InnerTubeError, case .badStatus(let status) = inner {
                    report.statusCode = status
                    report.contentType = "not available"
                    report.responseBytes = 0
                }
                report.finalErrorCategory = category(for: error)
                report.safeMessage = "\(identity.clientName) failed; the next search client was tried."
            }
        }
        if report.finalErrorCategory == "parserIncompatible" {
            report.safeMessage = "Search response received, but no supported song renderer was parsed."
        } else if report.finalErrorCategory == nil {
            report.finalErrorCategory = "allClientsFailed"
        }
        throw SearchServiceError.failed(report)
    }

    private func merge(_ metrics: SearchParseDiagnostics, into report: inout SearchDiagnosticsReport) {
        report.topLevelKeys = metrics.topLevelKeys
        report.rendererNodesVisited = metrics.rendererNodesVisited
        report.candidateSongRenderersFound = metrics.candidateSongRenderersFound
        report.rejectedMissingVideoId = metrics.rejectedMissingVideoId
        report.rejectedMissingTitle = metrics.rejectedMissingTitle
        report.rejectedMissingArtist = metrics.rejectedMissingArtist
        report.songsEmitted = metrics.songsEmitted
        report.finalErrorCategory = metrics.finalErrorCategory
    }

    private func category(for error: Error) -> String {
        if let inner = error as? InnerTubeError {
            if case .badStatus = inner { return "httpNon2xx" }
            if case .decodingFailed = inner { return "decodeFailure" }
        }
        return "requestFailure"
    }
}

@MainActor
final class SearchDiagnosticsCenter: ObservableObject {
    static let shared = SearchDiagnosticsCenter()
    @Published private(set) var latest: SearchDiagnosticsReport?

    func publish(_ report: SearchDiagnosticsReport) {
        latest = report
    }
}
