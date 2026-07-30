import SwiftUI

/// Minimal stand-in for `ContentUnavailableView`, which needs iOS 17+ — this
/// app's deployment target is iOS 15.
struct EmptyStateView: View {
    var title: String
    var systemImage: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
