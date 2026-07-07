import Foundation

public struct AutomationWorkflowDraftExportOptions: Equatable, Sendable {
    public var macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]

    public init(macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry] = []) {
        self.macroCatalog = macroCatalog
    }
}

public struct AutomationWorkflowDraftExportResult: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var isExportable: Bool
    public var document: AutomationWorkflowDraftDocument
    public var taskIDToKey: [UUID: String]
    public var dependencyIDToKey: [UUID: String]
    public var issues: [AutomationWorkflowDraftIssue]
    public var validation: AutomationWorkflowDraftValidationResult

    public init(
        workflowID: UUID,
        workflowName: String,
        isExportable: Bool,
        document: AutomationWorkflowDraftDocument,
        taskIDToKey: [UUID: String],
        dependencyIDToKey: [UUID: String],
        issues: [AutomationWorkflowDraftIssue],
        validation: AutomationWorkflowDraftValidationResult
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.isExportable = isExportable
        self.document = document
        self.taskIDToKey = taskIDToKey
        self.dependencyIDToKey = dependencyIDToKey
        self.issues = issues
        self.validation = validation
    }
}

public enum AutomationWorkflowDraftExporter {
    public static func export(
        _ workflow: AutomationWorkflow,
        options: AutomationWorkflowDraftExportOptions = AutomationWorkflowDraftExportOptions()
    ) -> AutomationWorkflowDraftExportResult {
        WorkflowDraftExportBuilder(
            workflow: workflow,
            options: options
        ).export()
    }
}

private struct WorkflowDraftExportBuilder {
    var workflow: AutomationWorkflow
    var options: AutomationWorkflowDraftExportOptions

    private var macroCatalogByID: [UUID: AutomationWorkflowDraftMacroCatalogEntry] {
        Dictionary(uniqueKeysWithValues: options.macroCatalog.map { ($0.id, $0) })
    }

