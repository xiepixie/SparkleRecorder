import Foundation

public struct AutomationWorkflowDraftEditResult: Codable, Equatable, Sendable {
    public var operation: String
    public var document: AutomationWorkflowDraftDocument
    public var validation: AutomationWorkflowDraftValidationResult
    public var changedTaskKeys: [String]
    public var changedDependencyKeys: [String]
    public var wrotePath: String?

    public init(
        operation: String,
        document: AutomationWorkflowDraftDocument,
        validation: AutomationWorkflowDraftValidationResult,
        changedTaskKeys: [String] = [],
        changedDependencyKeys: [String] = [],
        wrotePath: String? = nil
    ) {
        self.operation = operation
        self.document = document
        self.validation = validation
        self.changedTaskKeys = changedTaskKeys
        self.changedDependencyKeys = changedDependencyKeys
        self.wrotePath = wrotePath
    }

    public var isValid: Bool {
        validation.isValid
    }

    public func withWrotePath(_ path: String?) -> AutomationWorkflowDraftEditResult {
        var copy = self
        copy.wrotePath = path
        return copy
    }
}

public struct AutomationWorkflowDraftEditError: Error, Equatable, Sendable {
    public var code: String
    public var message: String
    public var path: String?

    public init(code: String, message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }
}

public struct AutomationWorkflowDraftDependencySelector: Equatable, Sendable {
    public var key: String?
    public var from: String?
    public var to: String?
    public var trigger: String?

    public init(
        key: String? = nil,
        from: String? = nil,
        to: String? = nil,
        trigger: String? = nil
    ) {
        self.key = key
        self.from = from
        self.to = to
        self.trigger = trigger
    }
}

