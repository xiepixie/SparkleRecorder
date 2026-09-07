import Foundation

struct AutomationTaskRunEvidenceActionPresentation: Equatable, Sendable {
    var message: String
    var systemImage: String
    var isError: Bool

    static func make(
        _ feedback: AutomationTaskRunEvidenceActionFeedback
    ) -> AutomationTaskRunEvidenceActionPresentation {
        switch feedback {
        case .succeeded(.revealReport):
            return AutomationTaskRunEvidenceActionPresentation(
                message: String(localized: "Report revealed in Finder.", table: "Common"),
                systemImage: "folder.badge.gearshape",
                isError: false
            )
        case .succeeded(.openScreenshot):
            return AutomationTaskRunEvidenceActionPresentation(
                message: String(localized: "Screenshot opened in the default image viewer.", table: "Common"),
                systemImage: "photo.badge.checkmark",
                isError: false
            )
        case .failed(_, let message):
            return AutomationTaskRunEvidenceActionPresentation(
                message: message,
                systemImage: "exclamationmark.triangle",
                isError: true
            )
        }
    }
}
