import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowDraftConditionEditorView: View {
    let document: AutomationWorkflowDraftDocument
    let onApply: (AutomationWorkflowDraftConditionEdit) -> Void

    @State private var selectedTaskKey = ""
    @State private var conditionKind: DraftConditionKind = .ocrText
    @State private var text = ""
    @State private var matchMode: TextMatchMode = .contains
    @State private var timeoutSeconds = 30.0
    @State private var pollingSeconds = 0.25
    @State private var requireVisible = true
    @State private var visualRegionRef = ""
    @State private var visualSearchRegionSpace: AutomationOCRSearchRegionSpace = .automatic
    @State private var hasVisualRegion = false
    @State private var visualRegionX = 0.0
    @State private var visualRegionY = 0.0
    @State private var visualRegionWidth = 0.0
    @State private var visualRegionHeight = 0.0
    @State private var visualImageRef = ""
    @State private var visualBaselineRef = ""
    @State private var hasVisualPixel = false
    @State private var visualPixelX = 0.0
    @State private var visualPixelY = 0.0
    @State private var visualColorHex = ""
    @State private var visualPixelSampleRadius = AutomationVisualCondition.defaultPixelSampleRadius
    @State private var hasVisualThreshold = false
    @State private var visualThreshold = 0.9
    @State private var visualRequiresVisible = true

    var body: some View {
        if !conditionTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("DRAFT CONDITION EDIT", comment: ""),
                    count: conditionTasks.count
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        taskPicker
                        conditionKindPicker
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        taskPicker
                        conditionKindPicker
                    }
                }

                conditionFields

                HStack(spacing: 8) {
                    Label(NSLocalizedString("Timeout", comment: ""), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Timeout", comment: ""), value: $timeoutSeconds, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)

                    Label(NSLocalizedString("Polling", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Polling", comment: ""), value: $pollingSeconds, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)

                    Spacer(minLength: 0)

                    Button(NSLocalizedString("Apply Draft Edit", comment: ""), systemImage: "checkmark", action: applyEdit)
                        .buttonStyle(.bordered)
                        .disabled(!canApplyEdit)
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)
            .onAppear(perform: selectInitialTaskIfNeeded)
            .onChange(of: document) {
                selectInitialTaskIfNeeded()
            }
        }
    }

    private var taskPicker: some View {
        Picker(NSLocalizedString("Task", comment: ""), selection: $selectedTaskKey) {
            ForEach(conditionTasks, id: \.key) { task in
                Text(task.name ?? task.key).tag(task.key)
            }
        }
        .frame(maxWidth: 220)
        .onChange(of: selectedTaskKey) {
            loadSelectedTask()
        }
    }

    private var conditionKindPicker: some View {
        Picker(NSLocalizedString("Condition", comment: ""), selection: $conditionKind) {
            ForEach(DraftConditionKind.allCases) { kind in
                Label(kind.title, systemImage: kind.systemImage).tag(kind)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 190)
    }

    @ViewBuilder
    private var conditionFields: some View {
        switch conditionKind {
        case .ocrText:
            ocrFields
        case .regionChanged, .imageAppeared, .imageDisappeared, .pixelMatched:
            visualFields
        }
    }

    private var ocrFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(NSLocalizedString("Match", comment: ""), selection: $matchMode) {
                    Text(NSLocalizedString("Contains", comment: "")).tag(TextMatchMode.contains)
                    Text(NSLocalizedString("Exact", comment: "")).tag(TextMatchMode.exact)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Toggle(NSLocalizedString("Require visible text", comment: ""), isOn: $requireVisible)
                    .font(.caption)
                    .toggleStyle(.checkbox)
            }

            TextField(NSLocalizedString("Text", comment: ""), text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var visualFields: some View {
        AutomationVisualConditionEditorView(
            regionStatusTitle: NSLocalizedString("Referenced bounds", comment: ""),
            regionStatusDetail: NSLocalizedString("Draft visual bounds are resolved later from regionRef or app-side picker data.", comment: ""),
            regionStatusImage: "viewfinder.rectangular",
            regionStatusTint: Brand.libraryBlue,
            referenceSize: nil,
            supportsBoundsPicker: false,
            showsTypePicker: false,
            regionReferenceOptions: visualRegionReferenceOptions,
            imageReferenceOptions: visualImageReferenceOptions,
            baselineReferenceOptions: visualBaselineReferenceOptions,
            type: visualTypeBinding,
            regionRef: $visualRegionRef,
            searchRegionSpace: $visualSearchRegionSpace,
            hasRegion: $hasVisualRegion,
            regionX: $visualRegionX,
            regionY: $visualRegionY,
            regionWidth: $visualRegionWidth,
            regionHeight: $visualRegionHeight,
            imageRef: $visualImageRef,
            baselineRef: $visualBaselineRef,
            hasPixel: $hasVisualPixel,
            pixelX: $visualPixelX,
            pixelY: $visualPixelY,
            colorHex: $visualColorHex,
            pixelSampleRadius: $visualPixelSampleRadius,
            hasThreshold: $hasVisualThreshold,
            threshold: $visualThreshold,
            requiresVisible: $visualRequiresVisible,
            onDrawRegion: {},
            onClearRegion: {}
        )
    }

    private var conditionTasks: [AutomationWorkflowDraftTask] {
        document.workflow.tasks.filter { $0.type == "condition" }
    }

    private var selectedTask: AutomationWorkflowDraftTask? {
        conditionTasks.first { $0.key == selectedTaskKey }
    }

    private var visualRegionReferenceOptions: [AutomationVisualReferenceOption] {
        document.visualAssets?.regions.map { region in
            AutomationVisualReferenceOption(
                key: region.key,
                label: region.label,
                detail: visualRegionDetail(region)
            )
        } ?? []
    }

    private var visualImageReferenceOptions: [AutomationVisualReferenceOption] {
        document.visualAssets?.images.map { asset in
            AutomationVisualReferenceOption(
                key: asset.key,
                label: asset.label,
                detail: visualImageAssetDetail(asset)
            )
        } ?? []
    }

    private var visualBaselineReferenceOptions: [AutomationVisualReferenceOption] {
        document.visualAssets?.baselines.map { asset in
            AutomationVisualReferenceOption(
                key: asset.key,
                label: asset.label,
                detail: visualImageAssetDetail(asset)
            )
        } ?? []
    }

    private var visualTypeBinding: Binding<AutomationVisualConditionType> {
        Binding(
            get: { conditionKind.visualType ?? .regionChanged },
            set: { conditionKind = DraftConditionKind(visualType: $0) }
        )
    }

    private var canApplyEdit: Bool {
        guard selectedTask != nil else {
            return false
        }

        switch conditionKind {
        case .ocrText:
            return !text.trimmedForDraftConditionEdit.isEmpty
        case .imageAppeared, .imageDisappeared:
            return !visualImageRef.trimmedForDraftConditionEdit.isEmpty
        case .pixelMatched:
            let hasColor = !visualColorHex.trimmedForDraftConditionEdit.isEmpty
            let hasTarget = hasVisualPixel || !visualRegionRef.trimmedForDraftConditionEdit.isEmpty
            return hasColor && hasTarget
        case .regionChanged:
            return true
        }
    }

    private func selectInitialTaskIfNeeded() {
        if selectedTask == nil {
            selectedTaskKey = conditionTasks.first?.key ?? ""
        }
        loadSelectedTask()
    }

    private func loadSelectedTask() {
        guard let selectedTask else {
            conditionKind = .ocrText
            text = ""
            matchMode = .contains
            timeoutSeconds = 30
            pollingSeconds = 0.25
            requireVisible = true
            resetVisualDraft(from: nil)
            return
        }

        let currentCondition = selectedTask.condition
        conditionKind = DraftConditionKind(conditionType: currentCondition?.type)
        text = currentCondition?.text ?? ""
        matchMode = currentCondition?.matchMode ?? .contains
        timeoutSeconds = selectedTask.timeoutSeconds ?? 30
        pollingSeconds = selectedTask.pollingSeconds ?? 0.25
        requireVisible = currentCondition?.requireVisible ?? true
        resetVisualDraft(from: currentCondition)
    }

    private func resetVisualDraft(from condition: AutomationWorkflowDraftCondition?) {
        visualRegionRef = condition?.regionRef ?? ""
        visualImageRef = condition?.imageRef ?? ""
        visualBaselineRef = condition?.baselineRef ?? ""
        if let pixel = condition?.pixel {
            hasVisualPixel = true
            visualPixelX = pixel.x
            visualPixelY = pixel.y
        } else {
            hasVisualPixel = false
            visualPixelX = 0
            visualPixelY = 0
        }
        visualColorHex = condition?.colorHex ?? ""
        visualPixelSampleRadius = condition?.pixelSampleRadius
            ?? AutomationVisualCondition.defaultPixelSampleRadius
        hasVisualThreshold = condition?.threshold != nil
        visualThreshold = condition?.threshold ?? 0.9
        visualRequiresVisible = condition?.requireVisible ?? true
    }

    private func visualRegionDetail(_ region: AutomationWorkflowDraftVisualRegion) -> String {
        String(
            format: NSLocalizedString("%@ bounds %@, %@, %@ x %@", comment: ""),
            region.space.titleForVisualCondition,
            formattedRegionValue(Double(region.bounds.x)),
            formattedRegionValue(Double(region.bounds.y)),
            formattedRegionValue(Double(region.bounds.width)),
            formattedRegionValue(Double(region.bounds.height))
        )
    }

    private func visualImageAssetDetail(_ asset: AutomationWorkflowDraftVisualImageAsset) -> String? {
        let path = asset.path?.trimmedForDraftConditionEdit.nilIfEmptyForDraftConditionEdit
        let checksum = asset.sha256?.trimmedForDraftConditionEdit.nilIfEmptyForDraftConditionEdit.map { sha in
            String(format: NSLocalizedString("SHA %@", comment: ""), String(sha.prefix(8)))
        }
        return [path, checksum].compactMap { $0 }.joined(separator: " · ")
            .nilIfEmptyForDraftConditionEdit
    }

    private func formattedRegionValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private func applyEdit() {
        guard let selectedTask else {
            return
        }

        onApply(AutomationWorkflowDraftConditionEdit(
            taskKey: selectedTask.key,
            condition: draftedCondition(currentCondition: selectedTask.condition),
            timeoutSeconds: max(0, timeoutSeconds),
            pollingSeconds: max(0.05, pollingSeconds)
        ))
    }

    private func draftedCondition(
        currentCondition: AutomationWorkflowDraftCondition?
    ) -> AutomationWorkflowDraftCondition {
        switch conditionKind {
        case .ocrText:
            return AutomationWorkflowDraftCondition(
                type: "ocrText",
                text: text.trimmedForDraftConditionEdit,
                matchMode: matchMode,
                regionRef: currentCondition?.regionRef,
                requireVisible: requireVisible,
                outcome: currentCondition?.outcome
            )
        case .regionChanged, .imageAppeared, .imageDisappeared, .pixelMatched:
            return AutomationWorkflowDraftCondition(
                type: conditionKind.rawValue,
                regionRef: visualRegionRef.trimmedForDraftConditionEdit.nilIfEmptyForDraftConditionEdit,
                requireVisible: visualRequiresVisible,
                outcome: currentCondition?.outcome,
                imageRef: conditionKind.usesImageReference
                    ? visualImageRef.trimmedForDraftConditionEdit.nilIfEmptyForDraftConditionEdit
                    : nil,
                baselineRef: conditionKind == .regionChanged
                    ? visualBaselineRef.trimmedForDraftConditionEdit.nilIfEmptyForDraftConditionEdit
                    : nil,
                pixel: conditionKind == .pixelMatched && hasVisualPixel
                    ? AutomationGraphPoint(x: visualPixelX, y: visualPixelY)
                    : nil,
                colorHex: conditionKind == .pixelMatched
                    ? visualColorHex.trimmedForDraftConditionEdit.nilIfEmptyForDraftConditionEdit
                    : nil,
                pixelSampleRadius: conditionKind == .pixelMatched
                    ? visualPixelSampleRadius
                    : nil,
                threshold: hasVisualThreshold ? min(max(visualThreshold, 0), 1) : nil
            )
        }
    }
}

private enum DraftConditionKind: String, CaseIterable, Identifiable {
    case ocrText
    case regionChanged
    case imageAppeared
    case imageDisappeared
    case pixelMatched

    var id: Self { self }

    init(conditionType: String?) {
        if let conditionType,
           let visualType = AutomationVisualConditionType(rawValue: conditionType.trimmedForDraftConditionEdit) {
            self = DraftConditionKind(visualType: visualType)
        } else {
            self = .ocrText
        }
    }

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
        case .ocrText:
            return NSLocalizedString("Screen text", comment: "")
        case .regionChanged:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.regionChanged)
        case .imageAppeared:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageAppeared)
        case .imageDisappeared:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageDisappeared)
        case .pixelMatched:
            return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.pixelMatched)
        }
    }

    var systemImage: String {
        switch self {
        case .ocrText:
            return "text.viewfinder"
        case .regionChanged:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.regionChanged)
        case .imageAppeared:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.imageAppeared)
        case .imageDisappeared:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.imageDisappeared)
        case .pixelMatched:
            return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.pixelMatched)
        }
    }

    var visualType: AutomationVisualConditionType? {
        switch self {
        case .ocrText:
            return nil
        case .regionChanged:
            return .regionChanged
        case .imageAppeared:
            return .imageAppeared
        case .imageDisappeared:
            return .imageDisappeared
        case .pixelMatched:
            return .pixelMatched
        }
    }

    var usesImageReference: Bool {
        switch self {
        case .imageAppeared, .imageDisappeared:
            return true
        case .ocrText, .regionChanged, .pixelMatched:
            return false
        }
    }
}

private extension String {
    var trimmedForDraftConditionEdit: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftConditionEdit: String? {
        isEmpty ? nil : self
    }
}