public enum AutomationWorkflowDraftEditor {
    public static func makeDocument(
        name: String,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let workflowName = try nonEmpty(name, code: "emptyWorkflowName", message: "Workflow name is required.", path: "$.workflow.name")
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(name: workflowName))
        return result(operation: "draft init", document: document, context: context)
    }

    public static func inspect(
        _ document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) -> AutomationWorkflowDraftEditResult {
        result(operation: "draft inspect", document: document, context: context)
    }

    public static func normalize(
        _ document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) -> AutomationWorkflowDraftEditResult {
        var document = document
        document.schema = AutomationWorkflowDraftSchema.current
        document.workflow.name = document.workflow.name.trimmedForDraftEditing
        document.workflow.tasks = document.workflow.tasks
            .map(normalizedTask)
            .sorted { $0.key < $1.key }
        document.workflow.dependencies = document.workflow.dependencies
            .map(normalizedDependency)
            .sorted { dependencySortKey($0) < dependencySortKey($1) }

        return result(
            operation: "draft normalize",
            document: document,
            context: context,
            changedTaskKeys: document.workflow.tasks.map(\.key),
            changedDependencyKeys: document.workflow.dependencies.map(dependencyDisplayKey)
        )
    }

    public static func addTask(
        _ task: AutomationWorkflowDraftTask,
        to document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try normalizedTaskKey(task.key)
        guard !document.workflow.tasks.contains(where: { $0.key.trimmedForDraftEditing == key }) else {
            throw AutomationWorkflowDraftEditError(
                code: AutomationWorkflowDraftIssueCode.duplicateTaskKey.rawValue,
                message: "Task key '\(key)' already exists.",
                path: "$.workflow.tasks"
            )
        }

        var task = task
        task.key = key
        task.type = try nonEmpty(task.type, code: AutomationWorkflowDraftIssueCode.unsupportedTaskType.rawValue, message: "Task type is required.", path: "$.workflow.tasks[].type")
        if task.type == "condition", task.condition == nil {
            task.condition = AutomationWorkflowDraftCondition(type: "ocrText")
        }
        task.name = task.name?.trimmedForDraftEditing.nilIfEmptyForDraftEditing

        var document = document
        document.workflow.tasks.append(task)
        return result(
            operation: "draft task add",
            document: document,
            context: context,
            changedTaskKeys: [key]
        )
    }

    public static func removeTask(
        key taskKey: String,
        from document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try normalizedTaskKey(taskKey)
        var document = document
        guard let index = document.workflow.tasks.firstIndex(where: { $0.key.trimmedForDraftEditing == key }) else {
            throw AutomationWorkflowDraftEditError(code: "missingTask", message: "Task '\(key)' was not found.", path: "$.workflow.tasks")
        }

        document.workflow.tasks.remove(at: index)
        let removedDependencies = document.workflow.dependencies.filter {
            $0.from.trimmedForDraftEditing == key || $0.to.trimmedForDraftEditing == key
        }
        document.workflow.dependencies.removeAll {
            $0.from.trimmedForDraftEditing == key || $0.to.trimmedForDraftEditing == key
        }

        return result(
            operation: "draft task remove",
            document: document,
            context: context,
            changedTaskKeys: [key],
            changedDependencyKeys: removedDependencies.map(dependencyDisplayKey)
        )
    }

    public static func setTask(
        key taskKey: String,
        in document: AutomationWorkflowDraftDocument,
        name: String? = nil,
        timeoutSeconds: TimeInterval? = nil,
        pollingSeconds: TimeInterval? = nil,
        retryMaxAttempts: Int? = nil,
        joinPolicy: String? = nil,
        resource: AutomationWorkflowDraftResource? = nil,
        maxResourceWaitSeconds: TimeInterval? = nil,
        enabled: Bool? = nil,
        graphPosition: AutomationGraphPoint? = nil,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try normalizedTaskKey(taskKey)
        var document = document
        guard let index = document.workflow.tasks.firstIndex(where: { $0.key.trimmedForDraftEditing == key }) else {
            throw AutomationWorkflowDraftEditError(code: "missingTask", message: "Task '\(key)' was not found.", path: "$.workflow.tasks")
        }

        if let name {
            document.workflow.tasks[index].name = name.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        }
        if let timeoutSeconds {
            document.workflow.tasks[index].timeoutSeconds = timeoutSeconds
        }
        if let pollingSeconds {
            document.workflow.tasks[index].pollingSeconds = pollingSeconds
        }
        if let retryMaxAttempts {
            document.workflow.tasks[index].retry = AutomationWorkflowDraftRetry(maxAttempts: retryMaxAttempts)
        }
        if let joinPolicy {
            document.workflow.tasks[index].joinPolicy = joinPolicy.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        }
        if let resource {
            document.workflow.tasks[index].resource = resource
        }
        if let maxResourceWaitSeconds {
            document.workflow.tasks[index].maxResourceWaitSeconds = maxResourceWaitSeconds
        }
        if let enabled {
            document.workflow.tasks[index].enabled = enabled
        }
        if let graphPosition {
            document.workflow.tasks[index].graphPosition = graphPosition
        }

        return result(
            operation: "draft task set",
            document: document,
            context: context,
            changedTaskKeys: [key]
        )
    }

    public static func setSchedule(
        taskKey: String,
        schedule: AutomationWorkflowDraftSchedule?,
        in document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try normalizedTaskKey(taskKey)
        var document = document
        guard let index = document.workflow.tasks.firstIndex(where: { $0.key.trimmedForDraftEditing == key }) else {
            throw AutomationWorkflowDraftEditError(code: "missingTask", message: "Task '\(key)' was not found.", path: "$.workflow.tasks")
        }

        document.workflow.tasks[index].schedule = schedule.map(normalizedSchedule)
        return result(
            operation: "draft schedule set",
            document: document,
            context: context,
            changedTaskKeys: [key]
        )
    }

    public static func setLoop(
        taskKey: String,
        count: Int,
        tasks: [AutomationWorkflowDraftTask],
        in document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try normalizedTaskKey(taskKey)
        var document = document
        guard let index = document.workflow.tasks.firstIndex(where: { $0.key.trimmedForDraftEditing == key }) else {
            throw AutomationWorkflowDraftEditError(code: "missingTask", message: "Task '\(key)' was not found.", path: "$.workflow.tasks")
        }

        document.workflow.tasks[index].type = "loop"
        document.workflow.tasks[index].loop = AutomationWorkflowDraftLoop(
            count: count,
            tasks: tasks.map(normalizedTask)
        )
        document.workflow.tasks[index].macroRef = nil
        document.workflow.tasks[index].condition = nil
        document.workflow.tasks[index].delaySeconds = nil
        document.workflow.tasks[index].notification = nil
        document.workflow.tasks[index].resource = nil
        document.workflow.tasks[index].maxResourceWaitSeconds = nil
        document.workflow.tasks[index].timeoutSeconds = nil
        document.workflow.tasks[index].pollingSeconds = nil
        document.workflow.tasks[index].retry = nil
        document.workflow.tasks[index].joinPolicy = nil

        return result(
            operation: "draft loop set",
            document: document,
            context: context,
            changedTaskKeys: [key]
        )
    }

    public static func setCondition(
        taskKey: String,
        condition: AutomationWorkflowDraftCondition,
        in document: AutomationWorkflowDraftDocument,
        timeoutSeconds: TimeInterval? = nil,
        pollingSeconds: TimeInterval? = nil,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try normalizedTaskKey(taskKey)
        var document = document
        guard let index = document.workflow.tasks.firstIndex(where: { $0.key.trimmedForDraftEditing == key }) else {
            throw AutomationWorkflowDraftEditError(code: "missingTask", message: "Task '\(key)' was not found.", path: "$.workflow.tasks")
        }

        document.workflow.tasks[index].type = "condition"
        document.workflow.tasks[index].condition = AutomationWorkflowDraftCondition(
            type: try nonEmpty(condition.type, code: AutomationWorkflowDraftIssueCode.unsupportedConditionType.rawValue, message: "Condition type is required.", path: "$.workflow.tasks[].condition.type"),
            text: condition.text?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            matchMode: condition.matchMode,
            regionRef: condition.regionRef?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            requireVisible: condition.requireVisible,
            outcome: condition.outcome?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            imageRef: condition.imageRef?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            baselineRef: condition.baselineRef?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            pixel: condition.pixel,
            colorHex: condition.colorHex?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            threshold: condition.threshold
        )
        if let timeoutSeconds {
            document.workflow.tasks[index].timeoutSeconds = timeoutSeconds
        }
        if let pollingSeconds {
            document.workflow.tasks[index].pollingSeconds = pollingSeconds
        }

        return result(
            operation: "draft condition set",
            document: document,
            context: context,
            changedTaskKeys: [key]
        )
    }

    public static func addDependency(
        _ dependency: AutomationWorkflowDraftDependency,
        to document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        let from = try normalizedTaskKey(dependency.from)
        let to = try normalizedTaskKey(dependency.to)
        let trigger = try nonEmpty(
            dependency.trigger,
            code: AutomationWorkflowDraftIssueCode.unsupportedTrigger.rawValue,
            message: "Dependency trigger is required.",
            path: "$.workflow.dependencies[].trigger"
        )
        let key = dependency.key?.trimmedForDraftEditing.nilIfEmptyForDraftEditing ?? "\(from)->\(to):\(trigger)"

        guard document.workflow.tasks.contains(where: { $0.key.trimmedForDraftEditing == from }) else {
            throw AutomationWorkflowDraftEditError(code: AutomationWorkflowDraftIssueCode.missingDependencyEndpoint.rawValue, message: "Dependency source '\(from)' does not match a task key.", path: "$.workflow.dependencies[].from")
        }
        guard document.workflow.tasks.contains(where: { $0.key.trimmedForDraftEditing == to }) else {
            throw AutomationWorkflowDraftEditError(code: AutomationWorkflowDraftIssueCode.missingDependencyEndpoint.rawValue, message: "Dependency target '\(to)' does not match a task key.", path: "$.workflow.dependencies[].to")
        }
        guard !document.workflow.dependencies.contains(where: {
            $0.from.trimmedForDraftEditing == from &&
                $0.to.trimmedForDraftEditing == to &&
                $0.trigger.trimmedForDraftEditing == trigger
        }) else {
            throw AutomationWorkflowDraftEditError(
                code: AutomationWorkflowDraftIssueCode.duplicateDependency.rawValue,
                message: "Dependency '\(key)' already exists.",
                path: "$.workflow.dependencies"
            )
        }

        var document = document
        document.workflow.dependencies.append(AutomationWorkflowDraftDependency(
            key: key,
            from: from,
            to: to,
            trigger: trigger,
            delaySeconds: dependency.delaySeconds,
            enabled: dependency.enabled
        ))

        return result(
            operation: "draft dependency add",
            document: document,
            context: context,
            changedDependencyKeys: [key]
        )
    }

    public static func setDependency(
        matching selector: AutomationWorkflowDraftDependencySelector,
        in document: AutomationWorkflowDraftDocument,
        key newKey: String? = nil,
        from newFrom: String? = nil,
        to newTo: String? = nil,
        trigger newTrigger: String? = nil,
        delaySeconds: TimeInterval? = nil,
        enabled: Bool? = nil,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        var document = document
        let index = try dependencyIndex(matching: selector, in: document)
        let oldDisplayKey = dependencyDisplayKey(document.workflow.dependencies[index])

        var dependency = document.workflow.dependencies[index]
        if let newKey {
            dependency.key = newKey.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        }
        if let newFrom {
            dependency.from = try normalizedTaskKey(newFrom)
        }
        if let newTo {
            dependency.to = try normalizedTaskKey(newTo)
        }
        if let newTrigger {
            dependency.trigger = try nonEmpty(
                newTrigger,
                code: AutomationWorkflowDraftIssueCode.unsupportedTrigger.rawValue,
                message: "Dependency trigger is required.",
                path: "$.workflow.dependencies[].trigger"
            )
        }
        if let delaySeconds {
            dependency.delaySeconds = delaySeconds
        }
        if let enabled {
            dependency.enabled = enabled
        }

        try assertDependencyEndpointsExist(dependency, in: document)
        try assertDependencyIsNotDuplicate(dependency, in: document, ignoring: index)

        document.workflow.dependencies[index] = normalizedDependency(dependency)
        let newDisplayKey = dependencyDisplayKey(document.workflow.dependencies[index])
        return result(
            operation: "draft dependency set",
            document: document,
            context: context,
            changedDependencyKeys: Array(Set([oldDisplayKey, newDisplayKey])).sorted()
        )
    }

    public static func removeDependency(
        matching selector: AutomationWorkflowDraftDependencySelector,
        from document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        var document = document
        let index = try dependencyIndex(matching: selector, in: document)
        let displayKey = dependencyDisplayKey(document.workflow.dependencies[index])
        document.workflow.dependencies.remove(at: index)

        return result(
            operation: "draft dependency remove",
            document: document,
            context: context,
            changedDependencyKeys: [displayKey]
        )
    }

    private static func result(
        operation: String,
        document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext,
        changedTaskKeys: [String] = [],
        changedDependencyKeys: [String] = []
    ) -> AutomationWorkflowDraftEditResult {
        AutomationWorkflowDraftEditResult(
            operation: operation,
            document: document,
            validation: AutomationWorkflowDraftValidator.validate(document, context: context),
            changedTaskKeys: changedTaskKeys,
            changedDependencyKeys: changedDependencyKeys
        )
    }

    private static func normalizedTaskKey(_ key: String) throws -> String {
        try nonEmpty(key, code: AutomationWorkflowDraftIssueCode.emptyTaskKey.rawValue, message: "Task key is required.", path: "$.workflow.tasks[].key")
    }

    private static func nonEmpty(
        _ value: String,
        code: String,
        message: String,
        path: String?
    ) throws -> String {
        let trimmed = value.trimmedForDraftEditing
        guard !trimmed.isEmpty else {
            throw AutomationWorkflowDraftEditError(code: code, message: message, path: path)
        }
        return trimmed
    }

    private static func normalizedTask(_ task: AutomationWorkflowDraftTask) -> AutomationWorkflowDraftTask {
        var task = task
        task.key = task.key.trimmedForDraftEditing
        task.name = task.name?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        task.type = task.type.trimmedForDraftEditing
        task.loop = task.loop.map { loop in
            AutomationWorkflowDraftLoop(
                count: loop.count,
                tasks: loop.tasks.map(normalizedTask)
            )
        }
        task.macroRef = task.macroRef.map { macroRef in
            AutomationWorkflowDraftMacroRef(
                id: macroRef.id,
                name: macroRef.name?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
            )
        }
        task.condition = task.condition.map { condition in
            AutomationWorkflowDraftCondition(
                type: condition.type.trimmedForDraftEditing,
                text: condition.text?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                matchMode: condition.matchMode,
                regionRef: condition.regionRef?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                requireVisible: condition.requireVisible,
                outcome: condition.outcome?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                imageRef: condition.imageRef?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                baselineRef: condition.baselineRef?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                pixel: condition.pixel,
                colorHex: condition.colorHex?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                threshold: condition.threshold
            )
        }
        task.notification = task.notification.map { notification in
            AutomationWorkflowDraftNotification(
                title: notification.title.trimmedForDraftEditing,
                body: notification.body?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
                severity: notification.severity?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
            )
        }
        task.schedule = task.schedule.map(normalizedSchedule)
        return task
    }

    private static func normalizedSchedule(_ schedule: AutomationWorkflowDraftSchedule) -> AutomationWorkflowDraftSchedule {
        AutomationWorkflowDraftSchedule(
            type: schedule.type.trimmedForDraftEditing,
            startAt: schedule.startAt,
            every: schedule.every,
            unit: schedule.unit?.trimmedForDraftEditing.nilIfEmptyForDraftEditing,
            timeZone: schedule.timeZone?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        )
    }

    private static func normalizedDependency(_ dependency: AutomationWorkflowDraftDependency) -> AutomationWorkflowDraftDependency {
        let from = dependency.from.trimmedForDraftEditing
        let to = dependency.to.trimmedForDraftEditing
        let trigger = dependency.trigger.trimmedForDraftEditing
        let key = dependency.key?.trimmedForDraftEditing.nilIfEmptyForDraftEditing ?? "\(from)->\(to):\(trigger)"
        return AutomationWorkflowDraftDependency(
            key: key,
            from: from,
            to: to,
            trigger: trigger,
            delaySeconds: dependency.delaySeconds,
            enabled: dependency.enabled
        )
    }

    private static func dependencyIndex(
        matching selector: AutomationWorkflowDraftDependencySelector,
        in document: AutomationWorkflowDraftDocument
    ) throws -> Int {
        let key = selector.key?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        let from = selector.from?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        let to = selector.to?.trimmedForDraftEditing.nilIfEmptyForDraftEditing
        let trigger = selector.trigger?.trimmedForDraftEditing.nilIfEmptyForDraftEditing

        guard key != nil || (from != nil && to != nil) else {
            throw AutomationWorkflowDraftEditError(
                code: "missingDependencySelector",
                message: "Dependency selector needs --key or both --from and --to.",
                path: "$.workflow.dependencies"
            )
        }

        let matches = document.workflow.dependencies.enumerated().filter { _, dependency in
            if let key, dependencyDisplayKey(dependency) != key {
                return false
            }
            if let from, dependency.from.trimmedForDraftEditing != from {
                return false
            }
            if let to, dependency.to.trimmedForDraftEditing != to {
                return false
            }
            if let trigger, dependency.trigger.trimmedForDraftEditing != trigger {
                return false
            }
            return true
        }

        guard !matches.isEmpty else {
            throw AutomationWorkflowDraftEditError(code: "missingDependency", message: "Dependency was not found.", path: "$.workflow.dependencies")
        }
        guard matches.count == 1 else {
            throw AutomationWorkflowDraftEditError(code: "ambiguousDependency", message: "Dependency selector matched multiple dependencies; include --trigger or --key.", path: "$.workflow.dependencies")
        }
        return matches[0].offset
    }

    private static func assertDependencyEndpointsExist(
        _ dependency: AutomationWorkflowDraftDependency,
        in document: AutomationWorkflowDraftDocument
    ) throws {
        let taskKeys = Set(document.workflow.tasks.map { $0.key.trimmedForDraftEditing })
        guard taskKeys.contains(dependency.from.trimmedForDraftEditing) else {
            throw AutomationWorkflowDraftEditError(code: AutomationWorkflowDraftIssueCode.missingDependencyEndpoint.rawValue, message: "Dependency source '\(dependency.from)' does not match a task key.", path: "$.workflow.dependencies[].from")
        }
        guard taskKeys.contains(dependency.to.trimmedForDraftEditing) else {
            throw AutomationWorkflowDraftEditError(code: AutomationWorkflowDraftIssueCode.missingDependencyEndpoint.rawValue, message: "Dependency target '\(dependency.to)' does not match a task key.", path: "$.workflow.dependencies[].to")
        }
    }

    private static func assertDependencyIsNotDuplicate(
        _ dependency: AutomationWorkflowDraftDependency,
        in document: AutomationWorkflowDraftDocument,
        ignoring ignoredIndex: Int
    ) throws {
        let from = dependency.from.trimmedForDraftEditing
        let to = dependency.to.trimmedForDraftEditing
        let trigger = dependency.trigger.trimmedForDraftEditing
        let isDuplicate = document.workflow.dependencies.enumerated().contains { index, existing in
            index != ignoredIndex &&
                existing.from.trimmedForDraftEditing == from &&
                existing.to.trimmedForDraftEditing == to &&
                existing.trigger.trimmedForDraftEditing == trigger
        }
        guard !isDuplicate else {
            throw AutomationWorkflowDraftEditError(
                code: AutomationWorkflowDraftIssueCode.duplicateDependency.rawValue,
                message: "Dependency '\(from)->\(to):\(trigger)' already exists.",
                path: "$.workflow.dependencies"
            )
        }
    }

    private static func dependencyDisplayKey(_ dependency: AutomationWorkflowDraftDependency) -> String {
        dependency.key?.trimmedForDraftEditing.nilIfEmptyForDraftEditing ??
            "\(dependency.from.trimmedForDraftEditing)->\(dependency.to.trimmedForDraftEditing):\(dependency.trigger.trimmedForDraftEditing)"
    }

    private static func dependencySortKey(_ dependency: AutomationWorkflowDraftDependency) -> String {
        "\(dependency.from.trimmedForDraftEditing)->\(dependency.to.trimmedForDraftEditing):\(dependency.trigger.trimmedForDraftEditing):\(dependencyDisplayKey(dependency))"
    }
}

private extension String {
    var trimmedForDraftEditing: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftEditing: String? {
        isEmpty ? nil : self
    }
}
