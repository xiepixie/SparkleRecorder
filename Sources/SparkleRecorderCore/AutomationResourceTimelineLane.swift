import Foundation

public enum AutomationResourceTimelineLane: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case foregroundInput
    case screenCapture
    case waiting
    case completed

    public var displayName: String {
        switch self {
        case .foregroundInput:
            String(localized: "Needs mouse and keyboard", table: "Common")
        case .screenCapture:
            String(localized: "Screen capture", table: "Recording")
        case .waiting:
            String(localized: "Waiting", table: "EditorUX")
        case .completed:
            String(localized: "Completed", table: "Common")
        }
    }
}
