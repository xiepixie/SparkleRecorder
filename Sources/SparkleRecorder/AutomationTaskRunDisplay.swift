import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunDisplay {
    let run: AutomationTaskRun
    var resourceRequirement: AutomationResourceRequirement?

    var title: String {
        if let outcome = run.outcome {
            return outcomeTitle(for: outcome)
        }

        return statusTitle(for: run.status)
    }

    var detail: String {
        if let outcome = run.outcome {
            return outcomeDetail(for: outcome)
        }

        return statusDetail(for: run.status)
    }

    var systemImage: String {
        displayStatus.systemImage
    }

    var tint: Color {
        displayStatus.tint
    }

    var primaryDate: Date {
        run.completedAt ?? run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    var timestampSummary: String {
        var parts = [timeLabel(String(localized: "Created", table: "Common"), run.createdAt)]

        if let scheduledStartTime = run.scheduledStartTime {
            parts.append(timeLabel(String(localized: "Scheduled", table: "Common"), scheduledStartTime))
        }

        if let earliestStartTime = run.earliestStartTime,
           run.scheduledStartTime.map({ $0 == earliestStartTime }) != true {
            parts.append(timeLabel(String(localized: "Ready", table: "Common"), earliestStartTime))
        }

        if let actualStartTime = run.actualStartTime {
            parts.append(timeLabel(String(localized: "Started", table: "Common"), actualStartTime))
        }

        if let completedAt = run.completedAt {
            parts.append(timeLabel(String(localized: "Completed", table: "Common"), completedAt))
        }

        return parts.joined(separator: " · ")
    }

    var metadataSummary: String {
        var parts = [
            String(format: String(localized: "Attempt %d", table: "Common"), run.attempt),
            String(format: String(localized: "Execution %@", table: "Common"), shortExecutionID)
        ]

        if !run.upstreamRunIDs.isEmpty {
            parts.append(String(format: String(localized: "Upstream %d", table: "Common"), run.upstreamRunIDs.count))
        }

        if run.evidenceID != nil {
            parts.append(String(localized: "Evidence available", table: "Automation"))
        }

        if let durationLabel {
            parts.append(String(format: String(localized: "Duration %@", table: "Common"), durationLabel))
        }

        return parts.joined(separator: " · ")
    }

    var accessibilitySummary: String {
        [title, detail, timestampSummary, metadataSummary].joined(separator: ", ")
    }

    private var displayStatus: AutomationDisplayStatus {
        guard let outcome = run.outcome else {
            switch run.status {
            case .planned:
                return .scheduled
            case .waitingForDependencies, .waitingForResource:
                return .waiting
            case .queued:
                return .queued
            case .running:
                return .running
            case .completed:
                return .completed
            }
        }

        switch outcome {
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .resourceConflict, .permissionDenied, .missingMacro, .rejected:
            return .blocked
        }
    }

    private var durationLabel: String? {
        if let reportDuration {
            return durationText(for: reportDuration)
        }

        guard let actualStartTime = run.actualStartTime,
              let completedAt = run.completedAt else {
            return nil
        }

        return durationText(for: completedAt.timeIntervalSince(actualStartTime))
    }

    private var reportDuration: TimeInterval? {
        guard let outcome = run.outcome else {
            return nil
        }

        switch outcome {
        case .succeeded(let report), .failed(let report):
            return report?.duration
        case .cancelled, .timedOut, .resourceConflict, .permissionDenied, .conditionMatched, .conditionNotMatched, .missingMacro, .rejected:
            return nil
        }
    }

    private var shortExecutionID: String {
        String(run.executionID.uuidString.prefix(8)).uppercased()
    }

    private func outcomeTitle(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return String(localized: "Completed successfully", table: "Common")
        case .failed:
            return String(localized: "Run failed", table: "Automation")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .timedOut:
            return String(localized: "Timed out", table: "Common")
        case .resourceConflict:
            return String(localized: "Resource conflict", table: "Common")
        case .permissionDenied:
            return String(localized: "Permission denied", table: "Settings")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition did not match", table: "Automation")
        case .missingMacro:
            return String(localized: "Macro is missing", table: "EditorUX")
        case .rejected:
            return String(localized: "Rejected", table: "Common")
        }
    }

    private func statusTitle(for status: AutomationTaskRunStatus) -> String {
        switch status {
        case .planned:
            return String(localized: "Scheduled", table: "Common")
        case .waitingForDependencies, .waitingForResource:
            return String(localized: "Waiting", table: "EditorUX")
        case .queued:
            return String(localized: "Queued", table: "Common")
        case .running:
            return String(localized: "Running", table: "Automation")
        case .completed:
            return String(localized: "Completed", table: "Common")
        }
    }

    private func outcomeDetail(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            if let durationLabel {
                return String(format: String(localized: "Completed in %@", table: "Common"), durationLabel)
            }
            return String(localized: "Completed successfully", table: "Common")
        case .failed(let report):
            var detail = report?.errorMessage ?? String(localized: "Run failed", table: "Automation")
            if let failedEventIndex = report?.failedEventIndex {
                detail += " · " + String(format: String(localized: "Event #%d", table: "EditorUX"), failedEventIndex + 1)
            }
            return detail
        case .cancelled(let reason):
            return reason ?? String(localized: "Cancelled", table: "Common")
        case .timedOut(let deadline):
            if let deadline {
                return String(format: String(localized: "Deadline %@", table: "Common"), deadline.formatted(date: .omitted, time: .shortened))
            }
            return String(localized: "Timed out before completion", table: "Common")
        case .resourceConflict(let resource):
            return resource.map {
                String(format: String(localized: "Resource conflict: %@", table: "Common"), resourceLabel(for: $0))
            } ?? String(localized: "Resource conflict", table: "Common")
        case .permissionDenied(let permission, let message):
            return String(format: String(localized: "%@: %@", table: "Common"), permissionLabel(for: permission), message)
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition did not match", table: "Automation")
        case .missingMacro:
            return String(localized: "The saved macro is not available locally.", table: "EditorUX")
        case .rejected(let reason):
            return reason
        }
    }

    private func statusDetail(for status: AutomationTaskRunStatus) -> String {
        switch status {
        case .planned:
            return String(localized: "Waiting for its scheduled start", table: "EditorUX")
        case .waitingForDependencies:
            return String(localized: "Waiting for an upstream task", table: "Automation")
        case .waitingForResource:
            return resourceWaitingDetail()
        case .queued:
            return String(localized: "Queued to run", table: "Automation")
        case .running:
            return String(localized: "Running now", table: "Automation")
        case .completed:
            return String(localized: "Completed", table: "Common")
        }
    }

    private func timeLabel(_ title: String, _ date: Date) -> String {
        String(format: String(localized: "%@: %@", table: "Common"), title, date.formatted(date: .omitted, time: .shortened))
    }

    private func durationText(for duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 {
            return String(format: String(localized: "%ds", table: "Common"), seconds)
        }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return String(format: String(localized: "%dm %ds", table: "Common"), minutes, remainingSeconds)
        }

        return String(format: String(localized: "%dh %dm", table: "Common"), minutes / 60, minutes % 60)
    }

    private func resourceLabel(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return String(localized: "Needs mouse and keyboard", table: "Common")
        case .screenCapture:
            return String(localized: "Screen capture", table: "Recording")
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .network:
            return String(localized: "Network", table: "Common")
        }
    }

    private func resourceWaitingDetail() -> String {
        guard let resourceRequirement else {
            return String(localized: "Waiting for a required resource", table: "EditorUX")
        }
        if resourceRequirement.resources.contains(.foregroundInput) {
            return String(localized: "Waiting for mouse and keyboard", table: "Common")
        }
        guard !resourceRequirement.resources.isEmpty else {
            return String(localized: "Waiting for a required resource", table: "EditorUX")
        }
        return String(
            format: String(localized: "Waiting for %@", table: "Common"),
            resourceRequirement.resources
                .sorted { $0.rawValue < $1.rawValue }
                .map(resourceLabel(for:))
                .joined(separator: ", ")
        )
    }

    private func permissionLabel(for permission: AutomationPermission) -> String {
        switch permission {
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .inputMonitoring:
            return String(localized: "Input Monitoring", table: "Common")
        case .screenRecording:
            return String(localized: "Screen Recording", table: "Recording")
        case .automation:
            return String(localized: "Automation", table: "Automation")
        case .postEvents:
            return String(localized: "Post Events", table: "EditorUX")
        }
    }
}
