import SwiftUI
import SparkleRecorderCore

struct AutomationRefreshStatusView: View {
    let refreshState: AutomationRepositoryRefreshState

    var body: some View {
        if refreshState.isLoading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(NSLocalizedString("Refreshing automation projection", comment: ""))
        } else if let failure = refreshState.failure {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Brand.sigAmber)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(failure.message)
        }
    }
}
