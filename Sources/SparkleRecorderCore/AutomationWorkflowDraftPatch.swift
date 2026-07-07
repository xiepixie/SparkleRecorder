import Foundation

public enum AutomationWorkflowDraftPatchSchema {
    public static let current = "sparkle.workflow.patch.v1"
}

public struct AutomationWorkflowDraftPatchDocument: Codable, Equatable, Sendable {
    public var schema: String
    public var ops: [AutomationWorkflowDraftPatchOperation]

    public init(
        schema: String = AutomationWorkflowDraftPatchSchema.current,
        ops: [AutomationWorkflowDraftPatchOperation]
    ) {
        self.schema = schema
        self.ops = ops
    }
}

public struct AutomationWorkflowDraftPatchOperation: Codable, Equatable, Sendable {
    public var op: String
    public var key: String?
    public var taskKey: String?
    public var task: AutomationWorkflowDraftTask?
    public var name: String?
    public var type: String?
    public var macroRef: AutomationWorkflowDraftMacroRef?
    public var condition: AutomationWorkflowDraftCondition?
    public var delaySeconds: TimeInterval?
    public var notification: AutomationWorkflowDraftNotification?
    public var schedule: AutomationWorkflowDraftSchedule?
    public var resource: AutomationWorkflowDraftResource?
    public var maxResourceWaitSeconds: TimeInterval?
    public var timeoutSeconds: TimeInterval?
    public var pollingSeconds: TimeInterval?
    public var retry: AutomationWorkflowDraftRetry?
    public var retryMaxAttempts: Int?
    public var joinPolicy: String?
    public var enabled: Bool?
    public var graphPosition: AutomationGraphPoint?
    public var dependency: AutomationWorkflowDraftDependency?
    public var from: String?
    public var to: String?
    public var trigger: String?
    public var newKey: String?
    public var newFrom: String?
    public var newTo: String?
    public var newTrigger: String?
    public var startAt: Date?
    public var every: Int?
    public var unit: String?
    public var timeZone: String?
    public var text: String?
    public var matchMode: TextMatchMode?
    public var regionRef: String?
    public var requireVisible: Bool?
    public var outcome: String?
    public var imageRef: String?
    public var baselineRef: String?
    public var pixel: AutomationGraphPoint?
    public var colorHex: String?
    public var pixelSampleRadius: Int?
    public var threshold: Double?
    public var visualRegion: AutomationWorkflowDraftVisualRegion?
    public var visualImage: AutomationWorkflowDraftVisualImageAsset?
    public var visualBaseline: AutomationWorkflowDraftVisualImageAsset?

