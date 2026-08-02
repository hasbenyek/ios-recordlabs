import SwiftUI

/// Shown whenever a production data load fails. Always paired with a Retry
/// action — this project never substitutes sample/placeholder content for a
/// failed real request.
struct ErrorStateView: View {
    var title: String = "Something went wrong"
    var message: String
    var retryTitle: String = "Retry"
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(retryTitle, action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
