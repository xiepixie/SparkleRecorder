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
            String(localized: "Scheduled", table: "Common")
        case .waiting:
            String(localized: "Waiting", table: "EditorUX")
        case .queued:
            String(localized: "Queued", table: "Common")
        case .running:
            String(localized: "Running", table: "Automation")
        case .completed:
            String(localized: "Completed", table: "Common")
        case .failed:
            String(localized: "Failed", table: "Common")
        case .cancelled:
            String(localized: "Cancelled", table: "Common")
        case .timedOut:
            String(localized: "Timed out", table: "Common")
        case .blocked:
            String(localized: "Blocked", table: "Common")
        }
    }
}
