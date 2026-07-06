import Cocoa
import CryptoKit
import SparkleRecorderCore

// CLI playback mode: ./SparkleRecorder --play /path/to/macro.tinyrec
// Used by exported .command scripts. Exempt from the single-instance guard —
// it never touches the library.
let args = CommandLine.arguments

private struct WorkflowCLIError: Error {
    var code: String
    var message: String
    var path: String?

    init(_ code: String, _ message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }
}

private struct WorkflowProductEvidenceSnapshotPayload: Codable, Equatable, Sendable {
    var scenario: String
    var outputPath: String
    var width: Double
    var height: Double
    var scale: Double
}

private struct WorkflowProductEvidencePreparedSidecarPayload: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var sidecarPath: String
    var clipPathCandidates: [String]
    var action: String
}

private struct WorkflowProductEvidencePrepareLiveCapturePayload: Codable, Equatable, Sendable {
    var directory: String
    var includeSatisfied: Bool
    var overwrite: Bool
    var writtenCount: Int
    var overwrittenCount: Int
    var skippedExistingCount: Int
    var sidecars: [WorkflowProductEvidencePreparedSidecarPayload]
}

private struct WorkflowProductEvidenceCompleteSidecarPayload: Codable, Equatable, Sendable {
    var directory: String
    var id: String
    var title: String
    var sidecarPath: String
    var clipPath: String
    var clipExists: Bool
    var clipMeetsMinimumByteCount: Bool
    var clipHasSupportedContainer: Bool
    var action: String
    var sidecarCompleteAfterWrite: Bool
    var incompleteSidecarLabels: [String]
    var targetSatisfiedAfterWrite: Bool
}

private enum SemanticRecordingDebugSmokeStatus: String, Codable, Equatable, Sendable {
    case blocked
    case finished
    case preflightReady
}

private struct SemanticRecordingDebugSmokePayload: Codable, Equatable, Sendable {
    var status: SemanticRecordingDebugSmokeStatus
    var recordingID: UUID
    var commandPlan: SemanticRecordingDebugSmokeCommandPlan?
    var capturePolicy: RecordingCapturePolicy
    var captureTarget: RecordingCaptureTarget
    var preflight: SemanticRecordingPreflightResult
    var preflightPresentation: SemanticRecordingPreflightPresentation
    var bundleDirectory: String?
    var manifestPath: String?
    var evidenceSidecarPath: String?
    var videoSegmentCount: Int
    var frameCount: Int
    var timelineEventCount: Int
    var aiSafeEventCount: Int
    var visualObservationCount: Int
    var suppressionCount: Int
    var syntheticSuppressionCount: Int
    var syntheticRedactionReason: RecordingSuppressionReason?
    var bundleReadinessPolicy: SemanticRecordingBundleReadinessPolicy
    var bundleReadinessStatus: SemanticRecordingBundleReadinessStatus?
    var bundleReadinessIssueCount: Int
    var bundleReadinessBlockingIssueCount: Int
    var bundleReadinessDegradedIssueCount: Int
    var bundleReadinessIssues: [SemanticRecordingBundleReadinessIssue]
    var bundleReadinessFollowUps: [String]
    var redactedFrameCount: Int
    var redactedFrameIndexPath: String?
    var redactedVideoCount: Int
    var redactedVideoIndexPath: String?
    var pendingVideoRangeRedactionCount: Int
    var persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    var persistedBundleCountCheck: SemanticRecordingDebugSmokePersistedBundleCountCheck
}

private struct RecordingCLIBundle {
    var requestedRecordingID: String
    var fixture: String?
    var sourceOption: String?
    var bundleDirectory: URL?
    var bundle: SemanticRecordingBundle
}

if args.count >= 2, args[1] == "workflow" {
    runWorkflowCLI(args)
}

if args.count >= 2, args[1] == "recording" {
    runRecordingCLI(args)
}

if args.count >= 2, args[1] == "semantic-recording" {
    runSemanticRecordingDebugCLI(args)
}

