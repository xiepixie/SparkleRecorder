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
            return NSLocalizedString("Region changed", comment: "")
        case .imageAppeared:
            return NSLocalizedString("Image appeared", comment: "")
        case .imageDisappeared:
            return NSLocalizedString("Image disappeared", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Pixel matched", comment: "")
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
            return NSLocalizedString("Detector: baseline diff", comment: "")
        case .imageAppeared, .imageDisappeared:
            return NSLocalizedString("Detector: image template", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Detector: pixel color", comment: "")
        }
    }

    static func detectorDetail(for type: AutomationVisualConditionType) -> String {
        switch type {
        case .regionChanged:
            return NSLocalizedString("Compares the watched area with a saved baseline image.", comment: "")
        case .imageAppeared:
            return NSLocalizedString("Looks for a saved image crop, such as an icon or button, inside the watched area.", comment: "")
        case .imageDisappeared:
            return NSLocalizedString("Continues when the saved image crop is absent from the watched area.", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Checks a target color at a pixel or small sampled area.", comment: "")
        }
    }

    static func title(for progressKind: AutomationConditionProgressKind) -> String {
        switch progressKind {
        case .ocrText:
            return NSLocalizedString("Screen text", comment: "")
        case .regionChanged:
            return NSLocalizedString("Region changed", comment: "")
        case .imageAppeared:
            return NSLocalizedString("Image appeared", comment: "")
        case .imageDisappeared:
            return NSLocalizedString("Image disappeared", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Pixel matched", comment: "")
        case .previousOutcome:
            return NSLocalizedString("Previous outcome", comment: "")
        case .externalSignal:
            return NSLocalizedString("External signal", comment: "")
        case .manualApproval:
            return NSLocalizedString("Manual approval", comment: "")
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
        NSLocalizedString("Detector: OCR text", comment: "")
    }

    static func ocrDetectorDetail() -> String {
        NSLocalizedString("Recognizes visible text only; icons and drawings need a visual condition.", comment: "")
    }

    static func scopeTitle(hasRegion: Bool) -> String {
        hasRegion
            ? NSLocalizedString("Scope: selected region", comment: "")
            : NSLocalizedString("Scope: full display", comment: "")
    }

    static func ocrScopeDetail(hasRegion: Bool) -> String {
        hasRegion
            ? NSLocalizedString("Only text detected inside the selected region can match.", comment: "")
            : NSLocalizedString("All detected text on the captured display can match.", comment: "")
    }

    static func visualScopeDetail(hasRegion: Bool) -> String {
        hasRegion
            ? NSLocalizedString("Only pixels inside the selected bounds are evaluated.", comment: "")
            : NSLocalizedString("The visual check scans the whole captured display.", comment: "")
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
