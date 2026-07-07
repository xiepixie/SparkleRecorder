import Foundation

public enum AutomationWorkflowDraftImportMode: String, Codable, Equatable, Sendable {
    case dryRun
    case confirm
}

public struct AutomationWorkflowDraftImportOptions: Equatable, Sendable {
    public var mode: AutomationWorkflowDraftImportMode
    public var importedAt: Date
    public var stableIDNamespace: String

    public init(
        mode: AutomationWorkflowDraftImportMode = .dryRun,
        importedAt: Date = Date.now,
        stableIDNamespace: String = "sparkle.workflow.import.v1"
    ) {
        self.mode = mode
        self.importedAt = importedAt
        self.stableIDNamespace = stableIDNamespace
    }
}

public struct AutomationWorkflowDraftImportResult: Codable, Equatable, Sendable {
    public var mode: AutomationWorkflowDraftImportMode
    public var isImportable: Bool
    public var workflow: AutomationWorkflow?
    public var taskKeyToID: [String: UUID]
    public var dependencyKeyToID: [String: UUID]
    public var macroResolutions: [AutomationWorkflowDraftMacroResolution]
    public var validationIssues: [AutomationWorkflowDraftIssue]
    public var workflowValidationIssues: [AutomationWorkflowValidationIssue]

    public init(
        mode: AutomationWorkflowDraftImportMode,
        isImportable: Bool,
        workflow: AutomationWorkflow?,
        taskKeyToID: [String: UUID],
        dependencyKeyToID: [String: UUID],
        macroResolutions: [AutomationWorkflowDraftMacroResolution],
        validationIssues: [AutomationWorkflowDraftIssue],
        workflowValidationIssues: [AutomationWorkflowValidationIssue]
    ) {
        self.mode = mode
        self.isImportable = isImportable
        self.workflow = workflow
        self.taskKeyToID = taskKeyToID
        self.dependencyKeyToID = dependencyKeyToID
        self.macroResolutions = macroResolutions
        self.validationIssues = validationIssues
        self.workflowValidationIssues = workflowValidationIssues
    }
}

public struct AutomationWorkflowDraftMacroResolution: Codable, Equatable, Sendable {
    public var taskKey: String
    public var macroID: UUID?
    public var macroName: String?
    public var source: AutomationWorkflowDraftMacroResolutionSource

    public init(
        taskKey: String,
        macroID: UUID?,
        macroName: String?,
        source: AutomationWorkflowDraftMacroResolutionSource
    ) {
        self.taskKey = taskKey
        self.macroID = macroID
        self.macroName = macroName
        self.source = source
    }
}

public enum AutomationWorkflowDraftMacroResolutionSource: String, Codable, Equatable, Sendable {
    case id
    case catalogName
    case unresolved
}

public enum AutomationWorkflowDraftImporter {
    public static func compile(
        _ document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext(),
        options: AutomationWorkflowDraftImportOptions = AutomationWorkflowDraftImportOptions()
    ) -> AutomationWorkflowDraftImportResult {
        DraftImportCompiler(
            document: document,
            context: context,
            options: options
        ).compile()
    }

    public static func dryRun(
        _ document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext(),
        options: AutomationWorkflowDraftImportOptions = AutomationWorkflowDraftImportOptions()
    ) -> AutomationWorkflowDraftImportResult {
        compile(
            document,
            context: context,
            options: AutomationWorkflowDraftImportOptions(
                mode: .dryRun,
                importedAt: options.importedAt,
                stableIDNamespace: options.stableIDNamespace
            )
        )
    }
}

private struct DraftImportCompiler {
    var document: AutomationWorkflowDraftDocument
    var context: AutomationWorkflowDraftValidationContext
    var options: AutomationWorkflowDraftImportOptions

