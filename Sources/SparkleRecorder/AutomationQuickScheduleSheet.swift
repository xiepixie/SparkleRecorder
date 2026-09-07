import SparkleRecorderCore
import SwiftUI

struct AutomationQuickScheduleSheet: View {
  private static let weekdaySymbols = DateFormatter().weekdaySymbols ?? []

  @Environment(\.dismiss) private var dismiss

  let macro: SavedMacro
  let existingSummary: AutomationMacroScheduleSummary?
  let onCreate: (AutomationWorkflow, UUID) async throws -> Void
  let onPreview: (AutomationWorkflow) async throws -> Void
  let onDisable: () async throws -> Void

  @State private var draft: AutomationQuickScheduleDraft
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var previewFeedback: String?
  @State private var isPreviewActive = false
  @State private var isDeleting = false
  @State private var showDisableConfirmation = false
  @State private var nextScheduledRun: Date?
  @State private var cachedValidationMessage: String?

  init(
    macro: SavedMacro,
    existingSummary: AutomationMacroScheduleSummary? = nil,
    startAt: Date = Date().addingTimeInterval(3_600),
    onPreview: @escaping (AutomationWorkflow) async throws -> Void,
    onDisable: @escaping () async throws -> Void,
    onCreate: @escaping (AutomationWorkflow, UUID) async throws -> Void
  ) {
    self.macro = macro
    self.existingSummary = existingSummary
    self.onCreate = onCreate
    self.onPreview = onPreview
    self.onDisable = onDisable
    let initialDraft: AutomationQuickScheduleDraft
    if let task = existingSummary?.task {
      initialDraft = AutomationQuickScheduleDraft(
        workflowName: macro.name,
        task: task,
        fallbackStartAt: startAt
      )
    } else {
      initialDraft = AutomationQuickScheduleDraft(
        workflowName: macro.name,
        startAt: startAt,
        targetApplicationPolicy: macro.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded
      )
    }
    _draft = State(initialValue: initialDraft)
    _nextScheduledRun = State(initialValue: initialDraft.previewOccurrences().first?.scheduledAt)
    _cachedValidationMessage = State(initialValue: initialDraft.validationMessage())
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      Form {
        Section(String(localized: "Schedule & Frequency", table: "Automation")) {
          Picker(String(localized: "Run", table: "Common"), selection: $draft.mode) {
            ForEach(AutomationQuickScheduleMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .pickerStyle(.segmented)

          if draft.mode == .daily || draft.mode == .weekly {
            if draft.mode == .weekly {
              Picker(String(localized: "Day", table: "Common"), selection: $draft.weeklyWeekday) {
                ForEach(1...7, id: \.self) { weekday in
                  Text(weekdayTitle(weekday)).tag(weekday)
                }
              }
            }
            DatePicker(
              String(localized: "At", table: "Common"),
              selection: $draft.startAt,
              displayedComponents: [.hourAndMinute]
            )
          } else {
            DatePicker(
              draft.mode == .once
                ? String(localized: "Run at", table: "Automation")
                : String(localized: "Start", table: "Common"),
              selection: $draft.startAt,
              displayedComponents: [.date, .hourAndMinute]
            )
          }

          if draft.mode == .custom {
            LabeledContent(String(localized: "Every", table: "Common")) {
              HStack(spacing: 8) {
                TextField(
                  String(localized: "Count", table: "Common"),
                  value: $draft.repeatEvery,
                  format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)

                Picker(String(localized: "Unit", table: "Common"), selection: $draft.repeatUnit) {
                  ForEach(AutomationTimelineRepeatUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                  }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 104)
              }
            }
          }
        }

        if !macro.surfaces.isEmpty {
          Section(String(localized: "Target Application", table: "Automation")) {
            LabeledContent(String(localized: "Target", table: "Common")) {
              Text(boundApplicationNames)
                .font(.system(.body, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Picker(
              String(localized: "Target application", table: "Automation"),
              selection: $draft.targetApplicationPolicy
            ) {
              ForEach(AutomationTargetApplicationPolicy.allCases, id: \.self) { policy in
                Text(policy.title).tag(policy)
              }
            }

            Text(draft.targetApplicationPolicy.detail)
              .font(.caption)
              .foregroundStyle(.secondary)

            if draft.targetApplicationPolicy != .doNotActivate {
              Picker(
                String(localized: "Wait after window appears", table: "Automation"),
                selection: $draft.targetApplicationReadyDelay
              ) {
                Text("No wait", tableName: "Automation").tag(TimeInterval(0))
                Text("2s").tag(TimeInterval(2))
                Text("5s").tag(TimeInterval(5))
                Text("10s").tag(TimeInterval(10))
                Text("20s").tag(TimeInterval(20))
              }

              Text(
                "Use this for startup loading. If login or navigation is required, create a sequence with preparation macros.",
                tableName: "Automation"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }

            Picker(
              String(localized: "After running", table: "Automation"),
              selection: $draft.targetApplicationCleanupPolicy
            ) {
              ForEach(AutomationTargetApplicationCleanupPolicy.allCases, id: \.self) { policy in
                Text(policy.title).tag(policy)
              }
            }

            if draft.targetApplicationCleanupPolicy == .quitIfLaunched {
              Picker(
                String(localized: "Wait before force quit", table: "Automation"),
                selection: $draft.targetApplicationQuitTimeout
              ) {
                Text("3s").tag(TimeInterval(3))
                Text("5s").tag(TimeInterval(5))
                Text("10s").tag(TimeInterval(10))
                Text("30s").tag(TimeInterval(30))
              }

              Toggle(
                String(localized: "Force quit if the app does not close", table: "Automation"),
                isOn: $draft.targetApplicationForceQuitOnTimeout
              )

              Text(
                draft.targetApplicationForceQuitOnTimeout
                  ? String(
                    localized: "Only the exact app process opened by this run can be force quit.",
                    table: "Automation")
                  : String(
                    localized: "The run finishes after the wait even if the app stays open.",
                    table: "Automation")
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }

        Section(String(localized: "Upcoming Run & Summary", table: "Automation")) {
          nextRuns

          if let validationMessage = cachedValidationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
          }

          LabeledContent(String(localized: "Playback", table: "Automation")) {
            Text("Complete macro once", tableName: "Automation")
              .foregroundStyle(.secondary)
          }

          Label(
            String(
              localized: "Keep SparkleRecorder open for on-time runs. Missed runs do not stack.",
              table: "Automation"),
            systemImage: "info.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)

      Divider()
      footer
    }
    .frame(minWidth: 520, idealWidth: 520, maxWidth: 540)
    .frame(minHeight: 520, idealHeight: 580, maxHeight: 720)
    .onChange(of: draft) { _, newDraft in
      nextScheduledRun = newDraft.previewOccurrences().first?.scheduledAt
      cachedValidationMessage = newDraft.validationMessage()
    }
    .confirmationDialog(
      String(localized: "Turn off automatic runs?", table: "Automation"),
      isPresented: $showDisableConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: "Turn off automatic runs", table: "Automation"), role: .destructive)
      {
        disableSchedule()
      }
      Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
    } message: {
      Text("The macro stays in Library and can still be run manually.", tableName: "Automation")
    }
  }

  private var boundApplicationNames: String {
    let names = Set(
      macro.surfaces.values.compactMap { surface -> String? in
        let appName = surface.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !appName.isEmpty {
          return appName
        }
        let bundleIdentifier =
          surface.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bundleIdentifier.isEmpty ? nil : bundleIdentifier
      })
    return names.sorted().joined(separator: ", ")
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "calendar.badge.clock")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(Brand.sigAmber)

      VStack(alignment: .leading, spacing: 2) {
        Text(headerTitle)
          .font(.headline)
        Text(macro.name)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      if existingSummary != nil {
        Label(
          existingStatusTitle,
          systemImage: existingSummary?.isEnabled == true
            ? "checkmark.circle.fill"
            : "pause.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(existingSummary?.isEnabled == true ? Brand.libraryGreen : .secondary)
      }
    }
    .padding(16)
  }

  private var nextRuns: some View {
    HStack(spacing: 12) {
      Image(systemName: "calendar.badge.checkmark")
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Brand.sigAmber)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 3) {
        Text("Next run", tableName: "Automation")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let next = nextScheduledRun {
          Text(next, format: .dateTime.year().month(.abbreviated).day().weekday().hour().minute())
            .font(.headline.monospacedDigit())
        } else {
          Text("No upcoming run", tableName: "Automation")
            .font(.headline)
        }
        if let existingSummary, existingSummary.duplicateCount > 0 {
          Text(
            "Multiple schedules were found. Saving will merge them into one.",
            tableName: "Automation"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  private var footer: some View {
    HStack(spacing: 10) {
      if existingSummary != nil {
        Button(role: .destructive) {
          showDisableConfirmation = true
        } label: {
          Label(
            String(localized: "Turn off automatic runs", table: "Automation"), systemImage: "trash"
          )
          .labelStyle(.iconOnly)
        }
        .help(String(localized: "Turn off automatic runs", table: "Automation"))
        .accessibilityLabel(String(localized: "Turn off automatic runs", table: "Automation"))
        .disabled(isSaving || isDeleting || isPreviewActive)
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if let previewFeedback {
        Label(previewFeedback, systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(Brand.libraryGreen)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Spacer(minLength: 0)
      }

      AutomationQuickSchedulePreviewButton(
        isDisabled: isSaving || isDeleting,
        onPreview: {
          try await onPreview(draft.makeWorkflow(for: macro))
        },
        onActivityChange: { isActive in
          isPreviewActive = isActive
          if isActive {
            errorMessage = nil
            previewFeedback = nil
          }
        },
        onResult: { result in
          switch result {
          case .success:
            previewFeedback = String(
              localized: "Preview completed. The result was saved to Latest run.",
              table: "Automation"
            )
          case .failure(let error):
            errorMessage = error.localizedDescription
          }
        }
      )

      Button(String(localized: "Cancel", table: "Common")) {
        dismiss()
      }
      .keyboardShortcut(.cancelAction)
      .disabled(isSaving || isDeleting || isPreviewActive)

      Button {
        createSchedule()
      } label: {
        if isSaving {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(createButtonTitle, systemImage: "calendar.badge.plus")
        }
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
      .disabled(cachedValidationMessage != nil || isSaving || isDeleting || isPreviewActive)
    }
    .padding(16)
  }

  private var headerTitle: String {
    existingSummary == nil
      ? String(localized: "Run automatically", table: "Automation")
      : String(localized: "Edit automatic run", table: "Automation")
  }

  private var existingStatusTitle: String {
    existingSummary?.isEnabled == true
      ? String(localized: "On", table: "Automation")
      : String(localized: "Paused", table: "Automation")
  }

  private func disableSchedule() {
    isDeleting = true
    errorMessage = nil
    Task { @MainActor in
      do {
        try await onDisable()
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
        isDeleting = false
      }
    }
  }

  private func weekdayTitle(_ weekday: Int) -> String {
    let symbols = Self.weekdaySymbols
    guard symbols.indices.contains(weekday - 1) else { return String(weekday) }
    return symbols[weekday - 1]
  }

  private var createButtonTitle: String {
    if existingSummary != nil {
      if existingSummary?.isEnabled == false {
        return String(localized: "Turn on and save", table: "Automation")
      }
      return String(localized: "Save changes", table: "Common")
    }
    return draft.mode == .daily
      ? String(localized: "Run every day", table: "Automation")
      : String(localized: "Create schedule", table: "Automation")
  }

  private func createSchedule() {
    guard cachedValidationMessage == nil else {
      return
    }

    let taskID = UUID()
    let workflow = draft.makeWorkflow(for: macro, taskID: taskID)
    isSaving = true
    errorMessage = nil
    Task { @MainActor in
      do {
        try await onCreate(workflow, taskID)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }
}

private struct AutomationQuickSchedulePreviewButton: View {
  let isDisabled: Bool
  let onPreview: () async throws -> Void
  let onActivityChange: (Bool) -> Void
  let onResult: (Result<Void, Error>) -> Void

  @State private var countdown: Int?
  @State private var previewTask: Task<Void, Never>?

  var body: some View {
    Button {
      countdown == nil ? beginPreview() : cancelPreview()
    } label: {
      Label(buttonTitle, systemImage: countdown == nil ? "play.fill" : "xmark")
    }
    .disabled(isDisabled)
    .onDisappear { cancelPreview() }
  }

  private var buttonTitle: String {
    guard let countdown else {
      return String(localized: "Preview in 5 seconds", table: "Automation")
    }
    return countdown > 0
      ? String(format: String(localized: "Cancel preview (%d)", table: "Automation"), countdown)
      : String(localized: "Starting preview…", table: "Automation")
  }

  private func beginPreview() {
    previewTask?.cancel()
    onActivityChange(true)
    previewTask = Task { @MainActor in
      for remaining in stride(from: 5, through: 1, by: -1) {
        guard !Task.isCancelled else { return }
        countdown = remaining
        try? await Task.sleep(for: .seconds(1))
      }
      guard !Task.isCancelled else { return }
      countdown = 0
      do {
        try await onPreview()
        guard !Task.isCancelled else { return }
        onResult(.success(()))
      } catch {
        guard !Task.isCancelled else { return }
        onResult(.failure(error))
      }
      countdown = nil
      previewTask = nil
      onActivityChange(false)
    }
  }

  private func cancelPreview() {
    let wasActive = previewTask != nil || countdown != nil
    previewTask?.cancel()
    previewTask = nil
    countdown = nil
    if wasActive { onActivityChange(false) }
  }
}
