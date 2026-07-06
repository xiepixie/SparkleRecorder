import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowDraftPreviewSheet: View {
    let existingWorkflowName: String?
    let onImportWorkflow: (AutomationWorkflow, URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var previewState: AutomationWorkflowDraftPreviewState
    @State private var isShowingImportConfirmation = false
    @State private var isShowingDraftEditError = false
    @State private var draftEditErrorMessage = ""
    @State private var selectedTaskRemovalKey = ""
    @State private var taskRemovalSnapshot: AutomationWorkflowDraftDocument?
    @State private var taskRemovalMessage = ""
    @State private var isShowingTaskRemovalConfirmation = false
    @State private var patchApplyMessage = ""
    @State private var patchChangedTaskKeys: [String] = []
    @State private var patchChangedDependencyKeys: [String] = []

    init(
        state: AutomationWorkflowDraftPreviewState,
        existingWorkflowName: String?,
        onImportWorkflow: @escaping (AutomationWorkflow, URL?) -> Void
    ) {
        _previewState = State(initialValue: state)
        self.existingWorkflowName = existingWorkflowName
        self.onImportWorkflow = onImportWorkflow
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summarySection
                    draftEditSection
                    taskSection
                    dependencySection
                    simulationSection
                    AutomationWorkflowDraftImportPreviewSection(preview: previewState.projection.importPreview)
                    validationSection
                    nextActionSection
                }
                .padding(16)
            }

            Divider().opacity(0.5)

            footer
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 640, idealHeight: 700)
        .alert(importConfirmationTitle, isPresented: $isShowingImportConfirmation) {
            if existingWorkflowName == nil {
                Button(NSLocalizedString("Import", comment: ""), action: confirmImport)
            } else {
                Button(NSLocalizedString("Replace", comment: ""), role: .destructive, action: confirmImport)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(importConfirmationMessage)
        }
        .alert(NSLocalizedString("Draft edit failed", comment: ""), isPresented: $isShowingDraftEditError) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(draftEditErrorMessage)
        }
        .alert(taskRemovalConfirmationTitle, isPresented: $isShowingTaskRemovalConfirmation) {
            Button(NSLocalizedString("Remove Task", comment: ""), role: .destructive, action: confirmTaskRemoval)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(taskRemovalConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: previewState.projection.isReadyForImport ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(previewState.projection.isReadyForImport ? Brand.libraryGreen : Brand.sigAmber)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(previewState.projection.workflowName)
                    .font(.headline)
                    .lineLimit(1)
                Text(previewState.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(previewState.projection.statusLabel)
                .font(.caption)
                .bold()
                .foregroundStyle(previewState.projection.isReadyForImport ? Brand.libraryGreen : Brand.sigAmber)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill((previewState.projection.isReadyForImport ? Brand.libraryGreen : Brand.sigAmber).opacity(0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder((previewState.projection.isReadyForImport ? Brand.libraryGreen : Brand.sigAmber).opacity(0.22), lineWidth: 0.6)
                        )
                )
        }
        .padding(16)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(title: NSLocalizedString("DRAFT SUMMARY", comment: ""))

            HStack(spacing: 8) {
                summaryPill(
                    title: NSLocalizedString("Tasks", comment: ""),
                    value: "\(previewState.projection.taskRows.count)",
                    systemImage: "square.stack.3d.up"
                )
                summaryPill(
                    title: NSLocalizedString("Dependencies", comment: ""),
                    value: "\(previewState.projection.dependencyRows.count)",
                    systemImage: "arrow.triangle.branch"
                )
                summaryPill(
                    title: NSLocalizedString("Macros", comment: ""),
                    value: "\(previewState.projection.macroCatalogCount)",
                    systemImage: "record.circle"
                )
                summaryPill(
                    title: NSLocalizedString("Issues", comment: ""),
                    value: "\(previewState.projection.issueRows.count)",
                    systemImage: "exclamationmark.circle"
                )
                summaryPill(
                    title: NSLocalizedString("Simulated", comment: ""),
                    value: "\(previewState.projection.simulationRows.count)",
                    systemImage: "play.circle"
                )
                summaryPill(
                    title: NSLocalizedString("Dry-run", comment: ""),
                    value: dryRunSummaryValue,
                    systemImage: "doc.badge.gearshape"
                )
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                .buttonStyle(.bordered)

            Spacer()

            Button(importButtonTitle, systemImage: importButtonImage, action: requestImport)
                .buttonStyle(.bordered)
                .disabled(!previewState.canImportCompiledWorkflow)
                .help(importButtonHelp)
                .accessibilityLabel(importButtonTitle)
        }
        .padding(16)
    }

    private var draftEditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationWorkflowDraftPatchSectionView(
                changedTaskKeys: patchChangedTaskKeys,
                changedDependencyKeys: patchChangedDependencyKeys,
                message: patchApplyMessage,
                onApplyPatch: openPatch
            )
            AutomationWorkflowDraftVisualAssetEditorView(
                document: previewState.document,
                sourceDirectory: previewState.sourceDirectory,
                onRegisterAsset: applyVisualAssetEdit
            )
            AutomationWorkflowDraftConditionEditorView(
                document: previewState.document,
                onApply: applyConditionEdit
            )
            AutomationWorkflowDraftScheduleEditorView(
                document: previewState.document,
                onApply: applyScheduleEdit
            )
            taskRemovalSection
            AutomationWorkflowDraftDependencyEditorView(
                document: previewState.document,
                onApply: applyDependencyEdit
            )
        }
    }

    @ViewBuilder
    private var taskRemovalSection: some View {
        if !previewState.document.workflow.tasks.isEmpty || taskRemovalSnapshot != nil {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("DRAFT TASK REMOVE", comment: ""),
                    count: previewState.document.workflow.tasks.count
                )

                HStack(spacing: 8) {
                    if previewState.document.workflow.tasks.isEmpty {
                        Label(NSLocalizedString("No tasks in draft", comment: ""), systemImage: "square.dashed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(NSLocalizedString("Task", comment: ""), selection: $selectedTaskRemovalKey) {
                            ForEach(previewState.document.workflow.tasks, id: \.key) { task in
                                Text(task.name ?? task.key).tag(task.key)
                            }
                        }
                        .frame(maxWidth: 260)
                    }

                    Label(taskRemovalImpactLabel, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if taskRemovalSnapshot != nil {
                        Button(NSLocalizedString("Undo Task Removal", comment: ""), systemImage: "arrow.uturn.backward", action: undoTaskRemoval)
                            .buttonStyle(.bordered)
                    }

                    Button(NSLocalizedString("Remove Task", comment: ""), systemImage: "trash", role: .destructive, action: requestTaskRemoval)
                        .buttonStyle(.bordered)
                        .disabled(selectedTaskForRemoval == nil)
                }

                if !taskRemovalMessage.isEmpty {
                    Text(taskRemovalMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)
            .onAppear(perform: selectInitialTaskForRemovalIfNeeded)
            .onChange(of: previewState.document) {
                selectInitialTaskForRemovalIfNeeded()
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: NSLocalizedString("DRAFT TASKS", comment: ""),
                count: previewState.projection.taskRows.count
            )

            if previewState.projection.taskRows.isEmpty {
                Label(NSLocalizedString("No tasks in draft", comment: ""), systemImage: "square.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewState.projection.taskRows) { row in
                    taskRow(row)
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var dependencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: NSLocalizedString("DRAFT DEPENDENCIES", comment: ""),
                count: previewState.projection.dependencyRows.count
            )

            if previewState.projection.dependencyRows.isEmpty {
                Label(NSLocalizedString("No dependencies in draft", comment: ""), systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewState.projection.dependencyRows) { row in
                    dependencyRow(row)
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: NSLocalizedString("VALIDATION", comment: ""),
                count: previewState.projection.issueRows.count
            )

            if previewState.projection.issueRows.isEmpty {
                Label(NSLocalizedString("No validation issues", comment: ""), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Brand.libraryGreen)
            } else {
                ForEach(previewState.projection.issueRows) { row in
                    issueRow(row)
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: NSLocalizedString("SIMULATION", comment: ""),
                count: previewState.projection.simulationRows.count
            )

            if previewState.projection.simulationRows.isEmpty {
                Label(NSLocalizedString("No simulated steps", comment: ""), systemImage: "play.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewState.projection.simulationRows) { row in
                    simulationRow(row)
                }

                if !previewState.projection.resourceRows.isEmpty {
                    Divider().opacity(0.45)
                    Text(NSLocalizedString("RESOURCE TIMELINE", comment: ""))
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.secondary)
                    ForEach(previewState.projection.resourceRows) { row in
                        resourceRow(row)
                    }
                }

                if !previewState.projection.branchRows.isEmpty {
                    Divider().opacity(0.45)
                    Text(NSLocalizedString("BRANCHES", comment: ""))
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.secondary)
                    ForEach(previewState.projection.branchRows) { row in
                        branchRow(row)
                    }
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    @ViewBuilder
    private var nextActionSection: some View {
        if !previewState.projection.nextActionRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("NEXT ACTIONS", comment: ""),
                    count: previewState.projection.nextActionRows.count
                )

                ForEach(previewState.projection.nextActionRows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.reason)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text(row.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowBackground())
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)
        }
    }

    private func taskRow(_ row: AutomationWorkflowDraftPreviewProjection.TaskRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: taskImage(for: row.typeLabel))
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.caption)
                        .bold()
                        .lineLimit(1)
                    Text(row.key)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(row.macroResolution.label)
                .font(.caption2)
                .bold()
                .foregroundStyle(macroTint(for: row.macroResolution))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(macroTint(for: row.macroResolution).opacity(0.09))
                )
        }
        .padding(8)
        .background(rowBackground())
        .accessibilityElement(children: .combine)
    }

    private func dependencyRow(_ row: AutomationWorkflowDraftPreviewProjection.DependencyRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(row.from)
                .font(.caption.monospaced())
                .lineLimit(1)
            Text(row.triggerLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            Text(row.to)
                .font(.caption.monospaced())
                .lineLimit(1)

            Spacer(minLength: 0)

            if let delayLabel = row.delayLabel {
                Text(delayLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(rowBackground())
        .accessibilityElement(children: .combine)
    }

    private func issueRow(_ row: AutomationWorkflowDraftPreviewProjection.IssueRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(row.severity.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.code)
                        .font(.caption)
                        .bold()
                    if let subject = row.subject {
                        Text(subject)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(row.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let path = row.path {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if row.candidateCount > 0 {
                Text(String(format: NSLocalizedString("%d candidates", comment: ""), row.candidateCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(rowBackground(tint: row.severity.tint))
        .accessibilityElement(children: .combine)
    }

    private func simulationRow(_ row: AutomationWorkflowDraftPreviewProjection.SimulationRow) -> some View {
        HStack(spacing: 8) {
            Text("\(row.order + 1)")
                .font(.caption.monospacedDigit())
                .bold()
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.taskName)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.taskKey)
                        .font(.caption2.monospaced())
                    Text(row.resourceLabel)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(row.outcomeLabel)
                .font(.caption2)
                .bold()
                .foregroundStyle(Brand.libraryGreen)

            HStack(spacing: 3) {
                Text(row.plannedStartAt, style: .time)
                Text("-")
                Text(row.plannedEndAt, style: .time)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(rowBackground())
        .accessibilityElement(children: .combine)
    }

    private func resourceRow(_ row: AutomationWorkflowDraftPreviewProjection.ResourceRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timeline.selection")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(row.resourceLabel)
                .font(.caption)
                .bold()
            Text(row.taskKey)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(String(format: NSLocalizedString("%.1fs", comment: ""), row.durationSeconds))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(rowBackground())
        .accessibilityElement(children: .combine)
    }

    private func branchRow(_ row: AutomationWorkflowDraftPreviewProjection.BranchRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.fired ? "checkmark.circle" : "circle")
                .foregroundStyle(row.fired ? Brand.libraryGreen : .secondary)
                .accessibilityHidden(true)
            Text(row.from)
                .font(.caption2.monospaced())
            Text(row.trigger)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(row.to)
                .font(.caption2.monospaced())
            Spacer(minLength: 0)
            Text(row.fired ? NSLocalizedString("Fired", comment: "") : NSLocalizedString("Skipped", comment: ""))
                .font(.caption2)
                .bold()
                .foregroundStyle(row.fired ? Brand.libraryGreen : .secondary)
        }
        .padding(8)
        .background(rowBackground(tint: row.fired ? Brand.libraryGreen : nil))
        .accessibilityElement(children: .combine)
    }

    private func summaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.caption.monospacedDigit())
                .bold()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground())
    }

    private var selectedTaskForRemoval: AutomationWorkflowDraftTask? {
        previewState.document.workflow.tasks.first { $0.key == selectedTaskRemovalKey }
    }

    private var selectedTaskRemovalDependencyCount: Int {
        dependencyCount(attachedTo: selectedTaskRemovalKey, in: previewState.document)
    }

    private var taskRemovalImpactLabel: String {
        guard selectedTaskForRemoval != nil else {
            return NSLocalizedString("No task selected", comment: "")
        }
        return String(
            format: NSLocalizedString("%d dependent edges will be removed", comment: ""),
            selectedTaskRemovalDependencyCount
        )
    }

    private var taskRemovalConfirmationTitle: String {
        guard let selectedTaskForRemoval else {
            return NSLocalizedString("Remove Task?", comment: "")
        }
        return String(
            format: NSLocalizedString("Remove %@?", comment: ""),
            taskRemovalDisplayName(for: selectedTaskForRemoval)
        )
    }

    private var taskRemovalConfirmationMessage: String {
        guard let selectedTaskForRemoval else {
            return NSLocalizedString("This edit only changes the draft preview.", comment: "")
        }
        return String(
            format: NSLocalizedString("This removes task \"%@\" and %d dependent edges from the draft preview. Saved workflows are unchanged until you import.", comment: ""),
            taskRemovalDisplayName(for: selectedTaskForRemoval),
            selectedTaskRemovalDependencyCount
        )
    }

    private var dryRunSummaryValue: String {
        guard let importPreview = previewState.projection.importPreview else {
            return NSLocalizedString("Not run", comment: "")
        }
        return importPreview.isImportable
            ? NSLocalizedString("Ready", comment: "")
            : NSLocalizedString("Blocked", comment: "")
    }

    private var importButtonTitle: String {
        existingWorkflowName == nil
            ? NSLocalizedString("Import Workflow", comment: "")
            : NSLocalizedString("Replace Workflow", comment: "")
    }

    private var importButtonImage: String {
        existingWorkflowName == nil ? "square.and.arrow.down" : "arrow.triangle.2.circlepath"
    }

    private var importButtonHelp: String {
        if previewState.canImportCompiledWorkflow {
            return existingWorkflowName == nil
                ? NSLocalizedString("Import the reviewed workflow draft", comment: "")
                : NSLocalizedString("Replace the existing workflow with this reviewed draft", comment: "")
        }
        return NSLocalizedString("Resolve import issues before importing", comment: "")
    }

    private var importConfirmationTitle: String {
        let workflowName = previewState.compiledWorkflow?.name ?? previewState.projection.workflowName
        if existingWorkflowName == nil {
            return String(format: NSLocalizedString("Import %@?", comment: ""), workflowName)
        }
        return String(format: NSLocalizedString("Replace %@?", comment: ""), workflowName)
    }

    private var importConfirmationMessage: String {
        let taskCount = previewState.compiledWorkflow?.tasks.count ?? previewState.projection.importPreview?.taskCount ?? 0
        let dependencyCount = previewState.compiledWorkflow?.dependencies.count ?? previewState.projection.importPreview?.dependencyCount ?? 0
        if let existingWorkflowName {
            return String(
                format: NSLocalizedString("This will replace the existing workflow \"%@\" with %d tasks and %d dependencies. It will not run until you start it.", comment: ""),
                existingWorkflowName,
                taskCount,
                dependencyCount
            )
        }
        return String(
            format: NSLocalizedString("This will add a workflow with %d tasks and %d dependencies. It will not run until you start it.", comment: ""),
            taskCount,
            dependencyCount
        )
    }

    private func requestImport() {
        guard previewState.canImportCompiledWorkflow else {
            return
        }
        isShowingImportConfirmation = true
    }

    private func confirmImport() {
        guard let workflow = previewState.compiledWorkflow, previewState.canImportCompiledWorkflow else {
            return
        }
        onImportWorkflow(workflow, previewState.sourceDirectory)
        dismiss()
    }

    private func selectInitialTaskForRemovalIfNeeded() {
        if selectedTaskForRemoval == nil {
            selectedTaskRemovalKey = previewState.document.workflow.tasks.first?.key ?? ""
        }
    }

    private func requestTaskRemoval() {
        guard selectedTaskForRemoval != nil else {
            return
        }
        isShowingTaskRemovalConfirmation = true
    }

    private func confirmTaskRemoval() {
        guard let selectedTaskForRemoval else {
            return
        }

        let previousDocument = previewState.document
        let removedDependencyCount = selectedTaskRemovalDependencyCount
        do {
            let result = try AutomationWorkflowDraftEditor.removeTask(
                key: selectedTaskForRemoval.key,
                from: previewState.document,
                context: AutomationWorkflowDraftValidationContext(macroCatalog: previewState.macroCatalog)
            )
            taskRemovalSnapshot = previousDocument
            taskRemovalMessage = String(
                format: NSLocalizedString("Removed %@ and %d dependent edges from this draft preview.", comment: ""),
                taskRemovalDisplayName(for: selectedTaskForRemoval),
                removedDependencyCount
            )
            rebuildPreview(with: result.document)
        } catch {
            draftEditErrorMessage = String(describing: error)
            isShowingDraftEditError = true
        }
    }

    private func undoTaskRemoval() {
        guard let taskRemovalSnapshot else {
            return
        }
        rebuildPreview(with: taskRemovalSnapshot)
        self.taskRemovalSnapshot = nil
        taskRemovalMessage = NSLocalizedString("Task removal undone.", comment: "")
    }

    private func applyConditionEdit(_ edit: AutomationWorkflowDraftConditionEdit) {
        do {
            let result = try AutomationWorkflowDraftEditor.setCondition(
                taskKey: edit.taskKey,
                condition: edit.condition,
                in: previewState.document,
                timeoutSeconds: edit.timeoutSeconds,
                pollingSeconds: edit.pollingSeconds,
                context: AutomationWorkflowDraftValidationContext(macroCatalog: previewState.macroCatalog)
            )
            rebuildPreview(with: result.document)
        } catch {
            draftEditErrorMessage = String(describing: error)
            isShowingDraftEditError = true
        }
    }

    private func applyScheduleEdit(_ edit: AutomationWorkflowDraftScheduleEdit) {
        do {
            let result = try AutomationWorkflowDraftEditor.setSchedule(
                taskKey: edit.taskKey,
                schedule: edit.schedule,
                in: previewState.document,
                context: AutomationWorkflowDraftValidationContext(macroCatalog: previewState.macroCatalog)
            )
            rebuildPreview(with: result.document)
        } catch {
            draftEditErrorMessage = String(describing: error)
            isShowingDraftEditError = true
        }
    }

    private func applyDependencyEdit(_ edit: AutomationWorkflowDraftDependencyEdit) {
        do {
            let result: AutomationWorkflowDraftEditResult
            if edit.removesDependency {
                result = try AutomationWorkflowDraftEditor.removeDependency(
                    matching: edit.selector,
                    from: previewState.document,
                    context: AutomationWorkflowDraftValidationContext(macroCatalog: previewState.macroCatalog)
                )
            } else {
                result = try AutomationWorkflowDraftEditor.setDependency(
                    matching: edit.selector,
                    in: previewState.document,
                    from: edit.from,
                    to: edit.to,
                    trigger: edit.trigger,
                    delaySeconds: edit.delaySeconds,
                    enabled: edit.enabled,
                    context: AutomationWorkflowDraftValidationContext(macroCatalog: previewState.macroCatalog)
                )
            }
            rebuildPreview(with: result.document)
        } catch {
            draftEditErrorMessage = String(describing: error)
            isShowingDraftEditError = true
        }
    }

    private func applyVisualAssetEdit(
        kind: String,
        asset: AutomationWorkflowDraftVisualImageAsset
    ) {
        var document = previewState.document
        var assets = document.visualAssets ?? AutomationWorkflowDraftVisualAssets()
        if kind == "baseline" {
            replaceOrAppendVisualAsset(asset, in: &assets.baselines)
        } else {
            replaceOrAppendVisualAsset(asset, in: &assets.images)
        }
        document.visualAssets = assets.isEmpty ? nil : assets
        rebuildPreview(with: document)
    }

    private func replaceOrAppendVisualAsset(
        _ asset: AutomationWorkflowDraftVisualImageAsset,
        in collection: inout [AutomationWorkflowDraftVisualImageAsset]
    ) {
        if let index = collection.firstIndex(where: { $0.key == asset.key }) {
            collection[index] = asset
        } else {
            collection.append(asset)
        }
    }

    private func openPatch() {
        AutomationWorkflowDraftPreviewPresenter.openPatch(
            document: previewState.document,
            macroCatalog: previewState.macroCatalog,
            onApply: applyPatchResult
        )
    }

    private func applyPatchResult(_ result: Result<AutomationWorkflowDraftEditResult, Error>) {
        switch result {
        case .success(let editResult):
            patchChangedTaskKeys = editResult.changedTaskKeys
            patchChangedDependencyKeys = editResult.changedDependencyKeys
            patchApplyMessage = String(
                format: NSLocalizedString("Applied patch: %d task changes, %d dependency changes.", comment: ""),
                editResult.changedTaskKeys.count,
                editResult.changedDependencyKeys.count
            )
            rebuildPreview(with: editResult.document)
        case .failure(let error):
            draftEditErrorMessage = String(describing: error)
            isShowingDraftEditError = true
        }
    }

    private func dependencyCount(attachedTo taskKey: String, in document: AutomationWorkflowDraftDocument) -> Int {
        guard !taskKey.isEmpty else {
            return 0
        }
        return document.workflow.dependencies.filter { dependency in
            dependency.from == taskKey || dependency.to == taskKey
        }.count
    }

    private func taskRemovalDisplayName(for task: AutomationWorkflowDraftTask) -> String {
        task.name ?? task.key
    }

    private func rebuildPreview(with document: AutomationWorkflowDraftDocument) {
        previewState = AutomationWorkflowDraftPreviewPresenter.previewState(
            document: document,
            sourceName: previewState.sourceName,
            sourceDirectory: previewState.sourceDirectory,
            loadedAt: Date(),
            macroCatalog: previewState.macroCatalog
        )
    }

    private func rowBackground(tint: Color? = nil) -> some View {
        let accent = tint ?? Color.primary
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(accent.opacity(tint == nil ? 0.035 : 0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(tint == nil ? 0.08 : 0.18), lineWidth: 0.6)
            )
    }

    private func taskImage(for typeLabel: String) -> String {
        switch typeLabel {
        case NSLocalizedString("Macro", comment: ""):
            return "play.rectangle"
        case NSLocalizedString("Condition", comment: ""):
            return "diamond"
        case NSLocalizedString("Delay", comment: ""):
            return "timer"
        case NSLocalizedString("Notification", comment: ""):
            return "bell"
        default:
            return "square"
        }
    }

    private func macroTint(for resolution: AutomationWorkflowDraftPreviewProjection.MacroResolution) -> Color {
        switch resolution {
        case .notRequired:
            return .secondary
        case .resolved:
            return Brand.libraryGreen
        case .missing:
            return Brand.red500
        case .ambiguous:
            return Brand.sigAmber
        }
    }
}

private extension AutomationWorkflowDraftPreviewProjection.Severity {
    var tint: Color {
        switch self {
        case .error:
            return Brand.red500
        case .warning:
            return Brand.sigAmber
        }
    }
}