    func compile() -> AutomationWorkflowDraftImportResult {
        var issues = AutomationWorkflowDraftValidator
            .validate(document, context: context)
            .issues
        guard !issues.contains(where: { $0.severity == .error }) else {
            return AutomationWorkflowDraftImportResult(
                mode: options.mode,
                isImportable: false,
                workflow: nil,
                taskKeyToID: [:],
                dependencyKeyToID: [:],
                macroResolutions: [],
                validationIssues: issues,
                workflowValidationIssues: []
            )
        }

        let expandedDocument = AutomationWorkflowDraftLoopExpander.expandedDocument(document)
        let workflowID = stableID(for: "workflow:\(document.workflow.name.trimmedForDraftImport)")
        var taskKeyToID: [String: UUID] = [:]
        var tasks: [AutomationTask] = []
        var macroResolutions: [AutomationWorkflowDraftMacroResolution] = []

        for (index, task) in expandedDocument.workflow.tasks.enumerated() {
            let taskKey = task.key.trimmedForDraftImport
            let taskID = stableID(for: "workflow:\(workflowID.uuidString):task:\(taskKey)")
            taskKeyToID[taskKey] = taskID

            let conversion = convertTask(task, index: index, taskID: taskID)
            issues.append(contentsOf: conversion.issues)
            macroResolutions.append(contentsOf: conversion.macroResolution.map { [$0] } ?? [])
            if let converted = conversion.task {
                tasks.append(converted)
            }
        }

        guard !issues.contains(where: { $0.severity == .error }) else {
            return AutomationWorkflowDraftImportResult(
                mode: options.mode,
                isImportable: false,
                workflow: nil,
                taskKeyToID: taskKeyToID,
                dependencyKeyToID: [:],
                macroResolutions: macroResolutions,
                validationIssues: issues,
                workflowValidationIssues: []
            )
        }

        var dependencyKeyToID: [String: UUID] = [:]
        let dependencies = expandedDocument.workflow.dependencies.compactMap { dependency -> AutomationDependency? in
            let dependencyKey = key(for: dependency)
            guard let fromID = taskKeyToID[dependency.from.trimmedForDraftImport],
                  let toID = taskKeyToID[dependency.to.trimmedForDraftImport],
                  let trigger = trigger(for: dependency.trigger)
            else {
                return nil
            }
            let dependencyID = stableID(for: "workflow:\(workflowID.uuidString):dependency:\(dependencyKey)")
            dependencyKeyToID[dependencyKey] = dependencyID
            return AutomationDependency(
                id: dependencyID,
                fromTaskID: fromID,
                toTaskID: toID,
                trigger: trigger,
                delay: dependency.delaySeconds ?? 0,
                isEnabled: dependency.enabled ?? true
            )
        }

        var workflow = AutomationWorkflow(
            id: workflowID,
            version: 1,
            name: document.workflow.name.trimmedForDraftImport,
            tasks: tasks,
            dependencies: dependencies,
            visualAssets: expandedDocument.visualAssets,
            createdAt: options.importedAt,
            modifiedAt: options.importedAt
        )
        let workflowIssues = workflow.validationIssues()
        if !workflowIssues.isEmpty {
            issues.append(contentsOf: workflowIssues.map(importIssue(for:)))
            workflow.tasks = []
            workflow.dependencies = []
        }

        let importable = !issues.contains(where: { $0.severity == .error }) && workflowIssues.isEmpty
        return AutomationWorkflowDraftImportResult(
            mode: options.mode,
            isImportable: importable,
            workflow: importable ? workflow : nil,
            taskKeyToID: taskKeyToID,
            dependencyKeyToID: dependencyKeyToID,
            macroResolutions: macroResolutions,
            validationIssues: issues,
            workflowValidationIssues: workflowIssues
        )
    }

    private struct TaskConversion {
        var task: AutomationTask?
        var macroResolution: AutomationWorkflowDraftMacroResolution?
        var issues: [AutomationWorkflowDraftIssue]
    }