    public init(
        op: String,
        key: String? = nil,
        taskKey: String? = nil,
        task: AutomationWorkflowDraftTask? = nil,
        name: String? = nil,
        type: String? = nil,
        macroRef: AutomationWorkflowDraftMacroRef? = nil,
        condition: AutomationWorkflowDraftCondition? = nil,
        delaySeconds: TimeInterval? = nil,
        notification: AutomationWorkflowDraftNotification? = nil,
        schedule: AutomationWorkflowDraftSchedule? = nil,
        resource: AutomationWorkflowDraftResource? = nil,
        maxResourceWaitSeconds: TimeInterval? = nil,
        timeoutSeconds: TimeInterval? = nil,
        pollingSeconds: TimeInterval? = nil,
        retry: AutomationWorkflowDraftRetry? = nil,
        retryMaxAttempts: Int? = nil,
        joinPolicy: String? = nil,
        enabled: Bool? = nil,
        graphPosition: AutomationGraphPoint? = nil,
        dependency: AutomationWorkflowDraftDependency? = nil,
        from: String? = nil,
        to: String? = nil,
        trigger: String? = nil,
        newKey: String? = nil,
        newFrom: String? = nil,
        newTo: String? = nil,
        newTrigger: String? = nil,
        startAt: Date? = nil,
        every: Int? = nil,
        unit: String? = nil,
        timeZone: String? = nil,
        text: String? = nil,
        matchMode: TextMatchMode? = nil,
        regionRef: String? = nil,
        requireVisible: Bool? = nil,
        outcome: String? = nil,
        imageRef: String? = nil,
        baselineRef: String? = nil,
        pixel: AutomationGraphPoint? = nil,
        colorHex: String? = nil,
        pixelSampleRadius: Int? = nil,
        threshold: Double? = nil,
        visualRegion: AutomationWorkflowDraftVisualRegion? = nil,
        visualImage: AutomationWorkflowDraftVisualImageAsset? = nil,
        visualBaseline: AutomationWorkflowDraftVisualImageAsset? = nil
    ) {
        self.op = op
        self.key = key
        self.taskKey = taskKey
        self.task = task
        self.name = name
        self.type = type
        self.macroRef = macroRef
        self.condition = condition
        self.delaySeconds = delaySeconds
        self.notification = notification
        self.schedule = schedule
        self.resource = resource
        self.maxResourceWaitSeconds = maxResourceWaitSeconds
        self.timeoutSeconds = timeoutSeconds
        self.pollingSeconds = pollingSeconds
        self.retry = retry
        self.retryMaxAttempts = retryMaxAttempts
        self.joinPolicy = joinPolicy
        self.enabled = enabled
        self.graphPosition = graphPosition
        self.dependency = dependency
        self.from = from
        self.to = to
        self.trigger = trigger
        self.newKey = newKey
        self.newFrom = newFrom
        self.newTo = newTo
        self.newTrigger = newTrigger
        self.startAt = startAt
        self.every = every
        self.unit = unit
        self.timeZone = timeZone
        self.text = text
        self.matchMode = matchMode
        self.regionRef = regionRef
        self.requireVisible = requireVisible
        self.outcome = outcome
        self.imageRef = imageRef
        self.baselineRef = baselineRef
        self.pixel = pixel
        self.colorHex = colorHex
        self.pixelSampleRadius = pixelSampleRadius
        self.threshold = threshold
        self.visualRegion = visualRegion
        self.visualImage = visualImage
        self.visualBaseline = visualBaseline
    }
}

public enum AutomationWorkflowDraftPatchApplier {
    public static func apply(
        _ patch: AutomationWorkflowDraftPatchDocument,
        to document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) throws -> AutomationWorkflowDraftEditResult {
        guard patch.schema == AutomationWorkflowDraftPatchSchema.current else {
            throw AutomationWorkflowDraftEditError(
                code: AutomationWorkflowDraftIssueCode.unsupportedSchema.rawValue,
                message: "Unsupported workflow patch schema '\(patch.schema)'.",
                path: "$.schema"
            )
        }

        var document = document
        var changedTaskKeys: Set<String> = []
        var changedDependencyKeys: Set<String> = []

        for (index, operation) in patch.ops.enumerated() {
            let result = try apply(
                operation,
                at: index,
                to: document,
                context: context
            )
            document = result.document
            changedTaskKeys.formUnion(result.changedTaskKeys)
            changedDependencyKeys.formUnion(result.changedDependencyKeys)
        }

        return AutomationWorkflowDraftEditResult(
            operation: "draft patch",
            document: document,
            validation: AutomationWorkflowDraftValidator.validate(document, context: context),
            changedTaskKeys: changedTaskKeys.sorted(),
            changedDependencyKeys: changedDependencyKeys.sorted()
        )
    }

