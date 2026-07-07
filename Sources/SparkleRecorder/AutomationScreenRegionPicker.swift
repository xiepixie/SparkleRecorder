import Foundation
import SparkleRecorderCore

@MainActor
enum AutomationScreenRegionPicker {
    static func pickRegion(
        instructionTitle: String = NSLocalizedString("Drag to select region", comment: ""),
        onPicked: @escaping (AutomationScreenRegionPickerSelection) -> Void,
        onCancelled: (() -> Void)? = nil
    ) {
        AutomationOCRRegionPickerOverlay.shared.onPicked = { selection in
            clearCallbacks()
            onPicked(selection)
        }
        AutomationOCRRegionPickerOverlay.shared.onCancelled = {
            clearCallbacks()
            onCancelled?()
        }
        AutomationOCRRegionPickerOverlay.shared.start(instructionTitle: instructionTitle)
    }

    private static func clearCallbacks() {
        AutomationOCRRegionPickerOverlay.shared.onPicked = nil
        AutomationOCRRegionPickerOverlay.shared.onCancelled = nil
    }
}

@MainActor
struct AutomationScreenRegionPickerSelection {
    var regionSelection: AutomationOCRSearchRegionSelection
    var windowSummary: AutomationRegionCaptureWindowSummary?
    var preview: AutomationRegionCapturePreview?

    func searchRegion(in space: AutomationOCRSearchRegionSpace) -> RectValue? {
        regionSelection.searchRegion(in: space)
    }

    func resolvedSpace(for requestedSpace: AutomationOCRSearchRegionSpace) -> AutomationOCRSearchRegionSpace {
        guard requestedSpace == .automatic else {
            return requestedSpace
        }

        if regionSelection.searchRegion(in: .contentNormalized) != nil {
            return .contentNormalized
        }
        if regionSelection.searchRegion(in: .windowNormalized) != nil {
            return .windowNormalized
        }
        return .displayAbsolute
    }
}

typealias AutomationOCRRegionPickerSelection = AutomationScreenRegionPickerSelection