    private func convertTask(
        _ task: AutomationWorkflowDraftTask,
        index: Int,
        taskID: UUID
    ) -> TaskConversion {
        let path = "$.workflow.tasks[\(index)]"
        let taskKey = task.key.trimmedForDraftImport
        var issues: [AutomationWorkflowDraftIssue] = []
        var macroResolution: AutomationWorkflowDraftMacroResolution?

        let kind: AutomationTaskKind?
        switch task.type.trimmedForDraftImport {
        case "macro":
            let resolution = resolveMacro(task: task, path: path)
            issues.append(contentsOf: resolution.issues)
            macroResolution = resolution.macroResolution
            if let macroID = resolution.macroResolution.macroID {
                kind = .macro(macroID: macroID)
            } else {
                kind = nil
            }

        case "delay":
            kind = .delay(task.delaySeconds ?? 0)

        case "notification":
            let severity = notificationSeverity(
                task.notification?.severity,
                path: "\(path).notification.severity",
                taskKey: taskKey,
                issues: &issues
            )
            kind = .notification(AutomationNotificationSpec(
                title: task.notification?.title.trimmedForDraftImport ?? taskKey,
                body: task.notification?.body?.trimmedForDraftImport ?? "",
                severity: severity
            ))

        case "condition":
            kind = conditionKind(for: task, path: path, issues: &issues)

        case "manualApproval":
            kind = .condition(AutomationConditionSpec(
                id: stableID(for: "condition:\(taskKey)"),
                name: displayName(for: task, fallback: taskKey),
                kind: .manualApproval,
                timeout: task.timeoutSeconds,
                pollingInterval: task.pollingSeconds ?? 0.25
            ))

        default:
            kind = nil
        }

        guard let kind else {
            return TaskConversion(task: nil, macroResolution: macroResolution, issues: issues)
        }

        return TaskConversion(
            task: AutomationTask(
                id: taskID,
                name: displayName(for: task, fallback: taskKey),
                kind: kind,
                schedule: schedule(for: task.schedule),
                resourceRequirement: resourceRequirement(for: task, kind: kind),
                timeout: task.timeoutSeconds,
                retryPolicy: retryPolicy(for: task.retry),
                joinPolicy: joinPolicy(for: task.joinPolicy),
                isEnabled: task.enabled ?? true,
                graphPosition: task.graphPosition
            ),
            macroResolution: macroResolution,
            issues: issues
        )
    }

    private struct MacroConversion {
        var macroResolution: AutomationWorkflowDraftMacroResolution
        var issues: [AutomationWorkflowDraftIssue]
    }

    private func resolveMacro(
        task: AutomationWorkflowDraftTask,
        path: String
    ) -> MacroConversion {
        let taskKey = task.key.trimmedForDraftImport
        guard let macroRef = task.macroRef else {
            return MacroConversion(
                macroResolution: AutomationWorkflowDraftMacroResolution(
                    taskKey: taskKey,
                    macroID: nil,
                    macroName: nil,
                    source: .unresolved
                ),
                issues: [issue(
                    .error,
                    .missingMacroRef,
                    "Macro task '\(taskKey)' needs a resolved macroRef before import.",
                    "\(path).macroRef",
                    taskKey: taskKey
                )]
            )
        }

        if let id = macroRef.id {
            let catalogName = context.macroCatalog.first { $0.id == id }?.name
            return MacroConversion(
                macroResolution: AutomationWorkflowDraftMacroResolution(
                    taskKey: taskKey,
                    macroID: id,
                    macroName: catalogName ?? macroRef.name?.trimmedForDraftImport.nilIfEmptyForDraftImport,
                    source: .id
                ),
                issues: []
            )
        }

        if let name = macroRef.name?.trimmedForDraftImport, !name.isEmpty {
            let matches = context.macroCatalog.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if matches.count == 1, let entry = matches.first {
                return MacroConversion(
                    macroResolution: AutomationWorkflowDraftMacroResolution(
                        taskKey: taskKey,
                        macroID: entry.id,
                        macroName: entry.name,
                        source: .catalogName
                    ),
                    issues: []
                )
            }

            let code: AutomationWorkflowDraftIssueCode = matches.isEmpty ? .missingMacroRef : .ambiguousMacroRef
            let message = matches.isEmpty
                ? "Macro named '\(name)' cannot be imported without a matching macro catalog entry."
                : "Macro name '\(name)' is ambiguous; choose an exact macro ID before import."
            return MacroConversion(
                macroResolution: AutomationWorkflowDraftMacroResolution(
                    taskKey: taskKey,
                    macroID: nil,
                    macroName: name,
                    source: .unresolved
                ),
                issues: [issue(
                    .error,
                    code,
                    message,
                    "\(path).macroRef.name",
                    taskKey: taskKey,
                    candidates: matches.map(\.id)
                )]
            )
        }

        return MacroConversion(
            macroResolution: AutomationWorkflowDraftMacroResolution(
                taskKey: taskKey,
                macroID: nil,
                macroName: nil,
                source: .unresolved
            ),
            issues: [issue(
                .error,
                .missingMacroRef,
                "Macro task '\(taskKey)' needs a macro ID or resolvable macro name before import.",
                "\(path).macroRef",
                taskKey: taskKey
            )]
        )
    }

