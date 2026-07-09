import Foundation
import SparkleRecorderCore

enum AutomationDependencyTriggerDraft: String, CaseIterable, Identifiable {
    case onSuccess
    case onFailure
    case onTimeout
    case onCancelled
    case onConditionMatched
    case onConditionNotMatched
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onSuccess:
            return String(localized: "Success", table: "Common")
        case .onFailure:
            return String(localized: "Failure", table: "Common")
        case .onTimeout:
            return String(localized: "Timeout", table: "Common")
        case .onCancelled:
            return String(localized: "Cancelled", table: "Common")
        case .onConditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .onConditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .always:
            return String(localized: "Always", table: "Common")
        }
    }

    var trigger: AutomationDependencyTrigger {
        switch self {
        case .onSuccess:
            return .onSuccess
        case .onFailure:
            return .onFailure
        case .onTimeout:
            return .onTimeout
        case .onCancelled:
            return .onCancelled
        case .onConditionMatched:
            return .onConditionMatched
        case .onConditionNotMatched:
            return .onConditionNotMatched
        case .always:
            return .always
        }
    }

    static func draft(for trigger: AutomationDependencyTrigger) -> AutomationDependencyTriggerDraft {
        switch trigger {
        case .onSuccess:
            return .onSuccess
        case .onFailure:
            return .onFailure
        case .onTimeout:
            return .onTimeout
        case .onCancelled:
            return .onCancelled
        case .onConditionMatched:
            return .onConditionMatched
        case .onConditionNotMatched:
            return .onConditionNotMatched
        case .always:
            return .always
        case .onOutcome(let predicate):
            return draft(for: predicate)
        }
    }

    static func options(for sourceTask: AutomationTask?) -> [AutomationDependencyTriggerDraft] {
        guard let sourceTask else {
            return allCases
        }

        switch sourceTask.kind {
        case .condition:
            return [.onConditionMatched, .onConditionNotMatched, .onTimeout, .onFailure, .onCancelled, .always]
        case .macro, .delay, .notification:
            return [.onSuccess, .onFailure, .onTimeout, .onCancelled, .always]
        }
    }

    private static func draft(for predicate: AutomationOutcomePredicate) -> AutomationDependencyTriggerDraft {
        switch predicate {
        case .success:
            return .onSuccess
        case .failure:
            return .onFailure
        case .timeout:
            return .onTimeout
        case .cancelled:
            return .onCancelled
        case .conditionMatched:
            return .onConditionMatched
        case .conditionNotMatched:
            return .onConditionNotMatched
        case .anyTerminal:
            return .always
        }
    }
}
