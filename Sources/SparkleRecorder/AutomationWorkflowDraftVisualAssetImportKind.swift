import Foundation

enum AutomationWorkflowDraftVisualAssetImportKind: Sendable {
    case image
    case baseline

    var directoryName: String {
        switch self {
        case .image:
            return "images"
        case .baseline:
            return "baselines"
        }
    }

    var pickerTitle: String {
        switch self {
        case .image:
            return String(localized: "Import Image Template", table: "Common")
        case .baseline:
            return String(localized: "Import Baseline Image", table: "Common")
        }
    }
}
