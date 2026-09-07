import Cocoa
import SparkleRecorderCore
import SparkleRecorderTooling

// CLI playback mode: ./SparkleRecorder --play /path/to/macro.tinyrec
// Used by exported .command scripts. Exempt from the single-instance guard —
// it never touches the library.
let args = CommandLine.arguments

if args.count >= 2, args[1] == "reconstruction" {
    let reconstructionArguments = Array(args.dropFirst(2))
    let wantsJSON = reconstructionArguments.contains("--json")
    let command = "reconstruction " + (reconstructionArguments.first ?? "")
    do {
        let result = try waitForWorkflowCLIAsync {
            try await MacroReconstructionCLI.execute(reconstructionArguments)
        }
        if wantsJSON {
            writeWorkflowJSON(AutomationCLIResultEnvelope(ok: true, command: command, data: result))
        } else {
            FileHandle.standardOutput.write(Data((result.summary + "\n").utf8))
        }
        exit(0)
    } catch {
        if wantsJSON {
            writeWorkflowJSON(AutomationCLIResultEnvelope<AutomationCLIEmptyPayload>.failure(
                command: command, code: (error as? MacroReconstructionCLIError)?.code ?? "commandFailed",
                message: error.localizedDescription))
        } else {
            FileHandle.standardError.write(Data(("SparkleRecorder: " + error.localizedDescription + "\n").utf8))
        }
        exit(1)
    }
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
    let command = SemanticRecordingCLI.commandName(recordingArgs)

    do {
        let exitCode = try SemanticRecordingCLI.run(recordingArgs, wantsJSON: wantsJSON)
        exit(Int32(exitCode))
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
            let exitCode = try SemanticRecordingDebugSmokeCLI.run(
                Array(semanticArgs.dropFirst()),
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

        if workflowArgs[0] == "product-evidence" {
            let exitCode = try WorkflowProductEvidenceCLI.run(
                Array(workflowArgs.dropFirst()),
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

        if workflowArgs[0] == "draft" {
            let exitCode = try WorkflowDraftCLI.run(
                Array(workflowArgs.dropFirst()),
                wantsJSON: wantsJSON,
                loadRecordingBundle: { arguments, additionalOptionHandler in
                    try RecordingCLIBundleLoader.load(
                        arguments,
                        additionalOptionHandler: additionalOptionHandler
                    )
                }
            )
            exit(Int32(exitCode))
        }

        guard workflowArgs.count >= 2 else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Unsupported workflow command '\(workflowArgs.joined(separator: " "))'."
            )
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

    let manifests = try WorkflowMacroCatalog.load(macrosDirectory: macrosDirectory)
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

    let macro = try WorkflowMacroCatalog.load(macrosDirectory: macrosDirectory)
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
            try WorkflowMacroCatalog.load(macrosDirectory: macrosDirectory)
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

private func workflowCommandName(_ workflowArgs: [String]) -> String {
    guard !workflowArgs.isEmpty else {
        return "workflow"
    }
    return "workflow " + workflowArgs.prefix(3).joined(separator: " ")
}

private func semanticRecordingCommandName(_ semanticArgs: [String]) -> String {
    guard !semanticArgs.isEmpty else {
        return "semantic-recording"
    }
    return "semantic-recording " + semanticArgs.prefix(1).joined(separator: " ")
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
    guard CGPreflightPostEventAccess() else {
        FileHandle.standardError.write(Data((String(localized: "Playback is blocked. Enable SparkleRecorder in System Settings > Privacy & Security > Accessibility, then reopen the app and retry.", table: "Recording") + "\n").utf8))
        exit(1)
    }
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
AppLanguagePreference.bootstrap()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
