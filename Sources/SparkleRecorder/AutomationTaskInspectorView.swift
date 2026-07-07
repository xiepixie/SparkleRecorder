import SwiftUI
import SparkleRecorderCore

struct AutomationTaskInspectorView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let graphPosition: AutomationGraphPoint?
    let taskProjection: AutomationTaskNodeProjection?
    let macros: [SavedMacro]
    let taskRuns: [AutomationTaskRun]
    let activeRunID: UUID?
    let initialSelectedRunID: UUID?
    let onImportWorkflowFromDraftPreview: (AutomationWorkflow, URL?) -> Void
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var nameDraft = ""
    @State private var isEnabledDraft = true
    @State private var scheduleMode: ScheduleMode = .manual
    @State private var onceDateDraft = Date()
    @State private var repeatStartDraft = Date()
    @State private var repeatEveryDraft = 1
    @State private var repeatUnitDraft: RepeatUnit = .hours
    @State private var hasTaskTimeoutDraft = false
    @State private var taskTimeoutDraft = 60.0
    @State private var retryAttemptsDraft = 1
    @State private var joinPolicyDraft: AutomationJoinPolicy = .all
    @State private var conditionNameDraft = ""
    @State private var conditionMode: ConditionMode = .manualApproval
    @State private var signalNameDraft = ""
    @State private var ocrTextDraft = ""
    @State private var ocrMatchModeDraft: TextMatchMode = .contains
    @State private var ocrSearchRegionSpaceDraft: AutomationOCRSearchRegionSpace = .automatic
    @State private var ocrRequiresVisibleDraft = true
    @State private var hasOCRRegionDraft = false
    @State private var ocrRegionXDraft = 0.0
    @State private var ocrRegionYDraft = 0.0
    @State private var ocrRegionWidthDraft = 0.0
    @State private var ocrRegionHeightDraft = 0.0
    @State private var visualTypeDraft: AutomationVisualConditionType = .regionChanged
    @State private var visualRegionRefDraft = ""
    @State private var visualSearchRegionSpaceDraft: AutomationOCRSearchRegionSpace = .automatic
    @State private var hasVisualRegionDraft = false
    @State private var visualRegionXDraft = 0.0
    @State private var visualRegionYDraft = 0.0
    @State private var visualRegionWidthDraft = 0.0
    @State private var visualRegionHeightDraft = 0.0
    @State private var visualImageRefDraft = ""
    @State private var visualBaselineRefDraft = ""
    @State private var hasVisualPixelDraft = false
    @State private var visualPixelXDraft = 0.0
    @State private var visualPixelYDraft = 0.0
    @State private var visualColorHexDraft = ""
    @State private var visualPixelSampleRadiusDraft = AutomationVisualCondition.defaultPixelSampleRadius
    @State private var hasVisualThresholdDraft = false
    @State private var visualThresholdDraft = 0.9
    @State private var visualRequiresVisibleDraft = true
    @State private var outcomePredicateDraft = AutomationOutcomePredicate.anyTerminal.rawValue
    @State private var hasConditionTimeoutDraft = false
    @State private var conditionTimeoutDraft = 30.0
    @State private var conditionPollingDraft = 0.25
    @State private var isConfirmingDeleteTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identitySection
            AutomationTaskRunControlView(
                taskName: task.name,
                isEnabled: task.isEnabled,
                resourceRequirement: task.resourceRequirement,
                activeRunID: activeRunID,
                onRun: runTask,
                onCancel: cancelActiveRun
            )
            if let taskProjection {
                AutomationTaskRuntimeDetailView(projection: taskProjection)
            }
            AutomationTaskRunHistoryView(
                runs: taskRuns,
                workflow: workflow,
                dependencyEdges: dependencyEdges,
                resourceRequirement: task.resourceRequirement,
                retryPolicy: task.retryPolicy,
                initialSelectedRunID: initialSelectedRunID,
                macros: macros,
                onImportWorkflowFromDraftPreview: onImportWorkflowFromDraftPreview
            )
            if let graphPosition {
                AutomationTaskPositionControlView(
                    position: graphPosition,
                    onMove: moveTask
                )
            }
            scheduleSection

            if case .macro(let macroID) = task.kind,
               let macro = macros.first(where: { $0.id == macroID }) {
                VStack(alignment: .leading, spacing: 8) {
                    AutomationSectionHeader(title: NSLocalizedString("MACRO", comment: ""))
                    detailRow(NSLocalizedString("Name", comment: ""), macro.name)
                    detailRow(NSLocalizedString("Events", comment: ""), "\(macro.eventCount)")
                }
                .padding(10)
                .sectionSurface(cornerRadius: 10)
            }

            if isConditionTask {
                conditionSection
                AutomationTaskBranchPanelView(
                    workflow: workflow,
                    task: task,
                    dependencyEdges: dependencyEdges,
                    onSelectTask: onSelectTask,
                    onSelectDependency: onSelectDependency,
                    onAction: onAction
                )
            }

            AutomationTaskDependencyAuthoringView(
                workflow: workflow,
                task: task,
                onSelectTask: onSelectTask,
                onSelectDependency: onSelectDependency,
                onAction: onAction
            )
            advancedSection
            actionSection
        }
        .alert(deleteTaskTitle, isPresented: $isConfirmingDeleteTask) {
            Button(NSLocalizedString("Delete Task", comment: ""), role: .destructive, action: deleteTask)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(deleteTaskMessage)
        }
        .onAppear(perform: resetDraft)
        .onChange(of: task.id) {
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

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(NSLocalizedString("Task name", comment: ""), text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveTask)

            Toggle(NSLocalizedString("Enabled", comment: ""), isOn: $isEnabledDraft)
                .toggleStyle(.switch)

            detailRow(NSLocalizedString("Kind", comment: ""), kindLabel)
            detailRow(NSLocalizedString("Resources", comment: ""), resourceLabel)
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("SCHEDULE", comment: ""))

            Picker(NSLocalizedString("Schedule", comment: ""), selection: $scheduleMode) {
                ForEach(ScheduleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch scheduleMode {
            case .manual:
                Label(NSLocalizedString("Manual start only", comment: ""), systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .once:
                DatePicker(
                    NSLocalizedString("Start", comment: ""),
                    selection: $onceDateDraft,
                    displayedComponents: [.date, .hourAndMinute]
                )
            case .repeating:
                DatePicker(
                    NSLocalizedString("Start", comment: ""),
                    selection: $repeatStartDraft,
                    displayedComponents: [.date, .hourAndMinute]
                )

                HStack(spacing: 8) {
                    LabeledContent(NSLocalizedString("Every", comment: "")) {
                        TextField(NSLocalizedString("Count", comment: ""), value: $repeatEveryDraft, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 58)
                    }

                    Picker(NSLocalizedString("Unit", comment: ""), selection: $repeatUnitDraft) {
                        ForEach(RepeatUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("CONDITION", comment: ""))

            TextField(NSLocalizedString("Condition name", comment: ""), text: $conditionNameDraft)
                .textFieldStyle(.roundedBorder)

            Picker(NSLocalizedString("Condition source", comment: ""), selection: $conditionMode) {
                ForEach(ConditionMode.editableModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            conditionSourceFields

            Divider().opacity(0.5)

            Toggle(NSLocalizedString("Timeout", comment: ""), isOn: $hasConditionTimeoutDraft)
                .toggleStyle(.switch)

            if hasConditionTimeoutDraft {
                numericField(
                    NSLocalizedString("Seconds", comment: ""),
                    value: $conditionTimeoutDraft,
                    width: 78
                )
            }

            numericField(
                NSLocalizedString("Polling", comment: ""),
                value: $conditionPollingDraft,
                width: 78
            )
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    @ViewBuilder
    private var conditionSourceFields: some View {
        switch conditionMode {
        case .manualApproval:
            Label(
                NSLocalizedString("Manual approval prompt", comment: ""),
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .externalSignal:
            TextField(NSLocalizedString("Signal name", comment: ""), text: $signalNameDraft)
                .textFieldStyle(.roundedBorder)
            AutomationExternalSignalSourceView(signalName: signalNameDraft)
        case .ocrText:
            TextField(NSLocalizedString("Text to find", comment: ""), text: $ocrTextDraft)
                .textFieldStyle(.roundedBorder)

            Picker(NSLocalizedString("Match", comment: ""), selection: $ocrMatchModeDraft) {
                Text(NSLocalizedString("Contains", comment: "")).tag(TextMatchMode.contains)
                Text(NSLocalizedString("Exact", comment: "")).tag(TextMatchMode.exact)
            }
            .pickerStyle(.segmented)

            Picker(NSLocalizedString("Region space", comment: ""), selection: $ocrSearchRegionSpaceDraft) {
                ForEach(AutomationOCRSearchRegionSpace.allCases, id: \.self) { space in
                    Text(space.title).tag(space)
                }
            }
            .pickerStyle(.menu)

            AutomationOCRRegionEditorView(
                spaceTitle: ocrSearchRegionSpaceDraft.title,
                statusTitle: ocrRegionStatusTitle,
                statusDetail: ocrRegionStatusDetail,
                statusImage: ocrRegionStatusImage,
                statusTint: ocrRegionStatusTint,
                hasRegion: hasOCRRegionDraft,
                isNormalizedSpace: ocrSearchRegionSpaceDraft.isNormalizedSpace,
                referenceSize: ocrRegionPreviewReferenceSize,
                regionX: $ocrRegionXDraft,
                regionY: $ocrRegionYDraft,
                regionWidth: $ocrRegionWidthDraft,
                regionHeight: $ocrRegionHeightDraft,
                onPickText: pickOCRRegion,
                onDraw: drawOCRRegion,
                onClear: clearOCRRegion
            )

            Toggle(NSLocalizedString("Require visible text", comment: ""), isOn: $ocrRequiresVisibleDraft)
                .toggleStyle(.switch)
        case .visual:
            AutomationVisualConditionEditorView(
                regionStatusTitle: visualRegionStatusTitle,
                regionStatusDetail: visualRegionStatusDetail,
                regionStatusImage: visualRegionStatusImage,
                regionStatusTint: visualRegionStatusTint,
                referenceSize: visualRegionPreviewReferenceSize,
                supportsBoundsPicker: true,
                showsTypePicker: true,
                regionReferenceOptions: [],
                imageReferenceOptions: [],
                baselineReferenceOptions: [],
                type: $visualTypeDraft,
                regionRef: $visualRegionRefDraft,
                searchRegionSpace: $visualSearchRegionSpaceDraft,
                hasRegion: $hasVisualRegionDraft,
                regionX: $visualRegionXDraft,
                regionY: $visualRegionYDraft,
                regionWidth: $visualRegionWidthDraft,
                regionHeight: $visualRegionHeightDraft,
                imageRef: $visualImageRefDraft,
                baselineRef: $visualBaselineRefDraft,
                hasPixel: $hasVisualPixelDraft,
                pixelX: $visualPixelXDraft,
                pixelY: $visualPixelYDraft,
                colorHex: $visualColorHexDraft,
                pixelSampleRadius: $visualPixelSampleRadiusDraft,
                hasThreshold: $hasVisualThresholdDraft,
                threshold: $visualThresholdDraft,
                requiresVisible: $visualRequiresVisibleDraft,
                onDrawRegion: drawVisualRegion,
                onClearRegion: clearVisualRegion
            )
        case .previousOutcome:
            Picker(NSLocalizedString("Outcome", comment: ""), selection: $outcomePredicateDraft) {
                ForEach(outcomeOptions, id: \.tag) { option in
                    Text(option.title).tag(option.tag)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("ADVANCED", comment: ""))

            Toggle(NSLocalizedString("Time limit", comment: ""), isOn: $hasTaskTimeoutDraft)
                .toggleStyle(.switch)

            if hasTaskTimeoutDraft {
                numericField(
                    NSLocalizedString("Seconds", comment: ""),
                    value: $taskTimeoutDraft,
                    width: 78
                )
            }

            LabeledContent(NSLocalizedString("Retry attempts", comment: "")) {
                TextField(NSLocalizedString("Count", comment: ""), value: $retryAttemptsDraft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
            }

            Divider().opacity(0.5)

            AutomationTaskJoinPolicyEditorView(
                selection: $joinPolicyDraft,
                incomingDependencyCount: taskProjection?.incomingDependencyCount ?? incomingDependencyCount
            )
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: saveTask) {
                Label(NSLocalizedString("Save Task", comment: ""), systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(trimmedName.isEmpty)

            Button(role: .destructive) {
                isConfirmingDeleteTask = true
            } label: {
                Label(NSLocalizedString("Delete Task", comment: ""), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Brand.red500)
        }
    }

    private var kindLabel: String {
        switch task.kind {
        case .macro:
            return NSLocalizedString("Macro", comment: "")
        case .condition:
            return NSLocalizedString("Condition", comment: "")
        case .delay:
            return NSLocalizedString("Delay", comment: "")
        case .notification:
            return NSLocalizedString("Notification", comment: "")
        }
    }

    private var resourceLabel: String {
        let resources = draftedResourceRequirement.resources
        if resources.isEmpty {
            return NSLocalizedString("None", comment: "")
        }
        return resources.map(\.rawValue).joined(separator: ", ")
    }

    private var draftedResourceRequirement: AutomationResourceRequirement {
        guard isConditionTask else {
            return task.resourceRequirement
        }
        return conditionMode.requiresScreenCapture ? .backgroundReadOnly : .none
    }

    private var incomingDependencyCount: Int {
        workflow.dependencies(to: task.id).count
    }

    private var outcomeOptions: [(tag: String, title: String)] {
        [
            (AutomationOutcomePredicate.anyTerminal.rawValue, NSLocalizedString("Any terminal", comment: "")),
            (AutomationOutcomePredicate.success.rawValue, NSLocalizedString("Success", comment: "")),
            (AutomationOutcomePredicate.failure.rawValue, NSLocalizedString("Failure", comment: "")),
            (AutomationOutcomePredicate.timeout.rawValue, NSLocalizedString("Timeout", comment: "")),
            (AutomationOutcomePredicate.cancelled.rawValue, NSLocalizedString("Cancelled", comment: "")),
            (AutomationOutcomePredicate.conditionMatched.rawValue, NSLocalizedString("Condition matched", comment: "")),
            (AutomationOutcomePredicate.conditionNotMatched.rawValue, NSLocalizedString("Condition not matched", comment: ""))
        ]
    }

    private var draftedOCRCondition: AutomationOCRCondition {
        existingOCRCondition.updatingTextMatchRegionAndSpace(
            text: ocrTextDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            matchMode: ocrMatchModeDraft,
            searchRegion: draftedOCRRegion,
            searchRegionSpace: ocrSearchRegionSpaceDraft,
            requireVisible: ocrRequiresVisibleDraft
        )
    }

    private var draftedOCRRegion: RectValue? {
        guard hasOCRRegionDraft else {
            return nil
        }

        return RectValue(
            x: CGFloat(max(0, ocrRegionXDraft)),
            y: CGFloat(max(0, ocrRegionYDraft)),
            width: CGFloat(max(0, ocrRegionWidthDraft)),
            height: CGFloat(max(0, ocrRegionHeightDraft))
        )
    }

    private var ocrRegionStatusTitle: String {
        switch ocrSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute:
            return NSLocalizedString("Display coordinates", comment: "")
        case .displayNormalized:
            return NSLocalizedString("Display-relative coordinates", comment: "")
        case .windowLocal:
            return NSLocalizedString("Window coordinates", comment: "")
        case .windowNormalized:
            return NSLocalizedString("Window-relative coordinates", comment: "")
        case .contentLocal:
            return NSLocalizedString("Content coordinates", comment: "")
        case .contentNormalized:
            return NSLocalizedString("Content-relative coordinates", comment: "")
        }
    }

    private var ocrRegionStatusDetail: String {
        switch ocrSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute:
            let displayCount = NSScreen.screens.count
            if displayCount > 1 {
                return NSLocalizedString("Draw Region records bounds on the display where you drag. Use this when the automation should stay tied to that monitor.", comment: "")
            }
            return NSLocalizedString("Draw Region records display-pixel bounds. Use this when the automation should inspect a fixed screen area.", comment: "")
        case .displayNormalized:
            return NSLocalizedString("Bounds are normalized to the selected display, which makes the region more tolerant of display size changes.", comment: "")
        case .windowLocal, .windowNormalized:
            if let targetSurfaceForOCRPicker {
                return String(
                    format: NSLocalizedString("Window context is available from %@. Draw Region can refresh it from the window under the pointer.", comment: ""),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return NSLocalizedString("No linked window context is available yet. Draw Region over the target window, or switch to display coordinates.", comment: "")
        case .contentLocal, .contentNormalized:
            if let targetSurfaceForOCRPicker,
               targetSurfaceForOCRPicker.recordedContentFrame != nil {
                return String(
                    format: NSLocalizedString("Content context is available from %@. Use this for OCR inside the app content area.", comment: ""),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return NSLocalizedString("Content bounds are not available yet. Draw Region over the app content, or switch to window/display coordinates.", comment: "")
        }
    }

    private var ocrRegionStatusImage: String {
        switch ocrSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute, .displayNormalized:
            return "display"
        case .windowLocal, .windowNormalized:
            return targetSurfaceForOCRPicker == nil ? "exclamationmark.triangle" : "macwindow"
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? "exclamationmark.triangle" : "rectangle.inset.filled"
        }
    }

    private var ocrRegionStatusTint: Color {
        switch ocrSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute, .displayNormalized:
            return Brand.libraryBlue
        case .windowLocal, .windowNormalized:
            return targetSurfaceForOCRPicker == nil ? Brand.sigAmber : Brand.libraryGreen
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? Brand.sigAmber : Brand.libraryGreen
        }
    }

    private var ocrRegionPreviewReferenceSize: CGSize? {
        switch ocrSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute:
            return displayReferenceSize
        case .displayNormalized, .windowNormalized, .contentNormalized:
            return CGSize(width: 1, height: 1)
        case .windowLocal:
            return targetSurfaceForOCRPicker.map {
                CGSize(width: $0.recordedFrame.width, height: $0.recordedFrame.height)
            }
        case .contentLocal:
            return targetSurfaceForOCRPicker?.recordedContentFrame.map {
                CGSize(width: $0.width, height: $0.height)
            }
        }
    }

    private var visualRegionStatusTitle: String {
        switch visualSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute, .displayNormalized:
            return NSLocalizedString("Display bounds", comment: "")
        case .windowLocal, .windowNormalized:
            return targetSurfaceForOCRPicker == nil
                ? NSLocalizedString("Window context missing", comment: "")
                : NSLocalizedString("Window bounds", comment: "")
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil
                ? NSLocalizedString("Content context missing", comment: "")
                : NSLocalizedString("Content bounds", comment: "")
        }
    }

    private var visualRegionStatusDetail: String {
        switch visualSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute:
            return NSLocalizedString("Draw Bounds records display-pixel bounds for the watched visual area.", comment: "")
        case .displayNormalized:
            return NSLocalizedString("Bounds are normalized to the selected display for more tolerant screen-size changes.", comment: "")
        case .windowLocal, .windowNormalized:
            if let targetSurfaceForOCRPicker {
                return String(
                    format: NSLocalizedString("Window context is available from %@. Draw over the target window to bind this visual wait.", comment: ""),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return NSLocalizedString("No linked window context is available yet. Draw over the target window, or switch to display coordinates.", comment: "")
        case .contentLocal, .contentNormalized:
            if let targetSurfaceForOCRPicker,
               targetSurfaceForOCRPicker.recordedContentFrame != nil {
                return String(
                    format: NSLocalizedString("Content context is available from %@. Use this for app-content visual waits.", comment: ""),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return NSLocalizedString("Content bounds are not available yet. Draw over app content, or switch to window/display coordinates.", comment: "")
        }
    }

    private var visualRegionStatusImage: String {
        switch visualSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute, .displayNormalized:
            return "display"
        case .windowLocal, .windowNormalized:
            return targetSurfaceForOCRPicker == nil ? "exclamationmark.triangle" : "macwindow"
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? "exclamationmark.triangle" : "rectangle.inset.filled"
        }
    }

    private var visualRegionStatusTint: Color {
        switch visualSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute, .displayNormalized:
            return Brand.libraryBlue
        case .windowLocal, .windowNormalized:
            return targetSurfaceForOCRPicker == nil ? Brand.sigAmber : Brand.libraryGreen
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? Brand.sigAmber : Brand.libraryGreen
        }
    }

    private var visualRegionPreviewReferenceSize: CGSize? {
        switch visualSearchRegionSpaceDraft {
        case .automatic, .displayAbsolute:
            return displayReferenceSize
        case .displayNormalized, .windowNormalized, .contentNormalized:
            return CGSize(width: 1, height: 1)
        case .windowLocal:
            return targetSurfaceForOCRPicker.map {
                CGSize(width: $0.recordedFrame.width, height: $0.recordedFrame.height)
            }
        case .contentLocal:
            return targetSurfaceForOCRPicker?.recordedContentFrame.map {
                CGSize(width: $0.width, height: $0.height)
            }
        }
    }

    private var displayReferenceSize: CGSize? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }

        return CGSize(
            width: screen.frame.width * screen.backingScaleFactor,
            height: screen.frame.height * screen.backingScaleFactor
        )
    }

    private func resetDraft() {
        nameDraft = task.name
        isEnabledDraft = task.isEnabled
        resetScheduleDraft()
        hasTaskTimeoutDraft = task.timeout != nil
        taskTimeoutDraft = task.timeout ?? 60
        retryAttemptsDraft = task.retryPolicy.maxAttempts
        joinPolicyDraft = task.joinPolicy
        resetConditionDraft()
    }

    private func resetScheduleDraft() {
        switch task.schedule {
        case .manual, nil:
            scheduleMode = .manual
        case .once(let date):
            scheduleMode = .once
            onceDateDraft = date
        case .repeating(let rule):
            scheduleMode = .repeating
            repeatStartDraft = rule.anchor
            switch rule.interval {
            case .minutes(let count):
                repeatEveryDraft = count
                repeatUnitDraft = .minutes
            case .hours(let count):
                repeatEveryDraft = count
                repeatUnitDraft = .hours
            case .days(let count):
                repeatEveryDraft = count
                repeatUnitDraft = .days
            case .weeks(let count):
                repeatEveryDraft = count
                repeatUnitDraft = .weeks
            }
        }
    }

    private func resetConditionDraft() {
        guard case .condition(let condition) = task.kind else {
            return
        }

        conditionNameDraft = condition.name
        hasConditionTimeoutDraft = condition.timeout != nil
        conditionTimeoutDraft = condition.timeout ?? 30
        conditionPollingDraft = condition.pollingInterval
        signalNameDraft = ""
        ocrTextDraft = ""
        ocrMatchModeDraft = .contains
        ocrSearchRegionSpaceDraft = .automatic
        ocrRequiresVisibleDraft = true
        resetOCRRegionDraft(from: nil)
        resetVisualConditionDraft(from: nil)
        outcomePredicateDraft = AutomationOutcomePredicate.anyTerminal.rawValue

        switch condition.kind {
        case .manualApproval:
            conditionMode = .manualApproval
        case .externalSignal(let signalName):
            conditionMode = .externalSignal
            signalNameDraft = signalName
        case .ocrText(let ocr):
            conditionMode = .ocrText
            ocrTextDraft = ocr.text
            ocrMatchModeDraft = ocr.matchMode
            ocrSearchRegionSpaceDraft = ocr.searchRegionSpace
            ocrRequiresVisibleDraft = ocr.requireVisible
            resetOCRRegionDraft(from: ocr.searchRegion)
        case .visual(let visual):
            conditionMode = .visual
            resetVisualConditionDraft(from: visual)
        case .previousOutcome(let predicate):
            conditionMode = .previousOutcome
            outcomePredicateDraft = predicate.rawValue
        }
    }

    private func resetOCRRegionDraft(from region: RectValue?) {
        guard let region else {
            hasOCRRegionDraft = false
            ocrRegionXDraft = 0
            ocrRegionYDraft = 0
            ocrRegionWidthDraft = 0
            ocrRegionHeightDraft = 0
            return
        }

        hasOCRRegionDraft = true
        ocrRegionXDraft = Double(region.x)
        ocrRegionYDraft = Double(region.y)
        ocrRegionWidthDraft = Double(region.width)
        ocrRegionHeightDraft = Double(region.height)
    }

    private func resetVisualConditionDraft(from condition: AutomationVisualCondition?) {
        visualTypeDraft = condition?.type ?? .regionChanged
        visualRegionRefDraft = condition?.regionRef ?? ""
        visualSearchRegionSpaceDraft = condition?.searchRegionSpace ?? .automatic
        resetVisualRegionDraft(from: condition?.searchRegion)
        visualImageRefDraft = condition?.imageRef ?? ""
        visualBaselineRefDraft = condition?.baselineRef ?? ""
        if let pixel = condition?.pixel {
            hasVisualPixelDraft = true
            visualPixelXDraft = pixel.x
            visualPixelYDraft = pixel.y
        } else {
            hasVisualPixelDraft = false
            visualPixelXDraft = 0
            visualPixelYDraft = 0
        }
        visualColorHexDraft = condition?.targetColorHex ?? ""
        visualPixelSampleRadiusDraft = condition?.pixelSampleRadius
            ?? AutomationVisualCondition.defaultPixelSampleRadius
        hasVisualThresholdDraft = condition?.threshold != nil
        visualThresholdDraft = condition?.threshold ?? 0.9
        visualRequiresVisibleDraft = condition?.requireVisible ?? true
    }

    private func resetVisualRegionDraft(from region: RectValue?) {
        guard let region else {
            hasVisualRegionDraft = false
            visualRegionXDraft = 0
            visualRegionYDraft = 0
            visualRegionWidthDraft = 0
            visualRegionHeightDraft = 0
            return
        }

        hasVisualRegionDraft = true
        visualRegionXDraft = Double(region.x)
        visualRegionYDraft = Double(region.y)
        visualRegionWidthDraft = Double(region.width)
        visualRegionHeightDraft = Double(region.height)
    }

    private func saveTask() {
        saveTask(ocrConditionOverride: nil)
    }

    private func saveTask(ocrConditionOverride: AutomationOCRCondition?) {
        guard !trimmedName.isEmpty else {
            return
        }

        var updated = task
        updated.name = trimmedName
        updated.isEnabled = isEnabledDraft
        updated.schedule = schedule()
        updated.timeout = hasTaskTimeoutDraft ? max(0, taskTimeoutDraft) : nil
        updated.retryPolicy = AutomationRetryPolicy(maxAttempts: max(1, retryAttemptsDraft))
        updated.joinPolicy = joinPolicyDraft

        if isConditionTask {
            updated.kind = .condition(conditionSpec(ocrConditionOverride: ocrConditionOverride))
            updated.resourceRequirement = draftedResourceRequirement
        }

        onAction(.upsertTask(workflowID: workflow.id, task: updated, at: Date()))
    }

    private func runTask() {
        let intent = AutomationViewIntent.startTask(workflowID: workflow.id, taskID: task.id)
        onAction(intent.reducerAction(at: Date.now))
    }

    private func cancelActiveRun() {
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

    private func deleteTask() {
        onAction(.deleteTask(workflowID: workflow.id, taskID: task.id, at: Date.now))
    }

    private var deleteTaskTitle: String {
        String(format: NSLocalizedString("Delete %@?", comment: ""), task.name)
    }

    private var deleteTaskMessage: String {
        String(
            format: NSLocalizedString("This removes \"%@\" from the workflow and removes dependencies attached to it.", comment: ""),
            task.name
        )
    }

    private func schedule() -> AutomationSchedule {
        switch scheduleMode {
        case .manual:
            return .manual
        case .once:
            return .once(onceDateDraft)
        case .repeating:
            return .repeating(
                AutomationRepeatRule(
                    anchor: repeatStartDraft,
                    interval: repeatInterval()
                )
            )
        }
    }

    private func repeatInterval() -> AutomationRepeatInterval {
        let count = max(1, repeatEveryDraft)
        switch repeatUnitDraft {
        case .minutes:
            return .minutes(count)
        case .hours:
            return .hours(count)
        case .days:
            return .days(count)
        case .weeks:
            return .weeks(count)
        }
    }

    private func conditionSpec(ocrConditionOverride: AutomationOCRCondition?) -> AutomationConditionSpec {
        let conditionName = conditionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return AutomationConditionSpec(
            name: conditionName.isEmpty ? trimmedName : conditionName,
            kind: conditionKind(ocrConditionOverride: ocrConditionOverride),
            timeout: hasConditionTimeoutDraft ? max(0, conditionTimeoutDraft) : nil,
            pollingInterval: max(0.05, conditionPollingDraft)
        )
    }

    private func conditionKind(ocrConditionOverride: AutomationOCRCondition?) -> AutomationConditionKind {
        switch conditionMode {
        case .manualApproval:
            return .manualApproval
        case .externalSignal:
            return .externalSignal(signalNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        case .ocrText:
            if let ocrConditionOverride {
                return .ocrText(ocrConditionOverride)
            }
            return .ocrText(existingOCRCondition.updatingTextMatchRegionAndSpace(
                text: ocrTextDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                matchMode: ocrMatchModeDraft,
                searchRegion: draftedOCRRegion,
                searchRegionSpace: ocrSearchRegionSpaceDraft,
                requireVisible: ocrRequiresVisibleDraft
            ))
        case .visual:
            return .visual(draftedVisualCondition)
        case .previousOutcome:
            let predicate = AutomationOutcomePredicate(rawValue: outcomePredicateDraft) ?? .anyTerminal
            return .previousOutcome(predicate)
        }
    }

    private func pickOCRRegion() {
        AutomationOCRRegionPicker.pick(
            currentCondition: draftedOCRCondition,
            targetSurface: targetSurfaceForOCRPicker,
            onPicked: applyPickedOCRCondition
        )
    }

    private func drawOCRRegion() {
        AutomationOCRRegionPicker.pickArea(
            currentCondition: draftedOCRCondition,
            searchRegionSpace: ocrSearchRegionSpaceDraft,
            onPicked: applyPickedOCRCondition
        )
    }

    private func applyPickedOCRCondition(_ condition: AutomationOCRCondition) {
        ocrTextDraft = condition.text
        ocrMatchModeDraft = condition.matchMode
        ocrSearchRegionSpaceDraft = condition.searchRegionSpace
        ocrRequiresVisibleDraft = condition.requireVisible
        resetOCRRegionDraft(from: condition.searchRegion)
        saveTask(ocrConditionOverride: condition)
    }

    private func clearOCRRegion() {
        resetOCRRegionDraft(from: nil)
    }

    private func drawVisualRegion() {
        AutomationOCRRegionPicker.pickArea(
            currentCondition: AutomationOCRCondition(text: ""),
            searchRegionSpace: visualSearchRegionSpaceDraft,
            onPicked: applyPickedVisualRegion
        )
    }

    private func applyPickedVisualRegion(_ condition: AutomationOCRCondition) {
        visualSearchRegionSpaceDraft = condition.searchRegionSpace
        resetVisualRegionDraft(from: condition.searchRegion)
    }

    private func clearVisualRegion() {
        resetVisualRegionDraft(from: nil)
    }

    private var targetSurfaceForOCRPicker: PlaybackSurface? {
        let upstreamTaskIDs = workflow.dependencies
            .filter { $0.toTaskID == task.id }
            .map(\.fromTaskID)
        let upstreamTasks = upstreamTaskIDs.compactMap { workflow.task(id: $0) }
        let candidates = upstreamTasks + workflow.tasks

        for candidate in candidates {
            guard case .macro(let macroID) = candidate.kind,
                  let macro = macros.first(where: { $0.id == macroID }),
                  let surface = macro.surfaces.sorted(by: { $0.key < $1.key }).first?.value else {
                continue
            }
            return surface
        }
        return nil
    }

    private var existingOCRCondition: AutomationOCRCondition {
        guard case .condition(let condition) = task.kind,
              case .ocrText(let ocr) = condition.kind else {
            return AutomationOCRCondition(text: "")
        }
        return ocr
    }

    private var draftedVisualCondition: AutomationVisualCondition {
        AutomationVisualCondition(
            type: visualTypeDraft,
            regionRef: visualRegionRefDraft,
            searchRegion: draftedVisualRegion,
            searchRegionSpace: visualSearchRegionSpaceDraft,
            imageRef: visualTypeDraft.usesImageReference ? visualImageRefDraft : nil,
            baselineRef: visualTypeDraft == .regionChanged ? visualBaselineRefDraft : nil,
            pixel: visualTypeDraft == .pixelMatched ? draftedVisualPixel : nil,
            targetColorHex: visualTypeDraft == .pixelMatched ? visualColorHexDraft : nil,
            pixelSampleRadius: visualTypeDraft == .pixelMatched
                ? visualPixelSampleRadiusDraft
                : nil,
            threshold: hasVisualThresholdDraft ? visualThresholdDraft : nil,
            requireVisible: visualRequiresVisibleDraft
        )
    }

    private var draftedVisualRegion: RectValue? {
        guard hasVisualRegionDraft, visualRegionWidthDraft > 0, visualRegionHeightDraft > 0 else {
            return nil
        }
        return RectValue(
            x: CGFloat(visualRegionXDraft),
            y: CGFloat(visualRegionYDraft),
            width: CGFloat(visualRegionWidthDraft),
            height: CGFloat(visualRegionHeightDraft)
        )
    }

    private var draftedVisualPixel: AutomationGraphPoint? {
        guard hasVisualPixelDraft else {
            return nil
        }
        return AutomationGraphPoint(x: visualPixelXDraft, y: visualPixelYDraft)
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

private extension RectValue {
    var summary: String {
        "\(Int(x)), \(Int(y)) · \(Int(width))×\(Int(height))"
    }
}

private extension PlaybackSurface {
    var windowContextLabel: String {
        if let windowTitle, !windowTitle.isEmpty {
            return windowTitle
        }
        if let appName, !appName.isEmpty {
            return appName
        }
        return NSLocalizedString("linked macro surface", comment: "")
    }
}

private enum ScheduleMode: String, CaseIterable, Identifiable {
    case manual
    case once
    case repeating

    var id: Self { self }

    var title: String {
        switch self {
        case .manual:
            return NSLocalizedString("Manual", comment: "")
        case .once:
            return NSLocalizedString("Once", comment: "")
        case .repeating:
            return NSLocalizedString("Repeating", comment: "")
        }
    }
}

private enum RepeatUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days
    case weeks

    var id: Self { self }

    var title: String {
        switch self {
        case .minutes:
            return NSLocalizedString("Minutes", comment: "")
        case .hours:
            return NSLocalizedString("Hours", comment: "")
        case .days:
            return NSLocalizedString("Days", comment: "")
        case .weeks:
            return NSLocalizedString("Weeks", comment: "")
        }
    }
}

private enum ConditionMode: String, CaseIterable, Identifiable {
    case manualApproval
    case externalSignal
    case ocrText
    case visual
    case previousOutcome

    var id: Self { self }

    static var editableModes: [ConditionMode] {
        [.manualApproval, .externalSignal, .ocrText, .visual, .previousOutcome]
    }

    var title: String {
        switch self {
        case .manualApproval:
            return NSLocalizedString("Manual approval", comment: "")
        case .externalSignal:
            return NSLocalizedString("External signal", comment: "")
        case .ocrText:
            return NSLocalizedString("Screen text", comment: "")
        case .visual:
            return NSLocalizedString("Visual condition", comment: "")
        case .previousOutcome:
            return NSLocalizedString("Previous outcome", comment: "")
        }
    }

    var requiresScreenCapture: Bool {
        switch self {
        case .ocrText, .visual:
            return true
        case .manualApproval, .externalSignal, .previousOutcome:
            return false
        }
    }
}

private extension AutomationOCRSearchRegionSpace {
    var title: String {
        switch self {
        case .automatic:
            return NSLocalizedString("Automatic", comment: "")
        case .displayAbsolute:
            return NSLocalizedString("Display absolute", comment: "")
        case .displayNormalized:
            return NSLocalizedString("Display normalized", comment: "")
        case .windowLocal:
            return NSLocalizedString("Window local", comment: "")
        case .windowNormalized:
            return NSLocalizedString("Window normalized", comment: "")
        case .contentLocal:
            return NSLocalizedString("Content local", comment: "")
        case .contentNormalized:
            return NSLocalizedString("Content normalized", comment: "")
        }
    }

    var isNormalizedSpace: Bool {
        switch self {
        case .displayNormalized, .windowNormalized, .contentNormalized:
            return true
        case .automatic, .displayAbsolute, .windowLocal, .contentLocal:
            return false
        }
    }
}