    func export() -> AutomationWorkflowDraftExportResult {
        let taskKeyPairs = makeTaskKeyPairs()
        let taskIDToKey = Dictionary(uniqueKeysWithValues: taskKeyPairs)
        var issues: [AutomationWorkflowDraftIssue] = []
        var visualRegions = workflow.visualAssets?.regions ?? []
        var usedVisualRegionKeys = Set(visualRegions.map { $0.key.trimmedForDraftExport })

        let tasks = workflow.tasks.compactMap { task -> AutomationWorkflowDraftTask? in
            guard let key = taskIDToKey[task.id] else {
                return nil
            }
            return exportTask(
                task,
                key: key,
                issues: &issues,
                visualRegions: &visualRegions,
                usedVisualRegionKeys: &usedVisualRegionKeys
            )
        }

        let dependencyKeyPairs = makeDependencyKeyPairs(taskIDToKey: taskIDToKey)
        let dependencyIDToKey = Dictionary(uniqueKeysWithValues: dependencyKeyPairs)
        let dependencies = workflow.dependencies.compactMap { dependency -> AutomationWorkflowDraftDependency? in
            guard let from = taskIDToKey[dependency.fromTaskID],
                  let to = taskIDToKey[dependency.toTaskID] else {
                issues.append(issue(
                    .warning,
                    .lossyWorkflowExport,
                    "Dependency \(dependency.id.uuidString) references a task that is not present in workflow '\(workflow.name)'; export skipped this edge.",
                    "$.workflow.dependencies",
                    dependencyKey: dependency.id.uuidString
                ))
                return nil
            }

            let trigger = rawTrigger(for: dependency.trigger)
            let key = dependencyIDToKey[dependency.id] ?? "\(from)->\(to):\(trigger)"
            return AutomationWorkflowDraftDependency(
                key: key,
                from: from,
                to: to,
                trigger: trigger,
                delaySeconds: dependency.delay == 0 ? nil : dependency.delay,
                enabled: dependency.isEnabled ? nil : false
            )
        }

        let visualAssets = AutomationWorkflowDraftVisualAssets(
            regions: visualRegions,
            images: workflow.visualAssets?.images ?? [],
            baselines: workflow.visualAssets?.baselines ?? []
        )
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: workflow.name,
                tasks: tasks,
                dependencies: dependencies
            ),
            visualAssets: visualAssets.isEmpty ? nil : visualAssets
        )
        let validation = AutomationWorkflowDraftValidator.validate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: options.macroCatalog)
        )
        let allIssues = issues + validation.issues

        return AutomationWorkflowDraftExportResult(
            workflowID: workflow.id,
            workflowName: workflow.name,
            isExportable: !allIssues.contains { $0.severity == .error },
            document: document,
            taskIDToKey: taskIDToKey,
            dependencyIDToKey: dependencyIDToKey,
            issues: allIssues,
            validation: validation
        )
    }

    private func makeTaskKeyPairs() -> [(UUID, String)] {
        var used: Set<String> = []
        return workflow.tasks.map { task in
            let suffix = shortID(task.id)
            let base = slug(task.name).nilIfEmptyForDraftExport ?? baseKey(for: task.kind)
            let key = uniqueKey("\(base)_\(suffix)", used: &used)
            return (task.id, key)
        }
    }

    private func makeDependencyKeyPairs(
        taskIDToKey: [UUID: String]
    ) -> [(UUID, String)] {
        var used: Set<String> = []
        return workflow.dependencies.compactMap { dependency in
            guard let from = taskIDToKey[dependency.fromTaskID],
                  let to = taskIDToKey[dependency.toTaskID] else {
                return nil
            }
            let trigger = rawTrigger(for: dependency.trigger)
            let key = uniqueKey("\(from)->\(to):\(trigger)", used: &used)
            return (dependency.id, key)
        }
    }

    private func exportTask(
        _ task: AutomationTask,
        key: String,
        issues: inout [AutomationWorkflowDraftIssue],
        visualRegions: inout [AutomationWorkflowDraftVisualRegion],
        usedVisualRegionKeys: inout Set<String>
    ) -> AutomationWorkflowDraftTask {
        let common = CommonTaskFields(
            name: task.name == key ? nil : task.name,
            schedule: draftSchedule(for: task.schedule, taskKey: key, issues: &issues),
            resource: draftResource(for: task.resourceRequirement, taskKey: key, issues: &issues),
            maxResourceWaitSeconds: task.resourceRequirement.maxWaitDuration,
            timeoutSeconds: task.timeout,
            retry: task.retryPolicy.maxAttempts > 1
                ? AutomationWorkflowDraftRetry(maxAttempts: task.retryPolicy.maxAttempts)
                : nil,
            joinPolicy: task.joinPolicy == .all ? nil : task.joinPolicy.rawValue,
            enabled: task.isEnabled ? nil : false,
            graphPosition: task.graphPosition
        )

        switch task.kind {
        case .macro(let macroID):
            let macroEntry = macroCatalogByID[macroID]
            return AutomationWorkflowDraftTask(
                key: key,
                type: "macro",
                name: common.name,
                macroRef: AutomationWorkflowDraftMacroRef(
                    id: macroID,
                    name: macroEntry?.name
                ),
                schedule: common.schedule,
                resource: common.resource,
                maxResourceWaitSeconds: common.maxResourceWaitSeconds,
                timeoutSeconds: common.timeoutSeconds,
                retry: common.retry,
                joinPolicy: common.joinPolicy,
                enabled: common.enabled,
                graphPosition: common.graphPosition
            )

        case .delay(let duration):
            return AutomationWorkflowDraftTask(
                key: key,
                type: "delay",
                name: common.name,
                delaySeconds: duration,
                schedule: common.schedule,
                resource: common.resource,
                maxResourceWaitSeconds: common.maxResourceWaitSeconds,
                timeoutSeconds: common.timeoutSeconds,
                retry: common.retry,
                joinPolicy: common.joinPolicy,
                enabled: common.enabled,
                graphPosition: common.graphPosition
            )

        case .notification(let notification):
            return AutomationWorkflowDraftTask(
                key: key,
                type: "notification",
                name: common.name,
                notification: AutomationWorkflowDraftNotification(
                    title: notification.title,
                    body: notification.body.isEmpty ? nil : notification.body,
                    severity: notification.severity.rawValue
                ),
                schedule: common.schedule,
                resource: common.resource,
                maxResourceWaitSeconds: common.maxResourceWaitSeconds,
                timeoutSeconds: common.timeoutSeconds,
                retry: common.retry,
                joinPolicy: common.joinPolicy,
                enabled: common.enabled,
                graphPosition: common.graphPosition
            )

        case .condition(let spec):
            return exportConditionTask(
                task,
                key: key,
                spec: spec,
                common: common,
                issues: &issues,
                visualRegions: &visualRegions,
                usedVisualRegionKeys: &usedVisualRegionKeys
            )
        }
    }

    private func exportConditionTask(
        _ task: AutomationTask,
        key: String,
        spec: AutomationConditionSpec,
        common: CommonTaskFields,
        issues: inout [AutomationWorkflowDraftIssue],
        visualRegions: inout [AutomationWorkflowDraftVisualRegion],
        usedVisualRegionKeys: inout Set<String>
    ) -> AutomationWorkflowDraftTask {
        switch spec.kind {
        case .manualApproval:
            return AutomationWorkflowDraftTask(
                key: key,
                type: "manualApproval",
                name: common.name,
                schedule: common.schedule,
                resource: common.resource,
                maxResourceWaitSeconds: common.maxResourceWaitSeconds,
                timeoutSeconds: common.timeoutSeconds ?? spec.timeout,
                pollingSeconds: spec.pollingInterval,
                retry: common.retry,
                joinPolicy: common.joinPolicy,
                enabled: common.enabled,
                graphPosition: common.graphPosition
            )

        case .ocrText(let condition):
            let regionRef: String?
            if let searchRegion = condition.searchRegion {
                regionRef = appendVisualRegion(
                    preferredKey: "\(key)_region",
                    label: task.name,
                    bounds: searchRegion,
                    space: condition.searchRegionSpace,
                    visualRegions: &visualRegions,
                    usedKeys: &usedVisualRegionKeys
                )
            } else {
                regionRef = nil
            }

            return AutomationWorkflowDraftTask(
                key: key,
                type: "condition",
                name: common.name,
                condition: AutomationWorkflowDraftCondition(
                    type: "ocrText",
                    text: condition.text,
                    matchMode: condition.matchMode,
                    regionRef: regionRef,
                    requireVisible: condition.requireVisible
                ),
                schedule: common.schedule,
                resource: common.resource,
                maxResourceWaitSeconds: common.maxResourceWaitSeconds,
                timeoutSeconds: common.timeoutSeconds ?? spec.timeout,
                pollingSeconds: spec.pollingInterval,
                retry: common.retry,
                joinPolicy: common.joinPolicy,
                enabled: common.enabled,
                graphPosition: common.graphPosition
            )

        case .visual(let condition):
            let regionRef: String?
            if let searchRegion = condition.searchRegion {
                if let existingRef = condition.regionRef,
                   visualRegion(
                    existingRef,
                    in: visualRegions,
                    matches: searchRegion,
                    space: condition.searchRegionSpace
                   ) {
                    regionRef = existingRef
                } else {
                    regionRef = appendVisualRegion(
                        preferredKey: condition.regionRef ?? "\(key)_region",
                        label: task.name,
                        bounds: searchRegion,
                        space: condition.searchRegionSpace,
                        visualRegions: &visualRegions,
                        usedKeys: &usedVisualRegionKeys
                    )
                }
            } else if let existingRef = condition.regionRef {
                regionRef = existingRef
            } else {
                regionRef = nil
            }

            return conditionDraftTask(
                key: key,
                common: common,
                spec: spec,
                condition: AutomationWorkflowDraftCondition(
                    type: condition.type.rawValue,
                    regionRef: regionRef,
                    requireVisible: condition.requireVisible,
                    imageRef: condition.imageRef,
                    baselineRef: condition.baselineRef,
                    pixel: condition.pixel,
                    colorHex: condition.targetColorHex,
                    pixelSampleRadius: condition.pixelSampleRadius,
                    threshold: condition.threshold
                )
            )

        case .previousOutcome(let predicate):
            return conditionDraftTask(
                key: key,
                common: common,
                spec: spec,
                condition: AutomationWorkflowDraftCondition(
                    type: "previousOutcome",
                    outcome: predicate.rawValue
                )
            )

        case .externalSignal(let signal):
            return conditionDraftTask(
                key: key,
                common: common,
                spec: spec,
                condition: AutomationWorkflowDraftCondition(
                    type: "externalSignal",
                    text: signal
                )
            )
        }
    }

    private func conditionDraftTask(
        key: String,
        common: CommonTaskFields,
        spec: AutomationConditionSpec,
        condition: AutomationWorkflowDraftCondition
    ) -> AutomationWorkflowDraftTask {
        AutomationWorkflowDraftTask(
            key: key,
            type: "condition",
            name: common.name,
            condition: condition,
            schedule: common.schedule,
            resource: common.resource,
            maxResourceWaitSeconds: common.maxResourceWaitSeconds,
            timeoutSeconds: common.timeoutSeconds ?? spec.timeout,
            pollingSeconds: spec.pollingInterval,
            retry: common.retry,
            joinPolicy: common.joinPolicy,
            enabled: common.enabled,
            graphPosition: common.graphPosition
        )
    }

    private func draftSchedule(
        for schedule: AutomationSchedule?,
        taskKey: String,
        issues: inout [AutomationWorkflowDraftIssue]
    ) -> AutomationWorkflowDraftSchedule? {
        guard let schedule else {
            return nil
        }

        switch schedule {
        case .manual:
            return AutomationWorkflowDraftSchedule(type: "manual")
        case .once(let date):
            return AutomationWorkflowDraftSchedule(type: "once", startAt: date)
        case .repeating(let rule):
            if rule.end != .never {
                issues.append(issue(
                    .warning,
                    .lossyWorkflowExport,
                    "Repeating schedule for task '\(taskKey)' has an end rule that draft v1 cannot represent; export keeps the repeating interval without the end rule.",
                    "$.workflow.tasks[\(taskKey)].schedule",
                    taskKey: taskKey
                ))
            }
            let interval = draftRepeatInterval(rule.interval)
            return AutomationWorkflowDraftSchedule(
                type: "repeating",
                startAt: rule.anchor,
                every: interval.count,
                unit: interval.unit,
                timeZone: rule.timeZoneIdentifier
            )
        }
    }

    private func draftRepeatInterval(_ interval: AutomationRepeatInterval) -> (count: Int, unit: String) {
        switch interval {
        case .minutes(let value):
            return (value, "minutes")
        case .hours(let value):
            return (value, "hours")
        case .days(let value):
            return (value, "days")
        case .weeks(let value):
            return (value, "weeks")
        }
    }

    private func draftResource(
        for requirement: AutomationResourceRequirement,
        taskKey: String,
        issues: inout [AutomationWorkflowDraftIssue]
    ) -> AutomationWorkflowDraftResource? {
        guard !requirement.resources.isEmpty else {
            return AutomationWorkflowDraftResource.none
        }

        if requirement.resources.count > 1 {
            issues.append(issue(
                .warning,
                .lossyWorkflowExport,
                "Task '\(taskKey)' requires multiple resources; draft v1 stores only the highest priority resource.",
                "$.workflow.tasks[\(taskKey)].resource",
                taskKey: taskKey
            ))
        }

        if requirement.resources.contains(.foregroundInput) {
            return .foregroundInput
        }
        if requirement.resources.contains(.screenCapture) {
            return .screenCapture
        }
        if requirement.resources.contains(.accessibility) {
            return .accessibility
        }
        if requirement.resources.contains(.network) {
            return .network
        }
        return AutomationWorkflowDraftResource.none
    }

    private func rawTrigger(for trigger: AutomationDependencyTrigger) -> String {
        switch trigger {
        case .onSuccess:
            return "success"
        case .onFailure:
            return "failure"
        case .onTimeout:
            return "timeout"
        case .onCancelled:
            return "cancelled"
        case .onConditionMatched:
            return "conditionMatched"
        case .onConditionNotMatched:
            return "conditionNotMatched"
        case .always:
            return "always"
        case .onOutcome(let predicate):
            switch predicate {
            case .success:
                return "success"
            case .failure:
                return "failure"
            case .timeout:
                return "timeout"
            case .cancelled:
                return "cancelled"
            case .conditionMatched:
                return "conditionMatched"
            case .conditionNotMatched:
                return "conditionNotMatched"
            case .anyTerminal:
                return "always"
            }
        }
    }

    private func appendVisualRegion(
        preferredKey: String,
        label: String?,
        bounds: RectValue,
        space: AutomationOCRSearchRegionSpace,
        visualRegions: inout [AutomationWorkflowDraftVisualRegion],
        usedKeys: inout Set<String>
    ) -> String {
        let key = appendVisualRegionReference(preferredKey, usedKeys: &usedKeys)
        visualRegions.append(AutomationWorkflowDraftVisualRegion(
            key: key,
            label: label,
            bounds: bounds,
            space: space
        ))
        return key
    }

    private func appendVisualRegionReference(
        _ reference: String,
        usedKeys: inout Set<String>
    ) -> String {
        let base = reference.trimmedForDraftExport.nilIfEmptyForDraftExport ?? "region"
        return uniqueKey(base, used: &usedKeys)
    }

    private func visualRegion(
        _ reference: String,
        in regions: [AutomationWorkflowDraftVisualRegion],
        matches bounds: RectValue,
        space: AutomationOCRSearchRegionSpace
    ) -> Bool {
        regions.contains { region in
            region.key.trimmedForDraftExport == reference.trimmedForDraftExport &&
            region.bounds == bounds &&
            region.space == space
        }
    }

    private func baseKey(for kind: AutomationTaskKind) -> String {
        switch kind {
        case .macro:
            return "macro"
        case .condition:
            return "condition"
        case .delay:
            return "delay"
        case .notification:
            return "notification"
        }
    }

    private func uniqueKey(_ candidate: String, used: inout Set<String>) -> String {
        var key = candidate
        var index = 2
        while used.contains(key) {
            key = "\(candidate)_\(index)"
            index += 1
        }
        used.insert(key)
        return key
    }

    private func slug(_ value: String) -> String {
        let lower = value.lowercased()
        var scalars: [UnicodeScalar] = []
        var previousWasSeparator = false

        for scalar in lower.unicodeScalars {
            let isLetterOrNumber = CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
            if isLetterOrNumber {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append("_")
                previousWasSeparator = true
            }
        }

        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    private func issue(
        _ severity: AutomationWorkflowDraftIssueSeverity,
        _ code: AutomationWorkflowDraftIssueCode,
        _ message: String,
        _ path: String,
        taskKey: String? = nil,
        dependencyKey: String? = nil
    ) -> AutomationWorkflowDraftIssue {
        AutomationWorkflowDraftIssue(
            severity: severity,
            code: code,
            message: message,
            path: path,
            taskKey: taskKey,
            dependencyKey: dependencyKey
        )
    }
}

private struct CommonTaskFields {
    var name: String?
    var schedule: AutomationWorkflowDraftSchedule?
    var resource: AutomationWorkflowDraftResource?
    var maxResourceWaitSeconds: TimeInterval?
    var timeoutSeconds: TimeInterval?
    var retry: AutomationWorkflowDraftRetry?
    var joinPolicy: String?
    var enabled: Bool?
    var graphPosition: AutomationGraphPoint?
}

private extension String {
    var trimmedForDraftExport: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftExport: String? {
        isEmpty ? nil : self
    }
}
