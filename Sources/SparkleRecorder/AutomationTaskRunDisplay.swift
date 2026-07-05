import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunDisplay {
    let run: AutomationTaskRun

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
        var parts = [timeLabel(NSLocalizedString("Created", comment: ""), run.createdAt)]

        if let scheduledStartTime = run.scheduledStartTime {
            parts.append(timeLabel(NSLocalizedString("Scheduled", comment: ""), scheduledStartTime))
        }

        if let earliestStartTime = run.earliestStartTime,
           run.scheduledStartTime.map({ $0 == earliestStartTime }) != true {
            parts.append(timeLabel(NSLocalizedString("Ready", comment: ""), earliestStartTime))
        }

        if let actualStartTime = run.actualStartTime {
            parts.append(timeLabel(NSLocalizedString("Started", comment: ""), actualStartTime))
        }

        if let completedAt = run.completedAt {
            parts.append(timeLabel(NSLocalizedString("Completed", comment: ""), completedAt))
        }

        return parts.joined(separator: " · ")
    }

    var metadataSummary: String {
        var parts = [
            String(format: NSLocalizedString("Attempt %d", comment: ""), run.attempt),
            String(format: NSLocalizedString("Execution %@", comment: ""), shortExecutionID)
        ]

        if !run.upstreamRunIDs.isEmpty {
            parts.append(String(format: NSLocalizedString("Upstream %d", comment: ""), run.upstreamRunIDs.count))
        }

        if run.evidenceID != nil {
            parts.append(NSLocalizedString("Evidence available", comment: ""))
        }

        if let durationLabel {
            parts.append(String(format: NSLocalizedString("Duration %@", comment: ""), durationLabel))
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
            return NSLocalizedString("Completed successfully", comment: "")
        case .failed:
            return NSLocalizedString("Run failed", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .timedOut:
            return NSLocalizedString("Timed out", comment: "")
        case .resourceConflict:
            return NSLocalizedString("Resource conflict", comment: "")
        case .permissionDenied:
            return NSLocalizedString("Permission denied", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition did not match", comment: "")
        case .missingMacro:
            return NSLocalizedString("Macro is missing", comment: "")
        case .rejected:
            return NSLocalizedString("Rejected", comment: "")
        }
    }

    private func statusTitle(for status: AutomationTaskRunStatus) -> String {
        switch status {
        case .planned:
            return NSLocalizedString("Scheduled", comment: "")
        case .waitingForDependencies, .waitingForResource:
            return NSLocalizedString("Waiting", comment: "")
        case .queued:
            return NSLocalizedString("Queued", comment: "")
        case .running:
            return NSLocalizedString("Running", comment: "")
        case .completed:
            return NSLocalizedString("Completed", comment: "")
        }
    }

    private func outcomeDetail(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            if let durationLabel {
                return String(format: NSLocalizedString("Completed in %@", comment: ""), durationLabel)
            }
            return NSLocalizedString("Completed successfully", comment: "")
        case .failed(let report):
            var detail = report?.errorMessage ?? NSLocalizedString("Run failed", comment: "")
            if let failedEventIndex = report?.failedEventIndex {
                detail += " · " + String(format: NSLocalizedString("Event #%d", comment: ""), failedEventIndex + 1)
            }
            return detail
        case .cancelled(let reason):
            return reason ?? NSLocalizedString("Cancelled", comment: "")
        case .timedOut(let deadline):
            if let deadline {
                return String(format: NSLocalizedString("Deadline %@", comment: ""), deadline.formatted(date: .omitted, time: .shortened))
            }
            return NSLocalizedString("Timed out before completion", comment: "")
        case .resourceConflict(let resource):
            return resource.map {
                String(format: NSLocalizedString("Resource conflict: %@", comment: ""), resourceLabel(for: $0))
            } ?? NSLocalizedString("Resource conflict", comment: "")
        case .permissionDenied(let permission, let message):
            return String(format: NSLocalizedString("%@: %@", comment: ""), permissionLabel(for: permission), message)
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition did not match", comment: "")
        case .missingMacro:
            return NSLocalizedString("The saved macro is not available locally.", comment: "")
        case .rejected(let reason):
            return reason
        }
    }

    private func statusDetail(for status: AutomationTaskRunStatus) -> String {
        switch status {
        case .planned:
            return NSLocalizedString("Waiting for its scheduled start", comment: "")
        case .waitingForDependencies:
            return NSLocalizedString("Waiting for an upstream task", comment: "")
        case .waitingForResource:
            return NSLocalizedString("Waiting for a required resource", comment: "")
        case .queued:
            return NSLocalizedString("Queued to run", comment: "")
        case .running:
            return NSLocalizedString("Running now", comment: "")
        case .completed:
            return NSLocalizedString("Completed", comment: "")
        }
    }

    private func timeLabel(_ title: String, _ date: Date) -> String {
        String(format: NSLocalizedString("%@: %@", comment: ""), title, date.formatted(date: .omitted, time: .shortened))
    }

    private func durationText(for duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 {
            return String(format: NSLocalizedString("%ds", comment: ""), seconds)
        }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return String(format: NSLocalizedString("%dm %ds", comment: ""), minutes, remainingSeconds)
        }

        return String(format: NSLocalizedString("%dh %dm", comment: ""), minutes / 60, minutes % 60)
    }

    private func resourceLabel(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return NSLocalizedString("Needs mouse and keyboard", comment: "")
        case .screenCapture:
            return NSLocalizedString("Screen capture", comment: "")
        case .accessibility:
            return NSLocalizedString("Accessibility", comment: "")
        case .network:
            return NSLocalizedString("Network", comment: "")
        }
    }

    private func permissionLabel(for permission: AutomationPermission) -> String {
        switch permission {
        case .accessibility:
            return NSLocalizedString("Accessibility", comment: "")
        case .inputMonitoring:
            return NSLocalizedString("Input Monitoring", comment: "")
        case .screenRecording:
            return NSLocalizedString("Screen Recording", comment: "")
        case .automation:
            return NSLocalizedString("Automation", comment: "")
        case .postEvents:
            return NSLocalizedString("Post Events", comment: "")
        }
    }
}