    private func conditionKind(
        for task: AutomationWorkflowDraftTask,
        path: String,
        issues: inout [AutomationWorkflowDraftIssue]
    ) -> AutomationTaskKind? {
        guard let condition = task.condition else {
            return nil
        }

        let taskKey = task.key.trimmedForDraftImport
        let conditionName = displayName(for: task, fallback: taskKey)
        let specKind: AutomationConditionKind?

        switch condition.type.trimmedForDraftImport {
        case "ocrText":
            let resolvedRegion = visualRegion(for: condition)
            if condition.regionRef?.trimmedForDraftImport.nilIfEmptyForDraftImport != nil,
               resolvedRegion == nil {
                issues.append(issue(
                    .warning,
                    .unresolvedRegionRef,
                    "Condition '\(taskKey)' references regionRef '\(condition.regionRef ?? "")', but visualAssets.regions does not define it.",
                    "\(path).condition.regionRef",
                    taskKey: taskKey
                ))
            }
            specKind = .ocrText(AutomationOCRCondition(
                text: condition.text?.trimmedForDraftImport ?? "",
                matchMode: condition.matchMode ?? .contains,
                searchRegion: resolvedRegion?.bounds,
                searchRegionSpace: resolvedRegion?.space ?? .automatic,
                requireVisible: condition.requireVisible ?? true
            ))

        case "previousOutcome":
            guard let rawOutcome = condition.outcome?.trimmedForDraftImport,
                  let predicate = AutomationOutcomePredicate(rawValue: rawOutcome)
            else {
                issues.append(issue(
                    .error,
                    .unsupportedConditionType,
                    "previousOutcome condition '\(taskKey)' needs outcome: success, failure, timeout, cancelled, conditionMatched, conditionNotMatched, or anyTerminal.",
                    "\(path).condition.outcome",
                    taskKey: taskKey
                ))
                return nil
            }
            specKind = .previousOutcome(predicate)

        case "externalSignal":
            let signalName = condition.text?.trimmedForDraftImport.nilIfEmptyForDraftImport ??
                condition.regionRef?.trimmedForDraftImport.nilIfEmptyForDraftImport ??
                condition.outcome?.trimmedForDraftImport.nilIfEmptyForDraftImport
            guard let signalName else {
                issues.append(issue(
                    .error,
                    .missingCondition,
                    "externalSignal condition '\(taskKey)' needs a signal name in text.",
                    "\(path).condition.text",
                    taskKey: taskKey
                ))
                return nil
            }
            specKind = .externalSignal(signalName)

        case "manualApproval":
            specKind = .manualApproval

        case "regionChanged", "imageAppeared", "imageDisappeared", "pixelMatched":
            if condition.regionRef?.trimmedForDraftImport.nilIfEmptyForDraftImport != nil,
               visualRegion(for: condition) == nil {
                issues.append(issue(
                    .warning,
                    .unresolvedRegionRef,
                    "Condition '\(taskKey)' references regionRef '\(condition.regionRef ?? "")', but visualAssets.regions does not define it.",
                    "\(path).condition.regionRef",
                    taskKey: taskKey
                ))
            }
            specKind = visualConditionKind(for: condition, taskKey: taskKey, path: path, issues: &issues)

        default:
            return nil
        }

        guard let specKind else {
            return nil
        }

        return .condition(AutomationConditionSpec(
            id: stableID(for: "condition:\(taskKey)"),
            name: conditionName,
            kind: specKind,
            timeout: task.timeoutSeconds,
            pollingInterval: task.pollingSeconds ?? 0.25
        ))
    }

    private func visualConditionKind(
        for condition: AutomationWorkflowDraftCondition,
        taskKey: String,
        path: String,
        issues: inout [AutomationWorkflowDraftIssue]
    ) -> AutomationConditionKind? {
        guard let type = AutomationVisualConditionType(rawValue: condition.type.trimmedForDraftImport) else {
            return nil
        }

        if let threshold = condition.threshold, !(0...1).contains(threshold) {
            issues.append(issue(
                .error,
                .invalidThreshold,
                "Condition threshold must be between 0 and 1.",
                "\(path).condition.threshold",
                taskKey: taskKey
            ))
            return nil
        }
        if let pixelSampleRadius = condition.pixelSampleRadius,
           !(0...AutomationVisualCondition.maximumPixelSampleRadius).contains(pixelSampleRadius) {
            issues.append(issue(
                .error,
                .invalidPixelSampleRadius,
                "Condition pixelSampleRadius must be between 0 and \(AutomationVisualCondition.maximumPixelSampleRadius).",
                "\(path).condition.pixelSampleRadius",
                taskKey: taskKey
            ))
            return nil
        }

        return .visual(AutomationVisualCondition(
            type: type,
            regionRef: condition.regionRef,
            searchRegion: visualRegion(for: condition)?.bounds,
            searchRegionSpace: visualRegion(for: condition)?.space ?? .automatic,
            imageRef: condition.imageRef,
            baselineRef: condition.baselineRef,
            pixel: condition.pixel,
            targetColorHex: condition.colorHex,
            pixelSampleRadius: condition.pixelSampleRadius,
            threshold: condition.threshold,
            requireVisible: condition.requireVisible ?? true
        ))
    }

