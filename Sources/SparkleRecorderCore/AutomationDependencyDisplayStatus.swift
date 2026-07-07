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
            NSLocalizedString("Pending", comment: "")
        case .waiting:
            NSLocalizedString("Waiting", comment: "")
        case .satisfied:
            NSLocalizedString("Satisfied", comment: "")
        case .blocked:
            NSLocalizedString("Blocked", comment: "")
        case .disabled:
            NSLocalizedString("Disabled", comment: "")
        }
    }
}
