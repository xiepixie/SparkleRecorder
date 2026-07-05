import Foundation

enum AutomationAuthoringSelection: Equatable {
    case workflow
    case task(UUID)
    case dependency(UUID)
}
