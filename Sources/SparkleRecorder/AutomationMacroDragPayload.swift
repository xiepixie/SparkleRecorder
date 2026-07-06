import Foundation

enum AutomationMacroDragPayload {
    private static let prefix = "sparkle.workflow.macro:"

    static func string(for macroID: UUID) -> String {
        prefix + macroID.uuidString
    }

    static func macroID(from string: String) -> UUID? {
        guard string.hasPrefix(prefix) else {
            return nil
        }

        return UUID(uuidString: String(string.dropFirst(prefix.count)))
    }
}
