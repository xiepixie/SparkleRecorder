import SparkleRecorderCore
import SwiftUI

struct AutomationOverviewHeader: View {
  let projection: AutomationOverviewProjection
  let refreshState: AutomationRepositoryRefreshState
  let onBack: () -> Void
  let onOpenAIDraftPreview: () -> Void
  let onRefresh: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(
        String(localized: "All automations", table: "Automation"), systemImage: "chevron.left",
        action: onBack
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .frame(width: 28, height: 28)
      .help(String(localized: "All automations", table: "Automation"))

      Label(
        String(localized: "Workflow Editor", table: "Automation"),
        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
      )
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

      LocalizedSystemButton(
        "AI Draft", tableName: L10nTable.automation, systemImage: "sparkles",
        action: onOpenAIDraftPreview
      )
      .buttonStyle(.borderless)
      .help(String(localized: "Open AI workflow draft", table: "Automation"))
      .accessibilityLabel(String(localized: "Open AI workflow draft", table: "Automation"))

      LocalizedSystemButton(
        "Refresh", tableName: L10nTable.common, systemImage: "arrow.clockwise", action: onRefresh
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .frame(width: 28, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(refreshState.isLoading ? Brand.libraryBlue.opacity(0.12) : Color.clear)
      )
      .disabled(refreshState.isLoading)
      .help(String(localized: "Refresh automations", table: "Automation"))
      .accessibilityLabel(String(localized: "Refresh automations", table: "Automation"))
    }
  }
}
