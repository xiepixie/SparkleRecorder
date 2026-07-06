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
