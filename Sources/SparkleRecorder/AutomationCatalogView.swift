import AppKit
import SparkleRecorderCore
import SwiftUI

private enum AutomationCatalogFilter: String, CaseIterable, Identifiable {
  case all
  case active
  case needsAttention

  var id: Self { self }

  var title: String {
    switch self {
    case .all: String(localized: "All", table: "Common")
    case .active: String(localized: "Active", table: "Common")
    case .needsAttention: String(localized: "Needs attention", table: "Automation")
    }
  }
}

struct AutomationCatalogView: View {
  let catalog: AutomationCatalogProjection
  let runs: AutomationRunCenterProjection
  let refreshState: AutomationRepositoryRefreshState
  let onOpen: (UUID) -> Void
  let onRun: (UUID) -> Void
  let onSetEnabled: (UUID, Bool) -> Void
  let onDelete: (UUID) -> Void
  let onCreateFromLibrary: () -> Void
  let onCreateAdvanced: () -> Void
  let onRefresh: () -> Void

  @State private var search = ""
  @State private var filter: AutomationCatalogFilter = .all
  @State private var selectedWorkflowID: UUID?
  @State private var pendingDeletion: AutomationCatalogItemProjection?
  @State private var selectedExecution: AutomationExecutionProjection?
  @State private var historyItem: AutomationCatalogItemProjection?
  @State private var showGlobalHistory = false

  private var filteredItems: [AutomationCatalogItemProjection] {
    catalog.items.filter { item in
      let matchesFilter: Bool
      switch filter {
      case .all:
        matchesFilter = true
      case .active:
        matchesFilter = item.isEnabled
      case .needsAttention:
        matchesFilter =
          item.status == .failed || item.status == .blocked || item.status == .timedOut
      }
      let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
      return matchesFilter && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
    }
  }

  private var selectedItem: AutomationCatalogItemProjection? {
    let resolvedID =
      selectedWorkflowID ?? filteredItems.first?.workflowID ?? catalog.items.first?.workflowID
    return catalog.items.first { $0.workflowID == resolvedID }
  }

  private func executions(for workflowID: UUID) -> [AutomationExecutionProjection] {
    runs.executions.filter { $0.workflowID == workflowID }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.5)
      HSplitView {
        masterPane
          .frame(minWidth: 310, idealWidth: 360, maxWidth: 420)
        detailPane
          .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear { repairSelection() }
    .onChange(of: catalog.items.map(\.workflowID)) { repairSelection() }
    .onChange(of: filteredItems.map(\.workflowID)) { repairSelection() }
    .alert(
      pendingDeletion.map {
        String(
          format: String(localized: "Delete automation “%@”?", table: "Automation"),
          $0.name
        )
      } ?? String(localized: "Delete automation?", table: "Automation"),
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      )
    ) {
      Button(String(localized: "Cancel", table: "Common"), role: .cancel) {
        pendingDeletion = nil
      }
      Button(String(localized: "Delete", table: "Common"), role: .destructive) {
        guard let item = pendingDeletion else { return }
        pendingDeletion = nil
        onDelete(item.workflowID)
      }
    } message: {
      Text(
        "The automation configuration will be removed. Its macros and saved run history will remain.",
        tableName: "Automation")
    }
    .sheet(item: $selectedExecution) { execution in
      AutomationExecutionDetailSheet(execution: execution)
    }
    .sheet(item: $historyItem) { item in
      AutomationHistorySheet(
        title: item.name,
        executions: executions(for: item.workflowID)
      )
    }
    .sheet(isPresented: $showGlobalHistory) {
      AutomationHistorySheet(
        title: String(localized: "All run history", table: "Automation"),
        executions: runs.executions
      )
    }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Label(
        String(localized: "Automations", table: "Automation"), systemImage: "bolt.horizontal.circle"
      )
      .font(.title3.weight(.semibold))

