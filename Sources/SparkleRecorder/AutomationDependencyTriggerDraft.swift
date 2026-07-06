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
            return NSLocalizedString("Success", comment: "")
        case .onFailure:
            return NSLocalizedString("Failure", comment: "")
        case .onTimeout:
            return NSLocalizedString("Timeout", comment: "")
        case .onCancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .onConditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .onConditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .always:
            return NSLocalizedString("Always", comment: "")
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
