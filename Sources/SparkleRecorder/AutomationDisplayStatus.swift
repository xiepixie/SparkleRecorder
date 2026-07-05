import Foundation

public enum AutomationDisplayStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case scheduled
    case waiting
    case queued
    case running
    case completed
    case failed
    case cancelled
    case timedOut
    case blocked

    public var label: String {
        switch self {
        case .scheduled:
            NSLocalizedString("Scheduled", comment: "")
        case .waiting:
            NSLocalizedString("Waiting", comment: "")
        case .queued:
            NSLocalizedString("Queued", comment: "")
        case .running:
            NSLocalizedString("Running", comment: "")
        case .completed:
            NSLocalizedString("Completed", comment: "")
        case .failed:
            NSLocalizedString("Failed", comment: "")
        case .cancelled:
            NSLocalizedString("Cancelled", comment: "")
        case .timedOut:
            NSLocalizedString("Timed out", comment: "")
        case .blocked:
            NSLocalizedString("Blocked", comment: "")
        }
    }
}
