import Foundation

/// Generic production-data loading state. Every screen that shows real
/// network-backed content (Search, Home) uses this instead of ad-hoc
/// booleans, so a failure state can never be silently skipped in favor of
/// placeholder content.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case error(LoadError)
}

/// Distinguishes *why* a load failed, so the UI (and diagnostics) can say
/// something more useful than "something went wrong".
enum LoadError: Error, Equatable {
    case network(String)
    case parsing(String)
    case cancelled

    var message: String {
        switch self {
        case .network(let detail): return "Network error: \(detail)"
        case .parsing(let detail): return "Couldn't understand the server's response: \(detail)"
        case .cancelled: return "Cancelled"
        }
    }
}
