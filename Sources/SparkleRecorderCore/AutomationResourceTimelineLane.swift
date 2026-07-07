import Foundation

public enum AutomationResourceTimelineLane: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case foregroundInput
    case screenCapture
    case waiting
    case completed

    public var displayName: String {
        switch self {
        case .foregroundInput:
            NSLocalizedString("Needs mouse and keyboard", comment: "")
        case .screenCapture:
            NSLocalizedString("Screen capture", comment: "")
        case .waiting:
            NSLocalizedString("Waiting", comment: "")
        case .completed:
            NSLocalizedString("Completed", comment: "")
        }
    }
}