private func runRecordingCLI(_ args: [String]) -> Never {
    let recordingArgs = Array(args.dropFirst(2))
    let wantsJSON = recordingArgs.contains("--json")
    let command = recordingCommandName(recordingArgs)

    do {
        guard !recordingArgs.isEmpty else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Expected a recording command, such as 'recording show checkout-demo --fixture checkout --json'."
            )
        }

        if recordingArgs[0] == "list" {
            let exitCode = try runRecordingList(
                Array(recordingArgs.dropFirst()),
                command: "recording.list",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs[0] == "show" {
            let exitCode = try runRecordingShow(
                Array(recordingArgs.dropFirst()),
                command: "recording.show",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs[0] == "explain" {
            let exitCode = try runRecordingExplain(
                Array(recordingArgs.dropFirst()),
                command: "recording.explain",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs[0] == "frames" {
            let exitCode = try runRecordingFrames(
                Array(recordingArgs.dropFirst()),
                command: "recording.frames",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs.count >= 2,
           recordingArgs[0] == "frame",
           recordingArgs[1] == "show" {
            let exitCode = try runRecordingFrameShow(
                Array(recordingArgs.dropFirst(2)),
                command: "recording.frame.show",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs[0] == "events-near" {
            let exitCode = try runRecordingEventsNear(
                Array(recordingArgs.dropFirst()),
                command: "recording.eventsNear",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs.count >= 2,
           recordingArgs[0] == "ocr",
           recordingArgs[1] == "search" {
            let exitCode = try runRecordingOCRSearch(
                Array(recordingArgs.dropFirst(2)),
                command: "recording.ocr.search",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs.count >= 2,
           recordingArgs[0] == "visual",
           recordingArgs[1] == "search" {
            let exitCode = try runRecordingVisualSearch(
                Array(recordingArgs.dropFirst(2)),
                command: "recording.visual.search",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if recordingArgs.count >= 2,
           recordingArgs[0] == "asset",
           (recordingArgs[1] == "extract" || recordingArgs[1] == "baseline") {
            let exitCode = try runRecordingAssetExtract(
                Array(recordingArgs.dropFirst(2)),
                command: recordingArgs[1] == "baseline" ? "recording.asset.baseline" : "recording.asset.extract",
                wantsJSON: wantsJSON,
                defaultKind: recordingArgs[1] == "baseline" ? .baseline : .imageTemplate
            )
            exit(Int32(exitCode))
        }

        if recordingArgs[0] == "suggest" {
            let exitCode = try runRecordingSuggest(
                Array(recordingArgs.dropFirst()),
                command: recordingCommandName(recordingArgs),
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        throw WorkflowCLIError(
            "unsupportedCommand",
            "Unsupported recording command '\(recordingArgs.joined(separator: " "))'."
        )
    } catch {
        let cliError = error as? WorkflowCLIError ?? WorkflowCLIError(
            "commandFailed",
            String(describing: error)
        )
        let envelope = AutomationCLIResultEnvelope<AutomationCLIEmptyPayload>.failure(
            command: command,
            code: cliError.code,
            message: cliError.message,
            path: cliError.path
        )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeWorkflowError("SparkleRecorder: \(cliError.message)")
        }
        exit(1)
    }
}

private func runSemanticRecordingDebugCLI(_ args: [String]) -> Never {
    let semanticArgs = Array(args.dropFirst(2))
    let wantsJSON = semanticArgs.contains("--json")
    let command = semanticRecordingCommandName(semanticArgs)

    do {
        guard !semanticArgs.isEmpty else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Expected a semantic-recording command, such as 'semantic-recording debug-smoke --json'."
            )
        }

        if semanticArgs[0] == "debug-smoke" {
            let exitCode = try runSemanticRecordingDebugSmoke(
                Array(semanticArgs.dropFirst()),
                command: "semantic-recording debug-smoke",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        throw WorkflowCLIError(
            "unsupportedCommand",
            "Unsupported semantic-recording command '\(semanticArgs.joined(separator: " "))'."
        )
    } catch {
        let cliError = error as? WorkflowCLIError ?? WorkflowCLIError(
            "commandFailed",
            String(describing: error)
        )
        let envelope = AutomationCLIResultEnvelope<AutomationCLIEmptyPayload>.failure(
            command: command,
            code: cliError.code,
            message: cliError.message,
            path: cliError.path
        )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeWorkflowError("SparkleRecorder: \(cliError.message)")
        }
        exit(1)
    }
}

private func runWorkflowCLI(_ args: [String]) -> Never {
    let workflowArgs = Array(args.dropFirst(2))
    let wantsJSON = workflowArgs.contains("--json")
    let command = workflowCommandName(workflowArgs)

    do {
        guard !workflowArgs.isEmpty else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Expected a workflow command, such as 'workflow draft validate <draft.json> --json'."
            )
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "product-evidence",
           workflowArgs[1] == "snapshot" {
            let exitCode = try runWorkflowProductEvidenceSnapshot(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow product-evidence snapshot",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "product-evidence",
           workflowArgs[1] == "audit" {
            let exitCode = try runWorkflowProductEvidenceAudit(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow product-evidence audit",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "product-evidence",
           workflowArgs[1] == "capture-plan" {
            let exitCode = try runWorkflowProductEvidenceCapturePlan(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow product-evidence capture-plan",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "product-evidence",
           workflowArgs[1] == "prepare-live-capture" {
            let exitCode = try runWorkflowProductEvidencePrepareLiveCapture(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow product-evidence prepare-live-capture",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "product-evidence",
           workflowArgs[1] == "complete-sidecar" {
            let exitCode = try runWorkflowProductEvidenceCompleteSidecar(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow product-evidence complete-sidecar",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "product-evidence",
           workflowArgs[1] == "sidecar-template" {
            let exitCode = try runWorkflowProductEvidenceSidecarTemplate(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow product-evidence sidecar-template",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "macros" {
            let exitCode = try runWorkflowMacros(
                Array(workflowArgs.dropFirst()),
                command: "workflow macros",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "list" {
            let exitCode = try runWorkflowList(
                Array(workflowArgs.dropFirst()),
                command: "workflow list",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "status" {
            let exitCode = try runWorkflowStatus(
                Array(workflowArgs.dropFirst()),
                command: "workflow status",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "run" {
            let exitCode = try runWorkflowRun(
                Array(workflowArgs.dropFirst()),
                command: "workflow run",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2,
           workflowArgs[0] == "acceptance",
           workflowArgs[1] == "bound-window" {
            let exitCode = try runWorkflowAcceptanceBoundWindow(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow acceptance bound-window",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "cancel" {
            let exitCode = try runWorkflowCancel(
                Array(workflowArgs.dropFirst()),
                command: "workflow cancel",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "runs" || workflowArgs[0] == "history" {
            let exitCode = try runWorkflowRuns(
                Array(workflowArgs.dropFirst()),
                command: workflowArgs[0] == "history" ? "workflow history" : "workflow runs",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 2, workflowArgs[0] == "handoff", workflowArgs[1] == "status" {
            let exitCode = try runWorkflowHandoffStatus(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow handoff status",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "show" {
            let exitCode = try runWorkflowShow(
                Array(workflowArgs.dropFirst()),
                command: "workflow show",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "export" {
            let exitCode = try runWorkflowExport(
                Array(workflowArgs.dropFirst()),
                command: "workflow export",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        guard workflowArgs.count >= 2 else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Unsupported workflow command '\(workflowArgs.joined(separator: " "))'."
            )
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "validate" {
            let exitCode = try runWorkflowDraftValidate(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft validate",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "simulate" {
            let exitCode = try runWorkflowDraftSimulate(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft simulate",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "init" {
            let exitCode = try runWorkflowDraftInit(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft init",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "inspect" {
            let exitCode = try runWorkflowDraftInspect(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft inspect",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "normalize" {
            let exitCode = try runWorkflowDraftNormalize(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft normalize",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "from-recording" {
            let exitCode = try runWorkflowDraftFromRecording(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft from-recording",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "draft", workflowArgs[1] == "patch" {
            let exitCode = try runWorkflowDraftPatch(
                Array(workflowArgs.dropFirst(2)),
                command: "workflow draft patch",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "task", workflowArgs[2] == "add" {
            let exitCode = try runWorkflowDraftTaskAdd(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft task add",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "task", workflowArgs[2] == "set" {
            let exitCode = try runWorkflowDraftTaskSet(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft task set",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "task", workflowArgs[2] == "remove" {
            let exitCode = try runWorkflowDraftTaskRemove(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft task remove",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "schedule", workflowArgs[2] == "set" {
            let exitCode = try runWorkflowDraftScheduleSet(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft schedule set",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "condition", workflowArgs[2] == "set" {
            let exitCode = try runWorkflowDraftConditionSet(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft condition set",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "dependency", workflowArgs[2] == "add" {
            let exitCode = try runWorkflowDraftDependencyAdd(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft dependency add",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "dependency", workflowArgs[2] == "set" {
            let exitCode = try runWorkflowDraftDependencySet(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft dependency set",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs.count >= 4, workflowArgs[0] == "draft", workflowArgs[1] == "dependency", workflowArgs[2] == "remove" {
            let exitCode = try runWorkflowDraftDependencyRemove(
                Array(workflowArgs.dropFirst(3)),
                command: "workflow draft dependency remove",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        if workflowArgs[0] == "import" {
            let exitCode = try runWorkflowImport(
                Array(workflowArgs.dropFirst()),
                command: "workflow import",
                wantsJSON: wantsJSON
            )
            exit(Int32(exitCode))
        }

        throw WorkflowCLIError(
            "unsupportedCommand",
            "Unsupported workflow command '\(workflowArgs.joined(separator: " "))'."
        )
    } catch {
        let cliError: WorkflowCLIError
        if let workflowError = error as? WorkflowCLIError {
            cliError = workflowError
        } else if let editError = error as? AutomationWorkflowDraftEditError {
            cliError = WorkflowCLIError(editError.code, editError.message, path: editError.path)
        } else {
            cliError = WorkflowCLIError(
                "commandFailed",
                String(describing: error)
            )
        }
        let envelope = AutomationCLIResultEnvelope<AutomationCLIEmptyPayload>.failure(
            command: command,
            code: cliError.code,
            message: cliError.message,
            path: cliError.path
        )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeWorkflowError("SparkleRecorder: \(cliError.message)")
        }
        exit(1)
    }
}

private func runWorkflowProductEvidenceSnapshot(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    guard let scenarioArgument = arguments.first,
          !scenarioArgument.hasPrefix("--") else {
        throw WorkflowCLIError(
            "missingArgument",
                "Expected a snapshot scenario: idle, drag-link-authoring, task-reorder-authoring, running, failed-run-detail, failed-run-preview-unavailable, visual-diagnostics-drill-in, branch-evidence, template-baseline-preview-refs, or semantic-review-timeline."
        )
    }

    guard let scenario = AutomationProductEvidenceSnapshotScenario(argument: scenarioArgument) else {
        throw WorkflowCLIError(
            "unsupportedScenario",
            "Unsupported product evidence snapshot scenario '\(scenarioArgument)'.",
            path: scenarioArgument
        )
    }

    var outputURL = URL(fileURLWithPath: "docs/workflow-page-productization/product-evidence")
        .appendingPathComponent(scenario.filename, isDirectory: false)
    var width: Double = 1440
    var height: Double = scenario.defaultHeight
    var scale: Double = 2
    var index = 1

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--output":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--output requires a file path.", path: token)
            }
            outputURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: false)
            index += 1
        case "--width":
            width = try parsePositiveDoubleOption(arguments, index: index, option: token)
            index += 1
        case "--height":
            height = try parsePositiveDoubleOption(arguments, index: index, option: token)
            index += 1
        case "--scale":
            scale = try parsePositiveDoubleOption(arguments, index: index, option: token)
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let resolvedOutputURL = outputURL.standardizedFileURL
    try MainActor.assumeIsolated {
        try AutomationProductEvidenceSnapshotRenderer.render(
            scenario: scenario,
            outputURL: resolvedOutputURL,
            width: CGFloat(width),
            height: CGFloat(height),
            scale: CGFloat(scale)
        )
    }

    let payload = WorkflowProductEvidenceSnapshotPayload(
        scenario: scenario.rawValue,
        outputPath: resolvedOutputURL.path,
        width: width,
        height: height,
        scale: scale
    )
    let envelope = AutomationCLIResultEnvelope<WorkflowProductEvidenceSnapshotPayload>(
        ok: true,
        command: command,
        data: payload
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        FileHandle.standardOutput.write(Data(
            "SparkleRecorder: wrote \(scenario.rawValue) product evidence snapshot -> \(resolvedOutputURL.path)\n".utf8
        ))
    }
    return 0
}

private func runWorkflowProductEvidenceAudit(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var directoryURL = URL(fileURLWithPath: AutomationProductEvidenceAudit.defaultDirectory, isDirectory: true)
    var requireLive = false
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--require-live":
            requireLive = true
        case "--directory":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--directory requires a path.", path: token)
            }
            directoryURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let resolvedDirectoryURL = directoryURL.standardizedFileURL
    let existingPaths = try productEvidenceExistingPaths(in: resolvedDirectoryURL)
    let fileByteCounts = try productEvidenceFileByteCounts(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let clipContainers = try productEvidenceClipContainers(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let sidecarContents = try productEvidenceSidecarContents(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let payload = AutomationProductEvidenceAudit.evaluate(
        directory: resolvedDirectoryURL.path,
        existingPaths: existingPaths,
        sidecarContents: sidecarContents,
        fileByteCounts: fileByteCounts,
        clipContainers: clipContainers
    )
    let missingMessages = payload.items
        .filter { $0.required && !$0.satisfied }
        .map { item in
            AutomationCLIMessage(
                code: "missingProductEvidence",
                message: "\(item.title) is not yet backed by the expected product-evidence files and sidecar content.",
                path: item.id
            )
        }
    let nextActions = [
        AutomationCLINextAction(
            command: "Record missing live artifacts and add same-name .md sidecars under docs/workflow-page-productization/product-evidence/",
            reason: "S0 live-product checklist items stay unchecked until real App evidence exists."
        ),
        AutomationCLINextAction(
            command: "SparkleRecorder workflow product-evidence audit --require-live --json",
            reason: "Use the strict audit gate before claiming S0 Workflow Evidence Closure."
        )
    ]
    let envelope = AutomationCLIResultEnvelope<AutomationProductEvidenceAuditPayload>(
        ok: !requireLive || payload.allRequiredPresent,
        command: command,
        data: payload,
        warnings: requireLive ? [] : missingMessages,
        errors: requireLive ? missingMessages : [],
        nextActions: payload.allRequiredPresent ? [] : nextActions
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        let summary = "SparkleRecorder: product evidence audit \(payload.satisfiedRequiredCount)/\(payload.requiredCount) required items present."
        FileHandle.standardOutput.write(Data((summary + "\n").utf8))
        if !payload.missingRequiredIDs.isEmpty {
            FileHandle.standardOutput.write(Data(("Missing required evidence: \(payload.missingRequiredIDs.joined(separator: ", "))\n").utf8))
        }
    }

    return requireLive && !payload.allRequiredPresent ? 1 : 0
}

private func runWorkflowProductEvidenceCapturePlan(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var directoryURL = URL(fileURLWithPath: AutomationProductEvidenceAudit.defaultDirectory, isDirectory: true)
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--directory":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--directory requires a path.", path: token)
            }
            directoryURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let resolvedDirectoryURL = directoryURL.standardizedFileURL
    let existingPaths = try productEvidenceExistingPaths(in: resolvedDirectoryURL)
    let fileByteCounts = try productEvidenceFileByteCounts(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let clipContainers = try productEvidenceClipContainers(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let sidecarContents = try productEvidenceSidecarContents(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let payload = AutomationProductEvidenceAudit.liveCapturePlan(
        directory: resolvedDirectoryURL.path,
        existingPaths: existingPaths,
        sidecarContents: sidecarContents,
        fileByteCounts: fileByteCounts,
        clipContainers: clipContainers
    )
    let warnings = payload.items
        .filter { !$0.satisfied }
        .map { item in
            AutomationCLIMessage(
                code: "missingLiveProductEvidence",
                message: "\(item.title) still needs a live clip and completed sidecar.",
                path: item.id
            )
        }
    let envelope = AutomationCLIResultEnvelope<AutomationProductEvidenceCapturePlanPayload>(
        ok: true,
        command: command,
        data: payload,
        warnings: warnings,
        nextActions: payload.allLiveSatisfied ? [
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "Run the strict gate before marking S0 complete."
            )
        ] : [
            AutomationCLINextAction(
                command: "Use sidecarTemplateCommand before recording, then sidecarCompletionCommand after saving the live clip.",
                reason: "The plan keeps preparation, reviewed metadata entry and strict completion separate."
            ),
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "Strict S0 audit must remain red until every live clip and sidecar is present."
            )
        ]
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        let summary = "SparkleRecorder: S0 live capture plan \(payload.missingLiveCount)/\(payload.items.count) live gates missing."
        FileHandle.standardOutput.write(Data((summary + "\n").utf8))
        for item in payload.items {
            let status = item.satisfied ? "satisfied" : "missing"
            FileHandle.standardOutput.write(Data(("\n- \(item.title) [\(status)]\n").utf8))
            FileHandle.standardOutput.write(Data(("  \(item.note)\n").utf8))
            for option in item.options {
                FileHandle.standardOutput.write(Data(("  option sidecar: \(option.sidecarPath)\n").utf8))
                FileHandle.standardOutput.write(Data(("    clips: \(option.clipPathCandidates.joined(separator: ", "))\n").utf8))
                FileHandle.standardOutput.write(Data(("    template: \(option.sidecarTemplateCommand)\n").utf8))
                FileHandle.standardOutput.write(Data(("    complete: \(option.sidecarCompletionCommand)\n").utf8))
                if !option.missingPaths.isEmpty {
                    FileHandle.standardOutput.write(Data(("    missing: \(option.missingPaths.joined(separator: ", "))\n").utf8))
                }
                if !option.undersizedPaths.isEmpty {
                    FileHandle.standardOutput.write(Data(("    undersized: \(option.undersizedPaths.joined(separator: ", "))\n").utf8))
                }
                if !option.invalidClipContainerPaths.isEmpty {
                    FileHandle.standardOutput.write(Data(("    invalid clip container: \(option.invalidClipContainerPaths.joined(separator: ", "))\n").utf8))
                }
                if !option.incompleteSidecarLabels.isEmpty {
                    FileHandle.standardOutput.write(Data(("    incomplete labels: \(option.incompleteSidecarLabels.joined(separator: ", "))\n").utf8))
                }
            }
        }
    }

    return 0
}

private func runWorkflowProductEvidencePrepareLiveCapture(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var directoryURL = URL(fileURLWithPath: AutomationProductEvidenceAudit.defaultDirectory, isDirectory: true)
    var includeSatisfied = false
    var overwrite = false
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--include-satisfied":
            includeSatisfied = true
        case "--overwrite":
            overwrite = true
        case "--directory":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--directory requires a path.", path: token)
            }
            directoryURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let resolvedDirectoryURL = directoryURL.standardizedFileURL
    try FileManager.default.createDirectory(
        at: resolvedDirectoryURL,
        withIntermediateDirectories: true
    )
    let existingPaths = try productEvidenceExistingPaths(in: resolvedDirectoryURL)
    let fileByteCounts = try productEvidenceFileByteCounts(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let clipContainers = try productEvidenceClipContainers(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let sidecarContents = try productEvidenceSidecarContents(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let draftsPayload = AutomationProductEvidenceAudit.liveSidecarDrafts(
        directory: resolvedDirectoryURL.path,
        existingPaths: existingPaths,
        sidecarContents: sidecarContents,
        fileByteCounts: fileByteCounts,
        clipContainers: clipContainers,
        includeSatisfied: includeSatisfied
    )

    var writtenCount = 0
    var overwrittenCount = 0
    var skippedExistingCount = 0
    var sidecars: [WorkflowProductEvidencePreparedSidecarPayload] = []

    for draft in draftsPayload.drafts {
        let sidecarURL = resolvedDirectoryURL.appendingPathComponent(
            draft.sidecarPath,
            isDirectory: false
        )
        let exists = FileManager.default.fileExists(atPath: sidecarURL.path)
        let action: String
        if exists && !overwrite {
            skippedExistingCount += 1
            action = "skippedExisting"
        } else {
            try draft.template.write(to: sidecarURL, atomically: true, encoding: .utf8)
            if exists {
                overwrittenCount += 1
                action = "overwritten"
            } else {
                writtenCount += 1
                action = "written"
            }
        }
        sidecars.append(WorkflowProductEvidencePreparedSidecarPayload(
            id: draft.id,
            title: draft.title,
            sidecarPath: draft.sidecarPath,
            clipPathCandidates: draft.clipPathCandidates,
            action: action
        ))
    }

    let payload = WorkflowProductEvidencePrepareLiveCapturePayload(
        directory: resolvedDirectoryURL.path,
        includeSatisfied: includeSatisfied,
        overwrite: overwrite,
        writtenCount: writtenCount,
        overwrittenCount: overwrittenCount,
        skippedExistingCount: skippedExistingCount,
        sidecars: sidecars
    )
    let envelope = AutomationCLIResultEnvelope<WorkflowProductEvidencePrepareLiveCapturePayload>(
        ok: true,
        command: command,
        data: payload,
        warnings: skippedExistingCount == 0 ? [] : [
            AutomationCLIMessage(
                code: "existingSidecarSkipped",
                message: "\(skippedExistingCount) sidecar draft(s) already existed and were left untouched.",
                path: resolvedDirectoryURL.path
            )
        ],
        nextActions: [
            AutomationCLINextAction(
                command: "Fill every sidecar placeholder, save the matching live .mov or .mp4 clip, then rerun capture-plan.",
                reason: "Prepared sidecars intentionally remain incomplete until a real App recording is reviewed."
            ),
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "Strict S0 audit must stay red until clips and completed sidecars exist."
            )
        ]
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        let summary = "SparkleRecorder: prepared \(writtenCount) S0 live sidecar draft(s), overwrote \(overwrittenCount), skipped \(skippedExistingCount)."
        FileHandle.standardOutput.write(Data((summary + "\n").utf8))
        for sidecar in sidecars {
            FileHandle.standardOutput.write(Data(
                "- \(sidecar.sidecarPath) [\(sidecar.action)] clips: \(sidecar.clipPathCandidates.joined(separator: ", "))\n".utf8
            ))
        }
        if sidecars.isEmpty {
            FileHandle.standardOutput.write(Data("No sidecar drafts were needed for the selected capture set.\n".utf8))
        }
    }

    return 0
}

private func runWorkflowProductEvidenceCompleteSidecar(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    guard let id = arguments.first,
          !id.hasPrefix("--") else {
        throw WorkflowCLIError(
            "missingArgument",
            "Expected a live product evidence id, such as 'live-visual-diagnostics-open-reveal'."
        )
    }

    var directoryURL = URL(fileURLWithPath: AutomationProductEvidenceAudit.defaultDirectory, isDirectory: true)
    var sidecarPath: String?
    var clipPath: String?
    var captureDate: String?
    var worktreeNote: String?
    var appBuildRunSource: String?
    var workflowPackage: String?
    var userAction: String?
    var knownGaps: String?
    var evidenceSource: String?
    var overwrite = false
    var index = 1

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--overwrite":
            overwrite = true
        case "--directory":
            directoryURL = URL(
                fileURLWithPath: try workflowCLIValue(after: token, in: arguments, at: &index),
                isDirectory: true
            )
        case "--sidecar":
            sidecarPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--clip":
            clipPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--capture-date":
            captureDate = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--worktree-note":
            worktreeNote = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--app-build":
            appBuildRunSource = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--workflow":
            workflowPackage = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--user-action":
            userAction = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--known-gaps":
            knownGaps = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--evidence-source":
            evidenceSource = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let completion = AutomationProductEvidenceSidecarCompletion(
        clipPath: try productEvidenceRequiredCompletionValue(clipPath, option: "--clip"),
        captureDate: try productEvidenceRequiredCompletionValue(captureDate, option: "--capture-date"),
        worktreeNote: try productEvidenceRequiredCompletionValue(worktreeNote, option: "--worktree-note"),
        appBuildRunSource: try productEvidenceRequiredCompletionValue(appBuildRunSource, option: "--app-build"),
        workflowPackage: try productEvidenceRequiredCompletionValue(workflowPackage, option: "--workflow"),
        userAction: try productEvidenceRequiredCompletionValue(userAction, option: "--user-action"),
        knownGaps: try productEvidenceRequiredCompletionValue(knownGaps, option: "--known-gaps"),
        evidenceSource: try productEvidenceRequiredCompletionValue(evidenceSource, option: "--evidence-source")
    )

    guard let completed = AutomationProductEvidenceAudit.completedLiveSidecar(
        id: id,
        sidecarPath: sidecarPath,
        completion: completion
    ) else {
        throw WorkflowCLIError(
            "unsupportedProductEvidence",
            "No live sidecar completion is defined for '\(id)' with clip '\(completion.clipPath)'. Use capture-plan for accepted filenames.",
            path: id
        )
    }

    let resolvedDirectoryURL = directoryURL.standardizedFileURL
    try FileManager.default.createDirectory(
        at: resolvedDirectoryURL,
        withIntermediateDirectories: true
    )
    let existingPaths = try productEvidenceExistingPaths(in: resolvedDirectoryURL)
    let existingByteCounts = try productEvidenceFileByteCounts(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let existingClipContainers = try productEvidenceClipContainers(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let existingSidecarContents = try productEvidenceSidecarContents(
        in: resolvedDirectoryURL,
        existingPaths: existingPaths
    )
    let existingPlan = AutomationProductEvidenceAudit.liveCapturePlan(
        directory: resolvedDirectoryURL.path,
        existingPaths: existingPaths,
        sidecarContents: existingSidecarContents,
        fileByteCounts: existingByteCounts,
        clipContainers: existingClipContainers
    )
    let existingOption = existingPlan.items
        .first { $0.id == completed.id }?
        .options
        .first { $0.sidecarPath == completed.sidecarPath }
    if existingPaths.contains(completed.sidecarPath),
       existingOption?.incompleteSidecarLabels.isEmpty == true,
       !overwrite {
        throw WorkflowCLIError(
            "sidecarAlreadyComplete",
            "\(completed.sidecarPath) already has all required labels. Pass --overwrite to replace it.",
            path: completed.sidecarPath
        )
    }

    let sidecarURL = resolvedDirectoryURL.appendingPathComponent(
        completed.sidecarPath,
        isDirectory: false
    )
    let existedBeforeWrite = FileManager.default.fileExists(atPath: sidecarURL.path)
    try completed.content.write(to: sidecarURL, atomically: true, encoding: .utf8)

    let refreshedPaths = try productEvidenceExistingPaths(in: resolvedDirectoryURL)
    let refreshedByteCounts = try productEvidenceFileByteCounts(
        in: resolvedDirectoryURL,
        existingPaths: refreshedPaths
    )
    let refreshedClipContainers = try productEvidenceClipContainers(
        in: resolvedDirectoryURL,
        existingPaths: refreshedPaths
    )
    let refreshedContents = try productEvidenceSidecarContents(
        in: resolvedDirectoryURL,
        existingPaths: refreshedPaths
    )
    let refreshedPlan = AutomationProductEvidenceAudit.liveCapturePlan(
        directory: resolvedDirectoryURL.path,
        existingPaths: refreshedPaths,
        sidecarContents: refreshedContents,
        fileByteCounts: refreshedByteCounts,
        clipContainers: refreshedClipContainers
    )
    let refreshedItem = refreshedPlan.items.first { $0.id == completed.id }
    let refreshedOption = refreshedItem?.options.first { $0.sidecarPath == completed.sidecarPath }
    let incompleteSidecarLabels = refreshedOption?.incompleteSidecarLabels ?? []
    let clipExists = refreshedPaths.contains(completed.clipPath)
    let clipMeetsMinimumByteCount = clipExists &&
        (refreshedByteCounts[completed.clipPath] ?? 0) >= AutomationProductEvidenceAudit.minimumLiveClipByteCount
    let clipHasSupportedContainer = refreshedClipContainers[completed.clipPath]?.isSupported == true
    let action = existedBeforeWrite ? (overwrite ? "overwritten" : "completedDraft") : "written"
    let payload = WorkflowProductEvidenceCompleteSidecarPayload(
        directory: resolvedDirectoryURL.path,
        id: completed.id,
        title: completed.title,
        sidecarPath: completed.sidecarPath,
        clipPath: completed.clipPath,
        clipExists: clipExists,
        clipMeetsMinimumByteCount: clipMeetsMinimumByteCount,
        clipHasSupportedContainer: clipHasSupportedContainer,
        action: action,
        sidecarCompleteAfterWrite: incompleteSidecarLabels.isEmpty,
        incompleteSidecarLabels: incompleteSidecarLabels,
        targetSatisfiedAfterWrite: refreshedItem?.satisfied == true
    )
    let warning: AutomationCLIMessage?
    if !payload.sidecarCompleteAfterWrite {
        warning = AutomationCLIMessage(
            code: "incompleteLiveSidecar",
            message: "\(completed.sidecarPath) still has incomplete or invalid live capture labels: \(payload.incompleteSidecarLabels.joined(separator: ", ")).",
            path: completed.sidecarPath
        )
    } else if !clipExists {
        warning = AutomationCLIMessage(
            code: "missingLiveClip",
            message: "\(completed.clipPath) is not present yet; the sidecar is complete but the live gate remains open.",
            path: completed.clipPath
        )
    } else if !clipMeetsMinimumByteCount {
        warning = AutomationCLIMessage(
            code: "undersizedLiveClip",
            message: "\(completed.clipPath) is present but empty or size-unknown; replace it with the real live recording.",
            path: completed.clipPath
        )
    } else if !clipHasSupportedContainer {
        warning = AutomationCLIMessage(
            code: "invalidLiveClipContainer",
            message: "\(completed.clipPath) is present but does not look like a supported .mov/.mp4 video container.",
            path: completed.clipPath
        )
    } else {
        warning = nil
    }
    let nextActions: [AutomationCLINextAction]
    if payload.targetSatisfiedAfterWrite {
        nextActions = [
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "This item now has a matching clip and completed sidecar; rerun the strict gate."
            )
        ]
    } else if !payload.sidecarCompleteAfterWrite {
        nextActions = [
            AutomationCLINextAction(
                command: "Review \(completed.sidecarPath), fix invalid labels, then rerun capture-plan.",
                reason: "S0 live sidecars must name one accepted clip, include worktree context, and identify a live recording source."
            ),
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "Strict S0 audit must stay red until every live gate is satisfied."
            )
        ]
    } else {
        nextActions = [
            AutomationCLINextAction(
                command: "Save or replace the live clip as \(completed.clipPath), then rerun capture-plan.",
                reason: "S0 live evidence requires both the completed sidecar and a non-empty supported .mov/.mp4 recording."
            ),
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "Strict S0 audit must stay red until every live gate is satisfied."
            )
        ]
    }
    let envelope = AutomationCLIResultEnvelope<WorkflowProductEvidenceCompleteSidecarPayload>(
        ok: true,
        command: command,
        data: payload,
        warnings: warning.map { [$0] } ?? [],
        nextActions: nextActions
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        FileHandle.standardOutput.write(Data("""
        SparkleRecorder: completed sidecar \(payload.sidecarPath) [\(payload.action)].
        - clip: \(payload.clipPath) \(payload.clipExists ? "present" : "missing")
        - clip non-empty: \(payload.clipMeetsMinimumByteCount ? "yes" : "no")
        - clip video container: \(payload.clipHasSupportedContainer ? "yes" : "no")
        - sidecar labels complete: \(payload.sidecarCompleteAfterWrite ? "yes" : "no")
        - incomplete labels: \(payload.incompleteSidecarLabels.isEmpty ? "none" : payload.incompleteSidecarLabels.joined(separator: ", "))
        - live gate satisfied: \(payload.targetSatisfiedAfterWrite ? "yes" : "no")

        """.utf8))
    }
    return 0
}

private func runWorkflowProductEvidenceSidecarTemplate(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    guard let id = arguments.first,
          !id.hasPrefix("--") else {
        throw WorkflowCLIError(
            "missingArgument",
            "Expected a live product evidence id, such as 'live-visual-diagnostics-open-reveal'."
        )
    }

    var sidecarPath: String?
    var index = 1
    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--sidecar":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--sidecar requires a .md filename.", path: token)
            }
            sidecarPath = arguments[index + 1]
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    guard let payload = AutomationProductEvidenceAudit.liveSidecarTemplate(
        id: id,
        sidecarPath: sidecarPath
    ) else {
        throw WorkflowCLIError(
            "unsupportedProductEvidence",
            "No live sidecar template is defined for '\(id)'.",
            path: id
        )
    }

    let envelope = AutomationCLIResultEnvelope<AutomationProductEvidenceSidecarTemplatePayload>(
        ok: true,
        command: command,
        data: payload,
        nextActions: [
            AutomationCLINextAction(
                command: "Save the filled sidecar next to the live clip, then run workflow product-evidence audit --require-live --json",
                reason: "Strict S0 audit requires the clip and sidecar fields before the gate can close."
            )
        ]
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        FileHandle.standardOutput.write(Data((payload.template + "\n").utf8))
    }
    return 0
}

private func productEvidenceExistingPaths(in directoryURL: URL) throws -> Set<String> {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return []
    }
    return Set(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path))
}

private func productEvidenceFileByteCounts(
    in directoryURL: URL,
    existingPaths: Set<String>
) throws -> [String: Int64] {
    var byteCounts: [String: Int64] = [:]
    for path in existingPaths {
        let url = directoryURL.appendingPathComponent(path, isDirectory: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            byteCounts[path] = size.int64Value
        }
    }
    return byteCounts
}

private func productEvidenceClipContainers(
    in directoryURL: URL,
    existingPaths: Set<String>
) throws -> [String: AutomationProductEvidenceClipContainer] {
    var containers: [String: AutomationProductEvidenceClipContainer] = [:]
    for path in existingPaths where path.hasSuffix(".mov") || path.hasSuffix(".mp4") {
        let url = directoryURL.appendingPathComponent(path, isDirectory: false)
        containers[path] = try productEvidenceClipContainer(at: url)
    }
    return containers
}

private func productEvidenceClipContainer(
    at url: URL
) throws -> AutomationProductEvidenceClipContainer {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
        try? handle.close()
    }
    let data = try handle.read(upToCount: 64) ?? Data()
    return productEvidenceClipContainer(from: data)
}

private func productEvidenceClipContainer(
    from data: Data
) -> AutomationProductEvidenceClipContainer {
    let bytes = Array(data)
    guard bytes.count >= 8 else {
        return .unsupported
    }
    let atomType = String(bytes: bytes[4..<8], encoding: .ascii) ?? ""
    if atomType == "ftyp" {
        return .isoBaseMedia
    }
    if ["moov", "mdat", "wide", "free"].contains(atomType) {
        return .isoBaseMedia
    }
    return .unsupported
}

private func productEvidenceSidecarContents(
    in directoryURL: URL,
    existingPaths: Set<String>
) throws -> [String: String] {
    var contents: [String: String] = [:]
    for path in existingPaths where path.hasSuffix(".md") {
        let url = directoryURL.appendingPathComponent(path, isDirectory: false)
        contents[path] = try String(contentsOf: url, encoding: .utf8)
    }
    return contents
}

private func productEvidenceRequiredCompletionValue(
    _ value: String?,
    option: String
) throws -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
        throw WorkflowCLIError("missingArgument", "\(option) requires a non-empty value.", path: option)
    }
    guard !trimmed.hasPrefix("<"), !trimmed.hasSuffix(">") else {
        throw WorkflowCLIError("placeholderValue", "\(option) must not be an angle-bracket placeholder.", path: option)
    }
    return trimmed
}

private func runRecordingShow(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    let recordingBundle = try loadRecordingCLIBundle(arguments)
    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload>
        .semanticRecordingShow(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingShowSummary(envelope.data)
    }
    return 0
}

private func runRecordingExplain(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    let recordingBundle = try loadRecordingCLIBundle(arguments)
    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIExplainPayload>
        .semanticRecordingExplain(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingExplainSummary(envelope.data)
    }
    return 0
}

private func runRecordingList(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var fixture: String?
    var recordingsRoot: URL?
    var index = 0
    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--fixture":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--fixture requires a fixture name.", path: token)
            }
            fixture = arguments[index + 1]
            index += 1
        case "--recordings-root":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--recordings-root requires a path.", path: token)
            }
            recordingsRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                .standardizedFileURL
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    switch (fixture, recordingsRoot) {
    case let (fixture?, nil):
        try validateRecordingCLIFixture(fixture)
        let entry = SemanticRecordingCLICatalogEntry(
            recordingID: SemanticRecordingFixture.recordingID,
            source: .fixture,
            fixture: fixture,
            manifestAvailable: true
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
            .semanticRecordingList(
                command: command,
                recordings: [entry],
                fixture: fixture
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeRecordingListSummary(envelope.data)
        }
        return 0
    case let (nil, recordingsRoot?):
        let store = RecordingBundleStore(rootDirectory: recordingsRoot)
        let catalog = try waitForWorkflowCLIAsync {
            try await store.listBundleCatalog()
        }
        let entries = catalog.map { entry in
            SemanticRecordingCLICatalogEntry(
                recordingID: entry.recordingID,
                source: .storedBundle,
                modifiedAt: entry.modifiedAt,
                manifestAvailable: true
            )
        }
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
            .semanticRecordingList(
                command: command,
                recordings: entries,
                recordingsRoot: recordingsRoot.path,
                sourceOption: recordingCLISourceOption("--recordings-root", url: recordingsRoot)
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeRecordingListSummary(envelope.data)
        }
        return 0
    case (.some, .some):
        throw WorkflowCLIError(
            "conflictingRecordingSource",
            "Use only one recording source: --fixture or --recordings-root.",
            path: "--recordings-root"
        )
    case (nil, nil):
        throw WorkflowCLIError(
            "missingArgument",
            "recording list requires --recordings-root <path> or --fixture checkout.",
            path: "--recordings-root"
        )
    }
}

private func runRecordingFrames(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    let recordingBundle = try loadRecordingCLIBundle(arguments)
    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
        .semanticRecordingFrames(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingFramesSummary(envelope.data)
    }
    return 0
}

private func runRecordingFrameShow(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var frameID: UUID?
    let recordingBundle = try loadRecordingCLIBundle(arguments) { token, index, arguments in
        switch token {
        case "--frame":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--frame requires a frame UUID.", path: token)
            }
            frameID = try parseWorkflowCLIUUID(arguments[index + 1], path: token)
            return 1
        default:
            return nil
        }
    }
    guard let frameID else {
        throw WorkflowCLIError("missingArgument", "recording frame show requires --frame <uuid>.", path: "--frame")
    }
    guard let frame = recordingBundle.bundle.frames.first(where: { $0.id == frameID }) else {
        throw WorkflowCLIError("unknownFrame", "Recording bundle does not contain frame '\(frameID.uuidString)'.", path: "--frame")
    }

    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
        .semanticRecordingFrameShow(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            frame: frame,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingFramesSummary(envelope.data)
    }
    return 0
}

private func runRecordingEventsNear(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var time: TimeInterval?
    var window: TimeInterval = 1.0
    let recordingBundle = try loadRecordingCLIBundle(arguments) { token, index, arguments in
        switch token {
        case "--time":
            guard index + 1 < arguments.count,
                  let parsedTime = TimeInterval(arguments[index + 1]),
                  parsedTime >= 0 else {
                throw WorkflowCLIError("invalidArgument", "--time requires a non-negative number of seconds.", path: token)
            }
            time = parsedTime
            return 1
        case "--window":
            guard index + 1 < arguments.count,
                  let parsedWindow = TimeInterval(arguments[index + 1]),
                  parsedWindow >= 0 else {
                throw WorkflowCLIError("invalidArgument", "--window requires a non-negative number of seconds.", path: token)
            }
            window = parsedWindow
            return 1
        default:
            return nil
        }
    }
    guard let time else {
        throw WorkflowCLIError("missingArgument", "recording events-near requires --time <seconds>.", path: "--time")
    }

    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIEventsNearPayload>
        .semanticRecordingEventsNear(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption,
            time: time,
            window: window
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingEventsNearSummary(envelope.data)
    }
    return 0
}

private func runRecordingOCRSearch(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var text: String?
    var matchMode: TextMatchMode = .contains
    let recordingBundle = try loadRecordingCLIBundle(arguments) { token, index, arguments in
        switch token {
        case "--text":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--text requires search text.", path: token)
            }
            text = arguments[index + 1]
            return 1
        case "--match":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--match requires contains or exact.", path: token)
            }
            matchMode = try parseWorkflowCLITextMatchMode(arguments[index + 1], path: token)
            return 1
        default:
            return nil
        }
    }
    let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedText.isEmpty else {
        throw WorkflowCLIError(
            "missingArgument",
            "recording ocr search requires --text <text>.",
            path: "--text"
        )
    }

    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIOCRSearchPayload>
        .semanticRecordingOCRSearch(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption,
            text: trimmedText,
            matchMode: matchMode,
            queryResults: recordingCLIQueryResults(for: recordingBundle)
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingOCRSearchSummary(envelope.data)
    }
    return 0
}

private func runRecordingVisualSearch(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var text: String?
    var matchMode: TextMatchMode = .contains
    var kind: RecordingVisualObservationKind?
    var label: String?
    let recordingBundle = try loadRecordingCLIBundle(arguments) { token, index, arguments in
        switch token {
        case "--text":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--text requires search text.", path: token)
            }
            text = arguments[index + 1]
            return 1
        case "--match":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--match requires contains or exact.", path: token)
            }
            matchMode = try parseWorkflowCLITextMatchMode(arguments[index + 1], path: token)
            return 1
        case "--kind":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--kind requires a visual observation kind.", path: token)
            }
            kind = try parseRecordingVisualObservationKind(arguments[index + 1], path: token)
            return 1
        case "--label":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--label requires a label.", path: token)
            }
            label = arguments[index + 1]
            return 1
        default:
            return nil
        }
    }

    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIVisualSearchPayload>
        .semanticRecordingVisualSearch(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption,
            text: text,
            matchMode: matchMode,
            kind: kind,
            label: label
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingVisualSearchSummary(envelope.data)
    }
    return 0
}

private func runRecordingAssetExtract(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool,
    defaultKind: SemanticRecordingCLIAssetExtractionKind
) throws -> Int {
    var frameID: UUID?
    var region: RecordingBounds?
    var regionSpace: RecordingCoordinateSpace = .framePixels
    var kind = defaultKind
    var name: String?
    var outputRoot: URL?
    var sourceRoot: URL?

    let recordingBundle = try loadRecordingCLIBundle(arguments) { token, index, arguments in
        switch token {
        case "--frame":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--frame requires a frame UUID.", path: token)
            }
            frameID = try parseWorkflowCLIUUID(arguments[index + 1], path: token)
            return 1
        case "--region":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--region requires x,y,width,height.", path: token)
            }
            region = try parseRecordingCLIRegion(arguments[index + 1], coordinateSpace: regionSpace, path: token)
            return 1
        case "--region-space":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--region-space requires a coordinate space.", path: token)
            }
            regionSpace = try parseRecordingCLIRegionSpace(arguments[index + 1], path: token)
            if let existingRegion = region {
                region = RecordingBounds(rect: existingRegion.rect, coordinateSpace: regionSpace)
            }
            return 1
        case "--kind":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--kind requires imageTemplate, image, or baseline.", path: token)
            }
            kind = try parseRecordingCLIAssetExtractionKind(arguments[index + 1], path: token)
            return 1
        case "--name":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--name requires an asset name.", path: token)
            }
            name = arguments[index + 1]
            return 1
        case "--output-root", "--assets-root":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a directory path.", path: token)
            }
            outputRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                .standardizedFileURL
            return 1
        case "--source-root", "--artifact-root":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a directory path.", path: token)
            }
            sourceRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                .standardizedFileURL
            return 1
        default:
            return nil
        }
    }

    guard let frameID else {
        throw WorkflowCLIError("missingArgument", "recording asset extract requires --frame <uuid>.", path: "--frame")
    }
    guard let region else {
        throw WorkflowCLIError("missingArgument", "recording asset extract requires --region x,y,width,height.", path: "--region")
    }
    let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedName.isEmpty else {
        throw WorkflowCLIError("missingArgument", "recording asset extract requires --name <asset-name>.", path: "--name")
    }
    guard let outputRoot else {
        throw WorkflowCLIError("missingArgument", "recording asset extract requires --output-root <draft-package-dir>.", path: "--output-root")
    }
    let bundle = recordingBundle.bundle
    guard let frame = bundle.frames.first(where: { $0.id == frameID }) else {
        throw WorkflowCLIError("unknownFrame", "Recording bundle does not contain frame '\(frameID.uuidString)'.", path: "--frame")
    }
    guard let sourceRoot = sourceRoot ?? recordingBundle.bundleDirectory else {
        throw WorkflowCLIError(
            "artifactRootRequired",
            "Fixture asset extraction requires --source-root <fixture-artifact-dir>; stored bundles use their bundle directory by default.",
            path: "--source-root"
        )
    }

    let sourceArtifactRef = bundle.redactedFrame(frameID: frame.id)?.redactedImageRef ?? frame.imageRef
    let sourceURL = try recordingCLIArtifactURL(
        ref: sourceArtifactRef,
        root: sourceRoot,
        optionPath: "--source-root"
    )
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        throw WorkflowCLIError(
            "missingSourceArtifact",
            "Source frame artifact '\(sourceArtifactRef.path)' was not found under '\(sourceRoot.path)'.",
            path: sourceArtifactRef.path
        )
    }

    let sourceImage = try recordingCLICGImage(at: sourceURL)
    let cropRect = try recordingCLICropRect(for: region, image: sourceImage)
    guard let croppedImage = sourceImage.cropping(to: cropRect) else {
        throw WorkflowCLIError("invalidRegion", "Could not crop the requested region from the source frame.", path: "--region")
    }
    let pngData = try recordingCLIPNGData(for: croppedImage)
    let digest = recordingCLISHA256(pngData)
    let assetKey = recordingCLIAssetKey(
        name: trimmedName,
        recordingID: bundle.id,
        kind: kind
    )
    let destinationPath = "assets/\(kind.materializedKind.directoryName)/\(assetKey).png"
    guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(destinationPath) == destinationPath else {
        throw WorkflowCLIError("unsafeDestinationPath", "Unsafe asset destination '\(destinationPath)'.", path: destinationPath)
    }
    let destinationURL = try recordingCLIOutputURL(
        root: outputRoot,
        relativePath: destinationPath,
        optionPath: "--output-root"
    )
    try FileManager.default.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: destinationURL, options: .atomic)

    let visualAsset = AutomationWorkflowDraftVisualImageAsset(
        key: assetKey,
        label: trimmedName,
        path: destinationPath,
        sha256: digest,
        sourceFrameID: frame.id,
        sourceSurfaceID: frame.surfaceID,
        sourceArtifactPath: sourceArtifactRef.path,
        sourceBounds: recordingCLIDraftRect(region.rect),
        sourceBoundsSpace: recordingCLIDraftRegionSpace(region.coordinateSpace)
    )
    let materializedAsset = SemanticRecordingReviewMaterializedAsset(
        kind: kind.materializedKind,
        key: assetKey,
        sourcePath: sourceArtifactRef.path,
        destinationPath: destinationPath,
        sha256: digest
    )
    let query = SemanticRecordingCLIAssetExtractionQuery(
        frameID: frame.id,
        region: region,
        kind: kind,
        name: trimmedName,
        assetKey: assetKey
    )
    let evidence = [
        RecordingEvidenceReference(
            frameID: frame.id,
            eventIDs: frame.relatedEventIDs,
            observationIDs: [],
            artifactRef: sourceArtifactRef,
            bounds: region,
            summary: "Frame region was extracted as a draft-compatible visual asset."
        )
    ]
    let payload = SemanticRecordingCLIAssetExtractionPayload(
        requestedRecordingID: recordingBundle.requestedRecordingID,
        recordingID: bundle.id,
        fixture: recordingBundle.fixture,
        query: query,
        sourceArtifactRef: sourceArtifactRef,
        outputRoot: outputRoot.path,
        materializedAsset: materializedAsset,
        visualAsset: visualAsset,
        evidence: evidence
    )
    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIAssetExtractionPayload>
        .semanticRecordingAssetExtraction(command: command, payload: payload)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingAssetExtractionSummary(envelope.data)
    }
    return 0
}

private func runRecordingSuggest(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    guard let categoryToken = arguments.first,
          !categoryToken.hasPrefix("--") else {
        throw WorkflowCLIError(
            "missingArgument",
            "recording suggest requires a category: waits, locators, conditions, cleanup, or all."
        )
    }
    guard let category = SemanticRecordingCLISuggestionCategory(rawValue: categoryToken) else {
        throw WorkflowCLIError(
            "unsupportedSuggestionCategory",
            "Unsupported suggestion category '\(categoryToken)'. Use waits, locators, conditions, cleanup, or all.",
            path: categoryToken
        )
    }

    let recordingBundle = try loadRecordingCLIBundle(Array(arguments.dropFirst()))
    let suggestionResult = recordingCLISuggestionResult(
        for: recordingBundle,
        category: category
    )
    let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>
        .semanticRecordingSuggestions(
            command: command,
            requestedRecordingID: recordingBundle.requestedRecordingID,
            bundle: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            sourceOption: recordingBundle.sourceOption,
            category: category,
            suggestionResult: suggestionResult
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeRecordingSuggestionsSummary(envelope.data)
    }
    return 0
}

private func loadRecordingCLIBundle(
    _ arguments: [String],
    additionalOptionHandler: ((String, Int, [String]) throws -> Int?)? = nil
) throws -> RecordingCLIBundle {
    guard let requestedRecordingID = arguments.first,
          !requestedRecordingID.hasPrefix("--") else {
        throw WorkflowCLIError(
            "missingArgument",
            "Expected a recording id, such as 'checkout-demo'."
        )
    }

    var fixture: String?
    var recordingsRoot: URL?
    var bundlePath: URL?
    var index = 1
    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--fixture":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--fixture requires a fixture name.", path: token)
            }
            fixture = arguments[index + 1]
            index += 1
        case "--recordings-root":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--recordings-root requires a path.", path: token)
            }
            recordingsRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                .standardizedFileURL
            index += 1
        case "--bundle-path", "--bundle-dir":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a path.", path: token)
            }
            bundlePath = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                .standardizedFileURL
            index += 1
        default:
            if let consumed = try additionalOptionHandler?(token, index, arguments) {
                index += consumed
            } else if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            } else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
        }
        index += 1
    }

    let sourceCount = [fixture != nil, recordingsRoot != nil, bundlePath != nil].filter { $0 }.count
    guard sourceCount == 1 else {
        if sourceCount == 0 {
            throw WorkflowCLIError(
                "missingArgument",
                "recording commands require --fixture checkout, --recordings-root <path>, or --bundle-path <path>.",
                path: "--recordings-root"
            )
        }
        throw WorkflowCLIError(
            "conflictingRecordingSource",
            "Use only one recording source: --fixture, --recordings-root, or --bundle-path.",
            path: "--recordings-root"
        )
    }

    if let fixture {
        try validateRecordingCLIFixture(fixture)
        try validateRecordingCLIFixtureRecordingID(requestedRecordingID)
        return RecordingCLIBundle(
            requestedRecordingID: requestedRecordingID,
            fixture: fixture,
            sourceOption: nil,
            bundleDirectory: nil,
            bundle: SemanticRecordingFixture.checkoutBundle()
        )
    }

    let requestedUUID = try parseWorkflowCLIUUID(requestedRecordingID, path: "recording-id")
    if let recordingsRoot {
        let store = RecordingBundleStore(rootDirectory: recordingsRoot)
        let bundle = try waitForWorkflowCLIAsync {
            try await store.loadBundle(recordingID: requestedUUID)
        }
        return RecordingCLIBundle(
            requestedRecordingID: requestedRecordingID,
            fixture: nil,
            sourceOption: recordingCLISourceOption("--recordings-root", url: recordingsRoot),
            bundleDirectory: recordingsRoot.appendingPathComponent(requestedUUID.uuidString, isDirectory: true),
            bundle: bundle
        )
    }

    guard let bundlePath else {
        throw WorkflowCLIError("missingArgument", "Missing recording source.", path: "recording-id")
    }
    let store = RecordingBundleStore(rootDirectory: bundlePath.deletingLastPathComponent())
    let bundle = try waitForWorkflowCLIAsync {
        try await store.loadBundle(from: bundlePath)
    }
    guard bundle.id == requestedUUID else {
        throw WorkflowCLIError(
            "recordingMismatch",
            "Bundle at '\(bundlePath.path)' contains recording '\(bundle.id.uuidString)', not '\(requestedUUID.uuidString)'.",
            path: "--bundle-path"
        )
    }
    return RecordingCLIBundle(
        requestedRecordingID: requestedRecordingID,
        fixture: nil,
        sourceOption: recordingCLISourceOption("--bundle-path", url: bundlePath),
        bundleDirectory: bundlePath,
        bundle: bundle
    )
}

private func validateRecordingCLIFixture(_ fixture: String) throws {
    guard fixture == "checkout" else {
        throw WorkflowCLIError(
            "unsupportedFixture",
            "Unsupported recording fixture '\(fixture)'. Use '--fixture checkout'.",
            path: fixture
        )
    }
}

private func validateRecordingCLIFixtureRecordingID(_ requestedRecordingID: String) throws {
    let acceptedRecordingIDs = Set([
        "checkout-demo",
        "recording-checkout-demo",
        SemanticRecordingFixture.recordingID.uuidString.lowercased()
    ])
    guard acceptedRecordingIDs.contains(requestedRecordingID.lowercased()) else {
        throw WorkflowCLIError(
            "unknownRecording",
            "Fixture 'checkout' exposes recording id 'checkout-demo'.",
            path: requestedRecordingID
        )
    }
}

private func recordingCLIQueryResults(for loadedBundle: RecordingCLIBundle) -> [RecordingQueryResult] {
    SemanticRecordingQueryEngine.deterministicQueryResults(
        for: loadedBundle.bundle,
        fixture: loadedBundle.fixture
    )
}

private func recordingCLISuggestionResult(
    for loadedBundle: RecordingCLIBundle,
    category: SemanticRecordingCLISuggestionCategory
) -> SemanticRecordingSuggestionResult {
    SemanticRecordingQueryEngine.deterministicSuggestions(
        for: loadedBundle.bundle,
        fixture: loadedBundle.fixture,
        query: .kinds(category.suggestionKinds)
    )
}

private func recordingCLISourceOption(_ option: String, url: URL) -> String {
    " \(option) \(workflowCLIShellQuote(url.path))"
}

private func recordingCLIArtifactURL(
    ref: RecordingArtifactRef,
    root: URL,
    optionPath: String
) throws -> URL {
    let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
    let artifactURL = root
        .appendingRecordingArtifactRef(ref)
        .standardizedFileURL
    let artifactPath = artifactURL.resolvingSymlinksInPath().path
    let rootPath = rootURL.path
    guard artifactPath == rootPath || artifactPath.hasPrefix(rootPath + "/") else {
        throw WorkflowCLIError(
            "unsafeSourceArtifactPath",
            "Artifact ref '\(ref.path)' escapes source root '\(root.path)'.",
            path: optionPath
        )
    }
    return artifactURL
}

private func recordingCLIOutputURL(
    root: URL,
    relativePath: String,
    optionPath: String
) throws -> URL {
    guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(relativePath) == relativePath else {
        throw WorkflowCLIError("unsafeDestinationPath", "Unsafe output asset path '\(relativePath)'.", path: relativePath)
    }
    let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
    let outputURL = relativePath
        .split(separator: "/")
        .map(String.init)
        .reduce(root.standardizedFileURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    let outputPath = outputURL.deletingLastPathComponent()
        .resolvingSymlinksInPath()
        .appendingPathComponent(outputURL.lastPathComponent)
        .path
    let rootPath = rootURL.path
    guard outputPath == rootPath || outputPath.hasPrefix(rootPath + "/") else {
        throw WorkflowCLIError(
            "unsafeOutputPath",
            "Output path '\(relativePath)' escapes output root '\(root.path)'.",
            path: optionPath
        )
    }
    return outputURL
}

private func recordingCLICGImage(at url: URL) throws -> CGImage {
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw WorkflowCLIError(
            "unreadableSourceImage",
            "Could not decode source frame image at '\(url.path)'.",
            path: url.path
        )
    }
    return cgImage
}

private func recordingCLICropRect(
    for bounds: RecordingBounds,
    image: CGImage
) throws -> CGRect {
    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let requested: CGRect
    switch bounds.coordinateSpace {
    case .normalizedFrame:
        requested = CGRect(
            x: CGFloat(bounds.rect.x * Double(image.width)),
            y: CGFloat(bounds.rect.y * Double(image.height)),
            width: CGFloat(bounds.rect.width * Double(image.width)),
            height: CGFloat(bounds.rect.height * Double(image.height))
        )
    case .screenPixels, .displayPixels, .windowPixels, .contentPixels, .framePixels:
        requested = CGRect(
            x: CGFloat(bounds.rect.x),
            y: CGFloat(bounds.rect.y),
            width: CGFloat(bounds.rect.width),
            height: CGFloat(bounds.rect.height)
        )
    }

    let clipped = requested.integral.intersection(imageBounds)
    guard !clipped.isNull,
          clipped.width >= 1,
          clipped.height >= 1 else {
        throw WorkflowCLIError(
            "regionOutsideFrame",
            "Requested region does not overlap the source frame.",
            path: "--region"
        )
    }
    return clipped
}

private func recordingCLIPNGData(for image: CGImage) throws -> Data {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw WorkflowCLIError("pngEncodingFailed", "Could not encode extracted asset as PNG.")
    }
    return data
}

private func recordingCLISHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func recordingCLIAssetKey(
    name: String,
    recordingID: UUID,
    kind: SemanticRecordingCLIAssetExtractionKind
) -> String {
    let suffix = kind == .baseline ? "baseline" : "template"
    return "sr_\(recordingCLIShortID(recordingID))_\(recordingCLISafeStem(name))_\(suffix)"
}

private func recordingCLIShortID(_ id: UUID) -> String {
    String(id.uuidString.prefix(8)).lowercased()
}

private func recordingCLISafeStem(_ value: String) -> String {
    let stem = value
        .lowercased()
        .map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        .reduce(into: "") { partial, character in
            if partial.last == "_" && character == "_" {
                return
            }
            partial.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return stem.isEmpty ? "asset" : stem
}

private func recordingCLIDraftRect(_ rect: RecordingRect) -> RectValue {
    RectValue(
        x: CGFloat(rect.x),
        y: CGFloat(rect.y),
        width: CGFloat(rect.width),
        height: CGFloat(rect.height)
    )
}

private func recordingCLIDraftRegionSpace(
    _ space: RecordingCoordinateSpace
) -> AutomationOCRSearchRegionSpace {
    switch space {
    case .screenPixels, .displayPixels, .framePixels:
        return .displayAbsolute
    case .windowPixels:
        return .windowLocal
    case .contentPixels:
        return .contentLocal
    case .normalizedFrame:
        return .displayNormalized
    }
}

private func workflowCLIShellQuote(_ value: String) -> String {
    let safeScalars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:-")
    guard !value.isEmpty else {
        return "''"
    }
    if value.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func writeRecordingListSummary(_ payload: SemanticRecordingCLIListPayload?) {
    guard let payload else {
        return
    }
    var lines = [
        "SparkleRecorder: semantic recordings [\(payload.fixtureMode ? "fixture" : "stored")].",
        "- recordings: \(payload.count)"
    ]
    for recording in payload.recordings {
        let modifiedAt = recording.modifiedAt.map(workflowCLIISO8601String) ?? "unknown"
        lines.append("- \(recording.recordingID.uuidString) source=\(recording.source.rawValue) modifiedAt=\(modifiedAt)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingShowSummary(_ payload: SemanticRecordingCLISummaryPayload?) {
    guard let payload else {
        return
    }
    let target = payload.captureTarget?.appName ?? payload.captureTarget?.appBundleIdentifier ?? "unknown app"
    let surface = payload.captureTarget?.surfaceID ?? "unknown surface"
    FileHandle.standardOutput.write(Data("""
    SparkleRecorder: semantic recording \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "live")].
    - recording: \(payload.recordingID.uuidString)
    - target: \(target) / \(surface)
    - video segments: \(payload.videoSegmentCount), frames: \(payload.frameCount), AI-safe events: \(payload.aiSafeEventCount)
    - visual observations: \(payload.visualObservationCount), OCR: \(payload.ocrObservationCount)
    - suppressions: \(payload.suppressionSummary.totalSuppressedCount)

    """.utf8))
}

private func writeRecordingExplainSummary(_ payload: SemanticRecordingCLIExplainPayload?) {
    guard let payload else {
        return
    }
    let target = payload.summary.captureTarget?.appName ??
        payload.summary.captureTarget?.appBundleIdentifier ??
        "unknown app"
    var lines = [
        "SparkleRecorder: semantic recording explanation \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "stored")].",
        "- recording: \(payload.recordingID.uuidString)",
        "- target: \(target)",
        "- key points: \(payload.keyPointCount), visual evidence: \(payload.visualEvidenceCount)"
    ]
    for point in payload.keyPoints.prefix(5) {
        let risk = point.risk.map { " risk=\($0)" } ?? ""
        lines.append("- \(point.kind.rawValue) t=\(point.recordingTime)s: \(point.title)\(risk)")
    }
    for note in payload.evidenceNotes {
        lines.append("- note: \(note)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingFramesSummary(_ payload: SemanticRecordingCLIFramesPayload?) {
    guard let payload else {
        return
    }
    var lines = [
        "SparkleRecorder: semantic recording frames \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "live")].",
        "- frames: \(payload.count)"
    ]
    for frame in payload.frames {
        lines.append(
            "- \(frame.id.uuidString) t=\(frame.recordingTime)s source=\(frame.source.rawValue) ref=\(frame.effectiveImageRef.path)"
        )
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingEventsNearSummary(_ payload: SemanticRecordingCLIEventsNearPayload?) {
    guard let payload else {
        return
    }
    var lines = [
        "SparkleRecorder: semantic recording events near \(payload.query.time)s +/- \(payload.query.window)s.",
        "- events: \(payload.eventCount), frames: \(payload.frameCount)"
    ]
    for event in payload.events {
        lines.append(
            "- \(event.id.uuidString) t=\(event.recordingTime)s kind=\(event.kind.rawValue) summary=\(event.summary ?? "")"
        )
    }
    for frame in payload.frames {
        lines.append(
            "- frame \(frame.id.uuidString) t=\(frame.recordingTime)s ref=\(frame.effectiveImageRef.path)"
        )
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingOCRSearchSummary(_ payload: SemanticRecordingCLIOCRSearchPayload?) {
    guard let payload else {
        return
    }
    var lines = [
        "SparkleRecorder: OCR search '\(payload.query.text)' [\(payload.fixtureMode ? "fixture" : "live")].",
        "- matches: \(payload.count)"
    ]
    for result in payload.results {
        let ref = result.artifactRef?.path ?? "no artifact ref"
        lines.append(
            "- \(result.observationID.uuidString) t=\(result.recordingTime)s text=\"\(result.text)\" ref=\(ref)"
        )
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingVisualSearchSummary(_ payload: SemanticRecordingCLIVisualSearchPayload?) {
    guard let payload else {
        return
    }
    let label = payload.query.label.map { " label='\($0)'" } ?? ""
    let kind = payload.query.kind.map { " kind=\($0.rawValue)" } ?? ""
    let text = payload.query.text.map { " text='\($0)'" } ?? ""
    var lines = [
        "SparkleRecorder: visual search\(kind)\(label)\(text) [\(payload.fixtureMode ? "fixture" : "live")].",
        "- matches: \(payload.count)"
    ]
    for result in payload.results {
        let ref = result.artifactRef?.path ?? "no artifact ref"
        lines.append(
            "- \(result.observationID.uuidString) t=\(result.recordingTime)s kind=\(result.kind.rawValue) ref=\(ref)"
        )
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingAssetExtractionSummary(_ payload: SemanticRecordingCLIAssetExtractionPayload?) {
    guard let payload else {
        return
    }
    let lines = [
        "SparkleRecorder: extracted \(payload.query.kind.rawValue) asset \(payload.query.assetKey) [\(payload.fixtureMode ? "fixture" : "stored")].",
        "- source: \(payload.sourceArtifactRef.path)",
        "- output: \(payload.materializedAsset.destinationPath)",
        "- sha256: \(payload.materializedAsset.sha256)"
    ]
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeRecordingSuggestionsSummary(_ payload: SemanticRecordingCLISuggestionsPayload?) {
    guard let payload else {
        return
    }
    var lines = [
        "SparkleRecorder: recording suggestions \(payload.category.rawValue) [\(payload.fixtureMode ? "fixture" : "live")].",
        "- suggestions: \(payload.count)"
    ]
    for suggestion in payload.suggestions {
        lines.append(
            "- \(suggestion.id.uuidString) \(suggestion.kind.rawValue) confidence=\(suggestion.confidence): \(suggestion.title)"
        )
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func runSemanticRecordingDebugSmoke(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var duration: TimeInterval = 1.0
    var recordingID = UUID()
    var rootDirectory: URL?
    var keyframesOnly = false
    var preflightOnly = false
    var displayID: UInt32?
    var windowID: UInt32?
    var appBundleIdentifier: String?
    var windowTitle: String?
    var evidenceSidecarURL: URL?
    var syntheticRedactionReason: RecordingSuppressionReason?
    var requiresOCRReadiness = false
    var requiresWindowOrAXReadiness = false
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--duration":
            duration = try parsePositiveDoubleOption(arguments, index: index, option: token)
            index += 1
        case "--recording-id":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--recording-id requires a UUID.", path: token)
            }
            recordingID = try parseWorkflowCLIUUID(arguments[index + 1], path: token)
            index += 1
        case "--root-directory":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--root-directory requires a path.", path: token)
            }
            rootDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            index += 1
        case "--keyframes-only":
            keyframesOnly = true
        case "--preflight-only":
            preflightOnly = true
        case "--require-ocr":
            requiresOCRReadiness = true
        case "--require-window-or-ax":
            requiresWindowOrAXReadiness = true
        case "--display-id":
            guard index + 1 < arguments.count,
                  let parsedDisplayID = UInt32(arguments[index + 1]) else {
                throw WorkflowCLIError("invalidArgument", "--display-id requires a UInt32 display ID.", path: token)
            }
            displayID = parsedDisplayID
            index += 1
        case "--window-id":
            guard index + 1 < arguments.count,
                  let parsedWindowID = UInt32(arguments[index + 1]) else {
                throw WorkflowCLIError("invalidArgument", "--window-id requires a UInt32 window ID.", path: token)
            }
            windowID = parsedWindowID
            index += 1
        case "--app-bundle-id":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--app-bundle-id requires a bundle identifier.", path: token)
            }
            appBundleIdentifier = arguments[index + 1]
            index += 1
        case "--window-title":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--window-title requires a title.", path: token)
            }
            windowTitle = arguments[index + 1]
            index += 1
        case "--evidence-sidecar":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--evidence-sidecar requires a path.", path: token)
            }
            evidenceSidecarURL = URL(fileURLWithPath: arguments[index + 1])
            index += 1
        case "--synthetic-redaction":
            syntheticRedactionReason = syntheticRedactionReason ?? .privateRegion
        case "--synthetic-redaction-reason":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--synthetic-redaction-reason requires a suppression reason.", path: token)
            }
            guard let reason = RecordingSuppressionReason(rawValue: arguments[index + 1]),
                  reason.redactsSemanticEvidence else {
                throw WorkflowCLIError(
                    "invalidArgument",
                    "--synthetic-redaction-reason requires a redacting suppression reason.",
                    path: arguments[index + 1]
                )
            }
            syntheticRedactionReason = reason
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let target = semanticRecordingDebugSmokeTarget(
        displayID: displayID,
        windowID: windowID,
        appBundleIdentifier: appBundleIdentifier,
        windowTitle: windowTitle
    )
    let policy = RecordingCapturePolicy(
        mode: keyframesOnly ? .keyframesOnly : .videoAndKeyframes
    )
    let readinessPolicy = SemanticRecordingBundleReadinessPolicy(
        capturePolicy: policy,
        requiresOCRObservations: requiresOCRReadiness,
        requiresWindowOrAXObservations: requiresWindowOrAXReadiness
    )
    let resolvedRecordingID = recordingID
    let resolvedDuration = duration
    let resolvedRootDirectory = rootDirectory
    let resolvedPreflightOnly = preflightOnly
    let resolvedSyntheticRedactionReason = syntheticRedactionReason
    let resolvedReadinessPolicy = readinessPolicy
    let commandPlan = semanticRecordingDebugSmokeCommandPlan(arguments)

    var payload = try waitForWorkflowCLIAsync {
        try await semanticRecordingDebugSmokePayload(
            recordingID: resolvedRecordingID,
            duration: resolvedDuration,
            capturePolicy: policy,
            captureTarget: target,
            rootDirectory: resolvedRootDirectory,
            preflightOnly: resolvedPreflightOnly,
            syntheticRedactionReason: resolvedSyntheticRedactionReason,
            readinessPolicy: resolvedReadinessPolicy
        )
    }
    payload.commandPlan = commandPlan
    if let evidenceSidecarURL {
        payload.evidenceSidecarPath = evidenceSidecarURL.path
        try writeSemanticRecordingDebugSmokeEvidenceSidecar(
            payload,
            command: semanticRecordingDebugSmokeCommandLine(arguments),
            to: evidenceSidecarURL
        )
    }
    let envelope = AutomationCLIResultEnvelope<SemanticRecordingDebugSmokePayload>(
        ok: payload.status != .blocked,
        command: command,
        data: payload,
        warnings: semanticRecordingDebugSmokeMessages(
            from: payload.preflight.degradedIssues
        ),
        errors: payload.status == .blocked
            ? semanticRecordingDebugSmokeMessages(from: payload.preflight.blockingIssues)
            : [],
        nextActions: semanticRecordingDebugSmokeNextActions(payload)
    )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeSemanticRecordingDebugSmokeSummary(payload)
    }
    return payload.status == .blocked ? 2 : 0
}

private func semanticRecordingDebugSmokePayload(
    recordingID: UUID,
    duration: TimeInterval,
    capturePolicy: RecordingCapturePolicy,
    captureTarget: RecordingCaptureTarget,
    rootDirectory: URL?,
    preflightOnly: Bool,
    syntheticRedactionReason: RecordingSuppressionReason? = nil,
    readinessPolicy: SemanticRecordingBundleReadinessPolicy,
    preflightClient: SemanticRecordingPreflightClient = .liveCommandLine
) async throws -> SemanticRecordingDebugSmokePayload {
    let preflightPolicy = SemanticRecordingPreflightPolicy(capturePolicy: capturePolicy)
    if preflightOnly {
        let preflight = await preflightClient.evaluate(policy: preflightPolicy)
        return SemanticRecordingDebugSmokePayload(
            status: preflight.isReadyToStart ? .preflightReady : .blocked,
            recordingID: recordingID,
            commandPlan: nil,
            capturePolicy: capturePolicy,
            captureTarget: captureTarget,
            preflight: preflight,
            preflightPresentation: SemanticRecordingPreflightPresenter.presentation(for: preflight),
            bundleDirectory: nil,
            manifestPath: nil,
            evidenceSidecarPath: nil,
            videoSegmentCount: 0,
            frameCount: 0,
            timelineEventCount: 0,
            aiSafeEventCount: 0,
            visualObservationCount: 0,
            suppressionCount: 0,
            syntheticSuppressionCount: 0,
            syntheticRedactionReason: syntheticRedactionReason,
            bundleReadinessPolicy: readinessPolicy,
            bundleReadinessStatus: nil,
            bundleReadinessIssueCount: 0,
            bundleReadinessBlockingIssueCount: 0,
            bundleReadinessDegradedIssueCount: 0,
            bundleReadinessIssues: [],
            bundleReadinessFollowUps: [],
            redactedFrameCount: 0,
            redactedFrameIndexPath: nil,
            redactedVideoCount: 0,
            redactedVideoIndexPath: nil,
            pendingVideoRangeRedactionCount: 0,
            persistedBundleLoad: nil,
            persistedBundleCountCheck: .none
        )
    }

    let store = rootDirectory.map { RecordingBundleStore(rootDirectory: $0) } ?? RecordingBundleStore()
    let configuration = SemanticRecordingCaptureConfiguration(
        recordingID: recordingID,
        createdAt: Date.now,
        capturePolicy: capturePolicy,
        captureTarget: captureTarget,
        defaultSurfaceID: captureTarget.surfaceID ?? "semantic-debug-smoke"
    )
    let session = LiveSemanticRecordingSession(
        configuration: configuration,
        dependencies: LiveSemanticRecordingSessionDependencies(
            store: store,
            preflightClient: preflightClient
        )
    )

    let start = try await session.start(recordingTime: 0)
    guard case .started(let preflight, _) = start else {
        return SemanticRecordingDebugSmokePayload(
            status: .blocked,
            recordingID: recordingID,
            commandPlan: nil,
            capturePolicy: capturePolicy,
            captureTarget: captureTarget,
            preflight: start.preflight,
            preflightPresentation: SemanticRecordingPreflightPresenter.presentation(for: start.preflight),
            bundleDirectory: nil,
            manifestPath: nil,
            evidenceSidecarPath: nil,
            videoSegmentCount: 0,
            frameCount: 0,
            timelineEventCount: 0,
            aiSafeEventCount: 0,
            visualObservationCount: 0,
            suppressionCount: 0,
            syntheticSuppressionCount: 0,
            syntheticRedactionReason: syntheticRedactionReason,
            bundleReadinessPolicy: readinessPolicy,
            bundleReadinessStatus: nil,
            bundleReadinessIssueCount: 0,
            bundleReadinessBlockingIssueCount: 0,
            bundleReadinessDegradedIssueCount: 0,
            bundleReadinessIssues: [],
            bundleReadinessFollowUps: [],
            redactedFrameCount: 0,
            redactedFrameIndexPath: nil,
            redactedVideoCount: 0,
            redactedVideoIndexPath: nil,
            pendingVideoRangeRedactionCount: 0,
            persistedBundleLoad: nil,
            persistedBundleCountCheck: .none
        )
    }

    let eventTime = max(0.05, min(duration * 0.5, duration))
    try await semanticRecordingDebugSmokeSleep(seconds: eventTime)
    try await session.record(
        semanticRecordingDebugSmokeEvent(
            time: eventTime,
            captureTarget: captureTarget
        ),
        index: 0
    )
    var syntheticSuppressionCount = 0
    if let syntheticRedactionReason {
        let suppression = SemanticRecordingDebugSmokeSyntheticRedaction(
            reason: syntheticRedactionReason,
            eventTime: eventTime,
            totalDuration: duration,
            target: captureTarget
        )
        try await session.addSuppression(suppression.suppressionRecord)
        syntheticSuppressionCount = 1
    }
    try await semanticRecordingDebugSmokeSleep(seconds: max(0, duration - eventTime))

    let finish = try await session.finish(recordingTime: duration)
    let persistedBundleLoadResult = try await store.loadBundleTolerant(from: finish.bundleDirectory)
    let persistedBundleLoad = SemanticRecordingDebugSmokePersistedBundleLoadEvidence(
        loadResult: persistedBundleLoadResult
    )
    let readiness = SemanticRecordingBundleReadiness.evaluate(
        persistedBundleLoadResult.bundle,
        policy: readinessPolicy
    )
    let readinessFollowUps = semanticRecordingDebugSmokeReadinessFollowUps(readiness)
    let persistedBundleCountCheck = SemanticRecordingDebugSmokePersistedBundleCountCheck.evaluate(
        videoSegmentCount: finish.bundle.videoSegments.count,
        frameCount: finish.bundle.frames.count,
        timelineEventCount: finish.bundle.timelineEvents.count,
        aiSafeEventCount: finish.bundle.aiSafeEvents.count,
        visualObservationCount: finish.bundle.visualObservations.count,
        suppressionCount: finish.bundle.suppressions.count,
        redactedFrameCount: finish.redactionResult?.renderedFrameRelativePaths.count ?? 0,
        redactedVideoCount: finish.redactionResult?.renderedVideoRelativePaths.count ?? 0,
        persistedBundleLoad: persistedBundleLoad
    )
    return SemanticRecordingDebugSmokePayload(
        status: .finished,
        recordingID: recordingID,
        commandPlan: nil,
        capturePolicy: capturePolicy,
        captureTarget: captureTarget,
        preflight: preflight,
        preflightPresentation: SemanticRecordingPreflightPresenter.presentation(for: preflight),
        bundleDirectory: finish.bundleDirectory.path,
        manifestPath: finish.bundleDirectory
            .appendingPathComponent(SemanticRecordingSchema.manifestFileName)
            .path,
        evidenceSidecarPath: nil,
        videoSegmentCount: finish.bundle.videoSegments.count,
        frameCount: finish.bundle.frames.count,
        timelineEventCount: finish.bundle.timelineEvents.count,
        aiSafeEventCount: finish.bundle.aiSafeEvents.count,
        visualObservationCount: finish.bundle.visualObservations.count,
        suppressionCount: finish.bundle.suppressions.count,
        syntheticSuppressionCount: syntheticSuppressionCount,
        syntheticRedactionReason: syntheticRedactionReason,
        bundleReadinessPolicy: readinessPolicy,
        bundleReadinessStatus: readiness.status,
        bundleReadinessIssueCount: readiness.issues.count,
        bundleReadinessBlockingIssueCount: readiness.blockingIssueCount,
        bundleReadinessDegradedIssueCount: readiness.degradedIssueCount,
        bundleReadinessIssues: readiness.issues,
        bundleReadinessFollowUps: readinessFollowUps,
        redactedFrameCount: finish.redactionResult?.renderedFrameRelativePaths.count ?? 0,
        redactedFrameIndexPath: semanticRecordingDebugSmokeRedactedFrameIndexPath(
            finish.redactionResult,
            bundleDirectory: finish.bundleDirectory
        ),
        redactedVideoCount: finish.redactionResult?.renderedVideoRelativePaths.count ?? 0,
        redactedVideoIndexPath: semanticRecordingDebugSmokeRedactedVideoIndexPath(
            finish.redactionResult,
            bundleDirectory: finish.bundleDirectory
        ),
        pendingVideoRangeRedactionCount: finish.redactionResult?.pendingVideoRangeRedactions.count ?? 0,
        persistedBundleLoad: persistedBundleLoad,
        persistedBundleCountCheck: persistedBundleCountCheck
    )
}

private func semanticRecordingDebugSmokeRedactedFrameIndexPath(
    _ result: RecordingBundleRedactionApplicationResult?,
    bundleDirectory: URL
) -> String? {
    guard let result,
          let ref = try? RecordingArtifactRef(result.frameIndexRelativePath) else {
        return nil
    }
    return bundleDirectory.appendingRecordingArtifactRef(ref).path
}

private func semanticRecordingDebugSmokeRedactedVideoIndexPath(
    _ result: RecordingBundleRedactionApplicationResult?,
    bundleDirectory: URL
) -> String? {
    guard let result,
          let ref = try? RecordingArtifactRef(result.videoIndexRelativePath) else {
        return nil
    }
    return bundleDirectory.appendingRecordingArtifactRef(ref).path
}

private func writeSemanticRecordingDebugSmokeEvidenceSidecar(
    _ payload: SemanticRecordingDebugSmokePayload,
    command: String,
    to url: URL
) throws {
    let input = SemanticRecordingDebugSmokeEvidenceInput(
        status: payload.status.rawValue,
        command: command,
        commandPlan: payload.commandPlan,
        generatedAt: Date(),
        recordingID: payload.recordingID,
        capturePolicy: payload.capturePolicy,
        captureTarget: payload.captureTarget,
        preflight: payload.preflight,
        bundleDirectory: payload.bundleDirectory,
        manifestPath: payload.manifestPath,
        evidenceSidecarPath: payload.evidenceSidecarPath,
        videoSegmentCount: payload.videoSegmentCount,
        frameCount: payload.frameCount,
        timelineEventCount: payload.timelineEventCount,
        aiSafeEventCount: payload.aiSafeEventCount,
        visualObservationCount: payload.visualObservationCount,
        suppressionCount: payload.suppressionCount,
        syntheticSuppressionCount: payload.syntheticSuppressionCount,
        syntheticRedactionReason: payload.syntheticRedactionReason,
        bundleReadinessPolicy: payload.bundleReadinessPolicy,
        bundleReadinessStatus: payload.bundleReadinessStatus,
        bundleReadinessIssueCount: payload.bundleReadinessIssueCount,
        bundleReadinessBlockingIssueCount: payload.bundleReadinessBlockingIssueCount,
        bundleReadinessDegradedIssueCount: payload.bundleReadinessDegradedIssueCount,
        bundleReadinessIssues: payload.bundleReadinessIssues,
        bundleReadinessFollowUps: payload.bundleReadinessFollowUps,
        redactedFrameCount: payload.redactedFrameCount,
        redactedFrameIndexPath: payload.redactedFrameIndexPath,
        redactedVideoCount: payload.redactedVideoCount,
        redactedVideoIndexPath: payload.redactedVideoIndexPath,
        pendingVideoRangeRedactionCount: payload.pendingVideoRangeRedactionCount,
        persistedBundleLoad: payload.persistedBundleLoad
    )
    let parent = url.deletingLastPathComponent()
    if !parent.path.isEmpty {
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }
    try SemanticRecordingDebugSmokeEvidenceSidecar
        .markdown(for: input)
        .write(to: url, atomically: true, encoding: .utf8)
}

private func semanticRecordingDebugSmokeCommandLine(
    _ arguments: [String]
) -> String {
    (["semantic-recording", "debug-smoke"] + arguments)
        .map(shellQuoted)
        .joined(separator: " ")
}

private func semanticRecordingDebugSmokeCommandPlan(
    _ arguments: [String]
) -> SemanticRecordingDebugSmokeCommandPlan {
    SemanticRecordingDebugSmokeCommandPlan(
        invocationCommand: semanticRecordingDebugSmokeCommandLine(arguments),
        preflightCommand: semanticRecordingDebugSmokeCommandLine(
            semanticRecordingDebugSmokeArguments(
                arguments,
                settingPreflightOnly: true
            )
        ),
        liveCaptureCommand: semanticRecordingDebugSmokeCommandLine(
            semanticRecordingDebugSmokeArguments(
                arguments,
                settingPreflightOnly: false
            )
        )
    )
}

private func semanticRecordingDebugSmokeArguments(
    _ arguments: [String],
    settingPreflightOnly enabled: Bool
) -> [String] {
    var updated = arguments.filter { $0 != "--preflight-only" }
    if enabled {
        updated.append("--preflight-only")
    }
    return updated
}

private func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty,
          value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          !value.contains("'") else {
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    return value
}

private func semanticRecordingDebugSmokeTarget(
    displayID: UInt32?,
    windowID: UInt32?,
    appBundleIdentifier: String?,
    windowTitle: String?
) -> RecordingCaptureTarget {
    let isWindowTarget = windowID != nil ||
        appBundleIdentifier?.isEmpty == false ||
        windowTitle?.isEmpty == false
    return RecordingCaptureTarget(
        kind: isWindowTarget ? .window : .display,
        surfaceID: isWindowTarget ? "semantic-debug-window" : "semantic-debug-display",
        displayID: displayID,
        windowID: windowID,
        appBundleIdentifier: appBundleIdentifier,
        windowTitle: windowTitle
    )
}

private func semanticRecordingDebugSmokeEvent(
    time: TimeInterval,
    captureTarget: RecordingCaptureTarget
) -> RecordedEvent {
    RecordedEvent(
        kind: .leftMouseUp,
        time: time,
        x: 1,
        y: 1,
        keyCode: 0,
        flags: 0,
        mouseButton: 0,
        clickCount: 1,
        scrollDeltaY: 0,
        scrollDeltaX: 0,
        surfaceId: captureTarget.surfaceID ?? "semantic-debug-smoke"
    )
}

private func semanticRecordingDebugSmokeSleep(seconds: TimeInterval) async throws {
    let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
    guard nanoseconds > 0 else { return }
    try await Task.sleep(nanoseconds: nanoseconds)
}

private func semanticRecordingDebugSmokeMessages(
    from issues: [SemanticRecordingPreflightIssue]
) -> [AutomationCLIMessage] {
    issues.map { issue in
        AutomationCLIMessage(
            code: issue.severity.rawValue,
            message: issue.message,
            path: issue.permission.rawValue
        )
    }
}

private func semanticRecordingDebugSmokeNextActions(
    _ payload: SemanticRecordingDebugSmokePayload
) -> [AutomationCLINextAction] {
    switch payload.status {
    case .finished:
        var actions = [
            AutomationCLINextAction(
                command: "Open the manifest path printed by this command and inspect video/segments.json plus frames/index.jsonl.",
                reason: "This smoke path proves live S2 capture wrote a semantic recording bundle, but it is not product evidence by itself."
            )
        ]
        actions += payload.bundleReadinessFollowUps.map { followUp in
            AutomationCLINextAction(
                command: followUp,
                reason: "Bundle readiness reported a missing or degraded S2 evidence requirement."
            )
        }
        if payload.persistedBundleLoad?.degraded == true {
            actions.append(
                AutomationCLINextAction(
                    command: "Inspect the persisted bundle failed sidecars in the debug-smoke JSON or evidence sidecar, then rerun semantic-recording debug-smoke after repairing the capture path.",
                    reason: "The bundle was written, but at least one persisted sidecar could not be decoded during the post-write reload audit."
                )
            )
        }
        if payload.persistedBundleCountCheck.status == .mismatched {
            actions.append(
                AutomationCLINextAction(
                    command: "Compare persistedBundleCountCheck.mismatches with manifest and sidecar writers before using this bundle as live S2 product evidence.",
                    reason: "The in-memory finish result and the just-reloaded bundle disagree on persisted evidence counts: \(payload.persistedBundleCountCheck.summary)."
                )
            )
        }
        return actions
    case .preflightReady:
        return [
            AutomationCLINextAction(
                command: payload.commandPlan?.liveCaptureCommand ??
                    "semantic-recording debug-smoke --json",
                reason: "Preflight-only mode proves S2 capture readiness without creating a bundle or touching ScreenCaptureKit."
            )
        ]
    case .blocked:
        return [
            AutomationCLINextAction(
                command: "Grant Input Monitoring and Screen Recording permissions, then rerun semantic-recording debug-smoke --json.",
                reason: "S2 capture is blocked before bundle creation when required permissions are missing."
            ),
            AutomationCLINextAction(
                command: payload.commandPlan?.preflightCommand ??
                    "semantic-recording debug-smoke --preflight-only --json",
                reason: "Use the same target/root/readiness options to verify preflight again before attempting live capture."
            )
        ]
    }
}

private func writeSemanticRecordingDebugSmokeSummary(
    _ payload: SemanticRecordingDebugSmokePayload
) {
    switch payload.status {
    case .finished:
        FileHandle.standardOutput.write(Data("""
        SparkleRecorder: semantic recording debug smoke finished.
        - bundle: \(payload.bundleDirectory ?? "(missing)")
        - manifest: \(payload.manifestPath ?? "(missing)")
        - evidence sidecar: \(payload.evidenceSidecarPath ?? "(not written)")
        - video segments: \(payload.videoSegmentCount)
        - frames: \(payload.frameCount)
        - timeline events: \(payload.timelineEventCount)
        - AI-safe events: \(payload.aiSafeEventCount)
        - suppressions: \(payload.suppressionCount)
        - synthetic suppressions: \(payload.syntheticSuppressionCount)
        - synthetic redaction reason: \(payload.syntheticRedactionReason?.rawValue ?? "none")
        - preflight guidance: \(payload.preflightPresentation.status.rawValue) - \(payload.preflightPresentation.title)
        - preflight primary action: \(semanticRecordingDebugSmokePreflightActionSummary(payload.preflightPresentation.primaryAction))
        - bundle readiness policy: \(semanticRecordingDebugSmokeReadinessPolicySummary(payload.bundleReadinessPolicy))
        - bundle readiness: \(payload.bundleReadinessStatus?.rawValue ?? "none")
        - bundle readiness issues: \(payload.bundleReadinessIssueCount) (blocking: \(payload.bundleReadinessBlockingIssueCount), degraded: \(payload.bundleReadinessDegradedIssueCount))
        - bundle readiness issue codes: \(semanticRecordingDebugSmokeReadinessIssueCodes(payload.bundleReadinessIssues))
        - bundle readiness follow-up: \(semanticRecordingDebugSmokeReadinessFollowUpSummary(payload.bundleReadinessFollowUps))
        - persisted bundle reload: \(semanticRecordingDebugSmokePersistedBundleReloadSummary(payload.persistedBundleLoad))
        - persisted bundle counts: \(semanticRecordingDebugSmokePersistedBundleCountSummary(payload.persistedBundleLoad))
        - persisted bundle count match: \(payload.persistedBundleCountCheck.summary)
        - persisted bundle loaded sidecars: \(semanticRecordingDebugSmokeSidecarKindSummary(payload.persistedBundleLoad?.sidecarDiagnostics.loadedKinds ?? []))
        - persisted bundle missing sidecars: \(semanticRecordingDebugSmokeSidecarKindSummary(payload.persistedBundleLoad?.sidecarDiagnostics.missingKinds ?? []))
        - persisted bundle failed sidecars: \(semanticRecordingDebugSmokeFailedSidecarSummary(payload.persistedBundleLoad?.sidecarDiagnostics.failedIssues ?? []))
        - redacted frames: \(payload.redactedFrameCount)
        - redacted videos: \(payload.redactedVideoCount)
        - pending video redactions: \(payload.pendingVideoRangeRedactionCount)

        """.utf8))
    case .preflightReady:
        let degraded = payload.preflight.degradedIssues
            .map { "- \($0.permission.rawValue): \($0.message)" }
            .joined(separator: "\n")
        let degradedText = degraded.isEmpty ? "- none" : degraded
        FileHandle.standardOutput.write(Data("""
        SparkleRecorder: semantic recording debug smoke preflight ready.
        - evidence sidecar: \(payload.evidenceSidecarPath ?? "(not written)")
        - synthetic redaction reason: \(payload.syntheticRedactionReason?.rawValue ?? "none")
        - preflight guidance: \(payload.preflightPresentation.status.rawValue) - \(payload.preflightPresentation.title)
        - preflight primary action: \(semanticRecordingDebugSmokePreflightActionSummary(payload.preflightPresentation.primaryAction))
        - degraded issues:
        \(degradedText)

        """.utf8))
    case .blocked:
        let issues = payload.preflight.blockingIssues
            .map { "- \($0.permission.rawValue): \($0.message)" }
            .joined(separator: "\n")
        FileHandle.standardOutput.write(Data("""
        SparkleRecorder: semantic recording debug smoke blocked by preflight.
        - evidence sidecar: \(payload.evidenceSidecarPath ?? "(not written)")
        - synthetic redaction reason: \(payload.syntheticRedactionReason?.rawValue ?? "none")
        - preflight guidance: \(payload.preflightPresentation.status.rawValue) - \(payload.preflightPresentation.title)
        - preflight primary action: \(semanticRecordingDebugSmokePreflightActionSummary(payload.preflightPresentation.primaryAction))
        \(issues)

        """.utf8))
    }
}

private func semanticRecordingDebugSmokeReadinessIssueCodes(
    _ issues: [SemanticRecordingBundleReadinessIssue]
) -> String {
    guard !issues.isEmpty else {
        return "none"
    }
    return issues
        .map { "\($0.code.rawValue):\($0.severity.rawValue)" }
        .joined(separator: ", ")
}

private func semanticRecordingDebugSmokePreflightActionSummary(
    _ action: SemanticRecordingPreflightPresentationAction
) -> String {
    [
        "kind=\(action.kind.rawValue)",
        "label=\(action.label)",
        "permission=\(action.permission?.rawValue ?? "none")"
    ].joined(separator: " ")
}

private func semanticRecordingDebugSmokeReadinessFollowUps(
    _ readiness: SemanticRecordingBundleReadiness
) -> [String] {
    let codes = readiness.issues.map(\.code)
    var followUps: [String] = []

    func add(_ followUp: String) {
        guard !followUps.contains(followUp) else { return }
        followUps.append(followUp)
    }

    if codes.contains(.missingVideoSegment) ||
        codes.contains(.frameMissingVideoSegment) ||
        codes.contains(.frameMissingVideoTime) {
        add("Rerun semantic-recording debug-smoke without --keyframes-only and inspect video/segments.json plus frames/index.jsonl.")
    }
    if codes.contains(.missingKeyframe) ||
        codes.contains(.timelineEventMissingFrame) ||
        codes.contains(.semanticEventMissingFrame) {
        add("Inspect frames/index.jsonl and timeline.jsonl; verify event-aligned keyframes are written around recorded events.")
    }
    if codes.contains(.missingTimelineEvent) ||
        codes.contains(.missingAISafeEvent) {
        add("Inspect timeline.jsonl and events.jsonl; verify the recorder emitted playable events before finish.")
    }
    if codes.contains(.missingOCRObservation) {
        add("Rerun on a safe text-bearing target with Screen Recording allowed, then inspect ocr/observations.jsonl.")
    }
    if codes.contains(.missingWindowOrAXObservation) {
        add("Grant Accessibility and target a real window with --window-id or --app-bundle-id, then inspect window/AX observations.")
    }
    if codes.contains(.redactingSuppressionMissingFrameRedaction) ||
        codes.contains(.redactingSuppressionMissingVideoRedaction) {
        add("Inspect redacted/frames/index.json and redacted/video/index.json; rerun with --synthetic-redaction on safe content if the redaction renderer needs rehearsal.")
    }
    if codes.contains(.redactingSuppressionHasNoVisualEvidence) {
        add("Inspect suppressed.jsonl, frames/index.jsonl and video/segments.json; verify the sensitive suppression overlaps captured visual evidence.")
    }
    if codes.contains(.invalidBundle) {
        add("Run recording show with the finished bundle path and inspect manifest plus sidecar reference consistency.")
    }

    return followUps
}

private func semanticRecordingDebugSmokeReadinessFollowUpSummary(
    _ followUps: [String]
) -> String {
    guard !followUps.isEmpty else {
        return "none"
    }
    return followUps.joined(separator: " | ")
}

private func semanticRecordingDebugSmokePersistedBundleReloadSummary(
    _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
) -> String {
    guard let evidence else {
        return "none"
    }
    return evidence.degraded ? "degraded" : "loaded"
}

private func semanticRecordingDebugSmokePersistedBundleCountSummary(
    _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
) -> String {
    guard let evidence else {
        return "none"
    }
    return [
        "video=\(evidence.videoSegmentCount)",
        "frames=\(evidence.frameCount)",
        "timeline=\(evidence.timelineEventCount)",
        "aiSafe=\(evidence.aiSafeEventCount)",
        "observations=\(evidence.visualObservationCount)",
        "suppressions=\(evidence.suppressionCount)",
        "redactedFrames=\(evidence.redactedFrameCount)",
        "redactedVideos=\(evidence.redactedVideoCount)"
    ].joined(separator: ", ")
}

private func semanticRecordingDebugSmokeSidecarKindSummary(
    _ kinds: [SemanticRecordingBundleSidecarKind]
) -> String {
    guard !kinds.isEmpty else {
        return "none"
    }
    return kinds
        .map(\.rawValue)
        .joined(separator: ", ")
}

private func semanticRecordingDebugSmokeFailedSidecarSummary(
    _ issues: [SemanticRecordingBundleSidecarLoadIssue]
) -> String {
    guard !issues.isEmpty else {
        return "none"
    }
    return issues
        .map { issue in
            "\(issue.kind.rawValue)=failed path=\(issue.relativePath) fallback=\(issue.fallbackToManifest)"
        }
        .joined(separator: " | ")
}

private func semanticRecordingDebugSmokeReadinessPolicySummary(
    _ policy: SemanticRecordingBundleReadinessPolicy
) -> String {
    [
        "video=\(policy.requiresVideoSegments)",
        "keyframes=\(policy.requiresEventAlignedKeyframes)",
        "timeline=\(policy.requiresTimelineEvents)",
        "aiSafe=\(policy.requiresAISafeEvents)",
        "ocr=\(policy.requiresOCRObservations)",
        "windowOrAX=\(policy.requiresWindowOrAXObservations)",
        "redactions=\(policy.requiresRedactionSidecars)"
    ].joined(separator: ", ")
}

private func parsePositiveDoubleOption(
    _ arguments: [String],
    index: Int,
    option: String
) throws -> Double {
    guard index + 1 < arguments.count else {
        throw WorkflowCLIError("missingArgument", "\(option) requires a positive numeric value.", path: option)
    }
    guard let value = Double(arguments[index + 1]),
          value > 0 else {
        throw WorkflowCLIError("invalidArgument", "\(option) requires a positive numeric value.", path: option)
    }
    return value
}

private func runWorkflowMacros(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var search: String?
    var macrosDirectory: URL?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--search":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--search requires a value.", path: token)
            }
            search = arguments[index + 1]
            index += 1
        case "--macros-dir":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--macros-dir requires a directory path.", path: token)
            }
            macrosDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let manifests = try loadWorkflowMacroManifests(macrosDirectory: macrosDirectory)
    let entries = manifests
        .map(AutomationWorkflowDraftMacroCatalogEntry.init(macro:))
        .filter { $0.matches(searchTerm: search) }
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>
        .workflowMacroCatalog(
            command: command,
            macros: entries,
            search: search?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowMacroSummary(entries)
    }
    return 0
}

private func runWorkflowList(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var repositoryDirectoryPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let snapshot = try waitForWorkflowCLIAsync {
        let workflows = try await repository.loadWorkflows()
        let runHistory = try await repository.loadRunHistory()
        return (workflows, runHistory)
    }
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowListPayload>
        .workflowList(
            command: command,
            workflows: snapshot.0,
            runHistory: snapshot.1
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowListSummary(envelope.data?.workflows ?? [])
    }
    return 0
}

private func runWorkflowStatus(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var workflowID: UUID?
    var repositoryDirectoryPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--workflow-id":
            workflowID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard workflowID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            workflowID = try parseWorkflowCLIUUID(token, path: "workflow-id")
        }
        index += 1
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let snapshot = try waitForWorkflowCLIAsync {
        let workflows = try await repository.loadWorkflows()
        let runHistory = try await repository.loadRunHistory()
        return (workflows, runHistory)
    }

    let workflows: [AutomationWorkflow]
    if let workflowID {
        guard let workflow = snapshot.0.first(where: { $0.id == workflowID }) else {
            throw WorkflowCLIError(
                "workflowNotFound",
                "Workflow '\(workflowID.uuidString)' was not found.",
                path: "workflow-id"
            )
        }
        workflows = [workflow]
    } else {
        workflows = snapshot.0
    }

    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowStatusPayload>
        .workflowStatus(
            command: command,
            workflows: workflows,
            runHistory: snapshot.1
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowStatusSummary(envelope.data)
    }
    return 0
}

private enum WorkflowCLIPlayerMode: String {
    case live
    case fakeSuccess
    case reject
}

private func runWorkflowRun(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var workflowID: UUID?
    var taskSelector: String?
    var repositoryDirectoryPath: String?
    var macrosDirectoryPath: String?
    var requestedAt = Date.now
    var waitTimeout: TimeInterval = 3_600
    var playerMode = WorkflowCLIPlayerMode.live
    var shouldHandoffToAppHost = false
    var isConfirmed = false
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--confirm", "--yes":
            isConfirmed = true
        case "--workflow-id":
            workflowID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--task":
            taskSelector = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macros-dir":
            macrosDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--handoff-app":
            shouldHandoffToAppHost = true
        case "--handoff":
            let value = try workflowCLIValue(after: token, in: arguments, at: &index)
            guard value == "app" || value == "appHost" else {
                throw WorkflowCLIError(
                    "unsupportedHandoffTarget",
                    "--handoff must be 'app'.",
                    path: token
                )
            }
            shouldHandoffToAppHost = true
        case "--at":
            requestedAt = try parseWorkflowCLIDate(workflowCLIValue(after: token, in: arguments, at: &index))
        case "--wait-timeout", "--timeout":
            waitTimeout = try parseWorkflowCLIDuration(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--player-mode":
            let value = try workflowCLIValue(after: token, in: arguments, at: &index)
            guard let mode = WorkflowCLIPlayerMode(rawValue: value) else {
                throw WorkflowCLIError(
                    "unsupportedPlayerMode",
                    "--player-mode must be live, fakeSuccess, or reject.",
                    path: token
                )
            }
            playerMode = mode
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard workflowID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            workflowID = try parseWorkflowCLIUUID(token, path: "workflow-id")
        }
        index += 1
    }

    guard isConfirmed else {
        throw WorkflowCLIError(
            "confirmationRequired",
            "workflow run can move mouse or keyboard input and requires --confirm.",
            path: "--confirm"
        )
    }
    guard let workflowID else {
        throw WorkflowCLIError("missingArgument", "workflow run requires a workflow ID.")
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let handoffClient = workflowCLIRuntimeHandoffClient(directoryPath: repositoryDirectoryPath)
    if shouldHandoffToAppHost {
        let handoffTaskSelector = taskSelector
        let handoffRequestedAt = requestedAt
        let payload = try waitForWorkflowCLIAsync {
            try await enqueueWorkflowRunHandoff(
                workflowID: workflowID,
                taskSelector: handoffTaskSelector,
                repository: repository,
                handoffClient: handoffClient,
                requestedAt: handoffRequestedAt
            )
        }
        let envelope = AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload>
            .workflowHandoff(command: command, payload: payload)

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeWorkflowHandoffSummary(payload)
        }
        return envelope.ok ? 0 : 1
    }

    let macrosDirectory = macrosDirectoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    let selectedTaskSelector = taskSelector
    let runRequestedAt = requestedAt
    let runWaitTimeout = waitTimeout
    let runPlayerMode = playerMode
    let payload = try waitForWorkflowCLIAsync {
        try await runWorkflowRuntimeControl(
            workflowID: workflowID,
            taskSelector: selectedTaskSelector,
            repository: repository,
            macrosDirectory: macrosDirectory,
            requestedAt: runRequestedAt,
            waitTimeout: runWaitTimeout,
            playerMode: runPlayerMode
        )
    }
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowRunPayload>
        .workflowRun(command: command, payload: payload)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowRunSummary(payload)
    }
    return envelope.ok ? 0 : 1
}

private func runWorkflowAcceptanceBoundWindow(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var workflowID: UUID?
    var taskSelector: String?
    var repositoryDirectoryPath: String?
    var macrosDirectoryPath: String?
    var shouldActivateTarget = false
    var shouldLaunchTarget = false
    var shouldConfirmPlayback = false
    var shouldHandoffToAppHost = false
    var requestedAt = Date.now
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--workflow-id":
            workflowID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--task":
            taskSelector = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macros-dir":
            macrosDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--activate-target":
            shouldActivateTarget = true
        case "--confirm-launch":
            shouldLaunchTarget = true
            shouldActivateTarget = true
        case "--confirm-playback":
            shouldConfirmPlayback = true
        case "--handoff-app":
            shouldHandoffToAppHost = true
        case "--handoff":
            let value = try workflowCLIValue(after: token, in: arguments, at: &index)
            guard value == "app" || value == "appHost" else {
                throw WorkflowCLIError(
                    "unsupportedHandoffTarget",
                    "--handoff must be 'app'.",
                    path: token
                )
            }
            shouldHandoffToAppHost = true
        case "--at":
            requestedAt = try parseWorkflowCLIDate(workflowCLIValue(after: token, in: arguments, at: &index))
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard workflowID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            workflowID = try parseWorkflowCLIUUID(token, path: "workflow-id")
        }
        index += 1
    }

    guard let workflowID else {
        throw WorkflowCLIError(
            "missingArgument",
            "workflow acceptance bound-window requires a workflow ID.",
            path: "workflow-id"
        )
    }
    if shouldConfirmPlayback, !shouldHandoffToAppHost {
        throw WorkflowCLIError(
            "handoffRequired",
            "Live bound-window workflow playback must use --handoff app so the running App host owns Player lifecycle.",
            path: "--handoff"
        )
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let macrosDirectory = macrosDirectoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    let handoffClient = workflowCLIRuntimeHandoffClient(directoryPath: repositoryDirectoryPath)
    let requestedPlaybackAt = requestedAt
    let selectedTaskSelector = taskSelector
    let activateTarget = shouldActivateTarget
    let launchTarget = shouldLaunchTarget
    let confirmPlayback = shouldConfirmPlayback
    let payload = try waitForWorkflowCLIAsync {
        try await runWorkflowBoundWindowAcceptance(
            workflowID: workflowID,
            taskSelector: selectedTaskSelector,
            repository: repository,
            macrosDirectory: macrosDirectory,
            handoffClient: handoffClient,
            activateTarget: activateTarget,
            launchTarget: launchTarget,
            confirmPlayback: confirmPlayback,
            requestedAt: requestedPlaybackAt
        )
    }
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowBoundWindowAcceptancePayload>
        .workflowBoundWindowAcceptance(command: command, payload: payload)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowBoundWindowAcceptanceSummary(payload)
    }
    return envelope.ok ? 0 : 1
}

private func runWorkflowCancel(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var runID: UUID?
    var repositoryDirectoryPath: String?
    var requestedAt = Date.now
    var shouldHandoffToAppHost = false
    var isConfirmed = false
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--confirm", "--yes":
            isConfirmed = true
        case "--run-id":
            runID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--handoff-app":
            shouldHandoffToAppHost = true
        case "--handoff":
            let value = try workflowCLIValue(after: token, in: arguments, at: &index)
            guard value == "app" || value == "appHost" else {
                throw WorkflowCLIError(
                    "unsupportedHandoffTarget",
                    "--handoff must be 'app'.",
                    path: token
                )
            }
            shouldHandoffToAppHost = true
        case "--at":
            requestedAt = try parseWorkflowCLIDate(workflowCLIValue(after: token, in: arguments, at: &index))
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard runID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            runID = try parseWorkflowCLIUUID(token, path: "run-id")
        }
        index += 1
    }

    guard isConfirmed else {
        throw WorkflowCLIError(
            "confirmationRequired",
            "workflow cancel changes runtime state and requires --confirm.",
            path: "--confirm"
        )
    }
    guard let runID else {
        throw WorkflowCLIError("missingArgument", "workflow cancel requires a run ID.")
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let handoffClient = workflowCLIRuntimeHandoffClient(directoryPath: repositoryDirectoryPath)
    if shouldHandoffToAppHost {
        let handoffRequestedAt = requestedAt
        let payload = try waitForWorkflowCLIAsync {
            try await enqueueWorkflowCancelHandoff(
                runID: runID,
                repository: repository,
                handoffClient: handoffClient,
                requestedAt: handoffRequestedAt
            )
        }
        let envelope = AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload>
            .workflowHandoff(command: command, payload: payload)

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeWorkflowHandoffSummary(payload)
        }
        return envelope.ok ? 0 : 1
    }

    let cancelRequestedAt = requestedAt
    let payload = try waitForWorkflowCLIAsync {
        try await cancelWorkflowRun(
            runID: runID,
            repository: repository,
            requestedAt: cancelRequestedAt
        )
    }
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowCancelPayload>
        .workflowCancel(command: command, payload: payload)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowCancelSummary(payload)
    }
    return envelope.ok ? 0 : 1
}

private func runWorkflowHandoffStatus(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var commandID: UUID?
    var repositoryDirectoryPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--command-id":
            commandID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard commandID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            commandID = try parseWorkflowCLIUUID(token, path: "command-id")
        }
        index += 1
    }

    guard let commandID else {
        throw WorkflowCLIError("missingArgument", "workflow handoff status requires a command ID.")
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let handoffClient = workflowCLIRuntimeHandoffClient(directoryPath: repositoryDirectoryPath)
    let payload = try waitForWorkflowCLIAsync {
        try await loadWorkflowHandoffStatus(
            commandID: commandID,
            handoffClient: handoffClient,
            repository: repository,
            checkedAt: Date.now
        )
    }
    let envelope = AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload>
        .workflowHandoffStatus(command: command, payload: payload)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowHandoffStatusSummary(payload)
    }
    return envelope.ok ? 0 : 1
}

private func runWorkflowRuns(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var workflowID: UUID?
    var repositoryDirectoryPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--workflow-id":
            workflowID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard workflowID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            workflowID = try parseWorkflowCLIUUID(token, path: "workflow-id")
        }
        index += 1
    }

    guard let workflowID else {
        throw WorkflowCLIError("missingArgument", "\(command) requires a workflow ID.")
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let snapshot = try waitForWorkflowCLIAsync {
        let workflows = try await repository.loadWorkflows()
        let runHistory = try await repository.loadRunHistory()
        return (workflows, runHistory)
    }
    guard let workflow = snapshot.0.first(where: { $0.id == workflowID }) else {
        throw WorkflowCLIError(
            "workflowNotFound",
            "Workflow '\(workflowID.uuidString)' was not found.",
            path: "workflow-id"
        )
    }

    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowRunsPayload>
        .workflowRuns(command: command, workflow: workflow, runHistory: snapshot.1)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowRunsSummary(envelope.data)
    }
    return 0
}

private func runWorkflowShow(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var workflowID: UUID?
    var repositoryDirectoryPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--workflow-id":
            workflowID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard workflowID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            workflowID = try parseWorkflowCLIUUID(token, path: "workflow-id")
        }
        index += 1
    }

    guard let workflowID else {
        throw WorkflowCLIError("missingArgument", "workflow show requires a workflow ID.")
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let snapshot = try waitForWorkflowCLIAsync {
        let workflows = try await repository.loadWorkflows()
        let runHistory = try await repository.loadRunHistory()
        return (workflows, runHistory)
    }
    guard let workflow = snapshot.0.first(where: { $0.id == workflowID }) else {
        throw WorkflowCLIError(
            "workflowNotFound",
            "Workflow '\(workflowID.uuidString)' was not found.",
            path: "workflow-id"
        )
    }

    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowShowPayload>
        .workflowShow(
            command: command,
            workflow: workflow,
            runHistory: snapshot.1
        )

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowShowSummary(envelope.data)
    }
    return 0
}

private func runWorkflowExport(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var workflowID: UUID?
    var repositoryDirectoryPath: String?
    var macroCatalogPath: String?
    var outPath: String?
    var format = "draft-json"
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--workflow-id":
            workflowID = try parseWorkflowCLIUUID(
                workflowCLIValue(after: token, in: arguments, at: &index),
                path: token
            )
        case "--repository-dir":
            repositoryDirectoryPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--format":
            format = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard workflowID == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            workflowID = try parseWorkflowCLIUUID(token, path: "workflow-id")
        }
        index += 1
    }

    guard format == "draft-json" else {
        throw WorkflowCLIError(
            "unsupportedFormat",
            "workflow export currently supports --format draft-json.",
            path: "--format"
        )
    }
    guard let workflowID else {
        throw WorkflowCLIError("missingArgument", "workflow export requires a workflow ID.")
    }

    let repository = workflowCLIRepository(directoryPath: repositoryDirectoryPath)
    let workflows = try waitForWorkflowCLIAsync {
        try await repository.loadWorkflows()
    }
    guard let workflow = workflows.first(where: { $0.id == workflowID }) else {
        throw WorkflowCLIError(
            "workflowNotFound",
            "Workflow '\(workflowID.uuidString)' was not found.",
            path: "workflow-id"
        )
    }

    let macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]
    if let macroCatalogPath {
        let data = try readWorkflowCLIFile(at: macroCatalogPath)
        macroCatalog = try decodeWorkflowMacroCatalog(from: data)
    } else {
        macroCatalog = []
    }
    let result = AutomationWorkflowDraftExporter.export(
        workflow,
        options: AutomationWorkflowDraftExportOptions(macroCatalog: macroCatalog)
    )
    if let outPath {
        let data = try encodeWorkflowCLIJSON(result.document)
        try writeWorkflowCLIFile(data, to: outPath)
    }

    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload>
        .workflowDraftExport(command: command, result: result, wrotePath: outPath)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowExportSummary(result, wrotePath: outPath)
    }
    return result.isExportable ? 0 : 1
}

private func runWorkflowDraftInit(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var name: String?
    var outPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--name":
            name = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
        }
        index += 1
    }

    guard let name else {
        throw WorkflowCLIError("missingArgument", "workflow draft init requires --name.", path: "--name")
    }

    let result = try AutomationWorkflowDraftEditor.makeDocument(name: name)
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftInspect(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var macroCatalogPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft inspect")
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = AutomationWorkflowDraftEditor.inspect(document, context: context)
    return try finishWorkflowDraftEdit(
        result,
        outPath: nil,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftNormalize(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var outPath: String?
    var macroCatalogPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft normalize")
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = AutomationWorkflowDraftEditor.normalize(document, context: context)
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftFromRecording(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var outPath: String?
    var workflowName: String?
    var maxTasks = 6
    var includeCandidateFallback = true
    let recordingBundle = try loadRecordingCLIBundle(arguments) { token, index, arguments in
        switch token {
        case "--out":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a path.", path: token)
            }
            outPath = arguments[index + 1]
            return 1
        case "--name":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a value.", path: token)
            }
            workflowName = arguments[index + 1]
            return 1
        case "--max-tasks":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a value.", path: token)
            }
            maxTasks = try parseWorkflowCLIInt(
                arguments[index + 1],
                path: token
            )
            return 1
        case "--suggestions-only":
            includeCandidateFallback = false
            return 0
        default:
            return nil
        }
    }

    let suggestionResult = recordingCLISuggestionResult(
        for: recordingBundle,
        category: .conditions
    )
    let result = SemanticRecordingWorkflowDraftBuilder.build(
        bundle: recordingBundle.bundle,
        suggestions: suggestionResult.suggestions,
        options: SemanticRecordingWorkflowDraftBuildOptions(
            workflowName: workflowName,
            maxTasks: maxTasks,
            includeCandidateFallback: includeCandidateFallback
        )
    )

    if let outPath {
        let data = try encodeWorkflowCLIJSON(result.document)
        try writeWorkflowCLIFile(data, to: outPath)
    }

    let payload = AutomationWorkflowDraftFromRecordingPayload(
        requestedRecordingID: recordingBundle.requestedRecordingID,
        recordingID: recordingBundle.bundle.id,
        fixture: recordingBundle.fixture,
        sourceOption: recordingBundle.sourceOption,
        wrotePath: outPath,
        result: result
    )
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftFromRecordingPayload>
        .workflowDraftFromRecording(command: command, payload: payload)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowDraftFromRecordingSummary(payload)
    }
    return result.isValid ? 0 : 1
}

private func runWorkflowDraftPatch(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var patchPath: String?
    var outPath: String?
    var macroCatalogPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            if draftPath == nil {
                draftPath = token
            } else if patchPath == nil {
                patchPath = token
            } else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: command)
    let patch = try loadWorkflowDraftPatchDocument(path: patchPath, command: command)
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftPatchApplier.apply(
        patch,
        to: document,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftTaskAdd(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var outPath: String?
    var macroCatalogPath: String?
    var key: String?
    var type: String?
    var name: String?
    var macroID: UUID?
    var macroName: String?
    var resource: AutomationWorkflowDraftResource?
    var delaySeconds: TimeInterval?
    var notificationTitle: String?
    var notificationBody: String?
    var notificationSeverity: String?
    var timeoutSeconds: TimeInterval?
    var pollingSeconds: TimeInterval?
    var retryMaxAttempts: Int?
    var joinPolicy: String?
    var enabled: Bool?
    var graphX: Double?
    var graphY: Double?
    var maxResourceWaitSeconds: TimeInterval?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--key":
            key = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--type":
            type = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--name":
            name = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-id":
            macroID = try parseWorkflowCLIUUID(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--macro-name":
            macroName = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--resource":
            resource = try parseWorkflowCLIResource(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--max-resource-wait":
            maxResourceWaitSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--delay":
            delaySeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--title":
            notificationTitle = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--body":
            notificationBody = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--severity":
            notificationSeverity = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--timeout":
            timeoutSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--polling":
            pollingSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--retry-max":
            retryMaxAttempts = try parseWorkflowCLIInt(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--join-policy":
            joinPolicy = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--enabled":
            enabled = try parseWorkflowCLIBool(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--x":
            graphX = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--y":
            graphY = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    guard let key else {
        throw WorkflowCLIError("missingArgument", "workflow draft task add requires --key.", path: "--key")
    }
    guard let type else {
        throw WorkflowCLIError("missingArgument", "workflow draft task add requires --type.", path: "--type")
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft task add")
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let graphPosition = try workflowCLIGraphPoint(x: graphX, y: graphY)
    let task = AutomationWorkflowDraftTask(
        key: key,
        type: type,
        name: name,
        macroRef: (macroID != nil || macroName != nil) ? AutomationWorkflowDraftMacroRef(id: macroID, name: macroName) : nil,
        condition: type == "condition" ? AutomationWorkflowDraftCondition(type: "ocrText") : nil,
        delaySeconds: delaySeconds,
        notification: notificationTitle.map {
            AutomationWorkflowDraftNotification(title: $0, body: notificationBody, severity: notificationSeverity)
        },
        resource: resource,
        maxResourceWaitSeconds: maxResourceWaitSeconds,
        timeoutSeconds: timeoutSeconds,
        pollingSeconds: pollingSeconds,
        retry: retryMaxAttempts.map { AutomationWorkflowDraftRetry(maxAttempts: $0) },
        joinPolicy: joinPolicy,
        enabled: enabled,
        graphPosition: graphPosition
    )
    let result = try AutomationWorkflowDraftEditor.addTask(task, to: document, context: context)
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftTaskSet(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var taskKey: String?
    var outPath: String?
    var macroCatalogPath: String?
    var name: String?
    var timeoutSeconds: TimeInterval?
    var pollingSeconds: TimeInterval?
    var retryMaxAttempts: Int?
    var joinPolicy: String?
    var resource: AutomationWorkflowDraftResource?
    var maxResourceWaitSeconds: TimeInterval?
    var enabled: Bool?
    var graphX: Double?
    var graphY: Double?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--name":
            name = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--timeout":
            timeoutSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--polling":
            pollingSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--retry-max":
            retryMaxAttempts = try parseWorkflowCLIInt(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--join-policy":
            joinPolicy = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--resource":
            resource = try parseWorkflowCLIResource(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--max-resource-wait":
            maxResourceWaitSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--enabled":
            enabled = try parseWorkflowCLIBool(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--x":
            graphX = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--y":
            graphY = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            if draftPath == nil {
                draftPath = token
            } else if taskKey == nil {
                taskKey = token
            } else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft task set")
    guard let taskKey else {
        throw WorkflowCLIError("missingArgument", "workflow draft task set requires a task key.")
    }
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let graphPosition = try workflowCLIGraphPoint(x: graphX, y: graphY)
    let result = try AutomationWorkflowDraftEditor.setTask(
        key: taskKey,
        in: document,
        name: name,
        timeoutSeconds: timeoutSeconds,
        pollingSeconds: pollingSeconds,
        retryMaxAttempts: retryMaxAttempts,
        joinPolicy: joinPolicy,
        resource: resource,
        maxResourceWaitSeconds: maxResourceWaitSeconds,
        enabled: enabled,
        graphPosition: graphPosition,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftTaskRemove(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var taskKey: String?
    var outPath: String?
    var macroCatalogPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            if draftPath == nil {
                draftPath = token
            } else if taskKey == nil {
                taskKey = token
            } else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft task remove")
    guard let taskKey else {
        throw WorkflowCLIError("missingArgument", "workflow draft task remove requires a task key.")
    }
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftEditor.removeTask(
        key: taskKey,
        from: document,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftScheduleSet(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var taskKey: String?
    var outPath: String?
    var macroCatalogPath: String?
    var scheduleType: String?
    var startAt: Date?
    var every: Int?
    var unit: String?
    var timeZone: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--type":
            scheduleType = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--at", "--start-at":
            startAt = try parseWorkflowCLIDate(workflowCLIValue(after: token, in: arguments, at: &index))
        case "--every":
            every = try parseWorkflowCLIInt(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--unit":
            unit = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--time-zone":
            timeZone = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            if draftPath == nil {
                draftPath = token
            } else if taskKey == nil {
                taskKey = token
            } else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft schedule set")
    guard let taskKey else {
        throw WorkflowCLIError("missingArgument", "workflow draft schedule set requires a task key.")
    }
    guard let scheduleType else {
        throw WorkflowCLIError("missingArgument", "workflow draft schedule set requires --type.", path: "--type")
    }
    let schedule = parseWorkflowCLIDraftSchedule(
        type: scheduleType,
        startAt: startAt,
        every: every,
        unit: unit,
        timeZone: timeZone
    )
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftEditor.setSchedule(
        taskKey: taskKey,
        schedule: schedule,
        in: document,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftConditionSet(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var taskKey: String?
    var outPath: String?
    var macroCatalogPath: String?
    var conditionType: String?
    var text: String?
    var matchMode: TextMatchMode?
    var regionRef: String?
    var requireVisible: Bool?
    var outcome: String?
    var imageRef: String?
    var baselineRef: String?
    var colorHex: String?
    var threshold: Double?
    var pixelX: Double?
    var pixelY: Double?
    var timeoutSeconds: TimeInterval?
    var pollingSeconds: TimeInterval?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--type":
            conditionType = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--text":
            text = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--match":
            matchMode = try parseWorkflowCLITextMatchMode(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--region":
            regionRef = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--require-visible":
            requireVisible = try parseWorkflowCLIBool(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--outcome":
            outcome = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--image", "--image-ref":
            imageRef = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--baseline", "--baseline-ref":
            baselineRef = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--color", "--color-hex":
            colorHex = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--threshold":
            threshold = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--pixel-x":
            pixelX = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--pixel-y":
            pixelY = try parseWorkflowCLIDouble(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--timeout":
            timeoutSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--polling":
            pollingSeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            if draftPath == nil {
                draftPath = token
            } else if taskKey == nil {
                taskKey = token
            } else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft condition set")
    guard let taskKey else {
        throw WorkflowCLIError("missingArgument", "workflow draft condition set requires a task key.")
    }
    let condition = AutomationWorkflowDraftCondition(
        type: conditionType ?? "ocrText",
        text: text,
        matchMode: matchMode,
        regionRef: regionRef,
        requireVisible: requireVisible,
        outcome: outcome,
        imageRef: imageRef,
        baselineRef: baselineRef,
        pixel: try workflowCLIOptionalPoint(x: pixelX, y: pixelY),
        colorHex: colorHex,
        threshold: threshold
    )
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftEditor.setCondition(
        taskKey: taskKey,
        condition: condition,
        in: document,
        timeoutSeconds: timeoutSeconds,
        pollingSeconds: pollingSeconds,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftDependencyAdd(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var outPath: String?
    var macroCatalogPath: String?
    var key: String?
    var from: String?
    var to: String?
    var trigger: String?
    var delaySeconds: TimeInterval?
    var enabled: Bool?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--key":
            key = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--from":
            from = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--to":
            to = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--trigger":
            trigger = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--delay":
            delaySeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--enabled":
            enabled = try parseWorkflowCLIBool(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft dependency add")
    guard let from else {
        throw WorkflowCLIError("missingArgument", "workflow draft dependency add requires --from.", path: "--from")
    }
    guard let to else {
        throw WorkflowCLIError("missingArgument", "workflow draft dependency add requires --to.", path: "--to")
    }
    guard let trigger else {
        throw WorkflowCLIError("missingArgument", "workflow draft dependency add requires --trigger.", path: "--trigger")
    }

    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftEditor.addDependency(
        AutomationWorkflowDraftDependency(
            key: key,
            from: from,
            to: to,
            trigger: trigger,
            delaySeconds: delaySeconds,
            enabled: enabled
        ),
        to: document,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftDependencySet(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var outPath: String?
    var macroCatalogPath: String?
    var selectorKey: String?
    var selectorFrom: String?
    var selectorTo: String?
    var selectorTrigger: String?
    var newKey: String?
    var newFrom: String?
    var newTo: String?
    var newTrigger: String?
    var delaySeconds: TimeInterval?
    var enabled: Bool?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--key":
            selectorKey = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--from":
            selectorFrom = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--to":
            selectorTo = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--trigger":
            selectorTrigger = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--new-key":
            newKey = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--new-from":
            newFrom = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--new-to":
            newTo = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--new-trigger":
            newTrigger = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--delay":
            delaySeconds = try parseWorkflowCLIDuration(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        case "--enabled":
            enabled = try parseWorkflowCLIBool(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft dependency set")
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftEditor.setDependency(
        matching: AutomationWorkflowDraftDependencySelector(
            key: selectorKey,
            from: selectorFrom,
            to: selectorTo,
            trigger: selectorTrigger
        ),
        in: document,
        key: newKey,
        from: newFrom,
        to: newTo,
        trigger: newTrigger,
        delaySeconds: delaySeconds,
        enabled: enabled,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftDependencyRemove(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var outPath: String?
    var macroCatalogPath: String?
    var selectorKey: String?
    var selectorFrom: String?
    var selectorTo: String?
    var selectorTrigger: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--out":
            outPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--macro-catalog", "--catalog":
            macroCatalogPath = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--key":
            selectorKey = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--from":
            selectorFrom = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--to":
            selectorTo = try workflowCLIValue(after: token, in: arguments, at: &index)
        case "--trigger":
            selectorTrigger = try workflowCLIValue(after: token, in: arguments, at: &index)
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    let document = try loadWorkflowDraftDocument(path: draftPath, command: "workflow draft dependency remove")
    let context = try loadWorkflowDraftValidationContext(macroCatalogPath: macroCatalogPath)
    let result = try AutomationWorkflowDraftEditor.removeDependency(
        matching: AutomationWorkflowDraftDependencySelector(
            key: selectorKey,
            from: selectorFrom,
            to: selectorTo,
            trigger: selectorTrigger
        ),
        from: document,
        context: context
    )
    return try finishWorkflowDraftEdit(
        result,
        outPath: outPath,
        command: command,
        wantsJSON: wantsJSON
    )
}

private func runWorkflowDraftValidate(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var macroCatalogPath: String?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--macro-catalog", "--catalog":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a file path.", path: token)
            }
            macroCatalogPath = arguments[index + 1]
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    guard let draftPath else {
        throw WorkflowCLIError("missingArgument", "workflow draft validate requires a draft JSON file path.")
    }

    let draftData = try readWorkflowCLIFile(at: draftPath)
    let document = try decodeWorkflowCLIJSON(AutomationWorkflowDraftDocument.self, from: draftData)
    let macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]
    if let macroCatalogPath {
        let data = try readWorkflowCLIFile(at: macroCatalogPath)
        macroCatalog = try decodeWorkflowMacroCatalog(from: data)
    } else {
        macroCatalog = []
    }
    let result = AutomationWorkflowDraftValidator.validate(
        document,
        context: AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog)
    )
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>
        .workflowDraftValidation(command: command, result: result)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowValidationSummary(result)
    }
    return result.isValid ? 0 : 1
}

private func runWorkflowDraftSimulate(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var macroCatalogPath: String?
    var startAt = Date(timeIntervalSince1970: 0)
    var scenario: AutomationWorkflowDraftSimulationScenario?
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--macro-catalog", "--catalog":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a file path.", path: token)
            }
            macroCatalogPath = arguments[index + 1]
            index += 1
        case "--at":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--at requires an ISO-8601 date.", path: token)
            }
            startAt = try parseWorkflowCLIDate(arguments[index + 1])
            index += 1
        case "--scenario":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--scenario requires a value like timeout:wait_exit.", path: token)
            }
            guard let parsed = AutomationWorkflowDraftSimulationScenario(rawValue: arguments[index + 1]) else {
                throw WorkflowCLIError("invalidScenario", "Scenario must look like timeout:<task>, failure:<task>, or conditionNotMatched:<task>.", path: token)
            }
            scenario = parsed
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    guard let draftPath else {
        throw WorkflowCLIError("missingArgument", "workflow draft simulate requires a draft JSON file path.")
    }

    let draftData = try readWorkflowCLIFile(at: draftPath)
    let document = try decodeWorkflowCLIJSON(AutomationWorkflowDraftDocument.self, from: draftData)
    let macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]
    if let macroCatalogPath {
        let data = try readWorkflowCLIFile(at: macroCatalogPath)
        macroCatalog = try decodeWorkflowMacroCatalog(from: data)
    } else {
        macroCatalog = []
    }
    let result = AutomationWorkflowDraftSimulator.simulate(
        document,
        context: AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog),
        options: AutomationWorkflowDraftSimulationOptions(startAt: startAt, scenario: scenario)
    )
    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>
        .workflowDraftSimulation(command: command, result: result)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowSimulationSummary(result)
    }
    return result.isSimulatable ? 0 : 1
}

private func runWorkflowImport(
    _ arguments: [String],
    command: String,
    wantsJSON: Bool
) throws -> Int {
    var draftPath: String?
    var macroCatalogPath: String?
    var repositoryDirectoryPath: String?
    var visualAssetsRootPath: String?
    var importedAt = Date.now
    var isDryRun = false
    var wantsConfirm = false
    var index = 0

    while index < arguments.count {
        let token = arguments[index]
        switch token {
        case "--json":
            break
        case "--dry-run":
            isDryRun = true
        case "--confirm":
            wantsConfirm = true
        case "--repository-dir":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--repository-dir requires a directory path.", path: token)
            }
            repositoryDirectoryPath = arguments[index + 1]
            index += 1
        case "--visual-assets-root":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--visual-assets-root requires a directory path.", path: token)
            }
            visualAssetsRootPath = arguments[index + 1]
            index += 1
        case "--macro-catalog", "--catalog":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "\(token) requires a file path.", path: token)
            }
            macroCatalogPath = arguments[index + 1]
            index += 1
        case "--at":
            guard index + 1 < arguments.count else {
                throw WorkflowCLIError("missingArgument", "--at requires an ISO-8601 date.", path: token)
            }
            importedAt = try parseWorkflowCLIDate(arguments[index + 1])
            index += 1
        default:
            if token.hasPrefix("--") {
                throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
            }
            guard draftPath == nil else {
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            draftPath = token
        }
        index += 1
    }

    if isDryRun && wantsConfirm {
        throw WorkflowCLIError(
            "unsupportedOption",
            "workflow import accepts either --dry-run or --confirm, not both.",
            path: "--confirm"
        )
    }
    guard isDryRun || wantsConfirm else {
        throw WorkflowCLIError(
            "missingArgument",
            "workflow import requires either --dry-run or --confirm.",
            path: "--dry-run"
        )
    }
    guard let draftPath else {
        throw WorkflowCLIError("missingArgument", "workflow import requires a draft JSON file path.")
    }

    let draftData = try readWorkflowCLIFile(at: draftPath)
    let document = try decodeWorkflowCLIJSON(AutomationWorkflowDraftDocument.self, from: draftData)
    let macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]
    if let macroCatalogPath {
        let data = try readWorkflowCLIFile(at: macroCatalogPath)
        macroCatalog = try decodeWorkflowMacroCatalog(from: data)
    } else {
        macroCatalog = []
    }

    var result = AutomationWorkflowDraftImporter.compile(
        document,
        context: AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog),
        options: AutomationWorkflowDraftImportOptions(
            mode: wantsConfirm ? .confirm : .dryRun,
            importedAt: importedAt
        )
    )

    if wantsConfirm && result.isImportable {
        guard let workflow = result.workflow else {
            throw WorkflowCLIError(
                "importRejected",
                "Workflow import reported success without a compiled workflow."
            )
        }
        let repository: AutomationRepositoryClient
        if let repositoryDirectoryPath {
            repository = .fileBacked(directoryURL: URL(fileURLWithPath: repositoryDirectoryPath, isDirectory: true))
        } else {
            repository = .fileBacked()
        }
        let visualAssetRootClient = workflowCLIVisualAssetRootClient(directoryPath: repositoryDirectoryPath)
        let visualAssetsRootURL = workflowCLIVisualAssetsRootURL(
            overridePath: visualAssetsRootPath,
            draftPath: draftPath
        )
        let confirmedAt = importedAt
        let importResult = result
        result = try waitForWorkflowCLIAsync {
            try await confirmWorkflowImport(
                result: importResult,
                workflow: workflow,
                repository: repository,
                visualAssetRootClient: visualAssetRootClient,
                visualAssetsRootURL: visualAssetsRootURL,
                importedAt: confirmedAt
            )
        }
    }

    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>
        .workflowDraftImport(command: command, result: result)

    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowImportSummary(result)
    }
    return result.isImportable ? 0 : 1
}

private func confirmWorkflowImport(
    result: AutomationWorkflowDraftImportResult,
    workflow: AutomationWorkflow,
    repository: AutomationRepositoryClient,
    visualAssetRootClient: AutomationVisualAssetPackageRootClient,
    visualAssetsRootURL: URL,
    importedAt: Date
) async throws -> AutomationWorkflowDraftImportResult {
    let existingWorkflows = try await repository.loadWorkflows()
    let initialState = AutomationRunState(workflows: existingWorkflows, now: importedAt)
    let reducerResult = AutomationReducer.reduce(
        state: initialState,
        action: .upsertWorkflow(workflow, at: importedAt)
    )

    guard case .persistWorkflows(let workflowsToPersist)? = reducerResult.effects.first else {
        throw WorkflowCLIError(
            "importRejected",
            "Compiled workflow was rejected by the Automation reducer."
        )
    }
    guard reducerResult.effects.count == 1 else {
        throw WorkflowCLIError(
            "unexpectedImportEffect",
            "Workflow import expected one persistence effect, got \(reducerResult.effects.count)."
        )
    }

    try await repository.saveWorkflows(workflowsToPersist)

    var confirmed = result
    confirmed.mode = .confirm
    confirmed.workflow = reducerResult.state.workflow(id: workflow.id) ?? workflow
    if let confirmedWorkflow = confirmed.workflow {
        let roots = AutomationVisualAssetPackageRoot.roots(
            for: [confirmedWorkflow],
            packageDirectoryURL: visualAssetsRootURL,
            source: .aiDraftImport,
            associatedAt: importedAt
        )
        if roots.isEmpty {
            try await visualAssetRootClient.removeRoots(Set([workflow.id]))
        } else {
            try await visualAssetRootClient.upsertRoots(roots)
        }
    }
    return confirmed
}

private func enqueueWorkflowRunHandoff(
    workflowID: UUID,
    taskSelector: String?,
    repository: AutomationRepositoryClient,
    handoffClient: AutomationRuntimeHandoffClient,
    requestedAt: Date
) async throws -> AutomationRuntimeHandoffPayload {
    let workflows = try await repository.loadWorkflows()
    guard let workflow = workflows.first(where: { $0.id == workflowID }) else {
        throw WorkflowCLIError(
            "workflowNotFound",
            "Workflow '\(workflowID.uuidString)' was not found.",
            path: "workflow-id"
        )
    }
    let task = try resolveWorkflowCLITask(selector: taskSelector, in: workflow)
    guard task.isEnabled else {
        throw WorkflowCLIError(
            "taskDisabled",
            "Task '\(task.name)' is disabled and cannot be started.",
            path: "--task"
        )
    }

    let command = AutomationRuntimeHandoffCommand(
        kind: .manualStart(workflowID: workflow.id, taskID: task.id),
        requestedAt: requestedAt,
        source: "SparkleRecorder CLI"
    )
    let enqueued = try await handoffClient.enqueue(command)
    let pendingCommands = try await handoffClient.loadCommands()
    return AutomationRuntimeHandoffPayload(
        command: enqueued,
        enqueuedAt: Date.now,
        pendingCommandCount: pendingCommands.count
    )
}

private func runWorkflowBoundWindowAcceptance(
    workflowID: UUID,
    taskSelector: String?,
    repository: AutomationRepositoryClient,
    macrosDirectory: URL?,
    handoffClient: AutomationRuntimeHandoffClient,
    activateTarget: Bool,
    launchTarget: Bool,
    confirmPlayback: Bool,
    requestedAt: Date
) async throws -> AutomationWorkflowBoundWindowAcceptancePayload {
    let workflows = try await repository.loadWorkflows()
    guard let workflow = workflows.first(where: { $0.id == workflowID }) else {
        throw WorkflowCLIError(
            "workflowNotFound",
            "Workflow '\(workflowID.uuidString)' was not found.",
            path: "workflow-id"
        )
    }
    let task = try resolveWorkflowCLITask(selector: taskSelector, in: workflow)
    guard task.isEnabled else {
        throw WorkflowCLIError(
            "taskDisabled",
            "Task '\(task.name)' is disabled and cannot be accepted for playback.",
            path: "--task"
        )
    }
    guard let macroID = task.kind.macroID else {
        throw WorkflowCLIError(
            "taskIsNotMacro",
            "Task '\(task.name)' is not a macro task.",
            path: "--task"
        )
    }

    let macro = try loadWorkflowMacroManifests(macrosDirectory: macrosDirectory)
        .first { $0.id == macroID }
    guard let macro else {
        throw WorkflowCLIError(
            "macroNotFound",
            "Macro '\(macroID.uuidString)' was not found in the macro library.",
            path: "macroID"
        )
    }
    guard !macro.surfaces.isEmpty else {
        throw WorkflowCLIError(
            "macroHasNoBoundSurfaces",
            "Macro '\(macro.name)' has no saved playback surfaces to activate.",
            path: "macro.surfaces"
        )
    }
    guard !PlaybackPlanner.plan(events: macro.events, loops: macro.loops, speed: macro.speed).steps.isEmpty else {
        throw WorkflowCLIError(
            "macroHasNoPlayableEvents",
            "Macro '\(macro.name)' has no playable events.",
            path: "macro.events"
        )
    }

    let activationResults = activateTarget
        ? workflowCLIActivateBoundTargetApps(
            surfaces: macro.surfaces,
            launchIfNeeded: launchTarget
        )
        : []
    let handoff: AutomationRuntimeHandoffPayload?
    if confirmPlayback {
        handoff = try await enqueueWorkflowRunHandoff(
            workflowID: workflow.id,
            taskSelector: task.id.uuidString,
            repository: repository,
            handoffClient: handoffClient,
            requestedAt: requestedAt
        )
    } else {
        handoff = nil
    }

    return AutomationWorkflowBoundWindowAcceptancePayload(
        workflow: workflow,
        task: task,
        macro: macro,
        activationRequested: activateTarget,
        launchRequested: launchTarget,
        playbackHandoffRequested: confirmPlayback,
        activationResults: activationResults,
        handoff: handoff,
        checkedAt: Date.now
    )
}

private func workflowCLIActivateBoundTargetApps(
    surfaces: [String: PlaybackSurface],
    launchIfNeeded: Bool
) -> [AutomationWorkflowBoundWindowActivationResult] {
    let surfacesByBundle = Dictionary(grouping: surfaces.values.compactMap { surface -> (String, PlaybackSurface)? in
        guard let bundleIdentifier = surface.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return nil
        }
        return (bundleIdentifier, surface)
    }, by: \.0)

    return surfacesByBundle.keys.sorted().map { bundleIdentifier in
        let surface = surfacesByBundle[bundleIdentifier]?.first?.1
        let runningBefore = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
        var app = runningBefore.first
        var didLaunch = false
        var errorMessage: String?

        if app == nil, launchIfNeeded {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                didLaunch = NSWorkspace.shared.open(appURL)
                if didLaunch {
                    Thread.sleep(forTimeInterval: 1.0)
                    app = NSRunningApplication
                        .runningApplications(withBundleIdentifier: bundleIdentifier)
                        .first
                }
            } else {
                errorMessage = "Could not locate an installed app for bundle identifier '\(bundleIdentifier)'."
            }
        }

        guard let app else {
            return AutomationWorkflowBoundWindowActivationResult(
                bundleIdentifier: bundleIdentifier,
                appName: surface?.appName,
                wasRunning: !runningBefore.isEmpty,
                didLaunch: didLaunch,
                didActivate: false,
                errorMessage: errorMessage ?? "Target app '\(bundleIdentifier)' is not running. Pass --confirm-launch to launch it before playback."
            )
        }

        let didActivate: Bool
        if #available(macOS 14.0, *) {
            didActivate = app.activate()
        } else {
            didActivate = app.activate(options: [.activateIgnoringOtherApps])
        }

        return AutomationWorkflowBoundWindowActivationResult(
            bundleIdentifier: bundleIdentifier,
            appName: app.localizedName ?? surface?.appName,
            wasRunning: !runningBefore.isEmpty,
            didLaunch: didLaunch,
            didActivate: didActivate,
            errorMessage: didActivate ? nil : "Target app '\(bundleIdentifier)' was found but did not activate."
        )
    }
}

private func enqueueWorkflowCancelHandoff(
    runID: UUID,
    repository: AutomationRepositoryClient,
    handoffClient: AutomationRuntimeHandoffClient,
    requestedAt: Date
) async throws -> AutomationRuntimeHandoffPayload {
    let beforeRuns = try await repository.loadRunHistory()
    guard let beforeRun = beforeRuns.first(where: { $0.id == runID }) else {
        throw WorkflowCLIError(
            "runNotFound",
            "Run '\(runID.uuidString)' was not found in workflow run history.",
            path: "run-id"
        )
    }
    guard !beforeRun.isTerminal else {
        throw WorkflowCLIError(
            "runAlreadyTerminal",
            "Run '\(runID.uuidString)' is already terminal and cannot be handed off for cancellation.",
            path: "run-id"
        )
    }

    let command = AutomationRuntimeHandoffCommand(
        kind: .cancelRun(runID: runID),
        requestedAt: requestedAt,
        source: "SparkleRecorder CLI"
    )
    let enqueued = try await handoffClient.enqueue(command)
    let pendingCommands = try await handoffClient.loadCommands()
    return AutomationRuntimeHandoffPayload(
        command: enqueued,
        enqueuedAt: Date.now,
        pendingCommandCount: pendingCommands.count
    )
}

private func loadWorkflowHandoffStatus(
    commandID: UUID,
    handoffClient: AutomationRuntimeHandoffClient,
    repository: AutomationRepositoryClient,
    checkedAt: Date
) async throws -> AutomationRuntimeHandoffStatusPayload {
    let commands = try await handoffClient.loadCommands()
    let receipts = try await handoffClient.loadReceipts()
    let command = commands.first { $0.id == commandID }
    let receipt = receipts.first { $0.commandID == commandID }
    let workflows = try await repository.loadWorkflows()
    let runHistory = try await repository.loadRunHistory()
    let runs = workflowHandoffRunSnapshots(
        command: command,
        receipt: receipt,
        runHistory: runHistory
    )
    let workflowStatus = workflowHandoffWorkflow(
        command: command,
        receipt: receipt,
        runs: runs,
        workflows: workflows
    ).map { workflow in
        AutomationWorkflowStatus(workflow: workflow, runHistory: runHistory)
    }
    return AutomationRuntimeHandoffStatusPayload(
        commandID: commandID,
        command: command,
        receipt: receipt,
        workflowStatus: workflowStatus,
        runs: runs,
        pendingCommandCount: commands.count,
        receiptCount: receipts.count,
        checkedAt: checkedAt
    )
}

private func workflowHandoffRunSnapshots(
    command: AutomationRuntimeHandoffCommand?,
    receipt: AutomationRuntimeHandoffReceipt?,
    runHistory: [AutomationTaskRun]
) -> [AutomationTaskRun] {
    let runIDs: [UUID]
    if let receipt, !receipt.runIDs.isEmpty {
        runIDs = receipt.runIDs
    } else if case .cancelRun(let runID) = command?.kind {
        runIDs = [runID]
    } else if case .cancelRun(let runID) = receipt?.commandKind {
        runIDs = [runID]
    } else {
        runIDs = []
    }

    guard !runIDs.isEmpty else {
        return []
    }
    let runsByID = Dictionary(grouping: runHistory, by: \.id)
        .mapValues { groupedRuns in
            groupedRuns.sorted { workflowCLIRunSortDate($0) > workflowCLIRunSortDate($1) }.first!
        }
    return runIDs.compactMap { runsByID[$0] }
}

private func workflowHandoffWorkflow(
    command: AutomationRuntimeHandoffCommand?,
    receipt: AutomationRuntimeHandoffReceipt?,
    runs: [AutomationTaskRun],
    workflows: [AutomationWorkflow]
) -> AutomationWorkflow? {
    let workflowID: UUID?
    if case .manualStart(let id, _) = command?.kind {
        workflowID = id
    } else if case .manualStart(let id, _) = receipt?.commandKind {
        workflowID = id
    } else {
        workflowID = runs.first?.workflowID
    }
    guard let workflowID else {
        return nil
    }
    return workflows.first { $0.id == workflowID }
}

private func workflowCLIRunSortDate(_ run: AutomationTaskRun) -> Date {
    run.completedAt ??
        run.actualStartTime ??
        run.earliestStartTime ??
        run.scheduledStartTime ??
        run.createdAt
}

private func runWorkflowRuntimeControl(
    workflowID: UUID,
    taskSelector: String?,
    repository: AutomationRepositoryClient,
    macrosDirectory: URL?,
    requestedAt: Date,
    waitTimeout: TimeInterval,
    playerMode: WorkflowCLIPlayerMode
) async throws -> AutomationWorkflowRunPayload {
    let workflows = try await repository.loadWorkflows()
    let beforeRuns = try await repository.loadRunHistory()
    guard let workflow = workflows.first(where: { $0.id == workflowID }) else {
        throw WorkflowCLIError(
            "workflowNotFound",
            "Workflow '\(workflowID.uuidString)' was not found.",
            path: "workflow-id"
        )
    }
    let task = try resolveWorkflowCLITask(selector: taskSelector, in: workflow)
    guard task.isEnabled else {
        throw WorkflowCLIError(
            "taskDisabled",
            "Task '\(task.name)' is disabled and cannot be started.",
            path: "--task"
        )
    }

    let now: @Sendable () -> Date = { Date() }
    let effectRunner = try await workflowCLIRuntimeEffectRunner(
        repository: repository,
        macrosDirectory: macrosDirectory,
        playerMode: playerMode,
        now: now
    )
    let session = AutomationRuntimeSession(
        repository: repository,
        scheduler: .fixed([]),
        effectRunner: effectRunner
    )
    _ = try await session.start()
    let dispatchedState = try await session.dispatch(.manualStart(
        workflowID: workflow.id,
        taskID: task.id,
        requestedAt: requestedAt
    ))
    let beforeRunIDs = Set(beforeRuns.map(\.id))
    guard let startedRun = dispatchedState.runs.first(where: {
        $0.workflowID == workflow.id &&
            $0.taskID == task.id &&
            !beforeRunIDs.contains($0.id)
    }) ?? dispatchedState.runs.first(where: {
        $0.workflowID == workflow.id && !beforeRunIDs.contains($0.id)
    }) else {
        await session.stop(at: requestedAt)
        throw WorkflowCLIError(
            "runNotCreated",
            "The Automation reducer did not create a run for task '\(task.name)'.",
            path: "--task"
        )
    }

    let waitResult = await waitForWorkflowCLIExecution(
        session: session,
        executionID: startedRun.executionID,
        startedRunID: startedRun.id,
        waitTimeout: waitTimeout
    )
    await session.stop()

    let finalState = await session.currentState() ?? dispatchedState

    return AutomationWorkflowRunPayload(
        workflow: workflow,
        requestedTaskID: task.id,
        requestedAt: requestedAt,
        beforeRuns: beforeRuns,
        afterState: finalState.runs.isEmpty ? waitResult.state : finalState,
        timedOut: waitResult.timedOut
    )
}

private func cancelWorkflowRun(
    runID: UUID,
    repository: AutomationRepositoryClient,
    requestedAt: Date
) async throws -> AutomationWorkflowCancelPayload {
    let workflows = try await repository.loadWorkflows()
    let beforeRuns = try await repository.loadRunHistory()
    guard let beforeRun = beforeRuns.first(where: { $0.id == runID }) else {
        throw WorkflowCLIError(
            "runNotFound",
            "Run '\(runID.uuidString)' was not found in workflow run history.",
            path: "run-id"
        )
    }

    let effectRunner = AutomationEffectRunner(
        resourceArbiter: .live(),
        player: .rejecting(.cancelled(reason: "CLI cancellation only")),
        repository: repository,
        now: { requestedAt },
        sleep: { _ in }
    )
    let session = AutomationRuntimeSession(
        repository: repository,
        scheduler: .fixed([]),
        effectRunner: effectRunner
    )
    _ = try await session.start()
    let state = try await session.dispatch(.cancelRun(runID: runID, at: requestedAt))
    await session.stop(at: requestedAt)

    let stateWithWorkflows = AutomationRunState(
        workflows: state.workflows.isEmpty ? workflows : state.workflows,
        runs: state.runs,
        leases: state.leases,
        now: state.now
    )
    return AutomationWorkflowCancelPayload(
        runID: runID,
        requestedAt: requestedAt,
        beforeRun: beforeRun,
        afterState: stateWithWorkflows
    )
}

private func workflowCLIRuntimeEffectRunner(
    repository: AutomationRepositoryClient,
    macrosDirectory: URL?,
    playerMode: WorkflowCLIPlayerMode,
    now: @escaping @Sendable () -> Date
) async throws -> AutomationEffectRunner {
    let playerClient: AutomationPlayerClient
    switch playerMode {
    case .live:
        playerClient = await MainActor.run {
            AutomationPlayerClient.live(
                player: Player(),
                windowTracker: WindowTracker(),
                now: now
            )
        }
    case .fakeSuccess:
        playerClient = AutomationPlayerClient(
            start: { _ in .rejected(.succeeded(report: nil)) },
            cancel: { _ in },
            events: { .finished }
        )
    case .reject:
        playerClient = .rejecting(.rejected(reason: "CLI player mode rejected playback"))
    }

    return AutomationEffectRunner(
        resourceArbiter: .live(),
        player: playerClient,
        conditionEvaluator: .live(now: now),
        repository: repository,
        loadMacro: { macroID in
            try loadWorkflowMacroManifests(macrosDirectory: macrosDirectory)
                .first { $0.id == macroID }
        },
        now: now
    )
}

private func waitForWorkflowCLIExecution(
    session: AutomationRuntimeSession,
    executionID: UUID,
    startedRunID: UUID,
    waitTimeout: TimeInterval
) async -> (state: AutomationRunState, timedOut: Bool) {
    let timeout = max(0, waitTimeout)
    let startedAt = Date()
    var latestState = await session.currentState() ?? AutomationRunState()

    while true {
        if let state = await session.currentState() {
            latestState = state
        }
        let executionRuns = latestState.runs.filter { $0.executionID == executionID }
        if !executionRuns.isEmpty, executionRuns.allSatisfy(\.isTerminal) {
            return (latestState, false)
        }
        if latestState.run(id: startedRunID)?.isTerminal == true, executionRuns.isEmpty {
            return (latestState, false)
        }
        if timeout > 0, Date().timeIntervalSince(startedAt) >= timeout {
            return (latestState, true)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}

private func resolveWorkflowCLITask(
    selector: String?,
    in workflow: AutomationWorkflow
) throws -> AutomationTask {
    if let selector {
        if let taskID = UUID(uuidString: selector) {
            guard let task = workflow.task(id: taskID) else {
                throw WorkflowCLIError(
                    "taskNotFound",
                    "Task '\(taskID.uuidString)' was not found in workflow '\(workflow.name)'.",
                    path: "--task"
                )
            }
            return task
        }

        let matches = workflow.tasks.filter {
            $0.name.localizedCaseInsensitiveCompare(selector) == .orderedSame
        }
        guard !matches.isEmpty else {
            throw WorkflowCLIError(
                "taskNotFound",
                "Task '\(selector)' was not found by UUID or exact name in workflow '\(workflow.name)'.",
                path: "--task"
            )
        }
        guard matches.count == 1 else {
            throw WorkflowCLIError(
                "ambiguousTask",
                "Task selector '\(selector)' matched \(matches.count) tasks. Use a task UUID.",
                path: "--task"
            )
        }
        return matches[0]
    }

    let dependencyTargets = Set(workflow.dependencies.filter(\.isEnabled).map(\.toTaskID))
    let rootTasks = workflow.tasks.filter { task in
        task.isEnabled && !dependencyTargets.contains(task.id)
    }
    guard !rootTasks.isEmpty else {
        throw WorkflowCLIError(
            "taskRequired",
            "workflow run could not infer a start task. Pass --task <task-id-or-name>.",
            path: "--task"
        )
    }
    guard rootTasks.count == 1 else {
        throw WorkflowCLIError(
            "ambiguousStartTask",
            "Workflow '\(workflow.name)' has \(rootTasks.count) possible start tasks. Pass --task <task-id-or-name>.",
            path: "--task"
        )
    }
    return rootTasks[0]
}

private func workflowCLIRepository(directoryPath: String?) -> AutomationRepositoryClient {
    if let directoryPath {
        return .fileBacked(directoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true))
    }
    return .fileBacked()
}

private func workflowCLIVisualAssetRootClient(directoryPath: String?) -> AutomationVisualAssetPackageRootClient {
    if let directoryPath {
        return .fileBacked(directoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true))
    }
    return .fileBacked()
}

private func workflowCLIRuntimeHandoffClient(directoryPath: String?) -> AutomationRuntimeHandoffClient {
    if let directoryPath {
        return .fileBacked(directoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true))
    }
    return .fileBacked()
}

private func workflowCLIVisualAssetsRootURL(overridePath: String?, draftPath: String) -> URL {
    if let overridePath {
        return URL(fileURLWithPath: overridePath, isDirectory: true)
    }
    return URL(fileURLWithPath: draftPath)
        .deletingLastPathComponent()
}

private final class WorkflowCLIAsyncResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Value, Error>? {
        lock.lock()
        let current = result
        lock.unlock()
        return current
    }
}

private func waitForWorkflowCLIAsync<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) throws -> Value {
    let semaphore = DispatchSemaphore(value: 0)
    let box = WorkflowCLIAsyncResultBox<Value>()

    Task {
        do {
            box.set(.success(try await operation()))
        } catch {
            box.set(.failure(error))
        }
        semaphore.signal()
    }

    semaphore.wait()
    guard let result = box.get() else {
        throw WorkflowCLIError("asyncBridgeFailed", "Workflow CLI async operation did not return a result.")
    }
    return try result.get()
}

private struct LegacyWorkflowCLILibraryData: Decodable {
    var macros: [SavedMacro]
}

private func loadWorkflowMacroManifests(macrosDirectory: URL?) throws -> [SavedMacro] {
    let fileManager = FileManager.default
    let directory = macrosDirectory ?? defaultWorkflowMacrosDirectory()
    guard fileManager.fileExists(atPath: directory.path) else {
        if macrosDirectory == nil, let legacy = try loadLegacyWorkflowMacroLibrary() {
            return legacy
        }
        return []
    }

    let packageURLs = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    let manifests = packageURLs
        .filter { $0.pathExtension == "sparkrec" }
        .compactMap { packageURL -> SavedMacro? in
            let manifestURL = packageURL.appendingPathComponent("macro.json")
            guard let data = try? Data(contentsOf: manifestURL) else {
                return nil
            }
            guard var macro = try? decodeWorkflowCLIJSON(SavedMacro.self, from: data) else {
                return nil
            }
            let eventsURL = packageURL.appendingPathComponent("events.json")
            if let eventData = try? Data(contentsOf: eventsURL),
               let events = try? decodeWorkflowCLIJSON([RecordedEvent].self, from: eventData) {
                macro.events = events
                macro.refreshCachesFromEvents()
            }
            return macro
        }

    if manifests.isEmpty, macrosDirectory == nil, let legacy = try loadLegacyWorkflowMacroLibrary() {
        return legacy
    }

    return manifests.sorted { left, right in
        if left.createdAt != right.createdAt {
            return left.createdAt > right.createdAt
        }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
}

private func defaultWorkflowMacrosDirectory() -> URL {
    let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
    return appSupport
        .appendingPathComponent("SparkleRecorder", isDirectory: true)
        .appendingPathComponent("Macros", isDirectory: true)
}

private func loadLegacyWorkflowMacroLibrary() throws -> [SavedMacro]? {
    let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
    let legacyURL = appSupport
        .appendingPathComponent("SparkleRecorder", isDirectory: true)
        .appendingPathComponent("library.json")
    guard FileManager.default.fileExists(atPath: legacyURL.path) else {
        return nil
    }
    let data = try readWorkflowCLIFile(at: legacyURL.path)
    return try decodeWorkflowCLIJSON(LegacyWorkflowCLILibraryData.self, from: data).macros
}

private func workflowCommandName(_ workflowArgs: [String]) -> String {
    guard !workflowArgs.isEmpty else {
        return "workflow"
    }
    return "workflow " + workflowArgs.prefix(3).joined(separator: " ")
}

private func recordingCommandName(_ recordingArgs: [String]) -> String {
    guard let command = recordingArgs.first else {
        return "recording"
    }
    switch command {
    case "show":
        return "recording.show"
    case "explain":
        return "recording.explain"
    case "frames":
        return "recording.frames"
    case "frame":
        if recordingArgs.dropFirst().first == "show" {
            return "recording.frame.show"
        }
        return "recording.frame"
    case "events-near":
        return "recording.eventsNear"
    case "ocr":
        if Array(recordingArgs.dropFirst().prefix(1)) == ["search"] {
            return "recording.ocr.search"
        }
        return "recording.ocr"
    case "visual":
        if Array(recordingArgs.dropFirst().prefix(1)) == ["search"] {
            return "recording.visual.search"
        }
        return "recording.visual"
    case "asset":
        if let subcommand = recordingArgs.dropFirst().first {
            return "recording.asset.\(subcommand)"
        }
        return "recording.asset"
    case "suggest":
        if let category = recordingArgs.dropFirst().first {
            return "recording.suggest.\(category)"
        }
        return "recording.suggest"
    default:
        return "recording.\(command)"
    }
}

private func semanticRecordingCommandName(_ semanticArgs: [String]) -> String {
    guard !semanticArgs.isEmpty else {
        return "semantic-recording"
    }
    return "semantic-recording " + semanticArgs.prefix(1).joined(separator: " ")
}

private func readWorkflowCLIFile(at path: String) throws -> Data {
    do {
        return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        throw WorkflowCLIError("fileReadFailed", "Could not read file '\(path)': \(error.localizedDescription)", path: path)
    }
}

private func decodeWorkflowCLIJSON<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    let isoDecoder = JSONDecoder()
    isoDecoder.dateDecodingStrategy = .iso8601
    do {
        return try isoDecoder.decode(type, from: data)
    } catch {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WorkflowCLIError("jsonDecodeFailed", "Could not decode workflow JSON: \(error.localizedDescription)")
        }
    }
}

private func decodeWorkflowMacroCatalog(from data: Data) throws -> [AutomationWorkflowDraftMacroCatalogEntry] {
    if let entries = try? decodeWorkflowCLIJSON([AutomationWorkflowDraftMacroCatalogEntry].self, from: data) {
        return entries
    }
    let envelope = try decodeWorkflowCLIJSON(
        AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>.self,
        from: data
    )
    return envelope.data?.macros ?? []
}

private func loadWorkflowDraftDocument(path: String?, command: String) throws -> AutomationWorkflowDraftDocument {
    guard let path else {
        throw WorkflowCLIError("missingArgument", "\(command) requires a draft JSON file path.")
    }
    let data = try readWorkflowCLIFile(at: path)
    return try decodeWorkflowCLIJSON(AutomationWorkflowDraftDocument.self, from: data)
}

private func loadWorkflowDraftPatchDocument(path: String?, command: String) throws -> AutomationWorkflowDraftPatchDocument {
    guard let path else {
        throw WorkflowCLIError("missingArgument", "\(command) requires a patch JSON file path.")
    }
    let data = try readWorkflowCLIFile(at: path)
    return try decodeWorkflowCLIJSON(AutomationWorkflowDraftPatchDocument.self, from: data)
}

private func loadWorkflowDraftValidationContext(
    macroCatalogPath: String?
) throws -> AutomationWorkflowDraftValidationContext {
    guard let macroCatalogPath else {
        return AutomationWorkflowDraftValidationContext()
    }
    let data = try readWorkflowCLIFile(at: macroCatalogPath)
    return AutomationWorkflowDraftValidationContext(
        macroCatalog: try decodeWorkflowMacroCatalog(from: data)
    )
}

private func finishWorkflowDraftEdit(
    _ result: AutomationWorkflowDraftEditResult,
    outPath: String?,
    command: String,
    wantsJSON: Bool
) throws -> Int {
    let finalResult: AutomationWorkflowDraftEditResult
    if let outPath {
        let data = try encodeWorkflowCLIJSON(result.document)
        try writeWorkflowCLIFile(data, to: outPath)
        finalResult = result.withWrotePath(outPath)
    } else {
        finalResult = result
    }

    let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftEditPayload>
        .workflowDraftEdit(command: command, result: finalResult)
    if wantsJSON {
        writeWorkflowJSON(envelope)
    } else {
        writeWorkflowDraftEditSummary(finalResult)
    }
    return 0
}

private func workflowCLIValue(
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

private func workflowCLIGraphPoint(x: Double?, y: Double?) throws -> AutomationGraphPoint? {
    switch (x, y) {
    case (.none, .none):
        return nil
    case (.some(let x), .some(let y)):
        return AutomationGraphPoint(x: x, y: y)
    default:
        throw WorkflowCLIError("missingArgument", "Graph position needs both --x and --y.")
    }
}

private func workflowCLIOptionalPoint(x: Double?, y: Double?) throws -> AutomationGraphPoint? {
    switch (x, y) {
    case (.none, .none):
        return nil
    case (.some(let x), .some(let y)):
        return AutomationGraphPoint(x: x, y: y)
    default:
        throw WorkflowCLIError("missingArgument", "Pixel match needs both --pixel-x and --pixel-y.")
    }
}

private func parseWorkflowCLIUUID(_ value: String, path: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw WorkflowCLIError("invalidUUID", "\(path) must be a UUID.", path: path)
    }
    return uuid
}

private func parseWorkflowCLIDuration(_ value: String, path: String) throws -> TimeInterval {
    guard let duration = TimeInterval(value) else {
        throw WorkflowCLIError("invalidDuration", "\(path) must be a number of seconds.", path: path)
    }
    return duration
}

private func parseWorkflowCLIDouble(_ value: String, path: String) throws -> Double {
    guard let number = Double(value) else {
        throw WorkflowCLIError("invalidNumber", "\(path) must be a number.", path: path)
    }
    return number
}

private func parseWorkflowCLIInt(_ value: String, path: String) throws -> Int {
    guard let number = Int(value) else {
        throw WorkflowCLIError("invalidInteger", "\(path) must be an integer.", path: path)
    }
    return number
}

private func parseWorkflowCLIBool(_ value: String, path: String) throws -> Bool {
    switch value.lowercased() {
    case "true", "yes", "1", "enabled":
        return true
    case "false", "no", "0", "disabled":
        return false
    default:
        throw WorkflowCLIError("invalidBoolean", "\(path) must be true or false.", path: path)
    }
}

private func parseWorkflowCLIResource(
    _ value: String,
    path: String
) throws -> AutomationWorkflowDraftResource {
    guard let resource = AutomationWorkflowDraftResource(rawValue: value) else {
        throw WorkflowCLIError(
            "unsupportedResource",
            "\(path) must be foregroundInput, screenCapture, accessibility, network, or none.",
            path: path
        )
    }
    return resource
}

private func parseWorkflowCLITextMatchMode(_ value: String, path: String) throws -> TextMatchMode {
    guard let matchMode = TextMatchMode(rawValue: value) else {
        throw WorkflowCLIError("unsupportedMatchMode", "\(path) must be contains or exact.", path: path)
    }
    return matchMode
}

private func parseRecordingVisualObservationKind(
    _ value: String,
    path: String
) throws -> RecordingVisualObservationKind {
    guard let kind = RecordingVisualObservationKind(rawValue: value) else {
        throw WorkflowCLIError(
            "unsupportedVisualObservationKind",
            "\(path) must be one of ocrText, axElement, windowSnapshot, pixelSample, imageTemplateCandidate, regionBaseline, regionDiff, or patternCandidate.",
            path: path
        )
    }
    return kind
}

private func parseRecordingCLIAssetExtractionKind(
    _ value: String,
    path: String
) throws -> SemanticRecordingCLIAssetExtractionKind {
    guard let kind = SemanticRecordingCLIAssetExtractionKind(rawValue: value) else {
        throw WorkflowCLIError(
            "unsupportedAssetKind",
            "\(path) must be imageTemplate, image, or baseline.",
            path: path
        )
    }
    return kind
}

private func parseRecordingCLIRegionSpace(
    _ value: String,
    path: String
) throws -> RecordingCoordinateSpace {
    guard let space = RecordingCoordinateSpace(rawValue: value) else {
        throw WorkflowCLIError(
            "unsupportedRegionSpace",
            "\(path) must be screenPixels, displayPixels, windowPixels, contentPixels, framePixels, or normalizedFrame.",
            path: path
        )
    }
    return space
}

private func parseRecordingCLIRegion(
    _ value: String,
    coordinateSpace: RecordingCoordinateSpace,
    path: String
) throws -> RecordingBounds {
    let parts = value
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard parts.count == 4,
          let x = Double(parts[0]),
          let y = Double(parts[1]),
          let width = Double(parts[2]),
          let height = Double(parts[3]),
          width > 0,
          height > 0 else {
        throw WorkflowCLIError(
            "invalidRegion",
            "\(path) must be x,y,width,height with positive width and height.",
            path: path
        )
    }
    return RecordingBounds(
        rect: RecordingRect(x: x, y: y, width: width, height: height),
        coordinateSpace: coordinateSpace
    )
}

private func parseWorkflowCLIDraftSchedule(
    type: String,
    startAt: Date?,
    every: Int?,
    unit: String?,
    timeZone: String?
) -> AutomationWorkflowDraftSchedule? {
    let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedType != "none" else {
        return nil
    }
    return AutomationWorkflowDraftSchedule(
        type: normalizedType,
        startAt: startAt,
        every: every,
        unit: unit,
        timeZone: timeZone
    )
}

private func parseWorkflowCLIDate(_ value: String) throws -> Date {
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
    throw WorkflowCLIError("invalidDate", "--at must be ISO-8601 or a Unix timestamp.", path: "--at")
}

private func workflowCLIISO8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func encodeWorkflowCLIJSON<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
        return try encoder.encode(value)
    } catch {
        throw WorkflowCLIError("jsonEncodeFailed", "Could not encode workflow JSON: \(error.localizedDescription)")
    }
}

private func writeWorkflowCLIFile(_ data: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    do {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    } catch {
        throw WorkflowCLIError("fileWriteFailed", "Could not write file '\(path)': \(error.localizedDescription)", path: path)
    }
}

private func writeWorkflowJSON<Value: Encodable>(_ value: Value) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(value) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func writeWorkflowDraftFromRecordingSummary(_ payload: AutomationWorkflowDraftFromRecordingPayload) {
    var lines = [
        "SparkleRecorder: generated workflow draft from recording.",
        "- recording \(payload.recordingID.uuidString)",
        "- workflow \(payload.result.document.workflow.name)",
        "- tasks \(payload.result.generatedTaskCount), dependencies \(payload.result.document.workflow.dependencies.count)",
        "- applied \(payload.result.appliedItems.count), skipped \(payload.result.skippedItems.count)",
        "- valid \(payload.result.isValid ? "yes" : "no")"
    ]
    if payload.fixtureMode, let fixture = payload.fixture {
        lines.append("- fixture \(fixture)")
    } else if let sourceOption = payload.sourceOption {
        lines.append("- source \(sourceOption)")
    }
    if let wrotePath = payload.wrotePath {
        lines.append("- wrote \(wrotePath)")
    }
    for issue in payload.result.validation.issues {
        lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
    }
    for skipped in payload.result.skippedItems {
        let id = skipped.suggestionID?.uuidString ?? skipped.candidateID ?? skipped.source.rawValue
        lines.append("- [warning] skipped \(skipped.source.rawValue) \(id): \(skipped.reason)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowDraftEditSummary(_ result: AutomationWorkflowDraftEditResult) {
    var lines = [
        "SparkleRecorder: \(result.operation) applied.",
        "- workflow \(result.document.workflow.name)",
        "- tasks \(result.document.workflow.tasks.count), dependencies \(result.document.workflow.dependencies.count)",
        "- valid \(result.isValid ? "yes" : "no")"
    ]
    if let wrotePath = result.wrotePath {
        lines.append("- wrote \(wrotePath)")
    }
    if !result.changedTaskKeys.isEmpty {
        lines.append("- changed tasks \(result.changedTaskKeys.joined(separator: ", "))")
    }
    if !result.changedDependencyKeys.isEmpty {
        lines.append("- changed dependencies \(result.changedDependencyKeys.joined(separator: ", "))")
    }
    for issue in result.validation.issues {
        lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowValidationSummary(_ result: AutomationWorkflowDraftValidationResult) {
    var lines: [String] = [
        result.isValid ? "SparkleRecorder: workflow draft is valid." : "SparkleRecorder: workflow draft has errors."
    ]
    for issue in result.issues {
        lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowSimulationSummary(_ result: AutomationWorkflowDraftSimulationResult) {
    var lines: [String] = [
        result.isSimulatable ? "SparkleRecorder: workflow draft simulation." : "SparkleRecorder: workflow draft cannot be simulated."
    ]
    for step in result.steps {
        lines.append("- #\(step.order + 1) \(step.taskKey) \(step.outcome.rawValue) \(step.durationSeconds)s")
    }
    for issue in result.validationIssues {
        lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowImportSummary(_ result: AutomationWorkflowDraftImportResult) {
    var lines: [String] = [
        result.isImportable
            ? (result.mode == .confirm ? "SparkleRecorder: workflow import confirmed." : "SparkleRecorder: workflow import dry-run passed.")
            : (result.mode == .confirm ? "SparkleRecorder: workflow import failed." : "SparkleRecorder: workflow import dry-run failed.")
    ]
    if let workflow = result.workflow {
        lines.append("- workflow \(workflow.id.uuidString) \(workflow.name)")
        lines.append("- tasks \(workflow.tasks.count), dependencies \(workflow.dependencies.count)")
    }
    for resolution in result.macroResolutions {
        lines.append("- macro \(resolution.taskKey): \(resolution.macroID?.uuidString ?? "unresolved")")
    }
    for issue in result.validationIssues {
        lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowListSummary(_ summaries: [AutomationWorkflowSummary]) {
    var lines = ["SparkleRecorder: \(summaries.count) workflows"]
    for summary in summaries {
        lines.append("- \(summary.id.uuidString)  \(summary.name)  \(summary.taskCount) tasks, \(summary.dependencyCount) dependencies, \(summary.runCount) runs")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowStatusSummary(_ payload: AutomationWorkflowStatusPayload?) {
    guard let payload else {
        FileHandle.standardOutput.write(Data("SparkleRecorder: workflow status unavailable.\n".utf8))
        return
    }

    var lines = ["SparkleRecorder: \(payload.count) workflow statuses"]
    for workflowStatus in payload.workflows {
        lines.append("- \(workflowStatus.summary.id.uuidString)  \(workflowStatus.summary.name)  \(workflowStatus.statusLabel)")
        lines.append("  \(workflowStatus.statusDetail)")
        for task in workflowStatus.tasks {
            lines.append("  - \(task.taskName): \(task.statusLabel)")
        }
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowRunSummary(_ payload: AutomationWorkflowRunPayload) {
    var lines = [
        payload.timedOut
            ? "SparkleRecorder: workflow run wait timed out."
            : "SparkleRecorder: workflow run finished.",
        "- workflow \(payload.workflowID.uuidString) \(payload.workflowName)",
        "- task \(payload.requestedTaskID.uuidString)",
        "- run \(payload.startedRunID?.uuidString ?? "not-created")",
        "- complete \(payload.isComplete ? "yes" : "no")"
    ]
    for run in payload.executionRuns {
        lines.append("- \(run.id.uuidString) \(run.status) \(run.outcome.map(String.init(describing:)) ?? "pending")")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowBoundWindowAcceptanceSummary(
    _ payload: AutomationWorkflowBoundWindowAcceptancePayload
) {
    var lines = [
        payload.readyForBoundWindowPlayback
            ? "SparkleRecorder: bound-window workflow acceptance is ready."
            : "SparkleRecorder: bound-window workflow acceptance is not ready.",
        "- workflow \(payload.workflowID.uuidString) \(payload.workflowName)",
        "- task \(payload.taskID.uuidString) \(payload.taskName)",
        "- macro \(payload.macroID.uuidString) \(payload.macroName)",
        "- events \(payload.macroEventCount)",
        "- surfaces \(payload.macroSurfaceCount)",
        "- coordinateMode \(payload.coordinateMode.rawValue)",
        "- foregroundInput \(payload.resourceRequiresForegroundInput ? "yes" : "no")"
    ]

    for surface in payload.surfaces {
        let target = [
            surface.bundleIdentifier,
            surface.windowTitle,
            surface.appName
        ]
            .compactMap { $0?.nilIfEmptyForWorkflowCLISummary }
            .joined(separator: " · ")
        lines.append("- surface \(surface.surfaceID) \(target)")
    }

    for result in payload.activationResults {
        let status = result.didActivate ? "activated" : "not-activated"
        var line = "- app \(result.bundleIdentifier) \(status)"
        if result.didLaunch {
            line += " launched"
        } else if result.wasRunning {
            line += " already-running"
        }
        if let errorMessage = result.errorMessage {
            line += " — \(errorMessage)"
        }
        lines.append(line)
    }

    if let handoff = payload.handoff {
        lines.append("- handoff \(handoff.command.id.uuidString)")
        lines.append("- pending \(handoff.pendingCommandCount)")
    } else if payload.playbackHandoffRequested {
        lines.append("- handoff not-created")
    }

    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowCancelSummary(_ payload: AutomationWorkflowCancelPayload) {
    var lines = [
        payload.cancelled
            ? "SparkleRecorder: workflow run cancelled."
            : "SparkleRecorder: workflow run was already terminal or not cancellable.",
        "- run \(payload.runID.uuidString)"
    ]
    if let run = payload.run {
        lines.append("- status \(run.status)")
        if let outcome = run.outcome {
            lines.append("- outcome \(outcome)")
        }
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowHandoffSummary(_ payload: AutomationRuntimeHandoffPayload) {
    let description: String
    switch payload.command.kind {
    case .manualStart(let workflowID, let taskID):
        description = "start workflow \(workflowID.uuidString) task \(taskID.uuidString)"
    case .cancelRun(let runID):
        description = "cancel run \(runID.uuidString)"
    }
    let lines = [
        "SparkleRecorder: workflow command handed off to App host.",
        "- command \(payload.command.id.uuidString)",
        "- target \(payload.target.rawValue)",
        "- action \(description)",
        "- pending \(payload.pendingCommandCount)"
    ]
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowHandoffStatusSummary(_ payload: AutomationRuntimeHandoffStatusPayload) {
    var lines = [
        "SparkleRecorder: workflow handoff \(payload.state.rawValue).",
        "- command \(payload.commandID.uuidString)",
        "- target \(payload.target.rawValue)",
        "- pending \(payload.pendingCommandCount)",
        "- receipts \(payload.receiptCount)"
    ]
    if let command = payload.command {
        lines.append("- queued \(workflowHandoffDescription(command.kind))")
    }
    if let receipt = payload.receipt {
        lines.append("- handledAt \(workflowCLIISO8601String(receipt.handledAt))")
        lines.append("- status \(receipt.status.rawValue)")
        if !receipt.runIDs.isEmpty {
            lines.append("- runs \(receipt.runIDs.map(\.uuidString).joined(separator: ", "))")
        }
        if let message = receipt.message, !message.isEmpty {
            lines.append("- message \(message)")
        }
    }
    if let workflowStatus = payload.workflowStatus {
        lines.append("- workflow \(workflowStatus.summary.id.uuidString) \(workflowStatus.summary.name)")
        lines.append("- workflowStatus \(workflowStatus.overallStatus.rawValue) \(workflowStatus.statusLabel)")
    }
    for run in payload.runs {
        let outcome = run.outcome.map { String(describing: $0) } ?? "pending"
        lines.append("- run \(run.id.uuidString) \(String(describing: run.status)) \(outcome)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func workflowHandoffDescription(_ kind: AutomationRuntimeHandoffCommandKind) -> String {
    switch kind {
    case .manualStart(let workflowID, let taskID):
        return "start workflow \(workflowID.uuidString) task \(taskID.uuidString)"
    case .cancelRun(let runID):
        return "cancel run \(runID.uuidString)"
    }
}

private func writeWorkflowRunsSummary(_ payload: AutomationWorkflowRunsPayload?) {
    guard let payload else {
        FileHandle.standardOutput.write(Data("SparkleRecorder: workflow runs unavailable.\n".utf8))
        return
    }

    var lines = [
        "SparkleRecorder: \(payload.count) runs",
        "- workflow \(payload.workflowID.uuidString) \(payload.workflowName)",
        "- status \(payload.status.statusLabel)"
    ]
    for run in payload.runs {
        lines.append("- \(run.id.uuidString) \(run.status) \(run.outcome.map(String.init(describing:)) ?? "pending")")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowShowSummary(_ payload: AutomationWorkflowShowPayload?) {
    guard let payload else {
        FileHandle.standardOutput.write(Data("SparkleRecorder: workflow not found.\n".utf8))
        return
    }

    var lines = [
        "SparkleRecorder: workflow \(payload.workflow.id.uuidString)",
        "- name \(payload.workflow.name)",
        "- tasks \(payload.workflow.tasks.count), dependencies \(payload.workflow.dependencies.count), runs \(payload.runHistory.count)"
    ]
    for task in payload.workflow.tasks {
        lines.append("- task \(task.id.uuidString) \(task.name)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowExportSummary(
    _ result: AutomationWorkflowDraftExportResult,
    wrotePath: String?
) {
    var lines = [
        result.isExportable
            ? "SparkleRecorder: workflow exported as draft."
            : "SparkleRecorder: workflow export has errors.",
        "- workflow \(result.workflowID.uuidString) \(result.workflowName)",
        "- tasks \(result.document.workflow.tasks.count), dependencies \(result.document.workflow.dependencies.count)"
    ]
    if let wrotePath {
        lines.append("- wrote \(wrotePath)")
    }
    for issue in result.issues {
        lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowMacroSummary(_ entries: [AutomationWorkflowDraftMacroCatalogEntry]) {
    var lines = ["SparkleRecorder: \(entries.count) macros"]
    for entry in entries {
        lines.append("- \(entry.id.uuidString)  \(entry.name)  \(entry.eventCount) events")
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

private func writeWorkflowError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private extension String {
    var nilIfEmptyForWorkflowCLISummary: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

if args.count >= 2, args[1] == "--self-test" {
    print("→ Running SparkleRecorder self-test...")
    // 1. TextMacroFormat round-trip
    let events = [
        RecordedEvent.make(.mouseMoved, time: 0.0, x: 100, y: 200),
        RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 200, mouseButton: 0, clickCount: 1),
        RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 200, mouseButton: 0, clickCount: 1)
    ]
    let text = TextMacroFormat.export(events)
    do {
        let parsed = try TextMacroFormat.parse(text)
        if parsed.events.count != events.count {
            print("❌ Self-test failed: TextMacroFormat round-trip mismatch count")
            exit(1)
        }
    } catch {
        print("❌ Self-test failed: TextMacroFormat parse error \(error)")
        exit(1)
    }
    
    // 2. PointResolver offset
    let resolver = PointResolver()
    let surface = PlaybackSurface(recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600))
    let currentFrame = RectValue(x: 200, y: 150, width: 800, height: 600)
    let ctx = PlaybackContext(surfaces: ["surface-1": surface], currentSurfaceFrames: ["surface-1": currentFrame], coordinateMode: .boundWindowOffset)
    let resolvedResult = resolver.resolve(events[0], context: ctx)
    guard case .success(let resolved) = resolvedResult else {
        print("❌ Self-test failed: PointResolver offset calculation failed")
        exit(1)
    }
    if resolved.x != 200 || resolved.y != 250 {
        print("❌ Self-test failed: PointResolver offset calculation wrong (\(resolved.x),\(resolved.y))")
        exit(1)
    }
    
    // 3. EventGrouper verification
    let grouper = EventGrouper()
    let clickEvents = [
        RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
        RecordedEvent.make(.leftMouseUp, time: 0.2, x: 100, y: 100)
    ]
    let clickGroups = grouper.group(clickEvents)
    if clickGroups.count != 1 || clickGroups[0].kind != .click {
        print("❌ Self-test failed: EventGrouper click grouping wrong")
        exit(1)
    }

    // 4. Strict Keyboard Continuity self-test
    let kbEvents = [
        RecordedEvent.make(.keyDown, time: 0.1, keyCode: 49, flags: 0),
        RecordedEvent.make(.leftMouseDown, time: 0.2, x: 100, y: 100),
        RecordedEvent.make(.leftMouseUp, time: 0.3, x: 100, y: 100),
        RecordedEvent.make(.keyUp, time: 0.4, keyCode: 49, flags: 0)
    ]
    let kbGroups = grouper.group(kbEvents)
    if kbGroups.count != 3 || kbGroups[0].kind != .keyPress || kbGroups[1].kind != .click || kbGroups[2].kind != .keyPress {
        print("❌ Self-test failed: EventGrouper keyboard continuity / interruption logic wrong")
        exit(1)
    }

    // 5. LongPress and KeyHold duration check
    let lpEvents = [
        RecordedEvent.make(.leftMouseDown, time: 0.1, x: 100, y: 100),
        RecordedEvent.make(.leftMouseUp, time: 0.5, x: 100, y: 100) // 0.4s > 0.35s
    ]
    let lpGroups = grouper.group(lpEvents)
    if lpGroups.count != 1 || lpGroups[0].kind != .longPress {
        print("❌ Self-test failed: EventGrouper longPress grouping wrong")
        exit(1)
    }

    let khEvents = [
        RecordedEvent.make(.keyDown, time: 0.1, keyCode: 49, flags: 0),
        RecordedEvent.make(.keyUp, time: 0.5, keyCode: 49, flags: 0) // 0.4s > 0.35s
    ]
    let khGroups = grouper.group(khEvents)
    if khGroups.count != 1 || khGroups[0].kind != .keyHold {
        print("❌ Self-test failed: EventGrouper keyHold grouping wrong")
        exit(1)
    }

    // 6. Scroll direction compatibility check
    let scrollEvents = [
        RecordedEvent.make(.scrollWheel, time: 0.1, scrollDeltaY: -5, scrollDeltaX: 0),
        RecordedEvent.make(.scrollWheel, time: 0.2, scrollDeltaY: -4, scrollDeltaX: 0),
        RecordedEvent.make(.scrollWheel, time: 0.3, scrollDeltaY: 3, scrollDeltaX: 0) // reversed
    ]
    let scrollGroups = grouper.group(scrollEvents)
    if scrollGroups.count != 2 || scrollGroups[0].eventIndices.count != 2 || scrollGroups[1].eventIndices.count != 1 {
        print("❌ Self-test failed: EventGrouper scroll direction compatibility wrong")
        exit(1)
    }
    
    // 7. Semantic click/keyboard grouping
    var repeatedClickEvents: [RecordedEvent] = []
    for i in 0..<5 {
        let t = Double(i) * 0.12
        repeatedClickEvents.append(.make(.leftMouseDown, time: t, x: 100, y: 100, mouseButton: 0, clickCount: 1))
        repeatedClickEvents.append(.make(.leftMouseUp, time: t + 0.04, x: 100, y: 100, mouseButton: 0, clickCount: 1))
    }
    let repeatedClickGroups = grouper.group(repeatedClickEvents)
    if repeatedClickGroups.count != 1 || repeatedClickGroups[0].kind != .repeatedClick || repeatedClickGroups[0].clickCount != 5 {
        print("❌ Self-test failed: repeated click grouping wrong")
        exit(1)
    }
    
    let shortcutEvents = [
        RecordedEvent.make(.flagsChanged, time: 0.00, keyCode: 55, flags: ModFlag.command),
        RecordedEvent.make(.keyDown, time: 0.02, keyCode: 1, flags: ModFlag.command),
        RecordedEvent.make(.keyUp, time: 0.04, keyCode: 1, flags: ModFlag.command),
        RecordedEvent.make(.flagsChanged, time: 0.06, keyCode: 55, flags: 0)
    ]
    let shortcutGroups = grouper.group(shortcutEvents)
    if shortcutGroups.count != 1 || shortcutGroups[0].kind != .shortcut || !shortcutGroups[0].summary.contains("Cmd+S") {
        print("❌ Self-test failed: shortcut grouping wrong")
        exit(1)
    }
    
    var h = RecordedEvent.make(.keyDown, time: 0.10, keyCode: 4)
    h.unicodeString = "h"
    let hUp = RecordedEvent.make(.keyUp, time: 0.12, keyCode: 4)
    var i = RecordedEvent.make(.keyDown, time: 0.20, keyCode: 34)
    i.unicodeString = "i"
    let iUp = RecordedEvent.make(.keyUp, time: 0.22, keyCode: 34)
    let textGroups = grouper.group([h, hUp, i, iUp])
    if textGroups.count != 1 || textGroups[0].kind != .textInput || textGroups[0].unicodeString != "hi" {
        print("❌ Self-test failed: text input grouping wrong")
        exit(1)
    }
    
    // 8. Content coordinate priority and bounds
    var contentEvent = RecordedEvent.make(.leftMouseDown, time: 0, x: 500, y: 400, mouseButton: 0)
    contentEvent.coordinateBinding = .targetWindow
    contentEvent.surfaceId = "main"
    contentEvent.contentNormalizedX = 0.25
    contentEvent.contentNormalizedY = 0.5
    contentEvent.contentLocalX = 10
    contentEvent.contentLocalY = 10
    let contentSurface = PlaybackSurface(
        recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
        recordedContentFrame: RectValue(x: 100, y: 128, width: 800, height: 572)
    )
    let contentContext = PlaybackContext(
        surfaces: ["main": contentSurface],
        currentSurfaceFrames: ["main": RectValue(x: 300, y: 200, width: 900, height: 700)],
        currentContentFrames: ["main": RectValue(x: 300, y: 235, width: 900, height: 665)]
    )
    guard case .success(let contentPoint) = resolver.resolve(contentEvent, context: contentContext),
          abs(contentPoint.x - 525) < 0.001,
          abs(contentPoint.y - 567.5) < 0.001 else {
        print("❌ Self-test failed: content coordinate priority wrong")
        exit(1)
    }
    contentEvent.contentNormalizedX = 1.2
    guard case .failure(.resolvedPointOutOfBounds(_, _)) = resolver.resolve(contentEvent, context: contentContext) else {
        print("❌ Self-test failed: content coordinate bounds check wrong")
        exit(1)
    }
    
    // 9. Full scroll payload aggregation
    var firstScroll = RecordedEvent.make(.scrollWheel, time: 0.1, x: 200, y: 200, scrollDeltaY: -5, scrollDeltaX: 1)
    firstScroll.scrollPayload = ScrollPayload(deltaX: 1, deltaY: -5, lineDeltaX: 0, lineDeltaY: -1, phase: 1, momentumPhase: 0, fixedDeltaX: 0.5, fixedDeltaY: -1.5, isContinuous: true)
    var secondScroll = RecordedEvent.make(.scrollWheel, time: 0.2, x: 202, y: 202, scrollDeltaY: -4, scrollDeltaX: 2)
    secondScroll.scrollPayload = ScrollPayload(deltaX: 2, deltaY: -4, lineDeltaX: 1, lineDeltaY: -1, phase: 2, momentumPhase: 3, fixedDeltaX: 1.0, fixedDeltaY: -2.0, isContinuous: false)
    let payloadGroups = grouper.group([firstScroll, secondScroll])
    if payloadGroups.count != 1 ||
        payloadGroups[0].scrollPayload?.deltaX != 3 ||
        payloadGroups[0].scrollPayload?.deltaY != -9 ||
        payloadGroups[0].scrollPayload?.lineDeltaY != -2 ||
        payloadGroups[0].scrollPayload?.momentumPhase != 3 ||
        payloadGroups[0].scrollPayload?.fixedDeltaY != -3.5 ||
        payloadGroups[0].scrollPayload?.isContinuous != true {
        print("❌ Self-test failed: scroll payload aggregation wrong")
        exit(1)
    }
    
    print("✅ Self-test completed successfully!")
    exit(0)
}

if args.count >= 3, args[1] == "--play" {
    let path = args[2]
    let url = URL(fileURLWithPath: path)
    do {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        let events: [RecordedEvent]
        let speed: Double
        let loops: Int
        var context = PlaybackContext()
        var targetID: UUID? = nil
        if let saved = try? dec.decode(SavedMacro.self, from: data), !saved.events.isEmpty {
            events = saved.events
            speed = saved.speed
            // Continuous (0) would run forever with no in-app stop hotkey — clamp.
            loops = max(1, saved.loops)
            targetID = saved.id
            
            if !saved.surfaces.isEmpty {
                // Activate target apps immediately so they can be ready.
                // The actual window frames will be lazily resolved by WindowTracker.
                let bundleIDs = Set(saved.surfaces.values.compactMap { $0.bundleIdentifier })
                for bid in bundleIDs {
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                    if let app = apps.first {
                        if #available(macOS 14.0, *) {
                            app.activate()
                        } else {
                            app.activate(options: [.activateIgnoringOtherApps])
                        }
                    } else {
                        FileHandle.standardError.write(Data("SparkleRecorder: Warning: A target app is not running.\n".utf8))
                    }
                }
                
                context = saved.playbackContext
            }
        } else {
            let macro = try dec.decode(Macro.self, from: data)
            events = macro.events
            speed = 1.0
            loops = 1
        }

        // Post events from a background thread with plain sleeps — no run-loop
        // pumping, no MainActor hops, so timing stays faithful to the recording.
        let semaphore = DispatchSemaphore(value: 0)
        let playbackEvents = events
        let playbackLoops = loops
        let playbackSpeed = speed
        let playbackContext = context
        let playbackTargetID = targetID
        Thread.detachNewThread {
            Player.playSynchronously(
                macroID: playbackTargetID,
                events: playbackEvents,
                loops: playbackLoops,
                speed: playbackSpeed,
                context: playbackContext,
                windowTracker: WindowTracker()
            )
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("SparkleRecorder: failed to play \(path): \(error)\n".utf8))
        exit(1)
    }
}

// CLI conversion mode: ./SparkleRecorder --convert in.rec out.tinyrec
// Converts legacy Windows .rec or text .txt/.trm to .tinyrec (JSON) or .txt (TRM),
// chosen by the OUTPUT extension. No GUI, exempt from the single-instance guard.
if args.count >= 4, args[1] == "--convert" {
    let inURL = URL(fileURLWithPath: args[2])
    let outURL = URL(fileURLWithPath: args[3])
    do {
        let data = try Data(contentsOf: inURL)
        let inExt = inURL.pathExtension.lowercased()
        let result: MacroImportResult
        switch inExt {
        case "rec":
            result = try LegacyRecImporter.parse(data)
        case "txt", "trm":
            guard let text = String(data: data, encoding: .utf8) else {
                throw MacroImportError.notTextFormat("input is not UTF-8 text.")
            }
            result = try TextMacroFormat.parse(text)
        case "tinyrec", "json":
            let dec = JSONDecoder()
            if let saved = try? dec.decode(SavedMacro.self, from: data) {
                result = MacroImportResult(events: saved.events, parsed: saved.events.count, skipped: 0, warning: nil)
            } else {
                let macro = try dec.decode(Macro.self, from: data)
                result = MacroImportResult(events: macro.events, parsed: macro.events.count, skipped: 0, warning: nil)
            }
        default:
            // Sniff.
            if data.count % 20 == 0, let r = try? LegacyRecImporter.parse(data) {
                result = r
            } else if let text = String(data: data, encoding: .utf8), let r = try? TextMacroFormat.parse(text) {
                result = r
            } else {
                throw MacroImportError.unreadable("unrecognized input format.")
            }
        }

        let outExt = outURL.pathExtension.lowercased()
        let name = inURL.deletingPathExtension().lastPathComponent
        if outExt == "txt" || outExt == "trm" {
            try TextMacroFormat.export(result.events).write(to: outURL, atomically: true, encoding: .utf8)
        } else {
            let macro = SavedMacro(name: name, events: result.events)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            try enc.encode(macro).write(to: outURL)
        }

        var msg = "SparkleRecorder: converted \(result.events.count) events -> \(outURL.lastPathComponent)"
        if result.skipped > 0 { msg += " (\(result.skipped) skipped)" }
        if let w = result.warning { msg += "\n  warning: \(w)" }
        FileHandle.standardOutput.write(Data((msg + "\n").utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("SparkleRecorder: conversion failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// Single-instance guard: a second copy would double-register Carbon hotkeys,
// run a second event tap, and clobber library.json last-writer-wins.
let myPID = ProcessInfo.processInfo.processIdentifier
let twin = NSWorkspace.shared.runningApplications.first { app in
    app.processIdentifier != myPID &&
    (app.bundleIdentifier == "com.sparklerecorder.app" ||
     app.executableURL?.lastPathComponent == "SparkleRecorder")
}
if let twin {
    twin.activate()
    exit(0)
}

// Normal app mode — full Dock app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
