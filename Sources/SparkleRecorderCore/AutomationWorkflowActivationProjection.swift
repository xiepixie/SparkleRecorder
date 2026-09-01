import Foundation

public struct AutomationWorkflowActivationProjection: Codable, Equatable, Sendable {
    public enum State: String, Codable, Equatable, Sendable {
        case blocked
        case manualOnly
        case scheduled
        case running
    }

    public enum CheckSeverity: String, Codable, Equatable, Sendable {
        case blocking
        case warning
        case ready
    }

    public struct Check: Identifiable, Codable, Equatable, Sendable {
        public var id: String
        public var severity: CheckSeverity
        public var title: String
        public var detail: String

        public init(id: String, severity: CheckSeverity, title: String, detail: String) {
            self.id = id
            self.severity = severity
            self.title = title
            self.detail = detail
        }
    }

    public var state: State
    public var nextOccurrence: Date?
    public var scheduledTaskCount: Int
    public var checks: [Check]

    public init(workflow: AutomationWorkflowProjection) {
        nextOccurrence = workflow.nextScheduledOccurrence
        scheduledTaskCount = workflow.nodes.reduce(into: 0) { count, node in
            if node.nextScheduledOccurrence != nil {
                count += 1
            }
        }

        if workflow.nodes.isEmpty {
            state = .blocked
            checks = [
                Check(
                    id: "missing-task",
                    severity: .blocking,
                    title: String(localized: "Add a task before scheduling", table: "Automation"),
                    detail: String(localized: "Drag a macro into the workflow, then choose when it should run.", table: "Automation")
                )
            ]
        } else if workflow.status == .running {
            state = .running
            checks = [
                Check(
                    id: "running",
                    severity: .ready,
                    title: String(localized: "Workflow is running", table: "Automation"),
                    detail: workflow.statusDetail
                )
            ]
        } else if workflow.nextScheduledOccurrence == nil {
            state = .manualOnly
            checks = [
                Check(
                    id: "manual-only",
                    severity: .warning,
                    title: String(localized: "No scheduled tasks", table: "Automation"),
                    detail: String(localized: "This workflow runs only when you start a task manually.", table: "Automation")
                )
            ]
        } else {
            state = .scheduled
            checks = [
                Check(
                    id: "app-online",
                    severity: .warning,
                    title: String(localized: "Keep SparkleRecorder open", table: "Automation"),
                    detail: String(localized: "Scheduled workflows currently run only while the app is open.", table: "Automation")
                ),
                Check(
                    id: "schedule-ready",
                    severity: .ready,
                    title: String(localized: "Schedule is ready", table: "Automation"),
                    detail: String(localized: "The next run time has been calculated.", table: "Automation")
                )
            ]
        }
    }

    public var title: String {
        switch state {
        case .blocked:
            String(localized: "Needs setup", table: "Automation")
        case .manualOnly:
            String(localized: "Manual only", table: "Automation")
        case .scheduled:
            String(localized: "Scheduled", table: "Automation")
        case .running:
            String(localized: "Running", table: "Automation")
        }
    }
}
