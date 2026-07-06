import Foundation

enum AutomationTaskDragPayload {
    private static let prefix = "sparkle.workflow.task:"

    static func string(for taskID: UUID) -> String {
        prefix + taskID.uuidString
    }

    static func taskID(from string: String) -> UUID? {
        guard string.hasPrefix(prefix) else {
            return nil
        }

        return UUID(uuidString: String(string.dropFirst(prefix.count)))
    }
}
