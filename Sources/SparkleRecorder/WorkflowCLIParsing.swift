import Foundation
import SparkleRecorderCore

package enum WorkflowCLIParsing {
    package static func value(
        after option: String,
        in arguments: [String],
        at index: inout Int
    ) throws -> String {
        guard index + 1 < arguments.count else {
            throw WorkflowCLIError("missingArgument", "\(option) requires a value.", path: option)
        }
        index += 1
        return arguments[index]
    }

    package static func uuid(_ value: String, path: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw WorkflowCLIError("invalidUUID", "\(path) must be a UUID.", path: path)
        }
        return uuid
    }

    package static func duration(_ value: String, path: String) throws -> TimeInterval {
        guard let duration = TimeInterval(value) else {
            throw WorkflowCLIError("invalidDuration", "\(path) must be a number of seconds.", path: path)
        }
        return duration
    }

    package static func double(_ value: String, path: String) throws -> Double {
        guard let number = Double(value) else {
            throw WorkflowCLIError("invalidNumber", "\(path) must be a number.", path: path)
        }
        return number
    }

    package static func int(_ value: String, path: String) throws -> Int {
        guard let number = Int(value) else {
            throw WorkflowCLIError("invalidInteger", "\(path) must be an integer.", path: path)
        }
        return number
    }

    package static func bool(_ value: String, path: String) throws -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1", "enabled":
            return true
        case "false", "no", "0", "disabled":
            return false
        default:
            throw WorkflowCLIError("invalidBoolean", "\(path) must be true or false.", path: path)
        }
    }

    package static func textMatchMode(_ value: String, path: String) throws -> TextMatchMode {
        guard let matchMode = TextMatchMode(rawValue: value) else {
            throw WorkflowCLIError(
                "unsupportedMatchMode",
                "\(path) must be contains or exact.",
                path: path
            )
        }
        return matchMode
    }

    package static func date(_ value: String, path: String = "--at") throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        if let seconds = TimeInterval(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        throw WorkflowCLIError("invalidDate", "\(path) must be ISO-8601 or a Unix timestamp.", path: path)
    }

    package static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

package func workflowCLIValue(
    after option: String,
    in arguments: [String],
    at index: inout Int
) throws -> String {
    try WorkflowCLIParsing.value(after: option, in: arguments, at: &index)
}

package func parseWorkflowCLIUUID(_ value: String, path: String) throws -> UUID {
    try WorkflowCLIParsing.uuid(value, path: path)
}

package func parseWorkflowCLIDuration(_ value: String, path: String) throws -> TimeInterval {
    try WorkflowCLIParsing.duration(value, path: path)
}

package func parseWorkflowCLIDouble(_ value: String, path: String) throws -> Double {
    try WorkflowCLIParsing.double(value, path: path)
}

package func parseWorkflowCLIInt(_ value: String, path: String) throws -> Int {
    try WorkflowCLIParsing.int(value, path: path)
}

package func parseWorkflowCLIBool(_ value: String, path: String) throws -> Bool {
    try WorkflowCLIParsing.bool(value, path: path)
}

package func parseWorkflowCLITextMatchMode(_ value: String, path: String) throws -> TextMatchMode {
    try WorkflowCLIParsing.textMatchMode(value, path: path)
}

package func parseWorkflowCLIDate(_ value: String, path: String = "--at") throws -> Date {
    try WorkflowCLIParsing.date(value, path: path)
}

package func workflowCLIISO8601String(_ date: Date) -> String {
    WorkflowCLIParsing.iso8601String(date)
}