    private static func apply(
        _ operation: AutomationWorkflowDraftPatchOperation,
        at index: Int,
        to document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext
    ) throws -> AutomationWorkflowDraftEditResult {
        switch operation.op {
        case "addTask":
            return try AutomationWorkflowDraftEditor.addTask(
                try taskToAdd(from: operation, index: index),
                to: document,
                context: context
            )
        case "setTask":
            return try setTask(
                from: operation,
                at: index,
                in: document,
                context: context
            )
        case "removeTask":
            return try AutomationWorkflowDraftEditor.removeTask(
                key: try taskKey(from: operation, index: index),
                from: document,
                context: context
            )
        case "setSchedule":
            return try AutomationWorkflowDraftEditor.setSchedule(
                taskKey: try taskKey(from: operation, index: index),
                schedule: try schedule(from: operation, index: index),
                in: document,
                context: context
            )
        case "setCondition":
            return try AutomationWorkflowDraftEditor.setCondition(
                taskKey: try taskKey(from: operation, index: index),
                condition: condition(from: operation),
                in: document,
                timeoutSeconds: operation.timeoutSeconds,
                pollingSeconds: operation.pollingSeconds,
                context: context
            )
        case "upsertVisualRegion":
            return try upsertVisualRegion(
                from: operation,
                at: index,
                in: document,
                context: context
            )
        case "upsertVisualImage":
            return try upsertVisualImage(
                from: operation,
                at: index,
                in: document,
                context: context
            )
        case "upsertVisualBaseline":
            return try upsertVisualBaseline(
                from: operation,
                at: index,
                in: document,
                context: context
            )
        case "addDependency":
            return try AutomationWorkflowDraftEditor.addDependency(
                try dependencyToAdd(from: operation, index: index),
                to: document,
                context: context
            )
        case "setDependency":
            return try AutomationWorkflowDraftEditor.setDependency(
                matching: dependencySelector(from: operation),
                in: document,
                key: operation.newKey,
                from: operation.newFrom,
                to: operation.newTo,
                trigger: operation.newTrigger,
                delaySeconds: operation.delaySeconds,
                enabled: operation.enabled,
                context: context
            )
        case "removeDependency":
            return try AutomationWorkflowDraftEditor.removeDependency(
                matching: dependencySelector(from: operation),
                from: document,
                context: context
            )
        case "normalize":
            return AutomationWorkflowDraftEditor.normalize(document, context: context)
        default:
            throw AutomationWorkflowDraftEditError(
                code: "unsupportedPatchOperation",
                message: "Unsupported patch operation '\(operation.op)'.",
                path: "$.ops[\(index)].op"
            )
        }
    }

    private static func upsertVisualRegion(
        from operation: AutomationWorkflowDraftPatchOperation,
        at index: Int,
        in document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext
    ) throws -> AutomationWorkflowDraftEditResult {
        guard let region = operation.visualRegion else {
            throw missingPatchField("visualRegion", index: index)
        }

        var document = document
        if document.visualAssets == nil {
            document.visualAssets = AutomationWorkflowDraftVisualAssets()
        }
        if let existingIndex = document.visualAssets?.regions.firstIndex(where: {
            $0.key.trimmedForPatchEditing == region.key.trimmedForPatchEditing
        }) {
            document.visualAssets?.regions[existingIndex] = region
        } else {
            document.visualAssets?.regions.append(region)
        }

        return AutomationWorkflowDraftEditResult(
            operation: "draft visual region upsert",
            document: document,
            validation: AutomationWorkflowDraftValidator.validate(document, context: context)
        )
    }

    private static func upsertVisualImage(
        from operation: AutomationWorkflowDraftPatchOperation,
        at index: Int,
        in document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext
    ) throws -> AutomationWorkflowDraftEditResult {
        guard let image = operation.visualImage else {
            throw missingPatchField("visualImage", index: index)
        }

        var document = document
        if document.visualAssets == nil {
            document.visualAssets = AutomationWorkflowDraftVisualAssets()
        }
        if let existingIndex = document.visualAssets?.images.firstIndex(where: {
            $0.key.trimmedForPatchEditing == image.key.trimmedForPatchEditing
        }) {
            document.visualAssets?.images[existingIndex] = image
        } else {
            document.visualAssets?.images.append(image)
        }

        return AutomationWorkflowDraftEditResult(
            operation: "draft visual image upsert",
            document: document,
            validation: AutomationWorkflowDraftValidator.validate(document, context: context)
        )
    }

