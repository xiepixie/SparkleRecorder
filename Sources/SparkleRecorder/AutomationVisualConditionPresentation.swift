import SwiftUI
import SparkleRecorderCore

enum AutomationVisualConditionPresentation {
    static let allTypes: [AutomationVisualConditionType] = [
        .regionChanged,
        .imageAppeared,
        .imageDisappeared,
        .pixelMatched
    ]

    static func title(for type: AutomationVisualConditionType) -> String {
        switch type {
        case .regionChanged:
            return String(localized: "Region changed", table: "EditorUX")
        case .imageAppeared:
            return String(localized: "Image appeared", table: "Common")
        case .imageDisappeared:
            return String(localized: "Image disappeared", table: "Common")
        case .pixelMatched:
            return String(localized: "Pixel matched", table: "Common")
        }
    }

    static func systemImage(for type: AutomationVisualConditionType) -> String {
        switch type {
        case .regionChanged:
            return "viewfinder.rectangular"
        case .imageAppeared:
            return "photo"
        case .imageDisappeared:
            return "photo.on.rectangle"
        case .pixelMatched:
            return "paintpalette"
        }
    }

    static func detectorTitle(for type: AutomationVisualConditionType) -> String {
        switch type {
        case .regionChanged:
            return String(localized: "Detector: baseline diff", table: "Common")
        case .imageAppeared, .imageDisappeared:
            return String(localized: "Detector: image template", table: "Common")
        case .pixelMatched:
            return String(localized: "Detector: pixel color", table: "Common")
        }
    }

    static func detectorDetail(for type: AutomationVisualConditionType) -> String {
        switch type {
        case .regionChanged:
            return String(localized: "Compares the watched area with a saved baseline image.", table: "Common")
        case .imageAppeared:
            return String(localized: "Looks for a saved image crop, such as an icon or button, inside the watched area.", table: "Common")
        case .imageDisappeared:
            return String(localized: "Continues when the saved image crop is absent from the watched area.", table: "Common")
        case .pixelMatched:
            return String(localized: "Checks a target color at a pixel or small sampled area.", table: "Common")
        }
    }

    static func title(for progressKind: AutomationConditionProgressKind) -> String {
        switch progressKind {
        case .ocrText:
            return String(localized: "Screen text", table: "Recording")
        case .regionChanged:
            return String(localized: "Region changed", table: "EditorUX")
        case .imageAppeared:
            return String(localized: "Image appeared", table: "Common")
        case .imageDisappeared:
            return String(localized: "Image disappeared", table: "Common")
        case .pixelMatched:
            return String(localized: "Pixel matched", table: "Common")
        case .previousOutcome:
            return String(localized: "Previous outcome", table: "Common")
        case .externalSignal:
            return String(localized: "External signal", table: "Common")
        case .manualApproval:
            return String(localized: "Manual approval", table: "Common")
        }
    }

    static func systemImage(for progressKind: AutomationConditionProgressKind) -> String {
        switch progressKind {
        case .ocrText:
            return "text.viewfinder"
        case .regionChanged:
            return "viewfinder.rectangular"
        case .imageAppeared:
            return "photo"
        case .imageDisappeared:
            return "photo.on.rectangle"
        case .pixelMatched:
            return "paintpalette"
        case .previousOutcome:
            return "arrow.uturn.backward"
        case .externalSignal:
            return "antenna.radiowaves.left.and.right"
        case .manualApproval:
            return "hand.raised.fill"
        }
    }
}

enum AutomationConditionObservationPresentation {
    static func ocrDetectorTitle() -> String {
        String(localized: "Detector: OCR text", table: "Common")
    }

    static func ocrDetectorDetail() -> String {
        String(localized: "Recognizes visible text only; icons and drawings need a visual condition.", table: "Common")
    }

    static func scopeTitle(hasRegion: Bool) -> String {
        hasRegion
            ? String(localized: "Scope: selected region", table: "Common")
            : String(localized: "Scope: full display", table: "Common")
    }

    static func ocrScopeDetail(hasRegion: Bool) -> String {
        hasRegion
            ? String(localized: "Only text detected inside the selected region can match.", table: "Common")
            : String(localized: "All detected text on the captured display can match.", table: "Common")
    }

    static func visualScopeDetail(hasRegion: Bool) -> String {
        hasRegion
            ? String(localized: "Only pixels inside the selected bounds are evaluated.", table: "Common")
            : String(localized: "The visual check scans the whole captured display.", table: "Common")
    }
}

extension AutomationVisualConditionType {
    var usesImageReference: Bool {
        switch self {
        case .imageAppeared, .imageDisappeared:
            return true
        case .regionChanged, .pixelMatched:
            return false
        }
    }
}
