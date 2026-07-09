import Foundation

public enum AutomationDependencyDisplayStatus: String, Codable, Equatable, Hashable, Sendable {
    case pending
    case waiting
    case satisfied
    case blocked
    case disabled

    public var label: String {
        switch self {
        case .pending:
            String(localized: "Pending", table: "Common")
        case .waiting:
            String(localized: "Waiting", table: "EditorUX")
        case .satisfied:
            String(localized: "Satisfied", table: "Common")
        case .blocked:
            String(localized: "Blocked", table: "Common")
        case .disabled:
            String(localized: "Disabled", table: "Common")
        }
    }
}