    private static func upsertVisualBaseline(
        from operation: AutomationWorkflowDraftPatchOperation,
        at index: Int,
        in document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext
    ) throws -> AutomationWorkflowDraftEditResult {
        guard let baseline = operation.visualBaseline else {
            throw missingPatchField("visualBaseline", index: index)
        }

        var document = document
        if document.visualAssets == nil {
            document.visualAssets = AutomationWorkflowDraftVisualAssets()
        }
        if let existingIndex = document.visualAssets?.baselines.firstIndex(where: {
            $0.key.trimmedForPatchEditing == baseline.key.trimmedForPatchEditing
        }) {
            document.visualAssets?.baselines[existingIndex] = baseline
        } else {
            document.visualAssets?.baselines.append(baseline)
        }

        return AutomationWorkflowDraftEditResult(
            operation: "draft visual baseline upsert",
            document: document,
            validation: AutomationWorkflowDraftValidator.validate(document, context: context)
        )
    }

    private static func taskToAdd(
        from operation: AutomationWorkflowDraftPatchOperation,
        index: Int
    ) throws -> AutomationWorkflowDraftTask {
        if let task = operation.task {
            return task
        }
        guard let key = operation.taskKey ?? operation.key else {
            throw missingPatchField("key", index: index)
        }
        guard let type = operation.type else {
            throw missingPatchField("type", index: index)
        }

        return AutomationWorkflowDraftTask(
            key: key,
            type: type,
            name: operation.name,
            macroRef: operation.macroRef,
            condition: operation.condition ?? (type == "condition" ? condition(from: operation) : nil),
            delaySeconds: operation.delaySeconds,
            notification: operation.notification,
            schedule: operation.schedule,
            resource: operation.resource,
            maxResourceWaitSeconds: operation.maxResourceWaitSeconds,
            timeoutSeconds: operation.timeoutSeconds,
            pollingSeconds: operation.pollingSeconds,
            retry: operation.retryMaxAttempts.map { AutomationWorkflowDraftRetry(maxAttempts: $0) } ?? operation.retry,
            joinPolicy: operation.joinPolicy,
            enabled: operation.enabled,
            graphPosition: operation.graphPosition
        )
    }

    private static func setTask(
        from operation: AutomationWorkflowDraftPatchOperation,
        at index: Int,
        in document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext
    ) throws -> AutomationWorkflowDraftEditResult {
        let key = try taskKey(from: operation, index: index)
        var document = document
        guard let taskIndex = document.workflow.tasks.firstIndex(where: { $0.key.trimmedForPatchEditing == key.trimmedForPatchEditing }) else {
            throw AutomationWorkflowDraftEditError(
                code: "missingTask",
                message: "Task '\(key)' was not found.",
                path: "$.workflow.tasks"
            )
        }

        if let name = operation.name {
            document.workflow.tasks[taskIndex].name = name.trimmedForPatchEditing.nilIfEmptyForPatchEditing
        }
        if let type = operation.type {
            document.workflow.tasks[taskIndex].type = type.trimmedForPatchEditing
        }
        if let macroRef = operation.macroRef {
            document.workflow.tasks[taskIndex].macroRef = macroRef
        }
        if let condition = operation.condition {
            document.workflow.tasks[taskIndex].condition = condition
        }
        if let delaySeconds = operation.delaySeconds {
            document.workflow.tasks[taskIndex].delaySeconds = delaySeconds
        }
        if let notification = operation.notification {
            document.workflow.tasks[taskIndex].notification = notification
        }
        if let schedule = operation.schedule {
            document.workflow.tasks[taskIndex].schedule = schedule.type.trimmedForPatchEditing == "none" ? nil : schedule
        }
        if let resource = operation.resource {
            document.workflow.tasks[taskIndex].resource = resource
        }
        if let maxResourceWaitSeconds = operation.maxResourceWaitSeconds {
            document.workflow.tasks[taskIndex].maxResourceWaitSeconds = maxResourceWaitSeconds
        }
        if let timeoutSeconds = operation.timeoutSeconds {
            document.workflow.tasks[taskIndex].timeoutSeconds = timeoutSeconds
        }
        if let pollingSeconds = operation.pollingSeconds {
            document.workflow.tasks[taskIndex].pollingSeconds = pollingSeconds
        }
        if let retryMaxAttempts = operation.retryMaxAttempts {
            document.workflow.tasks[taskIndex].retry = AutomationWorkflowDraftRetry(maxAttempts: retryMaxAttempts)
        } else if let retry = operation.retry {
            document.workflow.tasks[taskIndex].retry = retry
        }
        if let joinPolicy = operation.joinPolicy {
            document.workflow.tasks[taskIndex].joinPolicy = joinPolicy.trimmedForPatchEditing.nilIfEmptyForPatchEditing
        }
        if let enabled = operation.enabled {
            document.workflow.tasks[taskIndex].enabled = enabled
        }
        if let graphPosition = operation.graphPosition {
            document.workflow.tasks[taskIndex].graphPosition = graphPosition
        }

        return AutomationWorkflowDraftEditResult(
            operation: "draft task set",
            document: document,
            validation: AutomationWorkflowDraftValidator.validate(document, context: context),
            changedTaskKeys: [key]
        )
    }