      summaryValue(catalog.items.count, title: String(localized: "Total", table: "Common"))
      summaryValue(catalog.scheduledCount, title: String(localized: "Scheduled", table: "Common"))
      if catalog.needsAttentionCount > 0 {
        summaryValue(
          catalog.needsAttentionCount,
          title: String(localized: "Needs attention", table: "Automation"),
          tint: Brand.sigAmber
        )
      }

      Spacer(minLength: 12)
      AutomationRefreshStatusView(refreshState: refreshState)

      Button(
        String(localized: "Run History", table: "Automation"), systemImage: "clock.arrow.circlepath"
      ) {
        showGlobalHistory = true
      }
      .buttonStyle(.bordered)

      Button(
        String(localized: "Refresh", table: "Common"), systemImage: "arrow.clockwise",
        action: onRefresh
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .frame(width: 28, height: 28)
      .disabled(refreshState.isLoading)

      Menu {
        Button(action: onCreateFromLibrary) {
          Label(
            String(localized: "Create from Macro Library", table: "Automation"),
            systemImage: "rectangle.stack.badge.plus"
          )
        }
        Button(action: onCreateAdvanced) {
          Label(
            String(localized: "New advanced workflow", table: "Automation"),
            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
          )
        }
      } label: {
        Label(
          String(localized: "Create Automation", table: "Automation"),
          systemImage: "plus"
        )
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .padding(.horizontal, 18)
    .frame(height: 58)
  }

  private var masterPane: some View {
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        HStack(spacing: 7) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField(String(localized: "Search automations", table: "Automation"), text: $search)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.045))
        )

        Picker("", selection: $filter) {
          ForEach(AutomationCatalogFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
      .padding(12)

      Divider().opacity(0.35)

      if catalog.items.isEmpty {
        AutomationEmptyState(
          systemImage: "bolt.horizontal.circle",
          title: String(localized: "No automations", table: "Automation"),
          subtitle: String(
            localized: "Create one from a macro, then choose when it runs.", table: "Automation")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredItems.isEmpty {
        AutomationEmptyState(
          systemImage: "magnifyingglass",
          title: String(localized: "No matching automations", table: "Automation"),
          subtitle: String(localized: "Change the search or status filter.", table: "Automation")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(filteredItems) { item in
              AutomationMasterRow(
                item: item,
                isSelected: selectedItem?.workflowID == item.workflowID
              ) {
                selectedWorkflowID = item.workflowID
              }
            }
          }
          .padding(8)
        }
      }
    }
  }

  @ViewBuilder
  private var detailPane: some View {
    if let item = selectedItem {
      AutomationDetailView(
        item: item,
        executions: executions(for: item.workflowID),
        onRun: { onRun(item.workflowID) },
        onEdit: { onOpen(item.workflowID) },
        onSetEnabled: { onSetEnabled(item.workflowID, $0) },
        onDelete: { pendingDeletion = item },
        onOpenExecution: { selectedExecution = $0 },
        onOpenHistory: { historyItem = item }
      )
    } else {
      AutomationEmptyState(
        systemImage: "sidebar.right",
        title: String(localized: "Select an automation", table: "Automation"),
        subtitle: String(
          localized: "Choose an automation to manage its schedule and runs.", table: "Automation")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func repairSelection() {
    if let selectedWorkflowID,
      filteredItems.contains(where: { $0.workflowID == selectedWorkflowID })
    {
      return
    }
    selectedWorkflowID = filteredItems.first?.workflowID ?? catalog.items.first?.workflowID
  }

  private func summaryValue(_ value: Int, title: String, tint: Color = .secondary) -> some View {
    HStack(spacing: 5) {
      Text(value, format: .number)
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(tint)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

private struct AutomationMasterRow: View {
  let item: AutomationCatalogItemProjection
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 10) {
        Image(systemName: item.tier.systemImage)
          .foregroundStyle(item.status.tint)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(item.name)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            Spacer(minLength: 4)
            if !item.isEnabled {
              Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
            }
          }
          HStack(spacing: 7) {
            Text(item.tier.title)
            Text("·")
            Text(item.compositionLabel)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          HStack(spacing: 5) {
            Image(systemName: item.status.systemImage)
            Text(item.status.label)
            Spacer(minLength: 4)
            if let next = item.nextScheduledOccurrence {
              Text(next, format: .dateTime.month().day().hour().minute())
                .monospacedDigit()
            }
          }
          .font(.caption2)
          .foregroundStyle(item.status.tint)
        }
      }
      .padding(.horizontal, 10)
      .frame(minHeight: 72)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isSelected ? Brand.libraryBlue.opacity(0.14) : Color.clear)
    )
  }
}

private struct AutomationDetailView: View {
  let item: AutomationCatalogItemProjection
  let executions: [AutomationExecutionProjection]
  let onRun: () -> Void
  let onEdit: () -> Void
  let onSetEnabled: (Bool) -> Void
  let onDelete: () -> Void
  let onOpenExecution: (AutomationExecutionProjection) -> Void
  let onOpenHistory: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        detailHeader
        Divider().opacity(0.35)
        overviewSection
        Divider().opacity(0.35)
        recentRunsSection
      }
      .frame(maxWidth: 920, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 18)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  private var detailHeader: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: item.tier.systemImage)
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(item.status.tint)
        .frame(width: 34, height: 34)
      VStack(alignment: .leading, spacing: 5) {
        Text(item.name)
          .font(.title2.weight(.semibold))
          .lineLimit(2)
        HStack(spacing: 8) {
          Text(item.tier.title)
          Text("·")
          Text(item.compositionLabel)
          Text("·")
          Label(
            item.isEnabled
              ? String(localized: "On", table: "Automation")
              : String(localized: "Paused", table: "Automation"),
            systemImage: item.isEnabled ? "checkmark.circle" : "pause.circle"
          )
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 16)

      Button(
        String(localized: "Run now", table: "Automation"), systemImage: "play.fill", action: onRun
      )
      .buttonStyle(.borderedProminent)
      .disabled(!item.isEnabled)
      Button(
        String(localized: "Edit", table: "Common"), systemImage: "slider.horizontal.3",
        action: onEdit
      )
      .buttonStyle(.bordered)
      Menu {
        Button {
          onSetEnabled(!item.isEnabled)
        } label: {
          Label(
            item.isEnabled
              ? String(localized: "Pause automation", table: "Automation")
              : String(localized: "Resume automation", table: "Automation"),
            systemImage: item.isEnabled ? "pause" : "play"
          )
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
          Label(String(localized: "Delete automation", table: "Automation"), systemImage: "trash")
        }
      } label: {
        Label(String(localized: "More", table: "Common"), systemImage: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .padding(.bottom, 18)
  }

  private var overviewSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Overview", tableName: "Common")
        .font(.headline)
      HStack(alignment: .top, spacing: 28) {
        detailMetric(
          title: String(localized: "Next run", table: "Automation"),
          value: nextRunLabel,
          systemImage: "calendar.badge.clock"
        )
        detailMetric(
          title: String(localized: "Current status", table: "Automation"),
          value: item.statusDetail,
          systemImage: item.status.systemImage,
          tint: item.status.tint
        )
        detailMetric(
          title: String(localized: "Run history", table: "Automation"),
          value: String(
            format: String(localized: "%d executions", table: "Automation"),
            executions.count
          ),
          systemImage: "clock.arrow.circlepath"
        )
        detailMetric(
          title: String(localized: "Evidence", table: "Automation"),
          value: item.hasEvidence
            ? String(localized: "Available", table: "Automation")
            : String(localized: "No evidence", table: "Automation"),
          systemImage: item.hasEvidence ? "paperclip" : "paperclip.slash"
        )
      }
    }
    .padding(.vertical, 18)
  }

  private var recentRunsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Recent runs", tableName: "Automation")
          .font(.headline)
        Spacer()
        if !executions.isEmpty {
          Button(String(localized: "View all", table: "Common"), action: onOpenHistory)
            .buttonStyle(.link)
        }
      }

      if executions.isEmpty {
        HStack(spacing: 10) {
          Image(systemName: "clock.badge.questionmark")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text("No runs yet", tableName: "Automation")
              .font(.subheadline.weight(.medium))
            Text(
              "Run this automation to create its first result and evidence record.",
              tableName: "Automation"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 16)
      } else {
        VStack(spacing: 0) {
          ForEach(executions.prefix(5)) { execution in
            AutomationExecutionRow(execution: execution) {
              onOpenExecution(execution)
            }
            Divider().opacity(0.28)
          }
        }
      }
    }
    .padding(.vertical, 18)
  }

  private var nextRunLabel: String {
    if let next = item.nextScheduledOccurrence {
      return next.formatted(date: .abbreviated, time: .shortened)
    }
    return item.hasSchedule
      ? String(localized: "No upcoming run", table: "Automation")
      : String(localized: "Manual", table: "Common")
  }

  private func detailMetric(
    title: String,
    value: String,
    systemImage: String,
    tint: Color = .secondary
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct AutomationExecutionRow: View {
  let execution: AutomationExecutionProjection
  let onOpen: () -> Void

  var body: some View {
    Button(action: onOpen) {
      HStack(spacing: 11) {
        Image(systemName: execution.status.systemImage)
          .foregroundStyle(execution.status.tint)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 7) {
            Text(execution.status.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(execution.status.tint)
            if let taskName = execution.failureFocus?.taskName {
              Text(taskName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Text(
            String(
              format: String(localized: "%d steps · %d attempts", table: "Automation"),
              execution.taskRunCount,
              execution.attemptCount
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if execution.hasEvidence {
          Label(String(localized: "Evidence", table: "Automation"), systemImage: "paperclip")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(execution.latestActivityAt.formatted(date: .abbreviated, time: .shortened))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .padding(.vertical, 11)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct AutomationHistorySheet: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  let executions: [AutomationExecutionProjection]
  @State private var selectedExecution: AutomationExecutionProjection?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(Brand.libraryBlue)
        VStack(alignment: .leading, spacing: 2) {
          Text("Run history", tableName: "Automation")
            .font(.headline)
          Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text(executions.count, format: .number)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        Button(String(localized: "Done", table: "Common")) { dismiss() }
      }
      .padding(16)
      Divider()
      if executions.isEmpty {
        AutomationEmptyState(
          systemImage: "clock.badge.questionmark",
          title: String(localized: "No runs yet", table: "Automation"),
          subtitle: String(
            localized: "Run this automation to create its first result and evidence record.",
            table: "Automation")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(executions) { execution in
              AutomationExecutionRow(execution: execution) {
                selectedExecution = execution
              }
              Divider().opacity(0.28)
            }
          }
          .padding(.horizontal, 16)
        }
      }
    }
    .frame(width: 760, height: 620)
    .sheet(item: $selectedExecution) { execution in
      AutomationExecutionDetailSheet(execution: execution)
    }
  }
}

private struct AutomationExecutionDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  let execution: AutomationExecutionProjection
  @State private var evidenceSelection: AutomationRunCenterEvidenceSelection?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: execution.status.systemImage)
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(execution.status.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text(execution.status.title)
            .font(.headline)
          Text(execution.workflowName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(
          String(localized: "Copy diagnostics", table: "Automation"), systemImage: "doc.on.doc"
        ) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(diagnosticText, forType: .string)
        }
        .buttonStyle(.bordered)
        Button(String(localized: "Done", table: "Common")) { dismiss() }
      }
      .padding(16)
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          summary
          if let failure = execution.failureFocus {
            failureSection(failure)
          }
          diagnosticsSection
          Divider()
          Text("Steps and attempts", tableName: "Automation")
            .font(.headline)
          ForEach(execution.runs) { run in
            AutomationRunCenterStepRow(run: run)
          }
        }
        .padding(18)
      }
    }
    .frame(width: 720, height: 680)
    .sheet(item: $evidenceSelection) { selection in
      AutomationRunCenterEvidenceSheet(selection: selection)
    }
  }

  private var summary: some View {
    HStack(spacing: 24) {
      metric(
        String(localized: "Started", table: "Common"),
        execution.createdAt.formatted(date: .abbreviated, time: .shortened))
      metric(
        String(localized: "Latest activity", table: "Automation"),
        execution.latestActivityAt.formatted(date: .abbreviated, time: .shortened))
      metric(
        String(localized: "Steps", table: "Automation"),
        "\(execution.completedRunCount)/\(execution.taskRunCount)")
      metric(String(localized: "Attempts", table: "Automation"), "\(execution.attemptCount)")
    }
  }

  private func failureSection(_ failure: AutomationRunFailureFocus) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        String(localized: "Needs attention", table: "Automation"),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.headline)
      .foregroundStyle(Brand.sigAmber)
      Text(failure.taskName)
        .font(.subheadline.weight(.semibold))
      if let run = execution.runs.first(where: { $0.id == failure.runID }) {
        Text(AutomationTaskRunDisplay(run: run).detail)
          .font(.callout)
          .foregroundStyle(.secondary)
        if run.evidenceID != nil || run.macroID != nil {
          Button(
            String(localized: "Review Evidence", table: "Automation"),
            systemImage: "doc.text.magnifyingglass"
          ) {
            evidenceSelection = AutomationRunCenterEvidenceSelection(
              run: run,
              taskName: failure.taskName,
              failedEventIndex: failure.failedEventIndex
            )
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(12)
    .background(Brand.sigAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
  }

  private var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Diagnostics", tableName: "Automation")
        .font(.headline)
      Text(execution.recommendedAction.title)
        .font(.callout)
      HStack(spacing: 16) {
        metric(
          String(localized: "Execution ID", table: "Automation"), shortID(execution.executionID))
        metric(String(localized: "Evidence", table: "Automation"), evidenceLabel)
      }
    }
  }

  private var evidenceLabel: String {
    execution.hasEvidence
      ? String(localized: "Available", table: "Automation")
      : String(localized: "No evidence", table: "Automation")
  }

  private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline.monospacedDigit())
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var diagnosticText: String {
    var lines = [
      "Automation: \(execution.workflowName)",
      "Execution ID: \(execution.executionID.uuidString)",
      "Status: \(execution.status.title)",
      "Created: \(execution.createdAt.ISO8601Format())",
      "Latest activity: \(execution.latestActivityAt.ISO8601Format())",
      "Steps: \(execution.completedRunCount)/\(execution.taskRunCount)",
      "Attempts: \(execution.attemptCount)",
      "Recommendation: \(execution.recommendedAction.title)",
    ]
    for run in execution.runs {
      let display = AutomationTaskRunDisplay(run: run)
      lines.append("- \(run.id.uuidString): \(display.title) — \(display.detail)")
    }
    return lines.joined(separator: "\n")
  }

  private func shortID(_ id: UUID) -> String {
    String(id.uuidString.prefix(8))
  }
}

extension AutomationAuthoringTier {
  fileprivate var title: String {
    switch self {
    case .singleMacro: String(localized: "Single macro", table: "Automation")
    case .linearSequence: String(localized: "Sequence", table: "Automation")
    case .advancedWorkflow: String(localized: "Workflow", table: "Automation")
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .singleMacro: "record.circle"
    case .linearSequence: "point.3.connected.trianglepath.dotted"
    case .advancedWorkflow: "point.topleft.down.curvedto.point.bottomright.up"
    }
  }
}

extension AutomationCatalogItemProjection {
  fileprivate var compositionLabel: String {
    switch tier {
    case .singleMacro:
      return String(localized: "1 macro", table: "Automation")
    case .linearSequence, .advancedWorkflow:
      return String(
        format: String(localized: "%d macros · %d steps", table: "Automation"),
        macroCount,
        stepCount
      )
    }
  }
}
