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
            return NSLocalizedString("Import Image Template", comment: "")
        case .baseline:
            return NSLocalizedString("Import Baseline Image", comment: "")
        }
    }
}
