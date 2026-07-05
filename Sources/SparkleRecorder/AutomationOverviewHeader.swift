import SwiftUI
import SparkleRecorderCore

struct AutomationOverviewHeader: View {
    let projection: AutomationOverviewProjection
    let refreshState: AutomationRepositoryRefreshState
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(NSLocalizedString("Automation", comment: ""), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)

            Text(projection.generatedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            AutomationRefreshStatusView(refreshState: refreshState)

            HStack(spacing: 8) {
                ForEach(projection.statusCounts) { count in
                    AutomationStatusBadge(status: count.status, count: count.count)
                }
            }

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .controlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: refreshState.isLoading)
                .disabled(refreshState.isLoading)
                .help(NSLocalizedString("Refresh automation projection", comment: ""))
                .accessibilityLabel(NSLocalizedString("Refresh automation projection", comment: ""))
        }
    }
}
