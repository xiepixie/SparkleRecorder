import SwiftUI
import SparkleRecorderCore

struct AutomationTaskInspectorView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let graphPosition: AutomationGraphPoint?
    let taskProjection: AutomationTaskNodeProjection?
    let macros: [SavedMacro]
    let runs: [AutomationTaskRun]
    let initialSelectedRunID: UUID?
    let onImportWorkflowFromDraftPreview: @MainActor (AutomationWorkflow, URL?) async throws -> Void
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAction: (AutomationAction) -> Void
    let onCommitAction: @MainActor (AutomationAction) async throws -> Void

    @State private var nameDraft = ""
    @State private var isEnabledDraft = true
    @State private var scheduleDraft = AutomationTaskScheduleDraft()
    @State private var executionDraft = AutomationTaskExecutionDraft()
    @State private var resourceDraft = AutomationTaskResourceDraft()
    @State private var selectedMacroID: UUID?
    @State private var delayDurationDraft = 1.0
    @State private var notificationTitleDraft = ""
    @State private var notificationBodyDraft = ""
    @State private var notificationSeverityDraft: AutomationNotificationSeverity = .info
    @State private var conditionDraft = AutomationTaskConditionDraft()
    @State private var ocrRegionPreview: AutomationRegionCapturePreview?
    @State private var visualRegionPreview: AutomationRegionCapturePreview?
    @State private var isConfirmingDeleteTask = false
    @State private var isCommitInFlight = false
    @State private var commitErrorMessage: String?
    @State private var selectedTab: TaskInspectorTab = .block

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabPicker

            switch selectedTab {
            case .block:
                blockTab
            case .flow:
                flowTab
            case .run:
                runTab
            case .advanced:
                advancedTab
            }
        }
        .alert(deleteTaskTitle, isPresented: $isConfirmingDeleteTask) {
            Button(String(localized: "Delete Task", table: "Automation"), role: .destructive) {
                Task { await deleteTask() }
            }
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
        } message: {
            Text(deleteTaskMessage)
        }
        .onAppear(perform: resetDraft)
        .onChange(of: task.id) {
            selectedTab = .block
            clearRegionPreviews()
            resetDraft()
        }
        .onChange(of: task) {
            resetDraft()
        }
    }

    private var trimmedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isConditionTask: Bool {
        if case .condition = task.kind {
            return true
        }
        return false
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(TaskInspectorTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(String(localized: "Inspector section", table: "Common"))
    }

    private var blockTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            identitySection

            switch task.kind {
            case .macro:
                macroSection
            case .condition:
                conditionDefinitionSection
            case .delay:
                delaySection
            case .notification:
                notificationSection
            }

            saveFooter
        }
    }

    private var flowTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            AutomationTaskFlowEditorView(
                workflow: workflow,
                task: task,
                dependencyEdges: dependencyEdges,
                graphPosition: graphPosition,
                taskProjection: taskProjection,
                executionDraft: $executionDraft,
                onSelectTask: onSelectTask,
                onSelectDependency: onSelectDependency,
                onAction: onAction,
                onMoveTask: moveTask
            )
            saveFooter
        }
    }

    private var runTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            AutomationTaskRunEditorView(
                workflow: workflow,
                task: task,
                taskProjection: taskProjection,
                dependencyEdges: dependencyEdges,
                macros: macros,
                runs: runs,
                initialSelectedRunID: initialSelectedRunID,
                selectedMacroHasSurfaces: selectedMacro?.surfaces.isEmpty == false,
                scheduleDraft: $scheduleDraft,
                executionDraft: $executionDraft,
                onRun: runTask,
                onCancel: cancelActiveRun,
                onImportWorkflowFromDraftPreview: onImportWorkflowFromDraftPreview
            )
            saveFooter
        }
    }

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            AutomationTaskAdvancedEditorView(
                task: task,
                executionDraft: $executionDraft,
                conditionDraft: $conditionDraft,
                resourceDraft: $resourceDraft
            )
            saveFooter
            dangerSection
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "Task name", table: "Automation"), text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await saveTask() } }

            Toggle(String(localized: "Enabled", table: "Common"), isOn: $isEnabledDraft)
                .toggleStyle(.switch)

            detailRow(String(localized: "Kind", table: "Common"), kindLabel)
            detailRow(String(localized: "Resources", table: "Common"), resourceLabel)
        }
        .padding(.vertical, 8)
    }

    private var conditionDefinitionSection: some View {
        AutomationTaskConditionEditorView(
            workflow: workflow,
            task: task,
            macros: macros,
            draft: $conditionDraft,
            ocrRegionPreview: $ocrRegionPreview,
            visualRegionPreview: $visualRegionPreview,
            onSave: saveTask(ocrConditionOverride:),
            onError: { commitErrorMessage = $0 }
        )
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "MACRO", table: "EditorUX"))

            Picker(String(localized: "Macro source", table: "EditorUX"), selection: $selectedMacroID) {
                if selectedMacroID == nil || selectedMacro == nil {
                    Text("Missing macro", tableName: "EditorUX").tag(selectedMacroID)
                }
                ForEach(macros) { macro in
                    Text(macro.name).tag(Optional(macro.id))
                }
            }
            .pickerStyle(.menu)

            if let selectedMacro {
                detailRow(String(localized: "Events", table: "EditorUX"), "\(selectedMacro.eventCount)")
            } else {
                Label(String(localized: "Missing macro", table: "EditorUX"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Brand.sigAmber)
            }
        }
        .padding(.vertical, 8)
    }

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "DELAY", table: "EditorUX"))

            numericField(
                String(localized: "Duration (s)", table: "Common"),
                value: $delayDurationDraft,
                width: 86
            )
        }
        .padding(.vertical, 8)
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "NOTIFICATION", table: "Common"))

            Form {
                TextField(String(localized: "Notification title", table: "Common"), text: $notificationTitleDraft)
                    .textFieldStyle(.roundedBorder)

                TextField(String(localized: "Message", table: "Common"), text: $notificationBodyDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Picker(String(localized: "Severity", table: "Common"), selection: $notificationSeverityDraft) {
                    ForEach(notificationSeverityOptions, id: \.self) { severity in
                        Text(notificationSeverityTitle(severity)).tag(severity)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 8)
    }

    private var saveFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await saveTask() }
            } label: {
                if isCommitInFlight {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Label(String(localized: "Save Task", table: "Automation"), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(trimmedName.isEmpty || isCommitInFlight)

            if let commitErrorMessage {
                Label(commitErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(title: String(localized: "DANGER ZONE", table: "Common"))
            Button(role: .destructive) {
                isConfirmingDeleteTask = true
            } label: {
                Label(String(localized: "Delete Task", table: "Automation"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Brand.red500)
        }
        .padding(.vertical, 8)
    }

    private var kindLabel: String {
        switch task.kind {
        case .macro:
            return String(localized: "Macro", table: "EditorUX")
        case .condition:
            return String(localized: "Condition", table: "Automation")
        case .delay:
            return String(localized: "Delay", table: "EditorUX")
        case .notification:
            return String(localized: "Notification", table: "Common")
        }
    }

    private var resourceLabel: String {
        let resources = draftedResourceRequirement.resources
        if resources.isEmpty {
            return String(localized: "None", table: "Common")
        }
        return resources
            .sorted { resourceSortIndex($0) < resourceSortIndex($1) }
            .map(resourceTitle)
            .joined(separator: ", ")
    }

    private var selectedMacro: SavedMacro? {
        guard let selectedMacroID else {
            return nil
        }
        return macros.first { $0.id == selectedMacroID }
    }

    private var notificationSeverityOptions: [AutomationNotificationSeverity] {
        [.info, .warning, .error]
    }

    private var draftedResourceRequirement: AutomationResourceRequirement {
        resourceDraft.requirement(
            preserving: task.resourceRequirement,
            requiredResources: requiredResources
        )
    }

    private var requiredResources: Set<AutomationResource> {
        isConditionTask ? conditionDraft.requiredResources : []
    }

    private func notificationSeverityTitle(_ severity: AutomationNotificationSeverity) -> String {
        switch severity {
        case .info:
            return String(localized: "Info", table: "Common")
        case .warning:
            return String(localized: "Warning", table: "Common")
        case .error:
            return String(localized: "Error", table: "Common")
        }
    }

    private func resourceTitle(_ resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return String(localized: "Needs mouse and keyboard", table: "Common")
        case .screenCapture:
            return String(localized: "Screen capture", table: "Recording")
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .network:
            return String(localized: "Network", table: "Common")
        }
    }

    private func resourceSortIndex(_ resource: AutomationResource) -> Int {
        switch resource {
        case .foregroundInput:
            return 0
        case .screenCapture:
            return 1
        case .accessibility:
            return 2
        case .network:
            return 3
        }
    }

    private func resetDraft() {
        commitErrorMessage = nil
        nameDraft = task.name
        isEnabledDraft = task.isEnabled
        scheduleDraft = AutomationTaskScheduleDraft(schedule: task.schedule)
        executionDraft = AutomationTaskExecutionDraft(task: task)
        resourceDraft = AutomationTaskResourceDraft(requirement: task.resourceRequirement)
        resetTaskKindDraft()
    }

    private func resetTaskKindDraft() {
        switch task.kind {
        case .macro(let macroID):
            selectedMacroID = macroID
        case .condition(let condition):
            conditionDraft = AutomationTaskConditionDraft(condition: condition)
        case .delay(let duration):
            delayDurationDraft = duration
        case .notification(let notification):
            notificationTitleDraft = notification.title
            notificationBodyDraft = notification.body
            notificationSeverityDraft = notification.severity
        }
    }

    @MainActor
    private func saveTask() async {
        await saveTask(ocrConditionOverride: nil)
    }

    @MainActor
    private func saveTask(ocrConditionOverride: AutomationOCRCondition?) async {
        guard !trimmedName.isEmpty, !isCommitInFlight else {
            return
        }

        var updated = task
        updated.name = trimmedName
        updated.isEnabled = isEnabledDraft
        executionDraft.apply(to: &updated)
        updated.schedule = scheduleDraft.schedule
        updated.kind = draftedTaskKind(ocrConditionOverride: ocrConditionOverride)
        updated.resourceRequirement = draftedResourceRequirement

        isCommitInFlight = true
        commitErrorMessage = nil
        defer { isCommitInFlight = false }
        do {
            try await onCommitAction(.upsertTask(workflowID: workflow.id, task: updated, at: Date()))
        } catch {
            commitErrorMessage = error.localizedDescription
        }
    }

    private func draftedTaskKind(ocrConditionOverride: AutomationOCRCondition?) -> AutomationTaskKind {
        switch task.kind {
        case .macro(let macroID):
            return .macro(macroID: selectedMacroID ?? macroID)
        case .condition:
            return .condition(
                conditionDraft.conditionSpec(
                    taskName: trimmedName,
                    preserving: existingOCRCondition,
                    ocrConditionOverride: ocrConditionOverride
                )
            )
        case .delay:
            return .delay(max(0, delayDurationDraft))
        case .notification:
            let title = notificationTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return .notification(AutomationNotificationSpec(
                title: title.isEmpty ? trimmedName : title,
                body: notificationBodyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                severity: notificationSeverityDraft
            ))
        }
    }

    private func runTask() {
        let intent = AutomationViewIntent.startTask(workflowID: workflow.id, taskID: task.id)
        onAction(intent.reducerAction(at: Date.now))
    }

    private func cancelActiveRun(_ activeRunID: UUID?) {
        guard let activeRunID else {
            return
        }
        onAction(.cancelRun(runID: activeRunID, at: Date.now))
    }

    private func moveTask(to position: AutomationGraphPoint) {
        let intent = AutomationViewIntent.moveTask(
            workflowID: workflow.id,
            taskID: task.id,
            position: position
        )
        onAction(intent.reducerAction(at: Date.now))
    }

    @MainActor
    private func deleteTask() async {
        guard !isCommitInFlight else { return }
        isCommitInFlight = true
        commitErrorMessage = nil
        defer { isCommitInFlight = false }
        do {
            try await onCommitAction(.deleteTask(workflowID: workflow.id, taskID: task.id, at: Date.now))
        } catch {
            commitErrorMessage = error.localizedDescription
        }
    }

    private var deleteTaskTitle: String {
        String(format: String(localized: "Delete %@?", table: "Common"), task.name)
    }

    private var deleteTaskMessage: String {
        String(
            format: String(localized: "This removes \"%@\" from the workflow and removes dependencies attached to it.", table: "Common"),
            task.name
        )
    }



    private func clearRegionPreviews() {
        ocrRegionPreview = nil
        visualRegionPreview = nil
    }

    private var existingOCRCondition: AutomationOCRCondition {
        guard case .condition(let condition) = task.kind,
              case .ocrText(let ocr) = condition.kind else {
            return AutomationOCRCondition(text: "")
        }
        return ocr
    }

    private func numericField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum TaskInspectorTab: String, CaseIterable, Identifiable {
    case block
    case flow
    case run
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .block:
            return String(localized: "Block", table: "Common")
        case .flow:
            return String(localized: "Flow", table: "Common")
        case .run:
            return String(localized: "Run", table: "Automation")
        case .advanced:
            return String(localized: "Advanced", table: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .block:
            return "square.dashed"
        case .flow:
            return "arrow.triangle.branch"
        case .run:
            return "play.circle"
        case .advanced:
            return "slider.horizontal.3"
        }
    }
}
