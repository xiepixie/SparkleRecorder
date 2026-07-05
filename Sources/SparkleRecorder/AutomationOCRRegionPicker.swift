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
        AutomationOCRRegionPickerOverlay.shared.onPicked = { selection in
            defer {
                AutomationOCRRegionPickerOverlay.shared.onPicked = nil
                AutomationOCRRegionPickerOverlay.shared.onCancelled = nil
            }

            guard let region = selection.searchRegion(in: searchRegionSpace) else {
                NSSound.beep()
                return
            }

            onPicked(currentCondition.updatingTextMatchRegionAndSpace(
                text: currentCondition.text,
                matchMode: currentCondition.matchMode,
                searchRegion: region,
                searchRegionSpace: searchRegionSpace,
                requireVisible: currentCondition.requireVisible
            ))
        }
        AutomationOCRRegionPickerOverlay.shared.onCancelled = {
            AutomationOCRRegionPickerOverlay.shared.onPicked = nil
            AutomationOCRRegionPickerOverlay.shared.onCancelled = nil
        }
        AutomationOCRRegionPickerOverlay.shared.start()
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
