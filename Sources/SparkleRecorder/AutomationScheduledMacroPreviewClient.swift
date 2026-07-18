import Foundation
import SparkleRecorderCore

struct AutomationScheduledMacroPreviewFailure: Error, Equatable, LocalizedError, Sendable {
    var message: String

    var errorDescription: String? { message }
}

struct AutomationScheduledMacroPreviewClient: Sendable {
    var player: AutomationPlayerClient

    func run(_ request: AutomationPlayerStartRequest) async throws {
        try await withTaskCancellationHandler {
            switch await player.start(request) {
            case .started:
                break
            case .rejected(let outcome):
                throw AutomationScheduledMacroPreviewFailure(
                    message: outcome.userFacingPreviewFailureMessage
                )
            }

            for await action in player.events() {
                try Task.checkCancellation()
                guard case .playerFinished(let completedRunID, let outcome, _) = action,
                      completedRunID == request.runID else {
                    continue
                }
                if case .succeeded = outcome {
                    return
                }
                throw AutomationScheduledMacroPreviewFailure(
                    message: outcome.userFacingPreviewFailureMessage
                )
            }

            try Task.checkCancellation()
            throw AutomationScheduledMacroPreviewFailure(
                message: String(localized: "Preview ended before a result was reported.", table: "Automation")
            )
        } onCancel: {
            Task {
                await player.cancel(request.runID)
            }
        }
    }
}

extension AutomationOutcome {
    var userFacingPreviewFailureMessage: String {
        switch self {
        case .failed(let report):
            return report?.errorMessage ?? String(localized: "Preview failed.", table: "Automation")
        case .cancelled(let reason):
            return reason ?? String(localized: "Preview was cancelled.", table: "Automation")
        case .timedOut:
            return String(localized: "Preview timed out.", table: "Automation")
        case .resourceConflict:
            return String(localized: "Another foreground automation is running.", table: "Automation")
        case .permissionDenied(_, let message):
            return message
        case .missingMacro:
            return String(localized: "The macro is no longer available.", table: "Automation")
        case .rejected(let reason):
            return reason
        case .conditionMatched, .conditionNotMatched:
            return String(localized: "Preview could not be completed.", table: "Automation")
        case .succeeded:
            return String(localized: "Preview completed.", table: "Automation")
        }
    }
}