    private static func taskKey(
        from operation: AutomationWorkflowDraftPatchOperation,
        index: Int
    ) throws -> String {
        guard let key = operation.taskKey ?? operation.key ?? operation.task?.key else {
            throw missingPatchField("key", index: index)
        }
        return key
    }

    private static func schedule(
        from operation: AutomationWorkflowDraftPatchOperation,
        index: Int
    ) throws -> AutomationWorkflowDraftSchedule? {
        let schedule = operation.schedule ?? operation.type.map {
            AutomationWorkflowDraftSchedule(
                type: $0,
                startAt: operation.startAt,
                every: operation.every,
                unit: operation.unit,
                timeZone: operation.timeZone
            )
        }
        guard let schedule else {
            throw missingPatchField("schedule", index: index)
        }
        return schedule.type.trimmingCharacters(in: .whitespacesAndNewlines) == "none" ? nil : schedule
    }

    private static func condition(
        from operation: AutomationWorkflowDraftPatchOperation
    ) -> AutomationWorkflowDraftCondition {
        operation.condition ?? AutomationWorkflowDraftCondition(
            type: operation.type ?? "ocrText",
            text: operation.text,
            matchMode: operation.matchMode,
            regionRef: operation.regionRef,
            requireVisible: operation.requireVisible,
            outcome: operation.outcome,
            imageRef: operation.imageRef,
            baselineRef: operation.baselineRef,
            pixel: operation.pixel,
            colorHex: operation.colorHex,
            pixelSampleRadius: operation.pixelSampleRadius,
            threshold: operation.threshold
        )
    }

    private static func dependencyToAdd(
        from operation: AutomationWorkflowDraftPatchOperation,
        index: Int
    ) throws -> AutomationWorkflowDraftDependency {
        if let dependency = operation.dependency {
            return dependency
        }
        guard let from = operation.from else {
            throw missingPatchField("from", index: index)
        }
        guard let to = operation.to else {
            throw missingPatchField("to", index: index)
        }
        guard let trigger = operation.trigger else {
            throw missingPatchField("trigger", index: index)
        }
        return AutomationWorkflowDraftDependency(
            key: operation.key,
            from: from,
            to: to,
            trigger: trigger,
            delaySeconds: operation.delaySeconds,
            enabled: operation.enabled
        )
    }

    private static func dependencySelector(
        from operation: AutomationWorkflowDraftPatchOperation
    ) -> AutomationWorkflowDraftDependencySelector {
        AutomationWorkflowDraftDependencySelector(
            key: operation.key ?? operation.dependency?.key,
            from: operation.from ?? operation.dependency?.from,
            to: operation.to ?? operation.dependency?.to,
            trigger: operation.trigger ?? operation.dependency?.trigger
        )
    }

    private static func missingPatchField(
        _ field: String,
        index: Int
    ) -> AutomationWorkflowDraftEditError {
        AutomationWorkflowDraftEditError(
            code: "missingPatchField",
            message: "Patch operation requires '\(field)'.",
            path: "$.ops[\(index)].\(field)"
        )
    }
}

private extension String {
    var trimmedForPatchEditing: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForPatchEditing: String? {
        isEmpty ? nil : self
    }
}
