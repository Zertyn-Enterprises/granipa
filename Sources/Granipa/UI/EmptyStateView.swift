import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
