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
    @State private var usesForegroundInputResourceDraft = false
    @State private var usesScreenCaptureResourceDraft = false
    @State private var usesAccessibilityResourceDraft = false
    @State private var usesNetworkResourceDraft = false
    @State private var resourcePriorityDraft: AutomationResourcePriority = .normal
    @State private var hasMaxResourceWaitDraft = false
    @State private var maxResourceWaitDraft = 10.0
    @State private var selectedMacroID: UUID?
    @State private var delayDurationDraft = 1.0
    @State private var notificationTitleDraft = ""
    @State private var notificationBodyDraft = ""
    @State private var notificationSeverityDraft: AutomationNotificationSeverity = .info
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
    @State private var ocrRegionPreview: AutomationRegionCapturePreview?
    @State private var visualTypeDraft: AutomationVisualConditionType = .regionChanged
    @State private var visualRegionRefDraft = ""
    @State private var visualSearchRegionSpaceDraft: AutomationOCRSearchRegionSpace = .automatic
    @State private var hasVisualRegionDraft = false
    @State private var visualRegionXDraft = 0.0
    @State private var visualRegionYDraft = 0.0
    @State private var visualRegionWidthDraft = 0.0
    @State private var visualRegionHeightDraft = 0.0
    @State private var visualRegionPreview: AutomationRegionCapturePreview?
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
            Button(NSLocalizedString("Delete Task", comment: ""), role: .destructive, action: deleteTask)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
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

    private var isMacroTask: Bool {
        if case .macro = task.kind {
            return true
        }
        return false
    }

    private var isDelayTask: Bool {
        if case .delay = task.kind {
            return true
        }
        return false
    }

    private var isNotificationTask: Bool {
        if case .notification = task.kind {
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
        .help(NSLocalizedString("Inspector section", comment: ""))
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
            if isConditionTask {
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

            AutomationTaskJoinPolicyEditorView(
                selection: $joinPolicyDraft,
                incomingDependencyCount: taskProjection?.incomingDependencyCount ?? incomingDependencyCount
            )
            .padding(.vertical, 8)

            if let graphPosition {
                AutomationTaskPositionControlView(
                    position: graphPosition,
                    onMove: moveTask
                )
            }

            saveFooter
        }
    }

    private var runTab: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            scheduleSection

            saveFooter

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
        }
    }

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            executionPolicySection
            resourceSection
            saveFooter
            dangerSection
        }
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
        .padding(.vertical, 8)
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
        .padding(.vertical, 8)
    }

    private var conditionDefinitionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("CONDITION", comment: ""))

            Form {
                TextField(NSLocalizedString("Name", comment: ""), text: $conditionNameDraft)
                    .textFieldStyle(.roundedBorder)

                Picker(NSLocalizedString("Condition type", comment: ""), selection: conditionIntentBinding) {
                    ForEach(ConditionIntent.allCases) { intent in
                        Label(intent.title, systemImage: intent.systemImage).tag(intent)
                    }
                }
                .pickerStyle(.menu)

                conditionSourceFields
            }
        }
        .padding(.vertical, 8)
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("MACRO", comment: ""))

            Picker(NSLocalizedString("Macro source", comment: ""), selection: $selectedMacroID) {
                if selectedMacroID == nil || selectedMacro == nil {
                    Text(NSLocalizedString("Missing macro", comment: "")).tag(selectedMacroID)
                }
                ForEach(macros) { macro in
                    Text(macro.name).tag(Optional(macro.id))
                }
            }
            .pickerStyle(.menu)

            if let selectedMacro {
                detailRow(NSLocalizedString("Events", comment: ""), "\(selectedMacro.eventCount)")
            } else {
                Label(NSLocalizedString("Missing macro", comment: ""), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Brand.sigAmber)
            }
        }
        .padding(.vertical, 8)
    }

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("DELAY", comment: ""))

            numericField(
                NSLocalizedString("Duration (s)", comment: ""),
                value: $delayDurationDraft,
                width: 86
            )
        }
        .padding(.vertical, 8)
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("NOTIFICATION", comment: ""))

            Form {
                TextField(NSLocalizedString("Notification title", comment: ""), text: $notificationTitleDraft)
                    .textFieldStyle(.roundedBorder)

                TextField(NSLocalizedString("Message", comment: ""), text: $notificationBodyDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Picker(NSLocalizedString("Severity", comment: ""), selection: $notificationSeverityDraft) {
                    ForEach(notificationSeverityOptions, id: \.self) { severity in
                        Text(notificationSeverityTitle(severity)).tag(severity)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var conditionSourceFields: some View {
        switch conditionMode {
        case .manualApproval:
            LabeledContent(NSLocalizedString("Prompt", comment: "")) {
                Label(NSLocalizedString("Manual approval prompt", comment: ""), systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .externalSignal:
            TextField(NSLocalizedString("Signal Name", comment: ""), text: $signalNameDraft)
                .textFieldStyle(.roundedBorder)

            LabeledContent("") {
                AutomationExternalSignalSourceView(signalName: signalNameDraft)
            }
        case .ocrText:
            TextField(NSLocalizedString("Text to Find", comment: ""), text: $ocrTextDraft)
                .textFieldStyle(.roundedBorder)

            AutomationConditionObservationCard(
                systemImage: "text.viewfinder",
                title: AutomationConditionObservationPresentation.ocrDetectorTitle(),
                detail: AutomationConditionObservationPresentation.ocrDetectorDetail(),
                tint: Brand.libraryBlue
            )

            AutomationConditionObservationCard(
                systemImage: hasOCRRegionDraft ? "rectangle.dashed" : "display",
                title: AutomationConditionObservationPresentation.scopeTitle(hasRegion: hasOCRRegionDraft),
                detail: AutomationConditionObservationPresentation.ocrScopeDetail(hasRegion: hasOCRRegionDraft),
                tint: hasOCRRegionDraft ? Brand.libraryGreen : Brand.sigAmber
            )

            Picker(NSLocalizedString("Match Logic", comment: ""), selection: $ocrMatchModeDraft) {
                Text(NSLocalizedString("Contains", comment: "")).tag(TextMatchMode.contains)
                Text(NSLocalizedString("Exact", comment: "")).tag(TextMatchMode.exact)
            }
            .pickerStyle(.segmented)

            Picker(NSLocalizedString("Region Space", comment: ""), selection: $ocrSearchRegionSpaceDraft) {
                ForEach(AutomationOCRSearchRegionSpace.allCases, id: \.self) { space in
                    Text(space.title).tag(space)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("") {
                AutomationOCRRegionEditorView(
                    spaceTitle: ocrSearchRegionSpaceDraft.title,
                    statusTitle: ocrRegionStatusTitle,
                    statusDetail: ocrRegionStatusDetail,
                    statusImage: ocrRegionStatusImage,
                    statusTint: ocrRegionStatusTint,
                    hasRegion: hasOCRRegionDraft,
                    isNormalizedSpace: ocrSearchRegionSpaceDraft.isNormalizedSpace,
                    referenceSize: ocrRegionPreviewReferenceSize,
                    preview: ocrRegionPreview,
                    regionX: $ocrRegionXDraft,
                    regionY: $ocrRegionYDraft,
                    regionWidth: $ocrRegionWidthDraft,
                    regionHeight: $ocrRegionHeightDraft,
                    onPickText: pickOCRRegion,
                    onDraw: drawOCRRegion,
                    onClear: clearOCRRegion
                )
            }

            Toggle(NSLocalizedString("Require Visible Text", comment: ""), isOn: $ocrRequiresVisibleDraft)
                .toggleStyle(.switch)
        case .visual:
            AutomationVisualConditionEditorView(
                regionStatusTitle: visualRegionStatusTitle,
                regionStatusDetail: visualRegionStatusDetail,
                regionStatusImage: visualRegionStatusImage,
                regionStatusTint: visualRegionStatusTint,
                referenceSize: visualRegionPreviewReferenceSize,
                regionPreview: visualRegionPreview,
                supportsBoundsPicker: true,
                showsTypePicker: false,
                regionReferenceOptions: visualRegionReferenceOptions,
                imageReferenceOptions: visualImageReferenceOptions,
                baselineReferenceOptions: visualBaselineReferenceOptions,
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
                onClearRegion: clearVisualRegion,
                onPickPixel: applyPickedVisualPixel
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

    private var executionPolicySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("EXECUTION POLICY", comment: ""))

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

            if isConditionTask {
                Divider().opacity(0.5)
                conditionWaitPolicyEditor
            }
        }
        .padding(.vertical, 8)
    }

    private var conditionWaitPolicyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("Condition wait", comment: ""), systemImage: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(NSLocalizedString("Enable Timeout", comment: ""), isOn: $hasConditionTimeoutDraft)
                .toggleStyle(.switch)

            if hasConditionTimeoutDraft {
                numericField(
                    NSLocalizedString("Timeout (s)", comment: ""),
                    value: $conditionTimeoutDraft,
                    width: 78
                )
            }

            numericField(
                NSLocalizedString("Polling (s)", comment: ""),
                value: $conditionPollingDraft,
                width: 78
            )
        }
    }

    private var resourcePolicyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("Resource policy", comment: ""), systemImage: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(resourceOptions, id: \.resource) { option in
                    Toggle(isOn: resourceBinding(option.resource)) {
                        Label(option.title, systemImage: option.systemImage)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(requiredResources.contains(option.resource))
                }
            }

            if !requiredResources.isEmpty {
                Text(NSLocalizedString("Required resources are locked by this task type.", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(NSLocalizedString("Priority", comment: ""), selection: $resourcePriorityDraft) {
                ForEach(resourcePriorityOptions, id: \.self) { priority in
                    Text(resourcePriorityTitle(priority)).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .disabled(draftedResourceRequirement.resources.isEmpty)

            Toggle(NSLocalizedString("Max resource wait", comment: ""), isOn: $hasMaxResourceWaitDraft)
                .toggleStyle(.switch)
                .disabled(draftedResourceRequirement.resources.isEmpty)

            if hasMaxResourceWaitDraft, !draftedResourceRequirement.resources.isEmpty {
                numericField(
                    NSLocalizedString("Wait (s)", comment: ""),
                    value: $maxResourceWaitDraft,
                    width: 78
                )
            }
        }
    }

    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("RESOURCES", comment: ""))
            resourcePolicyEditor
        }
        .padding(.vertical, 8)
    }

    private var saveFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: saveTask) {
                Label(NSLocalizedString("Save Task", comment: ""), systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(trimmedName.isEmpty)
        }
        .padding(.top, 2)
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(title: NSLocalizedString("DANGER ZONE", comment: ""))
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
        .padding(.vertical, 8)
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
        let resources = selectedResources.union(requiredResources)
        return AutomationResourceRequirement(
            resources: resources,
            priority: resourcePriorityDraft,
            leaseTimeout: task.resourceRequirement.leaseTimeout,
            maxWaitDuration: resources.isEmpty || !hasMaxResourceWaitDraft
                ? nil
                : max(0, maxResourceWaitDraft)
        )
    }

    private var selectedResources: Set<AutomationResource> {
        var resources = Set<AutomationResource>()
        if usesForegroundInputResourceDraft {
            resources.insert(.foregroundInput)
        }
        if usesScreenCaptureResourceDraft {
            resources.insert(.screenCapture)
        }
        if usesAccessibilityResourceDraft {
            resources.insert(.accessibility)
        }
        if usesNetworkResourceDraft {
            resources.insert(.network)
        }
        return resources
    }

    private var requiredResources: Set<AutomationResource> {
        isConditionTask && conditionMode.requiresScreenCapture ? [.screenCapture] : []
    }

    private var resourceOptions: [(resource: AutomationResource, title: String, systemImage: String)] {
        [
            (.foregroundInput, resourceTitle(.foregroundInput), "keyboard"),
            (.screenCapture, resourceTitle(.screenCapture), "display"),
            (.accessibility, resourceTitle(.accessibility), "accessibility"),
            (.network, resourceTitle(.network), "network")
        ]
    }

    private var resourcePriorityOptions: [AutomationResourcePriority] {
        [.low, .normal, .high]
    }

    private func notificationSeverityTitle(_ severity: AutomationNotificationSeverity) -> String {
        switch severity {
        case .info:
            return NSLocalizedString("Info", comment: "")
        case .warning:
            return NSLocalizedString("Warning", comment: "")
        case .error:
            return NSLocalizedString("Error", comment: "")
        }
    }

    private func resourceTitle(_ resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return NSLocalizedString("Needs mouse and keyboard", comment: "")
        case .screenCapture:
            return NSLocalizedString("Screen capture", comment: "")
        case .accessibility:
            return NSLocalizedString("Accessibility", comment: "")
        case .network:
            return NSLocalizedString("Network", comment: "")
        }
    }

    private func resourcePriorityTitle(_ priority: AutomationResourcePriority) -> String {
        switch priority {
        case .low:
            return NSLocalizedString("Low", comment: "")
        case .normal:
            return NSLocalizedString("Normal", comment: "")
        case .high:
            return NSLocalizedString("High", comment: "")
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

    private func resourceBinding(_ resource: AutomationResource) -> Binding<Bool> {
        Binding(
            get: {
                switch resource {
                case .foregroundInput:
                    return usesForegroundInputResourceDraft
                case .screenCapture:
                    return usesScreenCaptureResourceDraft || requiredResources.contains(.screenCapture)
                case .accessibility:
                    return usesAccessibilityResourceDraft
                case .network:
                    return usesNetworkResourceDraft
                }
            },
            set: { newValue in
                switch resource {
                case .foregroundInput:
                    usesForegroundInputResourceDraft = newValue
                case .screenCapture:
                    usesScreenCaptureResourceDraft = newValue
                case .accessibility:
                    usesAccessibilityResourceDraft = newValue
                case .network:
                    usesNetworkResourceDraft = newValue
                }
            }
        )
    }

    private var conditionIntentBinding: Binding<ConditionIntent> {
        Binding(
            get: {
                switch conditionMode {
                case .manualApproval:
                    return .manualApproval
                case .externalSignal:
                    return .externalSignal
                case .ocrText:
                    return .ocrText
                case .visual:
                    return ConditionIntent(visualType: visualTypeDraft)
                case .previousOutcome:
                    return .previousOutcome
                }
            },
            set: { intent in
                switch intent {
                case .manualApproval:
                    conditionMode = .manualApproval
                case .externalSignal:
                    conditionMode = .externalSignal
                case .ocrText:
                    conditionMode = .ocrText
                case .regionChanged:
                    conditionMode = .visual
                    visualTypeDraft = .regionChanged
                case .imageAppeared:
                    conditionMode = .visual
                    visualTypeDraft = .imageAppeared
                case .imageDisappeared:
                    conditionMode = .visual
                    visualTypeDraft = .imageDisappeared
                case .pixelMatched:
                    conditionMode = .visual
                    visualTypeDraft = .pixelMatched
                case .previousOutcome:
                    conditionMode = .previousOutcome
                }
            }
        )
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

    private var visualRegionReferenceOptions: [AutomationVisualReferenceOption] {
        workflow.visualAssets?.regions.map { region in
            AutomationVisualReferenceOption(
                key: region.key,
                label: region.label,
                detail: visualRegionDetail(region)
            )
        } ?? []
    }

    private var visualImageReferenceOptions: [AutomationVisualReferenceOption] {
        workflow.visualAssets?.images.map { asset in
            AutomationVisualReferenceOption(
                key: asset.key,
                label: asset.label,
                detail: visualImageAssetDetail(asset)
            )
        } ?? []
    }

    private var visualBaselineReferenceOptions: [AutomationVisualReferenceOption] {
        workflow.visualAssets?.baselines.map { asset in
            AutomationVisualReferenceOption(
                key: asset.key,
                label: asset.label,
                detail: visualImageAssetDetail(asset)
            )
        } ?? []
    }

    private func visualRegionDetail(_ region: AutomationWorkflowDraftVisualRegion) -> String {
        String(
            format: NSLocalizedString("%@ bounds %@, %@, %@ x %@", comment: ""),
            region.space.titleForVisualCondition,
            formattedVisualAssetValue(Double(region.bounds.x)),
            formattedVisualAssetValue(Double(region.bounds.y)),
            formattedVisualAssetValue(Double(region.bounds.width)),
            formattedVisualAssetValue(Double(region.bounds.height))
        )
    }

    private func visualImageAssetDetail(_ asset: AutomationWorkflowDraftVisualImageAsset) -> String? {
        let path = asset.path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForTaskInspector
        let checksum = asset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForTaskInspector
            .map { sha in
                String(format: NSLocalizedString("SHA %@", comment: ""), String(sha.prefix(8)))
            }
        return [path, checksum]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmptyForTaskInspector
    }

    private func formattedVisualAssetValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
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
        resetTaskKindDraft()
        resetResourceRequirementDraft()
    }

    private func resetTaskKindDraft() {
        switch task.kind {
        case .macro(let macroID):
            selectedMacroID = macroID
        case .condition:
            resetConditionDraft()
        case .delay(let duration):
            delayDurationDraft = duration
        case .notification(let notification):
            notificationTitleDraft = notification.title
            notificationBodyDraft = notification.body
            notificationSeverityDraft = notification.severity
        }
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

    private func resetResourceRequirementDraft() {
        let requirement = task.resourceRequirement
        usesForegroundInputResourceDraft = requirement.resources.contains(.foregroundInput)
        usesScreenCaptureResourceDraft = requirement.resources.contains(.screenCapture)
        usesAccessibilityResourceDraft = requirement.resources.contains(.accessibility)
        usesNetworkResourceDraft = requirement.resources.contains(.network)
        resourcePriorityDraft = requirement.priority
        hasMaxResourceWaitDraft = requirement.maxWaitDuration != nil
        maxResourceWaitDraft = requirement.maxWaitDuration ?? 10
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
        updated.kind = draftedTaskKind(ocrConditionOverride: ocrConditionOverride)
        updated.resourceRequirement = draftedResourceRequirement

        onAction(.upsertTask(workflowID: workflow.id, task: updated, at: Date()))
    }

    private func draftedTaskKind(ocrConditionOverride: AutomationOCRCondition?) -> AutomationTaskKind {
        switch task.kind {
        case .macro(let macroID):
            return .macro(macroID: selectedMacroID ?? macroID)
        case .condition:
            return .condition(conditionSpec(ocrConditionOverride: ocrConditionOverride))
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
            onPicked: { condition, preview in
                applyPickedOCRCondition(condition, preview: preview)
            }
        )
    }

    private func applyPickedOCRCondition(_ condition: AutomationOCRCondition) {
        applyPickedOCRCondition(condition, preview: nil)
    }

    private func applyPickedOCRCondition(
        _ condition: AutomationOCRCondition,
        preview: AutomationRegionCapturePreview?
    ) {
        ocrTextDraft = condition.text
        ocrMatchModeDraft = condition.matchMode
        ocrSearchRegionSpaceDraft = condition.searchRegionSpace
        ocrRequiresVisibleDraft = condition.requireVisible
        resetOCRRegionDraft(from: condition.searchRegion)
        ocrRegionPreview = preview
        saveTask(ocrConditionOverride: condition)
    }

    private func clearOCRRegion() {
        resetOCRRegionDraft(from: nil)
        ocrRegionPreview = nil
        saveTask()
    }

    private func drawVisualRegion() {
        AutomationOCRRegionPicker.pickArea(
            currentCondition: AutomationOCRCondition(text: ""),
            searchRegionSpace: visualSearchRegionSpaceDraft,
            onPicked: { condition, preview in
                applyPickedVisualRegion(condition, preview: preview)
            }
        )
    }

    private func applyPickedVisualRegion(_ condition: AutomationOCRCondition) {
        applyPickedVisualRegion(condition, preview: nil)
    }

    private func applyPickedVisualRegion(
        _ condition: AutomationOCRCondition,
        preview: AutomationRegionCapturePreview?
    ) {
        visualSearchRegionSpaceDraft = condition.searchRegionSpace
        resetVisualRegionDraft(from: condition.searchRegion)
        visualRegionPreview = preview
        saveTask()
    }

    private func clearVisualRegion() {
        resetVisualRegionDraft(from: nil)
        visualRegionPreview = nil
        saveTask()
    }

    private func applyPickedVisualPixel(_ sample: AutomationRegionCapturePixelSample) {
        hasVisualPixelDraft = true
        visualPixelXDraft = sample.normalizedX
        visualPixelYDraft = sample.normalizedY
        if let colorHex = sample.colorHex {
            visualColorHexDraft = colorHex
        }
        saveTask()
    }

    private func clearRegionPreviews() {
        ocrRegionPreview = nil
        visualRegionPreview = nil
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

private enum TaskInspectorTab: String, CaseIterable, Identifiable {
    case block
    case flow
    case run
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .block:
            return NSLocalizedString("Block", comment: "")
        case .flow:
            return NSLocalizedString("Flow", comment: "")
        case .run:
            return NSLocalizedString("Run", comment: "")
        case .advanced:
            return NSLocalizedString("Advanced", comment: "")
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

private enum ConditionIntent: String, CaseIterable, Identifiable {
    case manualApproval
    case externalSignal
    case ocrText
    case imageAppeared
    case imageDisappeared
    case regionChanged
    case pixelMatched
    case previousOutcome

    var id: Self { self }

    init(visualType: AutomationVisualConditionType) {
        switch visualType {
        case .regionChanged:
            self = .regionChanged
        case .imageAppeared:
            self = .imageAppeared
        case .imageDisappeared:
            self = .imageDisappeared
        case .pixelMatched:
            self = .pixelMatched
        }
    }

    var title: String {
        switch self {
        case .manualApproval:
            return NSLocalizedString("Manual approval", comment: "")
        case .externalSignal:
            return NSLocalizedString("External signal", comment: "")
        case .ocrText:
            return NSLocalizedString("OCR text", comment: "")
        case .imageAppeared:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageAppeared)
        case .imageDisappeared:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageDisappeared)
        case .regionChanged:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.regionChanged)
        case .pixelMatched:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.pixelMatched)
        case .previousOutcome:
            return NSLocalizedString("Previous outcome", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .manualApproval:
            return "hand.raised.fill"
        case .externalSignal:
            return "antenna.radiowaves.left.and.right"
        case .ocrText:
            return "text.viewfinder"
        case .imageAppeared:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.imageAppeared)
        case .imageDisappeared:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.imageDisappeared)
        case .regionChanged:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.regionChanged)
        case .pixelMatched:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.pixelMatched)
        case .previousOutcome:
            return "arrow.uturn.backward"
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

private extension String {
    var nilIfEmptyForTaskInspector: String? {
        isEmpty ? nil : self
    }
}
