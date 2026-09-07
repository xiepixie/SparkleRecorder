import SparkleRecorderCore
import SwiftUI

struct AutomationRunCenterSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var model: AutomationRunCenterModel
  @State private var filter: AutomationRunCenterFilter = .all
  @State private var selectedExecutionID: UUID?
  @State private var evidenceSelection: AutomationRunCenterEvidenceSelection?
  @State private var pendingCancellation: AutomationRunCenterCommand?
  @State private var pendingDeletion: AutomationRunCenterCommand?
  @State private var commandInFlight = false
  @State private var commandFeedback: AutomationRunCenterCommandFeedback?
  @State private var storageUsage: AutomationRunStorageUsage?
  @State private var storageUsageError: String?

  private let onOpenWorkflow: (UUID, UUID?) -> Void
  private let onPerformCommand:
    @MainActor (AutomationRunCenterCommand) async -> AutomationRunCenterCommandFeedback
  private let onLoadStorageUsage: @Sendable () async throws -> AutomationRunStorageUsage

  init(
    runtimeHost: LiveAutomationRuntimeHost,
    onOpenWorkflow: @escaping (UUID, UUID?) -> Void,
    onLoadStorageUsage: @escaping @Sendable () async throws -> AutomationRunStorageUsage,
    onPerformCommand:
      @escaping @MainActor (AutomationRunCenterCommand) async -> AutomationRunCenterCommandFeedback
  ) {
    _model = State(initialValue: AutomationRunCenterModel(runtimeHost: runtimeHost))
    self.onOpenWorkflow = onOpenWorkflow
    self.onLoadStorageUsage = onLoadStorageUsage
    self.onPerformCommand = onPerformCommand
  }

  init(
    fixtureState: AutomationRunState,
    onOpenWorkflow: @escaping (UUID, UUID?) -> Void = { _, _ in },
    onLoadStorageUsage: @escaping @Sendable () async throws -> AutomationRunStorageUsage = {
      AutomationRunStorageUsage(
        breakdown: AutomationRunStorageBreakdown(),
        historyByteCount: 0,
        runCount: 0,
        executionBreakdowns: [:]
      )
    },
    onPerformCommand:
      @escaping @MainActor (AutomationRunCenterCommand) async -> AutomationRunCenterCommandFeedback =
      { _ in
        AutomationRunCenterCommandFeedback(message: "")
      }
  ) {
    _model = State(
      initialValue: AutomationRunCenterModel(
        initialState: fixtureState,
        now: { fixtureState.now ?? Date(timeIntervalSince1970: 0) },
        loader: { .loaded(fixtureState) }
      ))
    self.onOpenWorkflow = onOpenWorkflow
    self.onLoadStorageUsage = onLoadStorageUsage
    self.onPerformCommand = onPerformCommand
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      statusBanners
      filterTabs
      Divider()
      content
    }
    .frame(
      minWidth: 820,
      idealWidth: 980,
      maxWidth: .infinity,
      minHeight: 580,
      idealHeight: 680,
      maxHeight: .infinity,
      alignment: .top
    )
    .task {
      model.startAutoRefresh()
      await refreshStorageUsage()
    }
    .onDisappear {
      model.stopAutoRefresh()
    }
    .onChange(of: model.projection.generatedAt) {
      repairSelection()
    }
    .onChange(of: filter) {
      repairSelection()
    }
    .onChange(of: selectedExecutionID) {
      commandFeedback = nil
    }
    .sheet(item: $evidenceSelection) { selection in
      AutomationRunCenterEvidenceSheet(selection: selection)
    }
    .alert(
      String(localized: "Cancel this execution?", table: "Automation"),
      isPresented: Binding(
        get: { pendingCancellation != nil },
        set: { if !$0 { pendingCancellation = nil } }
      )
    ) {
      Button(String(localized: "Keep Running", table: "Automation"), role: .cancel) {
        pendingCancellation = nil
      }
      Button(String(localized: "Cancel Run", table: "Automation"), role: .destructive) {
        guard let command = pendingCancellation else { return }
        pendingCancellation = nil
        Task { await execute(command) }
      }
    } message: {
      Text(
        "Every active step in this execution will be stopped. Completed steps and saved evidence will remain in history.",
        tableName: "Automation")
    }
    .alert(
      deletionAlertTitle,
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      )
    ) {
      Button(String(localized: "Cancel", table: "Common"), role: .cancel) {
        pendingDeletion = nil
      }
      Button(String(localized: "Delete", table: "Common"), role: .destructive) {
        guard let command = pendingDeletion else { return }
        pendingDeletion = nil
        Task { await execute(command) }
      }
    } message: {
      Text(deletionAlertMessage)
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(Brand.libraryBlue)
        .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 2) {
        Text("Runs", tableName: "Automation")
          .font(.headline)
        Text(refreshLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      if model.loadState.isLoading {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(String(localized: "Loading runs", table: "Automation"))
      }

      Button("", systemImage: "arrow.clockwise") {
        Task {
          await model.refresh(
            showsLoading: true,
            forceProjection: true
          )
          await refreshStorageUsage()
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(model.loadState.isLoading)
      .help(String(localized: "Refresh runs", table: "Automation"))
      .accessibilityLabel(String(localized: "Refresh runs", table: "Automation"))

      Button(String(localized: "Done", table: "Common")) {
        dismiss()
      }
      .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  @ViewBuilder
  private var statusBanners: some View {
    if let issue = model.projection.persistenceIssue {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "externaldrive.badge.exclamationmark")
          .foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 2) {
          Text("Run data could not be saved", tableName: "Automation")
            .font(.caption)
            .fontWeight(.semibold)
          Text(AutomationRunCenterIssuePresenter.persistenceIssue(issue).detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Text("Live actions were stopped", tableName: "Automation")
          .font(.caption)
          .foregroundStyle(.red)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 9)
      Divider()
    }

    if let storageUsageError {
      HStack(spacing: 8) {
        Image(systemName: "externaldrive.badge.questionmark")
          .foregroundStyle(Brand.sigAmber)
        Text(storageUsageError)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer(minLength: 8)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 9)
      Divider()
    }

    if let failureMessage = model.loadState.failureMessage {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
          .foregroundStyle(Brand.sigAmber)
        Text(AutomationRunCenterIssuePresenter.loadFailure(failureMessage).detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer(minLength: 8)
        if model.loadState.lastLoadedAt != nil {
          Text("Showing last loaded runs", tableName: "Automation")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 9)
      Divider()
    }
  }

  private var filterTabs: some View {
    HStack(spacing: 0) {
      filterTab(.all)
      filterTab(.needsAttention)
      filterTab(.running)
      filterTab(.succeeded)
    }
    .frame(minHeight: 64)
    .background(Color.primary.opacity(0.018))
  }

  private func filterTab(_ candidate: AutomationRunCenterFilter) -> some View {
    let presentation = filterPresentation(candidate)
    let selected = filter == candidate
    return Button {
      filter = candidate
    } label: {
      HStack(spacing: 9) {
        Image(systemName: presentation.systemImage)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(selected ? presentation.tint : .secondary)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text(presentation.count, format: .number)
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .contentTransition(.numericText())
            .animation(controlAnimation, value: presentation.count)
          Text(presentation.title)
            .font(.caption)
            .foregroundStyle(selected ? .primary : .secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background {
        Rectangle()
          .fill(presentation.tint.opacity(0.08))
          .opacity(selected ? 1 : 0)
          .animation(controlAnimation, value: selected)
      }
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(presentation.tint)
          .frame(height: 2)
          .opacity(selected ? 1 : 0)
          .animation(controlAnimation, value: selected)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      String(
        format: String(localized: "%@, %d runs", table: "Automation"),
        presentation.title,
        presentation.count
      )
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func filterPresentation(
    _ candidate: AutomationRunCenterFilter
  ) -> (title: String, count: Int, systemImage: String, tint: Color) {
    switch candidate {
    case .all:
      return (
        String(localized: "All runs", table: "Automation"),
        model.projection.summary.totalCount,
        "tray.full",
        Brand.libraryBlue
      )
    case .needsAttention:
      return (
        String(localized: "Needs attention", table: "Automation"),
        model.projection.summary.needsAttentionCount,
        "exclamationmark.triangle.fill",
        Brand.sigAmber
      )
    case .running:
      return (
        String(localized: "Running", table: "Automation"),
        model.projection.summary.runningCount,
        "play.circle.fill",
        Brand.libraryBlue
      )
    case .succeeded:
      return (
        String(localized: "Succeeded", table: "Automation"),
        model.projection.summary.succeededCount,
        "checkmark.circle.fill",
        Brand.libraryGreen
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.projection.executions.isEmpty && model.loadState.isLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.projection.executions.isEmpty {
      ContentUnavailableView(
        String(localized: "No runs yet", table: "Automation"),
        systemImage: "clock.badge.questionmark",
        description: Text("Automatic and workflow runs will appear here.", tableName: "Automation")
      )
    } else if visibleExecutions.isEmpty {
      ContentUnavailableView(
        String(localized: "No matching runs", table: "Automation"),
        systemImage: "line.3.horizontal.decrease.circle",
        description: Text("Choose another run filter.", tableName: "Automation")
      )
    } else {
      HSplitView {
        executionList
          .frame(minWidth: 310, idealWidth: 350, maxWidth: 420)
        executionDetail
          .frame(minWidth: 490, maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var executionList: some View {
    List(visibleExecutions, selection: $selectedExecutionID) { execution in
      AutomationRunCenterExecutionRow(execution: execution)
        .tag(execution.executionID)
    }
    .listStyle(.sidebar)
    .onAppear(perform: repairSelection)
  }

  @ViewBuilder
  private var executionDetail: some View {
    if let selectedExecution {
      AutomationRunCenterExecutionDetail(
        execution: selectedExecution,
        primaryCommand: AutomationRunCenterCommandResolver.primaryCommand(for: selectedExecution),
        commandInFlight: commandInFlight,
        commandFeedback: commandFeedback,
        storage: storageUsage?.breakdown(for: selectedExecution.executionID),
        onPerformCommand: perform,
        onOpenWorkflow: {
          onOpenWorkflow(
            selectedExecution.workflowID,
            selectedExecution.failureFocus?.taskID
          )
          dismiss()
        }
      )
    } else {
      ContentUnavailableView(
        String(localized: "Select a run", table: "Automation"),
        systemImage: "cursorarrow.click.2"
      )
    }
  }

  private var visibleExecutions: [AutomationExecutionProjection] {
    model.projection.executions(matching: filter)
  }

  private var selectedExecution: AutomationExecutionProjection? {
    guard let selectedExecutionID else { return visibleExecutions.first }
    return visibleExecutions.first { $0.executionID == selectedExecutionID }
  }

  private var refreshLabel: String {
    if model.loadState.isLoading && model.projection.executions.isEmpty {
      return String(localized: "Loading runs", table: "Automation")
    }
    if case .failed = model.loadState {
      return String(localized: "Refresh failed", table: "Automation")
    }
    if let loadedAt = model.loadState.lastLoadedAt {
      return String(
        format: String(localized: "Updated %@", table: "Automation"),
        loadedAt.formatted(date: .omitted, time: .shortened)
      )
    }
    return String(localized: "Run history", table: "Automation")
  }

  private var controlAnimation: Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.12)
  }

  private func repairSelection() {
    guard !visibleExecutions.isEmpty else {
      selectedExecutionID = nil
      return
    }
    if selectedExecutionID == nil
      || !visibleExecutions.contains(where: { $0.executionID == selectedExecutionID })
    {
      selectedExecutionID = visibleExecutions[0].executionID
    }
  }

  private func perform(_ command: AutomationRunCenterCommand) {
    switch command {
    case .inspectEvidence(let runID, let failedEventIndex):
      guard let run = selectedExecution?.runs.first(where: { $0.id == runID }) else { return }
      evidenceSelection = AutomationRunCenterEvidenceSelection(
        run: run,
        taskName: selectedExecution?.failureFocus?.taskName,
        failedEventIndex: failedEventIndex
      )
    case .cancelExecution:
      pendingCancellation = command
    case .deleteExecution:
      pendingDeletion = command
    default:
      Task { await execute(command) }
    }
  }

  @MainActor
  private func execute(_ command: AutomationRunCenterCommand) async {
    guard !commandInFlight else { return }
    commandInFlight = true
    commandFeedback = nil
    let feedback = await onPerformCommand(command)
    commandInFlight = false
    commandFeedback = feedback
    if feedback.dismissesRunCenter {
      dismiss()
      return
    }
    await model.refresh(showsLoading: false, forceProjection: true)
    await refreshStorageUsage()
  }

  @MainActor
  private func refreshStorageUsage() async {
    do {
      storageUsage = try await onLoadStorageUsage()
      storageUsageError = nil
    } catch {
      storageUsage = nil
      storageUsageError = String(
        format: String(localized: "Run storage usage could not be calculated: %@", table: "Automation"),
        error.localizedDescription
      )
    }
  }

  private var deletionAlertTitle: String {
    guard case .deleteExecution(_, let scope) = pendingDeletion else { return "" }
    switch scope {
    case .screenshots: return String(localized: "Delete screenshots?", table: "Automation")
    case .evidence: return String(localized: "Delete evidence?", table: "Automation")
    case .history: return String(localized: "Delete this run history?", table: "Automation")
    }
  }

  private var deletionAlertMessage: String {
    guard case .deleteExecution(_, let scope) = pendingDeletion,
          let execution = selectedExecution else { return "" }
    guard let storage = storageUsage?.breakdown(for: execution.executionID) else {
      switch scope {
      case .screenshots:
        return String(localized: "This removes ending screenshots. Reports and run history stay available. Storage size is currently unavailable.", table: "Automation")
      case .evidence:
        return String(localized: "This removes reports, screenshots, and diagnostic evidence. A lightweight run record stays in history. Storage size is currently unavailable.", table: "Automation")
      case .history:
        return String(
          format: String(localized: "This permanently removes %d run record(s) and their associated evidence. Storage size is currently unavailable.", table: "Automation"),
          execution.runs.count
        )
      }
    }

    let bytes = scope == .screenshots ? storage.screenshotByteCount : storage.evidenceByteCount
    let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    switch scope {
    case .screenshots:
      return String(
        format: String(localized: "This removes about %@ of ending screenshots. Reports and run history stay available.", table: "Automation"),
        size
      )
    case .evidence:
      return String(
        format: String(localized: "This removes about %@ of reports, screenshots, and diagnostic evidence. A lightweight run record stays in history.", table: "Automation"),
        size
      )
    case .history:
      return String(
        format: String(localized: "This permanently removes %d run record(s) and about %@ of associated evidence.", table: "Automation"),
        execution.runs.count,
        size
      )
    }
  }
}

private struct AutomationRunCenterExecutionRow: View {
  let execution: AutomationExecutionProjection

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: execution.status.systemImage)
        .foregroundStyle(execution.status.tint)
        .frame(width: 18, height: 18)

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Text(execution.workflowName)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(1)
          Spacer(minLength: 4)
          if execution.hasEvidence {
            Image(systemName: "paperclip")
              .font(.caption)
              .foregroundStyle(.secondary)
              .help(String(localized: "Evidence available", table: "Automation"))
          }
        }

        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(execution.status.title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(execution.status.tint)
          if let failureTaskName = execution.failureFocus?.taskName {
            Text("·")
              .font(.caption)
              .foregroundStyle(.tertiary)
            Text(failureTaskName)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 4)
          Text(execution.latestActivityAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
            .lineLimit(1)
        }

        Text(executionMetadata)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 7)
    .accessibilityElement(children: .combine)
  }

  private var executionMetadata: String {
    String(
      format: String(localized: "%d steps · %d attempts", table: "Automation"),
      execution.taskRunCount,
      execution.attemptCount
    )
  }
}

private struct AutomationRunCenterExecutionDetail: View {
  let execution: AutomationExecutionProjection
  let primaryCommand: AutomationRunCenterCommand?
  let commandInFlight: Bool
  let commandFeedback: AutomationRunCenterCommandFeedback?
  let storage: AutomationRunStorageBreakdown?
  let onPerformCommand: (AutomationRunCenterCommand) -> Void
  let onOpenWorkflow: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        detailHeader

        if let failureFocus = execution.failureFocus {
          failureSection(failureFocus)
        } else if execution.status == .running {
          activeSection
        } else {
          completionSection
        }

        if primaryCommand != nil || execution.recommendedAction != .none {
          nextActionSection
          Divider()
        }

        Text("Run details", tableName: "Automation")
          .font(.subheadline)
          .fontWeight(.semibold)

        metrics
        Divider()

        Text("Steps and attempts", tableName: "Automation")
          .font(.subheadline)
          .fontWeight(.semibold)

        LazyVStack(spacing: 0) {
          ForEach(execution.runs) { run in
            AutomationRunCenterStepRow(run: run)
            if run.id != execution.runs.last?.id {
              Divider().opacity(0.5)
            }
          }
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var detailHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: execution.status.systemImage)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(execution.status.tint)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 3) {
        Text(execution.workflowName)
          .font(.title3)
          .fontWeight(.semibold)
          .lineLimit(2)
        Text(execution.status.title)
          .font(.subheadline)
          .foregroundStyle(execution.status.tint)
      }

      Spacer(minLength: 0)
      Menu {
        Button(
          String(localized: "Delete Screenshots", table: "Automation"),
          systemImage: "photo.badge.minus",
          role: .destructive
        ) {
          onPerformCommand(.deleteExecution(
            runIDs: Set(execution.runs.map(\.id)),
            scope: .screenshots
          ))
        }
        .disabled(execution.hasActiveRun || (storage?.screenshotByteCount == 0))
        Button(
          String(localized: "Delete Evidence", table: "Automation"),
          systemImage: "doc.badge.minus",
          role: .destructive
        ) {
          onPerformCommand(.deleteExecution(
            runIDs: Set(execution.runs.map(\.id)),
            scope: .evidence
          ))
        }
        .disabled(execution.hasActiveRun || (storage?.evidenceByteCount == 0))
        Divider()
        Button(
          String(localized: "Delete Run History", table: "Automation"),
          systemImage: "trash",
          role: .destructive
        ) {
          onPerformCommand(.deleteExecution(
            runIDs: Set(execution.runs.map(\.id)),
            scope: .history
          ))
        }
        .disabled(execution.hasActiveRun)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help(String(localized: "Manage run data", table: "Automation"))

      Button(
        String(localized: "Open Workflow", table: "Automation"),
        systemImage: "arrow.up.right.square"
      ) {
        onOpenWorkflow()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .help(String(localized: "Open Workflow", table: "Automation"))
    }
  }

  private var metrics: some View {
    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
      GridRow {
        metric(
          String(localized: "Started", table: "Common"),
          execution.createdAt.formatted(date: .abbreviated, time: .shortened))
        metric(
          String(localized: "Latest activity", table: "Automation"),
          execution.latestActivityAt.formatted(date: .abbreviated, time: .shortened))
      }
      GridRow {
        metric(String(localized: "Steps", table: "Automation"), "\(execution.taskRunCount)")
        metric(String(localized: "Attempts", table: "Automation"), "\(execution.attemptCount)")
      }
      GridRow {
        metric(String(localized: "Evidence", table: "Automation"), evidenceSummary)
        metric(
          String(localized: "Run ID", table: "Automation"),
          String(execution.executionID.uuidString.prefix(8)).uppercased())
      }
      GridRow {
        metric(
          String(localized: "Evidence size", table: "Automation"),
          storage.map { formattedBytes($0.evidenceByteCount) } ?? storageUnavailableLabel
        )
        metric(
          String(localized: "Reports", table: "Automation"),
          storage.map { formattedBytes($0.reportByteCount) } ?? storageUnavailableLabel
        )
      }
      GridRow {
        metric(
          String(localized: "Screenshots", table: "Automation"),
          storage.map { formattedBytes($0.screenshotByteCount) } ?? storageUnavailableLabel
        )
        metric(
          String(localized: "Diagnostics", table: "Automation"),
          storage.map { formattedBytes($0.conditionEvidenceByteCount + $0.otherEvidenceByteCount) }
            ?? storageUnavailableLabel
        )
      }
    }
  }

  private var storageUnavailableLabel: String {
    String(localized: "Storage size unavailable", table: "Automation")
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func failureSection(_ failure: AutomationRunFailureFocus) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(
        String(localized: "What happened", table: "Automation"),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.subheadline)
      .fontWeight(.semibold)
      .foregroundStyle(Brand.sigAmber)
      Text(failure.taskName)
        .font(.callout)
        .fontWeight(.semibold)
      Text(failureReason(failure))
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text(failureDetail(failure))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 6)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Brand.sigAmber)
        .frame(width: 3)
        .offset(x: -10)
    }
    .padding(.leading, 10)
  }

  private var activeSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(String(localized: "Running now", table: "Automation"), systemImage: "waveform.path.ecg")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(Brand.libraryBlue)
      Text(
        "SparkleRecorder is tracking this run live. If the app closes, the run will be marked as interrupted when it reopens.",
        tableName: "Automation"
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var completionSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(execution.status.title, systemImage: execution.status.systemImage)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(execution.status.tint)
      Text(completionSummary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var nextActionSection: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checklist")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Brand.libraryBlue)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text("Recommended next step", tableName: "Automation")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(Brand.libraryBlue)
        Text(execution.recommendedAction.title)
          .font(.callout)
          .fontWeight(.medium)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 7) {
        if let primaryCommand {
          Button(
            AutomationRunCenterCommandResolver.title(for: primaryCommand),
            systemImage: AutomationRunCenterCommandResolver.systemImage(for: primaryCommand)
          ) {
            onPerformCommand(primaryCommand)
          }
          .buttonStyle(.borderedProminent)
          .tint(primaryCommand.isCancellation ? .red : Brand.libraryBlue)
          .controlSize(.small)
          .disabled(commandInFlight)
        }
        if commandInFlight {
          ProgressView().controlSize(.small)
        }
        if let commandFeedback, !commandFeedback.message.isEmpty {
          Label(
            commandFeedback.message,
            systemImage: commandFeedback.isError ? "exclamationmark.triangle" : "checkmark.circle"
          )
          .font(.caption)
          .foregroundStyle(commandFeedback.isError ? Brand.sigAmber : Brand.libraryGreen)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(12)
    .background(Brand.libraryBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(Brand.libraryBlue.opacity(0.16), lineWidth: 0.5)
    )
  }

  private var completionSummary: String {
    switch execution.status {
    case .succeeded:
      return String(
        localized: "Every step in this run completed successfully.", table: "Automation")
    case .cancelled:
      return String(localized: "This run ended before all steps completed.", table: "Automation")
    case .running, .needsAttention:
      return ""
    }
  }

  private func failureReason(_ failure: AutomationRunFailureFocus) -> String {
    guard let run = execution.runs.first(where: { $0.id == failure.runID }) else {
      return String(localized: "Run failed", table: "Automation")
    }
    return AutomationTaskRunDisplay(run: run).detail
  }

  private func failureDetail(_ failure: AutomationRunFailureFocus) -> String {
    var parts = [String(format: String(localized: "Attempt %d", table: "Common"), failure.attempt)]
    if let eventIndex = failure.failedEventIndex {
      parts.append(
        String(format: String(localized: "Event #%d", table: "EditorUX"), eventIndex + 1))
    }
    if let run = execution.runs.first(where: { $0.id == failure.runID }) {
      parts.append(evidenceStatusLabel(for: run))
    }
    return parts.joined(separator: " · ")
  }

  private var evidenceSummary: String {
    let persistence = execution.runs.compactMap(\.evidencePersistence)
    if persistence.contains(where: { $0.health == .persisted }) {
      return String(localized: "Saved", table: "Common")
    }
    if persistence.contains(where: { $0.health == .partial }) {
      return String(localized: "Report only", table: "Automation")
    }
    if persistence.contains(where: { $0.health == .failed }) {
      return String(localized: "Save failed", table: "Automation")
    }
    if execution.runs.contains(where: { $0.evidenceID != nil }) {
      return String(localized: "Not verified", table: "Automation")
    }
    if execution.runs.contains(where: { $0.conditionEvidence?.artifacts.isEmpty == false }) {
      return String(localized: "Saved", table: "Common")
    }
    return String(localized: "None", table: "Automation")
  }

  private func evidenceStatusLabel(for run: AutomationTaskRun) -> String {
    switch run.evidencePersistence?.health {
    case .persisted:
      return String(localized: "Evidence saved", table: "Automation")
    case .partial:
      return String(localized: "Report saved; screenshot unavailable", table: "Automation")
    case .failed:
      return String(localized: "Evidence save failed", table: "Automation")
    case nil:
      return run.evidenceID == nil
        ? String(localized: "No evidence recorded", table: "Automation")
        : String(localized: "Evidence not verified", table: "Automation")
    }
  }
}

extension AutomationRunCenterCommand {
  fileprivate var isCancellation: Bool {
    if case .cancelExecution = self { return true }
    return false
  }

}

struct AutomationRunCenterEvidenceSelection: Identifiable {
  let run: AutomationTaskRun
  let taskName: String?
  let failedEventIndex: Int?

  var id: UUID { run.id }
}

struct AutomationRunCenterEvidenceSheet: View {
  @Environment(\.dismiss) private var dismiss
  let selection: AutomationRunCenterEvidenceSelection

  @State private var payload: AutomationTaskRunEvidencePayload?
  @State private var isLoading = true
  @State private var errorMessage = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "doc.text.magnifyingglass")
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(Brand.libraryBlue)
        VStack(alignment: .leading, spacing: 2) {
          Text("Run evidence", tableName: "Automation")
            .font(.headline)
          if let taskName = selection.taskName {
            Text(taskName).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button(String(localized: "Done", table: "Common")) { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(16)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let failedEventIndex = selection.failedEventIndex {
            Label(
              String(
                format: String(localized: "Failed at event #%d", table: "Automation"),
                failedEventIndex + 1
              ),
              systemImage: "scope"
            )
            .font(.subheadline)
            .foregroundStyle(Brand.sigAmber)
          }
          AutomationTaskRunEvidenceSectionView(
            run: selection.run,
            payload: payload,
            isLoading: isLoading,
            errorMessage: errorMessage,
            initialActionFeedback: nil,
            onLoad: { Task { await load() } }
          )
        }
        .padding(16)
      }
    }
    .frame(width: 620, height: 520)
    .task { await load() }
  }

  @MainActor
  private func load() async {
    isLoading = true
    errorMessage = ""
    do {
      payload = try await AutomationTaskRunEvidencePresenter.loadEvidence(for: selection.run)
      if payload == nil {
        errorMessage = String(
          localized: "The saved evidence files could not be found.", table: "Automation")
      }
    } catch {
      payload = nil
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }
}

struct AutomationRunCenterStepRow: View {
  let run: AutomationTaskRun

  var body: some View {
    let display = AutomationTaskRunDisplay(run: run)
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: display.systemImage)
        .foregroundStyle(display.tint)
        .frame(width: 18, height: 18)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(display.title)
            .font(.callout)
            .fontWeight(.semibold)
          Spacer(minLength: 8)
          Text(display.primaryDate, style: .time)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
        Text(display.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(display.metadataSummary)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 9)
    .accessibilityElement(children: .combine)
  }
}

extension AutomationExecutionDisplayStatus {
  var title: String {
    switch self {
    case .running:
      return String(localized: "Running", table: "Automation")
    case .needsAttention:
      return String(localized: "Needs attention", table: "Automation")
    case .cancelled:
      return String(localized: "Cancelled", table: "Common")
    case .succeeded:
      return String(localized: "Succeeded", table: "Automation")
    }
  }

  var systemImage: String {
    switch self {
    case .running: return "play.circle.fill"
    case .needsAttention: return "exclamationmark.triangle.fill"
    case .cancelled: return "xmark.circle.fill"
    case .succeeded: return "checkmark.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .running: return Brand.libraryBlue
    case .needsAttention: return Brand.sigAmber
    case .cancelled: return .secondary
    case .succeeded: return Brand.libraryGreen
    }
  }
}

extension AutomationRunRecommendedAction {
  var title: String {
    switch self {
    case .waitOrCancel:
      return String(
        localized: "Wait for completion, or cancel every active step in this run.",
        table: "Automation")
    case .grantPermission:
      return String(
        localized: "Grant the required macOS permission, then run again.", table: "Automation")
    case .restoreMacro:
      return String(localized: "Restore or replace the missing macro.", table: "Automation")
    case .inspectFailedEvent:
      return String(
        localized: "Inspect the failed macro event and its saved evidence.", table: "Automation")
    case .inspectEvidence:
      return String(
        localized: "Open the saved evidence before changing the automation.", table: "Automation")
    case .inspectTargetApplication:
      return String(
        localized: "Check the target application and target window.", table: "Automation")
    case .adjustTimeout:
      return String(localized: "Review the wait condition and timeout policy.", table: "Automation")
    case .adjustResourcePolicy:
      return String(
        localized: "Review the resource wait policy, then run again.", table: "Automation")
    case .retryExecution:
      return String(localized: "Review the failed task, then start a new run.", table: "Automation")
    case .reviewCancellation:
      return String(
        localized: "Confirm why the run was cancelled before restarting it.", table: "Automation")
    case .repairStorage:
      return String(
        localized: "Check available disk space and Application Support access, then run again.",
        table: "Automation")
    case .none:
      return String(localized: "No action is required.", table: "Automation")
    }
  }
}
