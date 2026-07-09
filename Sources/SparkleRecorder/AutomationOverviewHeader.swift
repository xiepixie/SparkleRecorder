import SwiftUI
import SparkleRecorderCore

struct AutomationOverviewHeader: View {
    let projection: AutomationOverviewProjection
    let refreshState: AutomationRepositoryRefreshState
    let onOpenAIDraftPreview: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(String(localized: "Automation", table: "Automation"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
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

            Button("AI Draft", systemImage: "sparkles", action: onOpenAIDraftPreview)
                .buttonStyle(.borderless)
                .help(String(localized: "Open AI workflow draft", table: "Automation"))
                .accessibilityLabel(String(localized: "Open AI workflow draft", table: "Automation"))

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(refreshState.isLoading ? Brand.libraryBlue.opacity(0.12) : Color.clear)
                )
                .disabled(refreshState.isLoading)
                .help(String(localized: "Refresh automation projection", table: "Automation"))
                .accessibilityLabel(String(localized: "Refresh automation projection", table: "Automation"))
        }
    }
}