    private func visualRegion(
        for condition: AutomationWorkflowDraftCondition
    ) -> AutomationWorkflowDraftVisualRegion? {
        document.visualAssets?.region(for: condition.regionRef)
    }

    private func schedule(for schedule: AutomationWorkflowDraftSchedule?) -> AutomationSchedule? {
        guard let schedule else {
            return nil
        }

        switch schedule.type.trimmedForDraftImport {
        case "manual":
            return .manual
        case "once":
            guard let startAt = schedule.startAt else {
                return nil
            }
            return .once(startAt)
        case "repeating":
            guard let startAt = schedule.startAt,
                  let every = schedule.every,
                  let unit = schedule.unit
            else {
                return nil
            }
            let interval: AutomationRepeatInterval
            switch unit {
            case "minutes":
                interval = .minutes(every)
            case "hours":
                interval = .hours(every)
            case "days":
                interval = .days(every)
            case "weeks":
                interval = .weeks(every)
            default:
                return nil
            }
            return .repeating(AutomationRepeatRule(
                anchor: startAt,
                interval: interval,
                timeZoneIdentifier: schedule.timeZone ?? TimeZone.current.identifier
            ))
        default:
            return nil
        }
    }

    private func retryPolicy(for retry: AutomationWorkflowDraftRetry?) -> AutomationRetryPolicy {
        guard let maxAttempts = retry?.maxAttempts else {
            return .none
        }
        return AutomationRetryPolicy(maxAttempts: maxAttempts)
    }

    private func joinPolicy(for value: String?) -> AutomationJoinPolicy {
        guard let value = value?.trimmedForDraftImport, !value.isEmpty else {
            return .all
        }
        return AutomationJoinPolicy(rawValue: value) ?? .all
    }

    private func notificationSeverity(
        _ rawSeverity: String?,
        path: String,
        taskKey: String,
        issues: inout [AutomationWorkflowDraftIssue]
    ) -> AutomationNotificationSeverity {
        guard let rawSeverity = rawSeverity?.trimmedForDraftImport.nilIfEmptyForDraftImport else {
            return .info
        }
        if let severity = AutomationNotificationSeverity(rawValue: rawSeverity) {
            return severity
        }
        issues.append(issue(
            .warning,
            .unsupportedNotificationSeverity,
            "Notification severity '\(rawSeverity)' is not supported; dry-run will use info.",
            path,
            taskKey: taskKey
        ))
        return .info
    }

    private func resourceRequirement(
        for task: AutomationWorkflowDraftTask,
        kind: AutomationTaskKind
    ) -> AutomationResourceRequirement {
        resourceRequirement(
            inferredResourceRequirement(for: task, kind: kind),
            maxWaitDuration: task.maxResourceWaitSeconds
        )
    }

