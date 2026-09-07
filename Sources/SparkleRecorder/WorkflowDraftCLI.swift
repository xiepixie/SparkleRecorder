import Foundation
import SparkleRecorderCore

package enum WorkflowDraftCLI {
    /// Pure workflow-draft commands do not need an app-side recording store.
    /// The overload keeps that common Interface small while `from-recording`
    /// explicitly requires the loader Seam below.
    package static func run(_ arguments: [String], wantsJSON: Bool) throws -> Int {
        try run(
            arguments,
            wantsJSON: wantsJSON,
            loadRecordingBundle: { _, _ in
                throw WorkflowCLIError(
                    "recordingSourceUnavailable",
                    "This workflow draft command requires a recording source adapter."
                )
            }
        )
    }

    package static func run(
        _ arguments: [String],
        wantsJSON: Bool,
        loadRecordingBundle: WorkflowRecordingBundleLoader
    ) throws -> Int {
        guard let command = arguments.first else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Unsupported workflow command 'draft'."
            )
        }

        let remaining = Array(arguments.dropFirst())
        switch command {
        case "validate":
            return try runValidate(remaining, command: "workflow draft validate", wantsJSON: wantsJSON)
        case "simulate":
            return try runSimulate(remaining, command: "workflow draft simulate", wantsJSON: wantsJSON)
        case "init":
            return try runInit(remaining, command: "workflow draft init", wantsJSON: wantsJSON)
        case "inspect":
            return try runInspect(remaining, command: "workflow draft inspect", wantsJSON: wantsJSON)
        case "normalize":
            return try runNormalize(remaining, command: "workflow draft normalize", wantsJSON: wantsJSON)
        case "from-recording":
            return try runFromRecording(
                remaining,
                command: "workflow draft from-recording",
                wantsJSON: wantsJSON,
                loadRecordingBundle: loadRecordingBundle
            )
        case "patch":
            return try runPatch(remaining, command: "workflow draft patch", wantsJSON: wantsJSON)
        case "task":
            guard arguments.count >= 3, let subcommand = remaining.first else {
                break
            }
            let nested = Array(remaining.dropFirst())
            switch subcommand {
            case "add":
                return try runTaskAdd(nested, command: "workflow draft task add", wantsJSON: wantsJSON)
            case "set":
                return try runTaskSet(nested, command: "workflow draft task set", wantsJSON: wantsJSON)
            case "remove":
                return try runTaskRemove(nested, command: "workflow draft task remove", wantsJSON: wantsJSON)
            default:
                break
            }
        case "loop":
            if arguments.count >= 3, remaining.first == "set" {
                return try runLoopSet(Array(remaining.dropFirst()), command: "workflow draft loop set", wantsJSON: wantsJSON)
            }
        case "schedule":
            if arguments.count >= 3, remaining.first == "set" {
                return try runScheduleSet(Array(remaining.dropFirst()), command: "workflow draft schedule set", wantsJSON: wantsJSON)
            }
        case "condition":
            if arguments.count >= 3, remaining.first == "set" {
                return try runConditionSet(Array(remaining.dropFirst()), command: "workflow draft condition set", wantsJSON: wantsJSON)
            }
        case "dependency":
            guard arguments.count >= 3, let subcommand = remaining.first else {
                break
            }
            let nested = Array(remaining.dropFirst())
            switch subcommand {
            case "add":
                return try runDependencyAdd(nested, command: "workflow draft dependency add", wantsJSON: wantsJSON)
            case "set":
                return try runDependencySet(nested, command: "workflow draft dependency set", wantsJSON: wantsJSON)
            case "remove":
                return try runDependencyRemove(nested, command: "workflow draft dependency remove", wantsJSON: wantsJSON)
            default:
                break
            }
        default:
            break
        }

        let suffix = (["draft"] + arguments).joined(separator: " ")
        throw WorkflowCLIError(
            "unsupportedCommand",
            "Unsupported workflow command '\(suffix)'."
        )
    }

    private static func runInit(
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
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runInspect(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft inspect")
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = AutomationWorkflowDraftEditor.inspect(document, context: context)
        return try finishEdit(result, outPath: nil, command: command, wantsJSON: wantsJSON)
    }

    private static func runNormalize(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft normalize")
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = AutomationWorkflowDraftEditor.normalize(document, context: context)
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runFromRecording(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool,
        loadRecordingBundle: WorkflowRecordingBundleLoader
    ) throws -> Int {
        var outPath: String?
        var workflowName: String?
        var maxTasks = 6
        var includeCandidateFallback = true
        let recordingBundle = try loadRecordingBundle(arguments) { token, index, arguments in
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
                maxTasks = try parseWorkflowCLIInt(arguments[index + 1], path: token)
                return 1
            case "--suggestions-only":
                includeCandidateFallback = false
                return 0
            default:
                return nil
            }
        }

        let suggestionResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: recordingBundle.bundle,
            fixture: recordingBundle.fixture,
            query: .kinds(SemanticRecordingCLISuggestionCategory.conditions.suggestionKinds)
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
            writeFromRecordingSummary(payload)
        }
        return result.isValid ? 0 : 1
    }

    private static func runPatch(
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

        let document = try loadDocument(path: draftPath, command: command)
        let patch = try loadPatchDocument(path: patchPath, command: command)
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = try AutomationWorkflowDraftPatchApplier.apply(patch, to: document, context: context)
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runTaskAdd(
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
                resource = try parseResource(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
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

        let document = try loadDocument(path: draftPath, command: "workflow draft task add")
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let graphPosition = try graphPoint(x: graphX, y: graphY)
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
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runTaskSet(
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
                resource = try parseResource(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
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

        let document = try loadDocument(path: draftPath, command: "workflow draft task set")
        guard let taskKey else {
            throw WorkflowCLIError("missingArgument", "workflow draft task set requires a task key.")
        }
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let graphPosition = try graphPoint(x: graphX, y: graphY)
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
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runTaskRemove(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft task remove")
        guard let taskKey else {
            throw WorkflowCLIError("missingArgument", "workflow draft task remove requires a task key.")
        }
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = try AutomationWorkflowDraftEditor.removeTask(key: taskKey, from: document, context: context)
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runLoopSet(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var draftPath: String?
        var taskKey: String?
        var outPath: String?
        var macroCatalogPath: String?
        var count: Int?
        var tasksJSON: String?
        var tasksFile: String?
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
            case "--count":
                count = try parseWorkflowCLIInt(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
            case "--tasks-json":
                tasksJSON = try workflowCLIValue(after: token, in: arguments, at: &index)
            case "--tasks-file":
                tasksFile = try workflowCLIValue(after: token, in: arguments, at: &index)
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

        let document = try loadDocument(path: draftPath, command: command)
        guard let taskKey else {
            throw WorkflowCLIError("missingArgument", "workflow draft loop set requires a task key.")
        }
        guard let count else {
            throw WorkflowCLIError("missingArgument", "workflow draft loop set requires --count.", path: "--count")
        }
        let tasks = try loadLoopTasks(tasksJSON: tasksJSON, tasksFile: tasksFile)
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = try AutomationWorkflowDraftEditor.setLoop(
            taskKey: taskKey,
            count: count,
            tasks: tasks,
            in: document,
            context: context
        )
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runScheduleSet(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft schedule set")
        guard let taskKey else {
            throw WorkflowCLIError("missingArgument", "workflow draft schedule set requires a task key.")
        }
        guard let scheduleType else {
            throw WorkflowCLIError("missingArgument", "workflow draft schedule set requires --type.", path: "--type")
        }
        let schedule = draftSchedule(type: scheduleType, startAt: startAt, every: every, unit: unit, timeZone: timeZone)
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = try AutomationWorkflowDraftEditor.setSchedule(
            taskKey: taskKey,
            schedule: schedule,
            in: document,
            context: context
        )
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runConditionSet(
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
        var pixelSampleRadius: Int?
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
            case "--pixel-sample-radius", "--sample-radius":
                pixelSampleRadius = try parseWorkflowCLIInt(workflowCLIValue(after: token, in: arguments, at: &index), path: token)
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

        let document = try loadDocument(path: draftPath, command: "workflow draft condition set")
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
            pixel: try optionalPoint(x: pixelX, y: pixelY),
            colorHex: colorHex,
            pixelSampleRadius: pixelSampleRadius,
            threshold: threshold
        )
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
        let result = try AutomationWorkflowDraftEditor.setCondition(
            taskKey: taskKey,
            condition: condition,
            in: document,
            timeoutSeconds: timeoutSeconds,
            pollingSeconds: pollingSeconds,
            context: context
        )
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runDependencyAdd(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft dependency add")
        guard let from else {
            throw WorkflowCLIError("missingArgument", "workflow draft dependency add requires --from.", path: "--from")
        }
        guard let to else {
            throw WorkflowCLIError("missingArgument", "workflow draft dependency add requires --to.", path: "--to")
        }
        guard let trigger else {
            throw WorkflowCLIError("missingArgument", "workflow draft dependency add requires --trigger.", path: "--trigger")
        }

        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
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
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runDependencySet(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft dependency set")
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
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
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runDependencyRemove(
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

        let document = try loadDocument(path: draftPath, command: "workflow draft dependency remove")
        let context = try loadValidationContext(macroCatalogPath: macroCatalogPath)
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
        return try finishEdit(result, outPath: outPath, command: command, wantsJSON: wantsJSON)
    }

    private static func runValidate(
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
        let macroCatalog = try loadMacroCatalog(path: macroCatalogPath)
        let result = AutomationWorkflowDraftValidator.validate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog)
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>
            .workflowDraftValidation(command: command, result: result)

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeValidationSummary(result)
        }
        return result.isValid ? 0 : 1
    }

    private static func runSimulate(
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
                    throw WorkflowCLIError(
                        "invalidScenario",
                        "Scenario must look like timeout:<task>, failure:<task>, or conditionNotMatched:<task>.",
                        path: token
                    )
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
        let macroCatalog = try loadMacroCatalog(path: macroCatalogPath)
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
            writeSimulationSummary(result)
        }
        return result.isSimulatable ? 0 : 1
    }

    private static func loadDocument(path: String?, command: String) throws -> AutomationWorkflowDraftDocument {
        guard let path else {
            throw WorkflowCLIError("missingArgument", "\(command) requires a draft JSON file path.")
        }
        let data = try readWorkflowCLIFile(at: path)
        return try decodeWorkflowCLIJSON(AutomationWorkflowDraftDocument.self, from: data)
    }

    private static func loadPatchDocument(path: String?, command: String) throws -> AutomationWorkflowDraftPatchDocument {
        guard let path else {
            throw WorkflowCLIError("missingArgument", "\(command) requires a patch JSON file path.")
        }
        let data = try readWorkflowCLIFile(at: path)
        return try decodeWorkflowCLIJSON(AutomationWorkflowDraftPatchDocument.self, from: data)
    }

    private static func loadLoopTasks(
        tasksJSON: String?,
        tasksFile: String?
    ) throws -> [AutomationWorkflowDraftTask] {
        switch (tasksJSON, tasksFile) {
        case (.some, .some):
            throw WorkflowCLIError(
                "conflictingArguments",
                "Use either --tasks-json or --tasks-file, not both.",
                path: "--tasks-json"
            )
        case (.some(let json), .none):
            return try decodeWorkflowCLIJSON([AutomationWorkflowDraftTask].self, from: Data(json.utf8))
        case (.none, .some(let path)):
            let data = try readWorkflowCLIFile(at: path)
            return try decodeWorkflowCLIJSON([AutomationWorkflowDraftTask].self, from: data)
        case (.none, .none):
            throw WorkflowCLIError(
                "missingArgument",
                "workflow draft loop set requires --tasks-json or --tasks-file.",
                path: "--tasks-json"
            )
        }
    }

    private static func loadValidationContext(
        macroCatalogPath: String?
    ) throws -> AutomationWorkflowDraftValidationContext {
        AutomationWorkflowDraftValidationContext(
            macroCatalog: try loadMacroCatalog(path: macroCatalogPath)
        )
    }

    private static func loadMacroCatalog(path: String?) throws -> [AutomationWorkflowDraftMacroCatalogEntry] {
        guard let path else { return [] }
        let data = try readWorkflowCLIFile(at: path)
        return try decodeWorkflowMacroCatalog(from: data)
    }

    private static func finishEdit(
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
            writeEditSummary(finalResult)
        }
        return 0
    }

    private static func graphPoint(x: Double?, y: Double?) throws -> AutomationGraphPoint? {
        switch (x, y) {
        case (.none, .none):
            return nil
        case (.some(let x), .some(let y)):
            return AutomationGraphPoint(x: x, y: y)
        default:
            throw WorkflowCLIError("missingArgument", "Graph position needs both --x and --y.")
        }
    }

    private static func optionalPoint(x: Double?, y: Double?) throws -> AutomationGraphPoint? {
        switch (x, y) {
        case (.none, .none):
            return nil
        case (.some(let x), .some(let y)):
            return AutomationGraphPoint(x: x, y: y)
        default:
            throw WorkflowCLIError("missingArgument", "Pixel match needs both --pixel-x and --pixel-y.")
        }
    }

    private static func parseResource(
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

    private static func draftSchedule(
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

    private static func writeFromRecordingSummary(_ payload: AutomationWorkflowDraftFromRecordingPayload) {
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

    private static func writeEditSummary(_ result: AutomationWorkflowDraftEditResult) {
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

    private static func writeValidationSummary(_ result: AutomationWorkflowDraftValidationResult) {
        var lines: [String] = [
            result.isValid ? "SparkleRecorder: workflow draft is valid." : "SparkleRecorder: workflow draft has errors."
        ]
        for issue in result.issues {
            lines.append("- [\(issue.severity.rawValue)] \(issue.code.rawValue): \(issue.message)")
        }
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private static func writeSimulationSummary(_ result: AutomationWorkflowDraftSimulationResult) {
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
}
