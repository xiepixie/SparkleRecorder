import SwiftUI
import SparkleRecorderCore

struct AutomationQuickScheduleSheet: View {
    private static let weekdaySymbols = DateFormatter().weekdaySymbols ?? []

    @Environment(\.dismiss) private var dismiss

    let macro: SavedMacro
    let existingSummary: AutomationMacroScheduleSummary?
    let onCreate: (AutomationWorkflow, UUID) async throws -> Void
    let onPreview: () async throws -> Void
    let onDisable: () async throws -> Void

    @State private var draft: AutomationQuickScheduleDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var previewFeedback: String?
    @State private var previewCountdown: Int?
    @State private var previewTask: Task<Void, Never>?
    @State private var isDeleting = false
    @State private var showDisableConfirmation = false

    init(
        macro: SavedMacro,
        existingSummary: AutomationMacroScheduleSummary? = nil,
        startAt: Date = Date().addingTimeInterval(3_600),
        onPreview: @escaping () async throws -> Void,
        onDisable: @escaping () async throws -> Void,
        onCreate: @escaping (AutomationWorkflow, UUID) async throws -> Void
    ) {
        self.macro = macro
        self.existingSummary = existingSummary
        self.onCreate = onCreate
        self.onPreview = onPreview
        self.onDisable = onDisable
        if let task = existingSummary?.task {
            _draft = State(initialValue: AutomationQuickScheduleDraft(
                workflowName: macro.name,
                task: task,
                fallbackStartAt: startAt
            ))
        } else {
            _draft = State(initialValue: AutomationQuickScheduleDraft(
                workflowName: macro.name,
                startAt: startAt,
                targetApplicationPolicy: macro.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded
            ))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
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

                if !macro.surfaces.isEmpty {
                    Picker(
                        String(localized: "Target application", table: "Automation"),
                        selection: $draft.targetApplicationPolicy
                    ) {
                        ForEach(AutomationTargetApplicationPolicy.allCases, id: \.self) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }

                    LabeledContent(String(localized: "Bound to", table: "Automation")) {
                        Text(boundApplicationNames)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Text(draft.targetApplicationPolicy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(
                        String(localized: "After running", table: "Automation"),
                        selection: $draft.targetApplicationCleanupPolicy
                    ) {
                        ForEach(AutomationTargetApplicationCleanupPolicy.allCases, id: \.self) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                }

                nextRuns

                if let validationMessage = draft.validationMessage() {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                LabeledContent(String(localized: "Playback", table: "Automation")) {
                    Text("Complete macro once", tableName: "Automation")
                        .foregroundStyle(.secondary)
                }

                Label(
                    String(localized: "Keep SparkleRecorder open for on-time runs. Missed runs do not stack.", table: "Automation"),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(
            width: 520,
            height: baseHeight + (macro.surfaces.isEmpty ? 0 : 152)
        )
        .onDisappear { previewTask?.cancel() }
        .confirmationDialog(
            String(localized: "Turn off automatic runs?", table: "Automation"),
            isPresented: $showDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Turn off automatic runs", table: "Automation"), role: .destructive) {
                disableSchedule()
            }
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
        } message: {
            Text("The macro stays in Library and can still be run manually.", tableName: "Automation")
        }
    }

    private var baseHeight: CGFloat {
        draft.mode == .custom || draft.mode == .weekly ? 404 : 366
    }

    private var boundApplicationNames: String {
        let names = Set(macro.surfaces.values.compactMap { surface -> String? in
            let appName = surface.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !appName.isEmpty {
                return appName
            }
            let bundleIdentifier = surface.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
                Label(existingStatusTitle, systemImage: existingSummary?.isEnabled == true
                    ? "checkmark.circle.fill"
                    : "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(existingSummary?.isEnabled == true ? Brand.libraryGreen : .secondary)
            }
        }
        .padding(16)
    }

    private var nextRuns: some View {
        let occurrences = draft.previewOccurrences()
        return HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Brand.sigAmber)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("Next run", tableName: "Automation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let next = occurrences.first?.scheduledAt {
                    Text(next, format: .dateTime.year().month(.abbreviated).day().weekday().hour().minute())
                        .font(.headline.monospacedDigit())
                } else {
                    Text("No upcoming run", tableName: "Automation")
                        .font(.headline)
                }
                if let existingSummary, existingSummary.duplicateCount > 0 {
                    Text("Multiple schedules were found. Saving will merge them into one.", tableName: "Automation")
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
                    Label(String(localized: "Turn off automatic runs", table: "Automation"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help(String(localized: "Turn off automatic runs", table: "Automation"))
                .accessibilityLabel(String(localized: "Turn off automatic runs", table: "Automation"))
                .disabled(isSaving || isDeleting || previewCountdown != nil)
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

            Button {
                previewCountdown == nil ? beginPreview() : cancelPreview()
            } label: {
                Label(previewButtonTitle, systemImage: previewCountdown == nil ? "play.fill" : "xmark")
            }
            .disabled(isSaving || isDeleting)

            Button(String(localized: "Cancel", table: "Common")) {
                cancelPreview()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

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
            .disabled(draft.validationMessage() != nil || isSaving || isDeleting || previewCountdown != nil)
        }
        .padding(16)
    }

    private var previewButtonTitle: String {
        guard let previewCountdown else {
            return String(localized: "Preview in 5 seconds", table: "Automation")
        }
        return previewCountdown > 0
            ? String(format: String(localized: "Cancel preview (%d)", table: "Automation"), previewCountdown)
            : String(localized: "Starting preview…", table: "Automation")
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

    private func beginPreview() {
        errorMessage = nil
        previewFeedback = nil
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            for remaining in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                previewCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            previewCountdown = 0
            do {
                try await onPreview()
                guard !Task.isCancelled else { return }
                previewFeedback = String(
                    localized: "Preview completed. The result was saved to Latest run.",
                    table: "Automation"
                )
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            previewCountdown = nil
            previewTask = nil
        }
    }

    private func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewCountdown = nil
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
        guard draft.validationMessage() == nil else {
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
