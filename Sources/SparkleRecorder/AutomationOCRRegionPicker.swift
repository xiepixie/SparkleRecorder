import AppKit
import Foundation
import SparkleRecorderCore

@MainActor
enum AutomationOCRRegionPicker {
    static func pick(
        currentCondition: AutomationOCRCondition,
        targetSurface: PlaybackSurface?,
        onPicked: @escaping (AutomationOCRCondition) -> Void
    ) {
        guard #available(macOS 14.0, *) else {
            return
        }

        TextPickerOverlay.shared.onPicked = { anchor in
            onPicked(condition(
                from: anchor,
                currentCondition: currentCondition,
                hasTargetSurface: targetSurface != nil
            ))
            TextPickerOverlay.shared.onPicked = nil
            TextPickerOverlay.shared.onCancelled = nil
        }
        TextPickerOverlay.shared.onCancelled = {
            TextPickerOverlay.shared.onPicked = nil
            TextPickerOverlay.shared.onCancelled = nil
        }
        TextPickerOverlay.shared.start(targetSurface: targetSurface)
    }

    static func pickArea(
        currentCondition: AutomationOCRCondition,
        searchRegionSpace: AutomationOCRSearchRegionSpace,
        onPicked: @escaping (AutomationOCRCondition) -> Void
    ) {
        pickArea(
            currentCondition: currentCondition,
            searchRegionSpace: searchRegionSpace
        ) { condition, _ in
            onPicked(condition)
        }
    }

    static func pickArea(
        currentCondition: AutomationOCRCondition,
        searchRegionSpace: AutomationOCRSearchRegionSpace,
        onPicked: @escaping (AutomationOCRCondition, AutomationRegionCapturePreview?) -> Void
    ) {
        AutomationScreenRegionPicker.pickRegion(
            instructionTitle: NSLocalizedString("Drag to select OCR region", comment: ""),
            onPicked: { selection in
                let resolvedSpace = selection.resolvedSpace(for: searchRegionSpace)
                guard let region = selection.searchRegion(in: resolvedSpace) else {
                    NSSound.beep()
                    return
                }

                onPicked(currentCondition.updatingTextMatchRegionAndSpace(
                    text: currentCondition.text,
                    matchMode: currentCondition.matchMode,
                    searchRegion: region,
                    searchRegionSpace: resolvedSpace,
                    requireVisible: currentCondition.requireVisible
                ), selection.preview)
            }
        )
    }

    private static func condition(
        from anchor: TextAnchor,
        currentCondition: AutomationOCRCondition,
        hasTargetSurface: Bool
    ) -> AutomationOCRCondition {
        let text = anchor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pickedText = text.isEmpty ? currentCondition.text : text

        if hasTargetSurface, let region = anchor.searchContentNormalizedRegion {
            return AutomationOCRCondition(
                text: pickedText,
                matchMode: .contains,
                searchRegion: region,
                searchRegionSpace: .contentNormalized,
                requireVisible: true
            )
        }

        if let region = anchor.searchRegion {
            return AutomationOCRCondition(
                text: pickedText,
                matchMode: .contains,
                searchRegion: region,
                searchRegionSpace: .displayAbsolute,
                requireVisible: true
            )
        }

        return AutomationOCRCondition(
            text: pickedText,
            matchMode: currentCondition.matchMode,
            searchRegion: currentCondition.searchRegion,
            searchRegionSpace: currentCondition.searchRegionSpace,
            requireVisible: currentCondition.requireVisible
        )
    }
}