    private func inferredResourceRequirement(
        for task: AutomationWorkflowDraftTask,
        kind: AutomationTaskKind
    ) -> AutomationResourceRequirement {
        if let explicit = task.resource {
            return resourceRequirement(for: explicit)
        }

        switch kind {
        case .macro:
            if let id = task.macroRef?.id,
               let entry = context.macroCatalog.first(where: { $0.id == id }) {
                return resourceRequirement(for: entry.resourceRequirement)
            }
            if let name = task.macroRef?.name?.trimmedForDraftImport,
               let entry = context.macroCatalog.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return resourceRequirement(for: entry.resourceRequirement)
            }
            return .foregroundInput

        case .condition(let spec):
            if case .ocrText = spec.kind {
                return .backgroundReadOnly
            }
            if case .visual = spec.kind {
                return .backgroundReadOnly
            }
            return .none

        case .delay, .notification:
            return .none
        }
    }

    private func resourceRequirement(
        _ requirement: AutomationResourceRequirement,
        maxWaitDuration: TimeInterval?
    ) -> AutomationResourceRequirement {
        AutomationResourceRequirement(
            resources: requirement.resources,
            priority: requirement.priority,
            leaseTimeout: requirement.leaseTimeout,
            maxWaitDuration: maxWaitDuration ?? requirement.maxWaitDuration
        )
    }

    private func resourceRequirement(
        for resource: AutomationWorkflowDraftResource
    ) -> AutomationResourceRequirement {
        switch resource {
        case .foregroundInput:
            return .foregroundInput
        case .screenCapture:
            return .backgroundReadOnly
        case .accessibility:
            return AutomationResourceRequirement(resources: [.accessibility])
        case .network:
            return AutomationResourceRequirement(resources: [.network])
        case .none:
            return .none
        }
    }

    private func trigger(for rawTrigger: String) -> AutomationDependencyTrigger? {
        switch rawTrigger.trimmedForDraftImport {
        case "success":
            return .onSuccess
        case "failure":
            return .onFailure
        case "timeout":
            return .onTimeout
        case "cancelled":
            return .onCancelled
        case "conditionMatched":
            return .onConditionMatched
        case "conditionNotMatched":
            return .onConditionNotMatched
        case "always":
            return .always
        default:
            return nil
        }
    }

    private func key(for dependency: AutomationWorkflowDraftDependency) -> String {
        dependency.key?.trimmedForDraftImport.nilIfEmptyForDraftImport ??
            "\(dependency.from.trimmedForDraftImport)->\(dependency.to.trimmedForDraftImport):\(dependency.trigger.trimmedForDraftImport)"
    }

    private func displayName(
        for task: AutomationWorkflowDraftTask,
        fallback: String
    ) -> String {
        if let name = task.name?.trimmedForDraftImport.nilIfEmptyForDraftImport {
            return name
        }
        if let name = task.macroRef?.name?.trimmedForDraftImport.nilIfEmptyForDraftImport {
            return name
        }
        if let title = task.notification?.title.trimmedForDraftImport.nilIfEmptyForDraftImport {
            return title
        }
        if let text = task.condition?.text?.trimmedForDraftImport.nilIfEmptyForDraftImport {
            return text
        }
        return fallback
    }

    private func importIssue(
        for workflowIssue: AutomationWorkflowValidationIssue
    ) -> AutomationWorkflowDraftIssue {
        issue(
            .error,
            .internalWorkflowValidationFailed,
            "Compiled workflow failed internal validation: \(workflowIssue).",
            "$.workflow"
        )
    }

    private func issue(
        _ severity: AutomationWorkflowDraftIssueSeverity,
        _ code: AutomationWorkflowDraftIssueCode,
        _ message: String,
        _ path: String,
        taskKey: String? = nil,
        dependencyKey: String? = nil,
        candidates: [UUID] = []
    ) -> AutomationWorkflowDraftIssue {
        AutomationWorkflowDraftIssue(
            severity: severity,
            code: code,
            message: message,
            path: path,
            taskKey: taskKey,
            dependencyKey: dependencyKey,
            candidates: candidates
        )
    }

    private func stableID(for key: String) -> UUID {
        StableDraftImportUUID.make(namespace: options.stableIDNamespace, key: key)
    }
}

private enum StableDraftImportUUID {
    static func make(namespace: String, key: String) -> UUID {
        let text = "\(namespace):\(key)"
        let first = fnv1a64(text.utf8, seed: 0xcbf2_9ce4_8422_2325)
        let second = fnv1a64(text.reversed().map(\.asciiValueForDraftImport), seed: 0x8422_2325_cbf2_9ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for offset in 0..<8 {
            bytes[offset] = UInt8((first >> UInt64((7 - offset) * 8)) & 0xff)
            bytes[offset + 8] = UInt8((second >> UInt64((7 - offset) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv1a64<Bytes: Sequence>(
        _ bytes: Bytes,
        seed: UInt64
    ) -> UInt64 where Bytes.Element == UInt8 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}

private extension Character {
    var asciiValueForDraftImport: UInt8 {
        unicodeScalars.first.map { UInt8(truncatingIfNeeded: $0.value) } ?? 0
    }
}

private extension String {
    var trimmedForDraftImport: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftImport: String? {
        isEmpty ? nil : self
    }
}
