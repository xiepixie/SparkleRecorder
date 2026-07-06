import Foundation
import SparkleRecorderCore

enum AutomationTaskRunEvidenceSource: Equatable, Sendable {
    case perRun
    case latestMatchingRun
    case latestMacro
}

struct AutomationTaskRunEvidencePayload: Sendable {
    var source: AutomationTaskRunEvidenceSource
    var manifest: RunEvidenceManifest?
    var report: RunReport
    var reportURL: URL
    var screenshotURL: URL?
    var screenshotData: Data?
    var packageURL: URL
    var loadedAt: Date
}

enum AutomationTaskRunEvidenceFileAction: Equatable, Sendable {
    case revealReport
    case openScreenshot
}

enum AutomationTaskRunEvidenceActionFeedback: Equatable, Sendable {
    case succeeded(AutomationTaskRunEvidenceFileAction)
    case failed(AutomationTaskRunEvidenceFileAction, message: String)

    var action: AutomationTaskRunEvidenceFileAction {
        switch self {
        case .succeeded(let action), .failed(let action, _):
            return action
        }
    }
}
