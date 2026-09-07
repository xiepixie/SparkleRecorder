import AppKit
import SparkleRecorderCore
import SwiftUI

struct AutomationTaskConditionEditorView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let macros: [SavedMacro]
    @Binding var draft: AutomationTaskConditionDraft
    @Binding var ocrRegionPreview: AutomationRegionCapturePreview?
    @Binding var visualRegionPreview: AutomationRegionCapturePreview?
    let onSave: @MainActor (AutomationOCRCondition?) async -> Void
    let onError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "CONDITION", table: "Automation"))

            Form {
                TextField(String(localized: "Name", table: "Common"), text: $draft.name)
                    .textFieldStyle(.roundedBorder)

                Picker(
                    String(localized: "Condition type", table: "Automation"),
                    selection: conditionIntentBinding
                ) {
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

    @ViewBuilder
    private var conditionSourceFields: some View {
        switch draft.mode {
        case .manualApproval:
            LabeledContent(String(localized: "Prompt", table: "Common")) {
                Label(
                    String(localized: "Manual approval prompt", table: "Common"),
                    systemImage: "hand.raised.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .externalSignal:
            TextField(String(localized: "Signal Name", table: "Common"), text: $draft.signalName)
                .textFieldStyle(.roundedBorder)

            LabeledContent("") {
                AutomationExternalSignalSourceView(signalName: draft.signalName)
            }
        case .ocrText:
            ocrFields
        case .visual:
            visualFields
        case .previousOutcome:
            Picker(String(localized: "Outcome", table: "Common"), selection: $draft.outcomePredicate) {
                ForEach(outcomeOptions, id: \.tag) { option in
                    Text(option.title).tag(option.tag)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var ocrFields: some View {
        TextField(String(localized: "Text to Find", table: "Common"), text: $draft.ocrText)
            .textFieldStyle(.roundedBorder)

        AutomationConditionObservationCard(
            systemImage: "text.viewfinder",
            title: AutomationConditionObservationPresentation.ocrDetectorTitle(),
            detail: AutomationConditionObservationPresentation.ocrDetectorDetail(),
            tint: Brand.libraryBlue
        )

        AutomationConditionObservationCard(
            systemImage: draft.ocrRegion.isEnabled ? "rectangle.dashed" : "display",
            title: AutomationConditionObservationPresentation.scopeTitle(hasRegion: draft.ocrRegion.isEnabled),
            detail: AutomationConditionObservationPresentation.ocrScopeDetail(hasRegion: draft.ocrRegion.isEnabled),
            tint: draft.ocrRegion.isEnabled ? Brand.libraryGreen : Brand.sigAmber
        )

        Picker(String(localized: "Match Logic", table: "Common"), selection: $draft.ocrMatchMode) {
            Text("Contains", tableName: "Common").tag(TextMatchMode.contains)
            Text("Exact", tableName: "Common").tag(TextMatchMode.exact)
        }
        .pickerStyle(.segmented)

        Picker(
            String(localized: "Region Space", table: "Common"),
            selection: $draft.ocrSearchRegionSpace
        ) {
            ForEach(AutomationOCRSearchRegionSpace.allCases, id: \.self) { space in
                Text(space.taskInspectorTitle).tag(space)
            }
        }
        .pickerStyle(.menu)

        LabeledContent("") {
            AutomationOCRRegionEditorView(
                spaceTitle: draft.ocrSearchRegionSpace.taskInspectorTitle,
                statusTitle: ocrRegionStatusTitle,
                statusDetail: ocrRegionStatusDetail,
                statusImage: ocrRegionStatusImage,
                statusTint: ocrRegionStatusTint,
                hasRegion: draft.ocrRegion.isEnabled,
                isNormalizedSpace: draft.ocrSearchRegionSpace.isTaskInspectorNormalizedSpace,
                referenceSize: ocrRegionPreviewReferenceSize,
                preview: ocrRegionPreview,
                regionX: $draft.ocrRegion.x,
                regionY: $draft.ocrRegion.y,
                regionWidth: $draft.ocrRegion.width,
                regionHeight: $draft.ocrRegion.height,
                onPickText: pickOCRRegion,
                onDraw: drawOCRRegion,
                onClear: clearOCRRegion
            )
        }

        Toggle(String(localized: "Require Visible Text", table: "Common"), isOn: $draft.ocrRequiresVisible)
            .toggleStyle(.switch)
    }

    private var visualFields: some View {
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
            type: $draft.visualType,
            regionRef: $draft.visualRegionRef,
            searchRegionSpace: $draft.visualSearchRegionSpace,
            hasRegion: $draft.visualRegion.isEnabled,
            regionX: $draft.visualRegion.x,
            regionY: $draft.visualRegion.y,
            regionWidth: $draft.visualRegion.width,
            regionHeight: $draft.visualRegion.height,
            imageRef: $draft.visualImageRef,
            baselineRef: $draft.visualBaselineRef,
            hasPixel: $draft.hasVisualPixel,
            pixelX: $draft.visualPixelX,
            pixelY: $draft.visualPixelY,
            colorHex: $draft.visualColorHex,
            pixelSampleRadius: $draft.visualPixelSampleRadius,
            hasThreshold: $draft.hasVisualThreshold,
            threshold: $draft.visualThreshold,
            requiresVisible: $draft.visualRequiresVisible,
            onDrawRegion: drawVisualRegion,
            onClearRegion: clearVisualRegion,
            onPickPixel: applyPickedVisualPixel
        )
    }

    private var conditionIntentBinding: Binding<ConditionIntent> {
        Binding(
            get: {
                switch draft.mode {
                case .manualApproval: return .manualApproval
                case .externalSignal: return .externalSignal
                case .ocrText: return .ocrText
                case .visual: return ConditionIntent(visualType: draft.visualType)
                case .previousOutcome: return .previousOutcome
                }
            },
            set: { intent in
                switch intent {
                case .manualApproval:
                    draft.mode = .manualApproval
                case .externalSignal:
                    draft.mode = .externalSignal
                case .ocrText:
                    draft.mode = .ocrText
                case .regionChanged:
                    draft.mode = .visual
                    draft.visualType = .regionChanged
                case .imageAppeared:
                    draft.mode = .visual
                    draft.visualType = .imageAppeared
                case .imageDisappeared:
                    draft.mode = .visual
                    draft.visualType = .imageDisappeared
                case .pixelMatched:
                    draft.mode = .visual
                    draft.visualType = .pixelMatched
                case .previousOutcome:
                    draft.mode = .previousOutcome
                }
            }
        )
    }

    private var outcomeOptions: [(tag: String, title: String)] {
        [
            (AutomationOutcomePredicate.anyTerminal.rawValue, String(localized: "Any terminal", table: "Common")),
            (AutomationOutcomePredicate.success.rawValue, String(localized: "Success", table: "Common")),
            (AutomationOutcomePredicate.failure.rawValue, String(localized: "Failure", table: "Common")),
            (AutomationOutcomePredicate.timeout.rawValue, String(localized: "Timeout", table: "Common")),
            (AutomationOutcomePredicate.cancelled.rawValue, String(localized: "Cancelled", table: "Common")),
            (AutomationOutcomePredicate.conditionMatched.rawValue, String(localized: "Condition matched", table: "Automation")),
            (AutomationOutcomePredicate.conditionNotMatched.rawValue, String(localized: "Condition not matched", table: "Automation"))
        ]
    }

    private var draftedOCRCondition: AutomationOCRCondition {
        draft.ocrCondition(preserving: existingOCRCondition)
    }

    private func pickOCRRegion() {
        AutomationOCRRegionPicker.pick(
            currentCondition: draftedOCRCondition,
            targetSurface: targetSurfaceForOCRPicker,
            onFailure: onError,
            onPicked: applyPickedOCRCondition
        )
    }

    private func drawOCRRegion() {
        AutomationOCRRegionPicker.pickArea(
            currentCondition: draftedOCRCondition,
            searchRegionSpace: draft.ocrSearchRegionSpace,
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
        draft.apply(ocrCondition: condition)
        ocrRegionPreview = preview
        Task { await onSave(condition) }
    }

    private func clearOCRRegion() {
        draft.ocrRegion = AutomationTaskRectDraft()
        ocrRegionPreview = nil
        Task { await onSave(nil) }
    }

    private func drawVisualRegion() {
        AutomationOCRRegionPicker.pickArea(
            currentCondition: AutomationOCRCondition(text: ""),
            searchRegionSpace: draft.visualSearchRegionSpace,
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
        draft.visualSearchRegionSpace = condition.searchRegionSpace
        draft.visualRegion = AutomationTaskRectDraft(rect: condition.searchRegion)
        visualRegionPreview = preview
        Task { await onSave(nil) }
    }

    private func clearVisualRegion() {
        draft.visualRegion = AutomationTaskRectDraft()
        visualRegionPreview = nil
        Task { await onSave(nil) }
    }

    private func applyPickedVisualPixel(_ sample: AutomationRegionCapturePixelSample) {
        draft.hasVisualPixel = true
        draft.visualPixelX = sample.normalizedX
        draft.visualPixelY = sample.normalizedY
        if let colorHex = sample.colorHex {
            draft.visualColorHex = colorHex
        }
        Task { await onSave(nil) }
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

    private var displayReferenceSize: CGSize? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return CGSize(
            width: screen.frame.width * screen.backingScaleFactor,
            height: screen.frame.height * screen.backingScaleFactor
        )
    }

    private var ocrRegionStatusTitle: String {
        switch draft.ocrSearchRegionSpace {
        case .automatic, .displayAbsolute: return String(localized: "Display coordinates", table: "Common")
        case .displayNormalized: return String(localized: "Display-relative coordinates", table: "Common")
        case .windowLocal: return String(localized: "Window coordinates", table: "Common")
        case .windowNormalized: return String(localized: "Window-relative coordinates", table: "Common")
        case .contentLocal: return String(localized: "Content coordinates", table: "Common")
        case .contentNormalized: return String(localized: "Content-relative coordinates", table: "Common")
        }
    }

    private var ocrRegionStatusDetail: String {
        switch draft.ocrSearchRegionSpace {
        case .automatic, .displayAbsolute:
            if NSScreen.screens.count > 1 {
                return String(localized: "Draw Region records bounds on the display where you drag. Use this when the automation should stay tied to that monitor.", table: "Automation")
            }
            return String(localized: "Draw Region records display-pixel bounds. Use this when the automation should inspect a fixed screen area.", table: "Automation")
        case .displayNormalized:
            return String(localized: "Bounds are normalized to the selected display, which makes the region more tolerant of display size changes.", table: "EditorUX")
        case .windowLocal, .windowNormalized:
            if let targetSurfaceForOCRPicker {
                return String(
                    format: String(localized: "Window context is available from %@. Draw Region can refresh it from the window under the pointer.", table: "EditorUX"),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return String(localized: "No linked window context is available yet. Draw Region over the target window, or switch to display coordinates.", table: "EditorUX")
        case .contentLocal, .contentNormalized:
            if let targetSurfaceForOCRPicker, targetSurfaceForOCRPicker.recordedContentFrame != nil {
                return String(
                    format: String(localized: "Content context is available from %@. Use this for OCR inside the app content area.", table: "EditorUX"),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return String(localized: "Content bounds are not available yet. Draw Region over the app content, or switch to window/display coordinates.", table: "EditorUX")
        }
    }

    private var ocrRegionStatusImage: String {
        switch draft.ocrSearchRegionSpace {
        case .automatic, .displayAbsolute, .displayNormalized: return "display"
        case .windowLocal, .windowNormalized: return targetSurfaceForOCRPicker == nil ? "exclamationmark.triangle" : "macwindow"
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? "exclamationmark.triangle" : "rectangle.inset.filled"
        }
    }

    private var ocrRegionStatusTint: Color {
        switch draft.ocrSearchRegionSpace {
        case .automatic, .displayAbsolute, .displayNormalized: return Brand.libraryBlue
        case .windowLocal, .windowNormalized: return targetSurfaceForOCRPicker == nil ? Brand.sigAmber : Brand.libraryGreen
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? Brand.sigAmber : Brand.libraryGreen
        }
    }

    private var ocrRegionPreviewReferenceSize: CGSize? {
        referenceSize(for: draft.ocrSearchRegionSpace)
    }

    private var visualRegionStatusTitle: String {
        switch draft.visualSearchRegionSpace {
        case .automatic, .displayAbsolute, .displayNormalized: return String(localized: "Display bounds", table: "Common")
        case .windowLocal, .windowNormalized:
            return targetSurfaceForOCRPicker == nil
                ? String(localized: "Window context missing", table: "Common")
                : String(localized: "Window bounds", table: "Common")
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil
                ? String(localized: "Content context missing", table: "Common")
                : String(localized: "Content bounds", table: "Common")
        }
    }

    private var visualRegionStatusDetail: String {
        switch draft.visualSearchRegionSpace {
        case .automatic, .displayAbsolute:
            return String(localized: "Draw Bounds records display-pixel bounds for the watched visual area.", table: "Common")
        case .displayNormalized:
            return String(localized: "Bounds are normalized to the selected display for more tolerant screen-size changes.", table: "Common")
        case .windowLocal, .windowNormalized:
            if let targetSurfaceForOCRPicker {
                return String(
                    format: String(localized: "Window context is available from %@. Draw over the target window to bind this visual wait.", table: "Common"),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return String(localized: "No linked window context is available yet. Draw over the target window, or switch to display coordinates.", table: "Common")
        case .contentLocal, .contentNormalized:
            if let targetSurfaceForOCRPicker, targetSurfaceForOCRPicker.recordedContentFrame != nil {
                return String(
                    format: String(localized: "Content context is available from %@. Use this for app-content visual waits.", table: "Common"),
                    targetSurfaceForOCRPicker.windowContextLabel
                )
            }
            return String(localized: "Content bounds are not available yet. Draw over app content, or switch to window/display coordinates.", table: "Common")
        }
    }

    private var visualRegionStatusImage: String {
        switch draft.visualSearchRegionSpace {
        case .automatic, .displayAbsolute, .displayNormalized: return "display"
        case .windowLocal, .windowNormalized: return targetSurfaceForOCRPicker == nil ? "exclamationmark.triangle" : "macwindow"
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? "exclamationmark.triangle" : "rectangle.inset.filled"
        }
    }

    private var visualRegionStatusTint: Color {
        switch draft.visualSearchRegionSpace {
        case .automatic, .displayAbsolute, .displayNormalized: return Brand.libraryBlue
        case .windowLocal, .windowNormalized: return targetSurfaceForOCRPicker == nil ? Brand.sigAmber : Brand.libraryGreen
        case .contentLocal, .contentNormalized:
            return targetSurfaceForOCRPicker?.recordedContentFrame == nil ? Brand.sigAmber : Brand.libraryGreen
        }
    }

    private var visualRegionPreviewReferenceSize: CGSize? {
        referenceSize(for: draft.visualSearchRegionSpace)
    }

    private func referenceSize(for space: AutomationOCRSearchRegionSpace) -> CGSize? {
        switch space {
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
            format: String(localized: "%@ bounds %@, %@, %@ x %@", table: "Common"),
            region.space.titleForVisualCondition,
            formattedVisualAssetValue(Double(region.bounds.x)),
            formattedVisualAssetValue(Double(region.bounds.y)),
            formattedVisualAssetValue(Double(region.bounds.width)),
            formattedVisualAssetValue(Double(region.bounds.height))
        )
    }

    private func visualImageAssetDetail(_ asset: AutomationWorkflowDraftVisualImageAsset) -> String? {
        let path = asset.path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForTaskConditionEditor
        let checksum = asset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForTaskConditionEditor
            .map { sha in
                String(format: String(localized: "SHA %@", table: "Common"), String(sha.prefix(8)))
            }
        return [path, checksum]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmptyForTaskConditionEditor
    }

    private func formattedVisualAssetValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
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
        case .regionChanged: self = .regionChanged
        case .imageAppeared: self = .imageAppeared
        case .imageDisappeared: self = .imageDisappeared
        case .pixelMatched: self = .pixelMatched
        }
    }

    var title: String {
        switch self {
        case .manualApproval: return String(localized: "Manual approval", table: "Common")
        case .externalSignal: return String(localized: "External signal", table: "Common")
        case .ocrText: return String(localized: "OCR text", table: "EditorUX")
        case .imageAppeared: return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageAppeared)
        case .imageDisappeared: return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageDisappeared)
        case .regionChanged: return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.regionChanged)
        case .pixelMatched: return AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.pixelMatched)
        case .previousOutcome: return String(localized: "Previous outcome", table: "Common")
        }
    }

    var systemImage: String {
        switch self {
        case .manualApproval: return "hand.raised.fill"
        case .externalSignal: return "antenna.radiowaves.left.and.right"
        case .ocrText: return "text.viewfinder"
        case .imageAppeared: return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.imageAppeared)
        case .imageDisappeared: return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.imageDisappeared)
        case .regionChanged: return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.regionChanged)
        case .pixelMatched: return AutomationVisualConditionPresentation.systemImage(for: AutomationVisualConditionType.pixelMatched)
        case .previousOutcome: return "arrow.uturn.backward"
        }
    }
}

private extension AutomationOCRSearchRegionSpace {
    var taskInspectorTitle: String {
        switch self {
        case .automatic: return String(localized: "Automatic", table: "Common")
        case .displayAbsolute: return String(localized: "Display absolute", table: "Common")
        case .displayNormalized: return String(localized: "Display normalized", table: "Common")
        case .windowLocal: return String(localized: "Window local", table: "Common")
        case .windowNormalized: return String(localized: "Window normalized", table: "Common")
        case .contentLocal: return String(localized: "Content local", table: "Common")
        case .contentNormalized: return String(localized: "Content normalized", table: "Common")
        }
    }

    var isTaskInspectorNormalizedSpace: Bool {
        switch self {
        case .displayNormalized, .windowNormalized, .contentNormalized: return true
        case .automatic, .displayAbsolute, .windowLocal, .contentLocal: return false
        }
    }
}

private extension PlaybackSurface {
    var windowContextLabel: String {
        if let windowTitle, !windowTitle.isEmpty { return windowTitle }
        if let appName, !appName.isEmpty { return appName }
        return String(localized: "linked macro surface", table: "EditorUX")
    }
}

private extension String {
    var nilIfEmptyForTaskConditionEditor: String? {
        isEmpty ? nil : self
    }
}
