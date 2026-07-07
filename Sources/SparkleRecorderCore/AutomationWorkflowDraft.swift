import Foundation

public enum AutomationWorkflowDraftSchema {
    public static let current = "sparkle.workflow.draft.v1"
}

public struct AutomationWorkflowDraftDocument: Codable, Equatable, Sendable {
    public var schema: String
    public var workflow: AutomationWorkflowDraft
    public var visualAssets: AutomationWorkflowDraftVisualAssets?

    public init(
        schema: String = AutomationWorkflowDraftSchema.current,
        workflow: AutomationWorkflowDraft,
        visualAssets: AutomationWorkflowDraftVisualAssets? = nil
    ) {
        self.schema = schema
        self.workflow = workflow
        self.visualAssets = visualAssets
    }
}

public struct AutomationWorkflowDraft: Codable, Equatable, Sendable {
    public var name: String
    public var tasks: [AutomationWorkflowDraftTask]
    public var dependencies: [AutomationWorkflowDraftDependency]

    public init(
        name: String,
        tasks: [AutomationWorkflowDraftTask] = [],
        dependencies: [AutomationWorkflowDraftDependency] = []
    ) {
        self.name = name
        self.tasks = tasks
        self.dependencies = dependencies
    }
}

public struct AutomationWorkflowDraftTask: Codable, Equatable, Sendable {
    public var key: String
    public var name: String?
    public var type: String
    public var loop: AutomationWorkflowDraftLoop?
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
    public var joinPolicy: String?
    public var enabled: Bool?
    public var graphPosition: AutomationGraphPoint?

    public init(
        key: String,
        type: String,
        name: String? = nil,
        loop: AutomationWorkflowDraftLoop? = nil,
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
        joinPolicy: String? = nil,
        enabled: Bool? = nil,
        graphPosition: AutomationGraphPoint? = nil
    ) {
        self.key = key
        self.name = name
        self.type = type
        self.loop = loop
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
        self.joinPolicy = joinPolicy
        self.enabled = enabled
        self.graphPosition = graphPosition
    }
}

public struct AutomationWorkflowDraftLoop: Codable, Equatable, Sendable {
    public static let maxFixedCount = 50

    public var kind: String?
    public var count: Int
    public var tasks: [AutomationWorkflowDraftTask]
    public var until: AutomationWorkflowDraftCondition?
    public var maxAttempts: Int?
    public var timeoutSeconds: TimeInterval?
    public var pollingSeconds: TimeInterval?
    public var onFailure: String?

    public init(
        count: Int,
        tasks: [AutomationWorkflowDraftTask],
        kind: String? = nil,
        until: AutomationWorkflowDraftCondition? = nil,
        maxAttempts: Int? = nil,
        timeoutSeconds: TimeInterval? = nil,
        pollingSeconds: TimeInterval? = nil,
        onFailure: String? = nil
    ) {
        self.kind = kind
        self.count = count
        self.tasks = tasks
        self.until = until
        self.maxAttempts = maxAttempts
        self.timeoutSeconds = timeoutSeconds
        self.pollingSeconds = pollingSeconds
        self.onFailure = onFailure
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case count
        case tasks
        case until
        case maxAttempts
        case timeoutSeconds
        case pollingSeconds
        case onFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        tasks = try container.decodeIfPresent([AutomationWorkflowDraftTask].self, forKey: .tasks) ?? []
        until = try container.decodeIfPresent(AutomationWorkflowDraftCondition.self, forKey: .until)
        maxAttempts = try container.decodeIfPresent(Int.self, forKey: .maxAttempts)
        timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds)
        pollingSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingSeconds)
        onFailure = try container.decodeIfPresent(String.self, forKey: .onFailure)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encode(count, forKey: .count)
        try container.encode(tasks, forKey: .tasks)
        try container.encodeIfPresent(until, forKey: .until)
        try container.encodeIfPresent(maxAttempts, forKey: .maxAttempts)
        try container.encodeIfPresent(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encodeIfPresent(pollingSeconds, forKey: .pollingSeconds)
        try container.encodeIfPresent(onFailure, forKey: .onFailure)
    }

    public var normalizedKind: String {
        kind?.trimmedForDraftValidation.nilIfEmpty ?? AutomationWorkflowDraftLoopKind.fixedCount
    }

    public var isFixedCount: Bool {
        normalizedKind == AutomationWorkflowDraftLoopKind.fixedCount
    }

    public var isRepeatUntil: Bool {
        normalizedKind == AutomationWorkflowDraftLoopKind.repeatUntil
    }
}

public enum AutomationWorkflowDraftLoopKind {
    public static let fixedCount = "fixedCount"
    public static let repeatUntil = "repeatUntil"
}

public enum AutomationWorkflowDraftLoopFailurePolicy {
    public static let failRun = "failRun"
    public static let `continue` = "continue"
    public static let requireManualApproval = "requireManualApproval"
}

public struct AutomationWorkflowDraftMacroRef: Codable, Equatable, Sendable {
    public var id: UUID?
    public var name: String?

    public init(id: UUID? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }

    public var isEmpty: Bool {
        id == nil && (name?.trimmedForDraftValidation.isEmpty ?? true)
    }
}

public struct AutomationWorkflowDraftCondition: Codable, Equatable, Sendable {
    public var type: String
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

    public init(
        type: String,
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
        threshold: Double? = nil
    ) {
        self.type = type
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
    }
}

public struct AutomationWorkflowDraftVisualAssets: Codable, Equatable, Sendable {
    public var regions: [AutomationWorkflowDraftVisualRegion]
    public var images: [AutomationWorkflowDraftVisualImageAsset]
    public var baselines: [AutomationWorkflowDraftVisualImageAsset]

    public init(
        regions: [AutomationWorkflowDraftVisualRegion] = [],
        images: [AutomationWorkflowDraftVisualImageAsset] = [],
        baselines: [AutomationWorkflowDraftVisualImageAsset] = []
    ) {
        self.regions = regions
        self.images = images
        self.baselines = baselines
    }

    public var isEmpty: Bool {
        regions.isEmpty && images.isEmpty && baselines.isEmpty
    }

    public func region(for key: String?) -> AutomationWorkflowDraftVisualRegion? {
        guard let key = key?.trimmedForDraftValidation, !key.isEmpty else {
            return nil
        }
        return regions.first { $0.key.trimmedForDraftValidation == key }
    }

    public func image(for key: String?) -> AutomationWorkflowDraftVisualImageAsset? {
        guard let key = key?.trimmedForDraftValidation, !key.isEmpty else {
            return nil
        }
        return images.first { $0.key.trimmedForDraftValidation == key }
    }

    public func baseline(for key: String?) -> AutomationWorkflowDraftVisualImageAsset? {
        guard let key = key?.trimmedForDraftValidation, !key.isEmpty else {
            return nil
        }
        return baselines.first { $0.key.trimmedForDraftValidation == key }
    }

    public func imagePath(for key: String?) -> String? {
        Self.normalizedRelativeAssetPath(image(for: key)?.path)
    }

    public func baselinePath(for key: String?) -> String? {
        Self.normalizedRelativeAssetPath(baseline(for: key)?.path)
    }

    public static func normalizedRelativeAssetPath(_ path: String?) -> String? {
        guard let path = path?.trimmedForDraftValidation, !path.isEmpty else {
            return nil
        }
        guard !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("://"),
              !path.contains(":"),
              !path.contains("\\") else {
            return nil
        }

        let components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components.joined(separator: "/")
    }
}

public struct AutomationWorkflowDraftVisualRegion: Codable, Equatable, Sendable {
    public var key: String
    public var label: String?
    public var bounds: RectValue
    public var space: AutomationOCRSearchRegionSpace

    public init(
        key: String,
        label: String? = nil,
        bounds: RectValue,
        space: AutomationOCRSearchRegionSpace = .displayAbsolute
    ) {
        self.key = key
        self.label = label?.trimmedForDraftValidation.nilIfEmpty
        self.bounds = bounds
        self.space = space
    }
}

public struct AutomationWorkflowDraftVisualImageAsset: Codable, Equatable, Sendable {
    public var key: String
    public var label: String?
    public var path: String?
    public var sha256: String?
    public var sourceFrameID: UUID?
    public var sourceSurfaceID: String?
    public var sourceArtifactPath: String?
    public var sourceBounds: RectValue?
    public var sourceBoundsSpace: AutomationOCRSearchRegionSpace?

    public init(
        key: String,
        label: String? = nil,
        path: String? = nil,
        sha256: String? = nil,
        sourceFrameID: UUID? = nil,
        sourceSurfaceID: String? = nil,
        sourceArtifactPath: String? = nil,
        sourceBounds: RectValue? = nil,
        sourceBoundsSpace: AutomationOCRSearchRegionSpace? = nil
    ) {
        self.key = key
        self.label = label?.trimmedForDraftValidation.nilIfEmpty
        self.path = path?.trimmedForDraftValidation.nilIfEmpty
        self.sha256 = sha256?.trimmedForDraftValidation.nilIfEmpty
        self.sourceFrameID = sourceFrameID
        self.sourceSurfaceID = sourceSurfaceID?.trimmedForDraftValidation.nilIfEmpty
        self.sourceArtifactPath = sourceArtifactPath?.trimmedForDraftValidation.nilIfEmpty
        self.sourceBounds = sourceBounds
        self.sourceBoundsSpace = sourceBoundsSpace
    }
}

public struct AutomationWorkflowDraftNotification: Codable, Equatable, Sendable {
    public var title: String
    public var body: String?
    public var severity: String?

    public init(title: String, body: String? = nil, severity: String? = nil) {
        self.title = title
        self.body = body
        self.severity = severity
    }
}

public struct AutomationWorkflowDraftSchedule: Codable, Equatable, Sendable {
    public var type: String
    public var startAt: Date?
    public var every: Int?
    public var unit: String?
    public var timeZone: String?

    public init(
        type: String,
        startAt: Date? = nil,
        every: Int? = nil,
        unit: String? = nil,
        timeZone: String? = nil
    ) {
        self.type = type
        self.startAt = startAt
        self.every = every
        self.unit = unit
        self.timeZone = timeZone
    }
}

public enum AutomationWorkflowDraftResource: String, Codable, Equatable, Sendable {
    case foregroundInput
    case screenCapture
    case accessibility
    case network
    case none
}

public struct AutomationWorkflowDraftRetry: Codable, Equatable, Sendable {
    public var maxAttempts: Int?

    public init(maxAttempts: Int? = nil) {
        self.maxAttempts = maxAttempts
    }
}

public struct AutomationWorkflowDraftDependency: Codable, Equatable, Sendable {
    public var key: String?
    public var from: String
    public var to: String
    public var trigger: String
    public var delaySeconds: TimeInterval?
    public var enabled: Bool?

    public init(
        key: String? = nil,
        from: String,
        to: String,
        trigger: String,
        delaySeconds: TimeInterval? = nil,
        enabled: Bool? = nil
    ) {
        self.key = key
        self.from = from
        self.to = to
        self.trigger = trigger
        self.delaySeconds = delaySeconds
        self.enabled = enabled
    }
}

public enum AutomationWorkflowDraftLoopExpander {
    public static func expandedDocument(
        _ document: AutomationWorkflowDraftDocument
    ) -> AutomationWorkflowDraftDocument {
        var expandedTasks: [AutomationWorkflowDraftTask] = []
        var loopPorts: [String: (entry: String, exit: String, exitTrigger: String)] = [:]

        for task in document.workflow.tasks {
            guard task.type.trimmedForDraftLoopExpansion == "loop",
                  let loop = task.loop,
                  loop.isFixedCount,
                  loop.count > 0,
                  !loop.tasks.isEmpty
            else {
                expandedTasks.append(task)
                continue
            }

            let loopKey = task.key.trimmedForDraftLoopExpansion
            let copies = expandedLoopTasks(for: task, loop: loop)
            guard let entry = copies.first?.key,
                  let exit = copies.last?.key,
                  let exitBodyTask = loop.tasks.last else {
                continue
            }
            loopPorts[loopKey] = (
                entry: entry,
                exit: exit,
                exitTrigger: defaultCompletionTrigger(for: exitBodyTask)
            )
            expandedTasks.append(contentsOf: copies)
        }

        var expandedDependencies: [AutomationWorkflowDraftDependency] = []
        expandedDependencies.append(contentsOf: generatedLoopDependencies(
            for: document.workflow.tasks
        ))
        expandedDependencies.append(contentsOf: document.workflow.dependencies.map { dependency in
            let fromLoop = loopPorts[dependency.from.trimmedForDraftLoopExpansion]
            let toLoop = loopPorts[dependency.to.trimmedForDraftLoopExpansion]
            let from = fromLoop?.exit ?? dependency.from
            let to = toLoop?.entry ?? dependency.to
            let trigger = fromLoop != nil &&
                dependency.trigger.trimmedForDraftLoopExpansion == "success"
                ? fromLoop?.exitTrigger ?? dependency.trigger
                : dependency.trigger
            let key = dependency.key?.trimmedForDraftLoopExpansion.nilIfEmptyForDraftLoopExpansion.map { key in
                fromLoop != nil || toLoop != nil ? "loop-expanded:\(key)" : key
            }
            return AutomationWorkflowDraftDependency(
                key: key,
                from: from,
                to: to,
                trigger: trigger,
                delaySeconds: dependency.delaySeconds,
                enabled: dependency.enabled
            )
        })

        return AutomationWorkflowDraftDocument(
            schema: document.schema,
            workflow: AutomationWorkflowDraft(
                name: document.workflow.name,
                tasks: expandedTasks,
                dependencies: expandedDependencies
            ),
            visualAssets: document.visualAssets
        )
    }

    private static func expandedLoopTasks(
        for task: AutomationWorkflowDraftTask,
        loop: AutomationWorkflowDraftLoop
    ) -> [AutomationWorkflowDraftTask] {
        let loopKey = task.key.trimmedForDraftLoopExpansion
        let loopName = task.name?.trimmedForDraftLoopExpansion.nilIfEmptyForDraftLoopExpansion ?? loopKey
        let enabled = task.enabled ?? true

        return (1...loop.count).flatMap { iteration in
            loop.tasks.enumerated().map { bodyIndex, bodyTask in
                var copy = bodyTask
                let bodyKey = bodyTask.key.trimmedForDraftLoopExpansion
                copy.key = expandedKey(loopKey: loopKey, iteration: iteration, bodyKey: bodyKey)
                copy.name = expandedName(
                    loopName: loopName,
                    iteration: iteration,
                    bodyTask: bodyTask
                )
                copy.schedule = iteration == 1 && bodyIndex == 0 ? task.schedule : nil
                copy.enabled = enabled && (bodyTask.enabled ?? true)
                return copy
            }
        }
    }

    private static func generatedLoopDependencies(
        for tasks: [AutomationWorkflowDraftTask]
    ) -> [AutomationWorkflowDraftDependency] {
        var dependencies: [AutomationWorkflowDraftDependency] = []

        for task in tasks {
            guard task.type.trimmedForDraftLoopExpansion == "loop",
                  let loop = task.loop,
                  loop.isFixedCount,
                  loop.count > 0,
                  !loop.tasks.isEmpty
            else {
                continue
            }

            let loopKey = task.key.trimmedForDraftLoopExpansion
            let bodyKeys = loop.tasks.map { $0.key.trimmedForDraftLoopExpansion }

            for iteration in 1...loop.count {
                for pairIndex in bodyKeys.indices.dropLast() {
                    let from = expandedKey(loopKey: loopKey, iteration: iteration, bodyKey: bodyKeys[pairIndex])
                    let to = expandedKey(loopKey: loopKey, iteration: iteration, bodyKey: bodyKeys[pairIndex + 1])
                    let trigger = defaultCompletionTrigger(for: loop.tasks[pairIndex])
                    dependencies.append(AutomationWorkflowDraftDependency(
                        key: "\(from)->\(to):\(trigger)",
                        from: from,
                        to: to,
                        trigger: trigger
                    ))
                }

                if iteration < loop.count,
                   let last = bodyKeys.last,
                   let first = bodyKeys.first {
                    let from = expandedKey(loopKey: loopKey, iteration: iteration, bodyKey: last)
                    let to = expandedKey(loopKey: loopKey, iteration: iteration + 1, bodyKey: first)
                    let trigger = loop.tasks.last.map(defaultCompletionTrigger(for:)) ?? "success"
                    dependencies.append(AutomationWorkflowDraftDependency(
                        key: "\(from)->\(to):\(trigger)",
                        from: from,
                        to: to,
                        trigger: trigger
                    ))
                }
            }
        }

        return dependencies
    }

    private static func expandedKey(loopKey: String, iteration: Int, bodyKey: String) -> String {
        "\(loopKey)__\(iteration)__\(bodyKey)"
    }

    private static func expandedName(
        loopName: String,
        iteration: Int,
        bodyTask: AutomationWorkflowDraftTask
    ) -> String {
        let bodyName = bodyTask.name?.trimmedForDraftLoopExpansion.nilIfEmptyForDraftLoopExpansion ??
            bodyTask.key.trimmedForDraftLoopExpansion
        return "\(loopName) \(iteration): \(bodyName)"
    }

    private static func defaultCompletionTrigger(for task: AutomationWorkflowDraftTask) -> String {
        switch task.type.trimmedForDraftLoopExpansion {
        case "condition", "manualApproval":
            return "conditionMatched"
        default:
            return "success"
        }
    }
}

public struct AutomationWorkflowDraftMacroCatalogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var tags: [String]
    public var notes: String?
    public var durationSeconds: TimeInterval
    public var eventCount: Int
    public var clickCount: Int
    public var keyCount: Int
    public var scrollCount: Int
    public var resourceRequirement: AutomationWorkflowDraftResource
    public var surfaces: [AutomationWorkflowDraftSurfaceSummary]?
    public var semanticRecording: MacroSemanticRecordingReference?

    public init(
        id: UUID,
        name: String,
        tags: [String] = [],
        notes: String? = nil,
        durationSeconds: TimeInterval = 0,
        eventCount: Int = 0,
        clickCount: Int = 0,
        keyCount: Int = 0,
        scrollCount: Int = 0,
        resourceRequirement: AutomationWorkflowDraftResource = .foregroundInput,
        surfaces: [AutomationWorkflowDraftSurfaceSummary]? = nil,
        semanticRecording: MacroSemanticRecordingReference? = nil
    ) {
        self.id = id
        self.name = name
        self.tags = tags
        self.notes = notes?.trimmedForDraftValidation.nilIfEmpty
        self.durationSeconds = max(0, durationSeconds)
        self.eventCount = max(0, eventCount)
        self.clickCount = max(0, clickCount)
        self.keyCount = max(0, keyCount)
        self.scrollCount = max(0, scrollCount)
        self.resourceRequirement = resourceRequirement
        self.surfaces = surfaces?.isEmpty == true ? nil : surfaces
        self.semanticRecording = semanticRecording
    }

    public init(macro: SavedMacro) {
        self.init(
            id: macro.id,
            name: macro.name,
            tags: macro.tags,
            notes: macro.notes,
            durationSeconds: macro.duration,
            eventCount: macro.eventCount,
            clickCount: macro.clickCount,
            keyCount: macro.keyCount,
            scrollCount: macro.scrollCount,
            resourceRequirement: .foregroundInput,
            surfaces: macro.surfaces
                .sorted { $0.key < $1.key }
                .map { AutomationWorkflowDraftSurfaceSummary(key: $0.key, surface: $0.value) },
            semanticRecording: macro.semanticRecording
        )
    }

    public func matches(searchTerm: String?) -> Bool {
        guard let searchTerm = searchTerm?.trimmedForDraftValidation.lowercased(),
              !searchTerm.isEmpty else {
            return true
        }
        if name.lowercased().contains(searchTerm) {
            return true
        }
        if tags.contains(where: { $0.lowercased().contains(searchTerm) }) {
            return true
        }
        if notes?.lowercased().contains(searchTerm) == true {
            return true
        }
        if surfaces?.contains(where: { $0.matches(searchTerm: searchTerm) }) == true {
            return true
        }
        return false
    }
}

public struct AutomationWorkflowDraftSurfaceSummary: Codable, Equatable, Sendable {
    public var key: String
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var recordedFrame: RectValue
    public var recordedContentFrame: RectValue?

    public init(
        key: String,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        recordedFrame: RectValue,
        recordedContentFrame: RectValue? = nil
    ) {
        self.key = key
        self.appName = appName?.trimmedForDraftValidation.nilIfEmpty
        self.bundleIdentifier = bundleIdentifier?.trimmedForDraftValidation.nilIfEmpty
        self.windowTitle = windowTitle?.trimmedForDraftValidation.nilIfEmpty
        self.recordedFrame = recordedFrame
        self.recordedContentFrame = recordedContentFrame
    }

    public init(key: String, surface: PlaybackSurface) {
        self.init(
            key: key,
            appName: surface.appName,
            bundleIdentifier: surface.bundleIdentifier,
            windowTitle: surface.windowTitle,
            recordedFrame: surface.recordedFrame,
            recordedContentFrame: surface.recordedContentFrame
        )
    }

    fileprivate func matches(searchTerm: String) -> Bool {
        appName?.lowercased().contains(searchTerm) == true ||
            bundleIdentifier?.lowercased().contains(searchTerm) == true ||
            windowTitle?.lowercased().contains(searchTerm) == true
    }
}

public struct AutomationWorkflowDraftValidationContext: Sendable {
    public var macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]

    public init(macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry] = []) {
        self.macroCatalog = macroCatalog
    }
}

public struct AutomationWorkflowDraftValidationResult: Codable, Equatable, Sendable {
    public var issues: [AutomationWorkflowDraftIssue]

    public init(issues: [AutomationWorkflowDraftIssue] = []) {
        self.issues = issues
    }

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }
}

public struct AutomationWorkflowDraftIssue: Codable, Equatable, Sendable {
    public var severity: AutomationWorkflowDraftIssueSeverity
    public var code: AutomationWorkflowDraftIssueCode
    public var message: String
    public var path: String
    public var taskKey: String?
    public var dependencyKey: String?
    public var candidates: [UUID]

    public init(
        severity: AutomationWorkflowDraftIssueSeverity,
        code: AutomationWorkflowDraftIssueCode,
        message: String,
        path: String,
        taskKey: String? = nil,
        dependencyKey: String? = nil,
        candidates: [UUID] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.path = path
        self.taskKey = taskKey
        self.dependencyKey = dependencyKey
        self.candidates = candidates
    }
}

public enum AutomationWorkflowDraftIssueSeverity: String, Codable, Equatable, Sendable {
    case error
    case warning
    case suggestion
}

public enum AutomationWorkflowDraftIssueCode: String, Codable, Equatable, Sendable {
    case unsupportedSchema
    case emptyWorkflowName
    case emptyTaskKey
    case duplicateTaskKey
    case unsupportedTaskType
    case missingMacroRef
    case ambiguousMacroRef
    case missingDelayDuration
    case invalidDuration
    case missingCondition
    case unsupportedConditionType
    case missingConditionText
    case missingNotificationTitle
    case missingDependencyEndpoint
    case selfDependency
    case unsupportedTrigger
    case duplicateDependency
    case cycleDetected
    case missingTimeoutBranch
    case invalidSchedule
    case invalidRetry
    case invalidJoinPolicy
    case invalidLoop
    case missingVisualReference
    case missingPixel
    case invalidThreshold
    case invalidPixelSampleRadius
    case invalidColor
    case unresolvedRegionRef
    case duplicateVisualAssetKey
    case invalidVisualAsset
    case missingVisualAsset
    case lossyWorkflowExport
    case unsupportedNotificationSeverity
    case internalWorkflowValidationFailed
}

public enum AutomationWorkflowDraftValidator {
    public static func validate(
        _ document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext()
    ) -> AutomationWorkflowDraftValidationResult {
        var validator = Validator(document: document, context: context)
        return validator.validate()
    }
}

private struct Validator {
    private static let supportedTaskTypes: Set<String> = [
        "macro",
        "condition",
        "delay",
        "notification",
        "manualApproval",
        "loop"
    ]
    private static let supportedConditionTypes: Set<String> = [
        "ocrText",
        "previousOutcome",
        "manualApproval",
        "externalSignal",
        "regionChanged",
        "imageAppeared",
        "imageDisappeared",
        "pixelMatched"
    ]
    private static let supportedTriggers: Set<String> = [
        "success",
        "failure",
        "timeout",
        "cancelled",
        "conditionMatched",
        "conditionNotMatched",
        "always"
    ]
    private static let supportedJoinPolicies: Set<String> = [
        AutomationJoinPolicy.all.rawValue,
        AutomationJoinPolicy.any.rawValue,
        AutomationJoinPolicy.firstMatched.rawValue
    ]
    private static let supportedLoopKinds: Set<String> = [
        AutomationWorkflowDraftLoopKind.fixedCount,
        AutomationWorkflowDraftLoopKind.repeatUntil
    ]
    private static let supportedLoopFailurePolicies: Set<String> = [
        AutomationWorkflowDraftLoopFailurePolicy.failRun,
        AutomationWorkflowDraftLoopFailurePolicy.continue,
        AutomationWorkflowDraftLoopFailurePolicy.requireManualApproval
    ]
    private static let visualConditionTypes: Set<String> = [
        "regionChanged",
        "imageAppeared",
        "imageDisappeared",
        "pixelMatched"
    ]

    var document: AutomationWorkflowDraftDocument
    var context: AutomationWorkflowDraftValidationContext
    var issues: [AutomationWorkflowDraftIssue] = []

    mutating func validate() -> AutomationWorkflowDraftValidationResult {
        validateSchema()
        validateWorkflowName()
        validateVisualAssets()
        let taskKeys = validateTasks()
        validateDependencies(taskKeys: taskKeys)
        return AutomationWorkflowDraftValidationResult(issues: issues)
    }

    private mutating func validateSchema() {
        guard document.schema == AutomationWorkflowDraftSchema.current else {
            add(
                .error,
                .unsupportedSchema,
                "Unsupported workflow draft schema '\(document.schema)'.",
                "$.schema"
            )
            return
        }
    }

    private mutating func validateWorkflowName() {
        guard !document.workflow.name.trimmedForDraftValidation.isEmpty else {
            add(.error, .emptyWorkflowName, "Workflow name is required.", "$.workflow.name")
            return
        }
    }

    private mutating func validateVisualAssets() {
        guard let visualAssets = document.visualAssets else {
            return
        }

        validateVisualAssetKeys(
            visualAssets.regions.map(\.key),
            path: "$.visualAssets.regions",
            noun: "visual region"
        )
        validateVisualAssetKeys(
            visualAssets.images.map(\.key),
            path: "$.visualAssets.images",
            noun: "visual image"
        )
        validateVisualAssetKeys(
            visualAssets.baselines.map(\.key),
            path: "$.visualAssets.baselines",
            noun: "visual baseline"
        )

        for (index, region) in visualAssets.regions.enumerated() {
            let key = region.key.trimmedForDraftValidation
            guard !key.isEmpty else {
                continue
            }
            if region.bounds.width <= 0 || region.bounds.height <= 0 {
                add(
                    .error,
                    .invalidVisualAsset,
                    "Visual region '\(key)' must have positive width and height.",
                    "$.visualAssets.regions[\(index)].bounds"
                )
            }
        }

        validateVisualImageAssetPaths(
            visualAssets.images,
            path: "$.visualAssets.images",
            noun: "visual image"
        )
        validateVisualImageAssetPaths(
            visualAssets.baselines,
            path: "$.visualAssets.baselines",
            noun: "visual baseline"
        )
    }

    private mutating func validateVisualAssetKeys(
        _ keys: [String],
        path: String,
        noun: String
    ) {
        var seen: Set<String> = []
        for (index, rawKey) in keys.enumerated() {
            let key = rawKey.trimmedForDraftValidation
            if key.isEmpty {
                add(.error, .invalidVisualAsset, "\(noun.capitalized) key is required.", "\(path)[\(index)].key")
            } else if !seen.insert(key).inserted {
                add(.error, .duplicateVisualAssetKey, "Duplicate \(noun) key '\(key)'.", "\(path)[\(index)].key")
            }
        }
    }

    private mutating func validateVisualImageAssetPaths(
        _ assets: [AutomationWorkflowDraftVisualImageAsset],
        path: String,
        noun: String
    ) {
        for (index, asset) in assets.enumerated() {
            if let pathValue = asset.path?.trimmedForDraftValidation,
               !pathValue.isEmpty,
               AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(pathValue) == nil {
                add(
                    .error,
                    .invalidVisualAsset,
                    "\(noun.capitalized) path must be a relative package path.",
                    "\(path)[\(index)].path"
                )
            }
            if let sourceArtifactPath = asset.sourceArtifactPath?.trimmedForDraftValidation,
               !sourceArtifactPath.isEmpty,
               AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(sourceArtifactPath) == nil {
                add(
                    .error,
                    .invalidVisualAsset,
                    "\(noun.capitalized) source artifact path must be a relative package path.",
                    "\(path)[\(index)].sourceArtifactPath"
                )
            }
        }
    }

    private mutating func validateTasks() -> Set<String> {
        var keys: Set<String> = []
        var duplicates: Set<String> = []

        for (index, task) in document.workflow.tasks.enumerated() {
            let path = "$.workflow.tasks[\(index)]"
            let key = task.key.trimmedForDraftValidation
            if key.isEmpty {
                add(.error, .emptyTaskKey, "Task key is required.", "\(path).key")
            } else if !keys.insert(key).inserted {
                duplicates.insert(key)
                add(.error, .duplicateTaskKey, "Task key '\(key)' is duplicated.", "\(path).key", taskKey: key)
            }

            validateTask(task, path: path, key: key)
        }

        return keys.subtracting(duplicates)
    }

    private mutating func validateTask(_ task: AutomationWorkflowDraftTask, path: String, key: String) {
        let type = task.type.trimmedForDraftValidation
        guard Self.supportedTaskTypes.contains(type) else {
            add(.error, .unsupportedTaskType, "Task type '\(task.type)' is not supported.", "\(path).type", taskKey: key)
            return
        }

        if let timeout = task.timeoutSeconds, timeout < 0 {
            add(.error, .invalidDuration, "Task timeout cannot be negative.", "\(path).timeoutSeconds", taskKey: key)
        }
        if let polling = task.pollingSeconds, polling < 0 {
            add(.error, .invalidDuration, "Task polling interval cannot be negative.", "\(path).pollingSeconds", taskKey: key)
        }
        if let threshold = task.condition?.threshold, !(0...1).contains(threshold) {
            add(.error, .invalidThreshold, "Condition threshold must be between 0 and 1.", "\(path).condition.threshold", taskKey: key)
        }
        if let retry = task.retry, let maxAttempts = retry.maxAttempts, maxAttempts < 1 {
            add(.error, .invalidRetry, "Retry maxAttempts must be at least 1.", "\(path).retry.maxAttempts", taskKey: key)
        }
        if let joinPolicy = task.joinPolicy?.trimmedForDraftValidation,
           !joinPolicy.isEmpty,
           !Self.supportedJoinPolicies.contains(joinPolicy) {
            add(
                .error,
                .invalidJoinPolicy,
                "Join policy '\(joinPolicy)' must be all, any, or firstMatched.",
                "\(path).joinPolicy",
                taskKey: key
            )
        }
        if let schedule = task.schedule {
            validateSchedule(schedule, path: "\(path).schedule", taskKey: key)
        }

        switch type {
        case "macro":
            validateMacroTask(task, path: path, key: key)
        case "condition":
            validateConditionTask(task, path: path, key: key)
        case "delay":
            validateDelayTask(task, path: path, key: key)
        case "notification":
            validateNotificationTask(task, path: path, key: key)
        case "manualApproval":
            break
        case "loop":
            validateLoopTask(task, path: path, key: key)
        default:
            break
        }
    }

    private mutating func validateMacroTask(_ task: AutomationWorkflowDraftTask, path: String, key: String) {
        guard let macroRef = task.macroRef, !macroRef.isEmpty else {
            add(.error, .missingMacroRef, "Macro task '\(key)' needs a macroRef.", "\(path).macroRef", taskKey: key)
            return
        }

        guard !context.macroCatalog.isEmpty else {
            return
        }

        if let id = macroRef.id {
            guard context.macroCatalog.contains(where: { $0.id == id }) else {
                add(.error, .missingMacroRef, "Macro ID '\(id.uuidString)' was not found.", "\(path).macroRef.id", taskKey: key)
                return
            }
        }

        if let name = macroRef.name?.trimmedForDraftValidation, !name.isEmpty {
            let matches = context.macroCatalog.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if matches.isEmpty, macroRef.id == nil {
                add(.error, .missingMacroRef, "Macro named '\(name)' was not found.", "\(path).macroRef.name", taskKey: key)
            } else if matches.count > 1, macroRef.id == nil {
                add(
                    .error,
                    .ambiguousMacroRef,
                    "Macro name '\(name)' matches multiple macros.",
                    "\(path).macroRef.name",
                    taskKey: key,
                    candidates: matches.map(\.id)
                )
            }
        }
    }

    private mutating func validateConditionTask(_ task: AutomationWorkflowDraftTask, path: String, key: String) {
        guard let condition = task.condition else {
            add(.error, .missingCondition, "Condition task '\(key)' needs a condition.", "\(path).condition", taskKey: key)
            return
        }

        validateConditionPayload(condition, conditionPath: "\(path).condition", taskKey: key)
    }

    private mutating func validateConditionPayload(
        _ condition: AutomationWorkflowDraftCondition,
        conditionPath: String,
        taskKey: String
    ) {
        let type = condition.type.trimmedForDraftValidation
        guard Self.supportedConditionTypes.contains(type) else {
            add(
                .error,
                .unsupportedConditionType,
                "Condition type '\(condition.type)' is not supported.",
                "\(conditionPath).type",
                taskKey: taskKey
            )
            return
        }

        if type == "ocrText", condition.text?.trimmedForDraftValidation.isEmpty ?? true {
            add(.error, .missingConditionText, "OCR text condition needs text.", "\(conditionPath).text", taskKey: taskKey)
        }

        validateVisualCondition(condition, type: type, conditionPath: conditionPath, taskKey: taskKey)
    }

    private mutating func validateVisualCondition(
        _ condition: AutomationWorkflowDraftCondition,
        type: String,
        conditionPath: String,
        taskKey: String
    ) {
        guard Self.visualConditionTypes.contains(type) else {
            return
        }

        if condition.regionRef?.trimmedForDraftValidation.isEmpty ?? true {
            add(
                .warning,
                .missingCondition,
                "Visual condition '\(type)' should name a regionRef so users can inspect what is being watched.",
                "\(conditionPath).regionRef",
                taskKey: taskKey
            )
        } else if let visualAssets = document.visualAssets,
                  visualAssets.region(for: condition.regionRef) == nil {
            add(
                .warning,
                .missingVisualAsset,
                "Visual condition '\(type)' references regionRef '\(condition.regionRef ?? "")', but visualAssets.regions does not define it.",
                "\(conditionPath).regionRef",
                taskKey: taskKey
            )
        }

        switch type {
        case "imageAppeared", "imageDisappeared":
            if condition.imageRef?.trimmedForDraftValidation.isEmpty ?? true {
                add(
                    .error,
                    .missingVisualReference,
                    "Visual condition '\(type)' needs imageRef.",
                    "\(conditionPath).imageRef",
                    taskKey: taskKey
                )
            } else if let visualAssets = document.visualAssets,
                      visualAssets.image(for: condition.imageRef) == nil {
                add(
                    .warning,
                    .missingVisualAsset,
                    "Visual condition '\(type)' references imageRef '\(condition.imageRef ?? "")', but visualAssets.images does not define it.",
                    "\(conditionPath).imageRef",
                    taskKey: taskKey
                )
            }

        case "pixelMatched":
            if condition.colorHex?.trimmedForDraftValidation.isEmpty ?? true {
                add(
                    .error,
                    .invalidColor,
                    "pixelMatched condition needs colorHex such as #FFCC00.",
                    "\(conditionPath).colorHex",
                    taskKey: taskKey
                )
            } else if let colorHex = condition.colorHex?.trimmedForDraftValidation,
                      !Self.isSupportedColorHex(colorHex) {
                add(
                    .error,
                    .invalidColor,
                    "Color '\(colorHex)' must be #RGB, #RRGGBB, or #RRGGBBAA.",
                    "\(conditionPath).colorHex",
                    taskKey: taskKey
                )
            }
            if condition.pixel == nil && (condition.regionRef?.trimmedForDraftValidation.isEmpty ?? true) {
                add(
                    .error,
                    .missingPixel,
                    "pixelMatched condition needs either pixel coordinates or regionRef.",
                    "\(conditionPath).pixel",
                    taskKey: taskKey
                )
            }
            if let pixelSampleRadius = condition.pixelSampleRadius,
               !(0...AutomationVisualCondition.maximumPixelSampleRadius).contains(pixelSampleRadius) {
                add(
                    .error,
                    .invalidPixelSampleRadius,
                    "pixelMatched condition pixelSampleRadius must be between 0 and \(AutomationVisualCondition.maximumPixelSampleRadius).",
                    "\(conditionPath).pixelSampleRadius",
                    taskKey: taskKey
                )
            }

        default:
            break
        }

        if let baselineRef = condition.baselineRef?.trimmedForDraftValidation,
           !baselineRef.isEmpty,
           let visualAssets = document.visualAssets,
           visualAssets.baseline(for: baselineRef) == nil {
            add(
                .warning,
                .missingVisualAsset,
                "Visual condition '\(type)' references baselineRef '\(baselineRef)', but visualAssets.baselines does not define it.",
                "\(conditionPath).baselineRef",
                taskKey: taskKey
            )
        }
    }

    private static func isSupportedColorHex(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#" else {
            return false
        }
        let digits = trimmed.dropFirst()
        guard [3, 6, 8].contains(digits.count) else {
            return false
        }
        return digits.allSatisfy { character in
            character.isHexDigit
        }
    }

    private mutating func validateDelayTask(_ task: AutomationWorkflowDraftTask, path: String, key: String) {
        guard let duration = task.delaySeconds else {
            add(.error, .missingDelayDuration, "Delay task '\(key)' needs delaySeconds.", "\(path).delaySeconds", taskKey: key)
            return
        }
        guard duration >= 0 else {
            add(.error, .invalidDuration, "Delay duration cannot be negative.", "\(path).delaySeconds", taskKey: key)
            return
        }
    }

    private mutating func validateNotificationTask(_ task: AutomationWorkflowDraftTask, path: String, key: String) {
        guard let title = task.notification?.title.trimmedForDraftValidation, !title.isEmpty else {
            add(.error, .missingNotificationTitle, "Notification task '\(key)' needs a title.", "\(path).notification.title", taskKey: key)
            return
        }
    }

    private mutating func validateLoopTask(_ task: AutomationWorkflowDraftTask, path: String, key: String) {
        guard let loop = task.loop else {
            add(.error, .invalidLoop, "Loop task '\(key)' needs a loop body.", "\(path).loop", taskKey: key)
            return
        }

        let kind = loop.normalizedKind
        guard Self.supportedLoopKinds.contains(kind) else {
            add(
                .error,
                .invalidLoop,
                "Loop task '\(key)' kind '\(kind)' is not supported.",
                "\(path).loop.kind",
                taskKey: key
            )
            return
        }

        switch kind {
        case AutomationWorkflowDraftLoopKind.fixedCount:
            validateFixedCountLoop(loop, path: path, key: key)
        case AutomationWorkflowDraftLoopKind.repeatUntil:
            validateRepeatUntilLoop(loop, path: path, key: key)
        default:
            break
        }
    }

    private mutating func validateFixedCountLoop(
        _ loop: AutomationWorkflowDraftLoop,
        path: String,
        key: String
    ) {
        guard loop.count >= 1, loop.count <= AutomationWorkflowDraftLoop.maxFixedCount else {
            add(
                .error,
                .invalidLoop,
                "Loop task '\(key)' count must be between 1 and \(AutomationWorkflowDraftLoop.maxFixedCount).",
                "\(path).loop.count",
                taskKey: key
            )
            return
        }
        validateLoopBody(loop, path: path, key: key)
    }

    private mutating func validateRepeatUntilLoop(
        _ loop: AutomationWorkflowDraftLoop,
        path: String,
        key: String
    ) {
        add(
            .error,
            .invalidLoop,
            "Repeat-until loop '\(key)' is draft-only until structured runtime loop support lands.",
            "\(path).loop.kind",
            taskKey: key
        )

        validateLoopBody(loop, path: path, key: key)

        if let until = loop.until {
            validateConditionPayload(until, conditionPath: "\(path).loop.until", taskKey: key)
        } else {
            add(
                .error,
                .missingCondition,
                "Repeat-until loop '\(key)' needs an until condition.",
                "\(path).loop.until",
                taskKey: key
            )
        }

        if let maxAttempts = loop.maxAttempts, maxAttempts < 1 {
            add(
                .error,
                .invalidLoop,
                "Repeat-until loop '\(key)' maxAttempts must be at least 1.",
                "\(path).loop.maxAttempts",
                taskKey: key
            )
        }
        if let timeout = loop.timeoutSeconds, timeout < 0 {
            add(
                .error,
                .invalidDuration,
                "Repeat-until loop '\(key)' timeout cannot be negative.",
                "\(path).loop.timeoutSeconds",
                taskKey: key
            )
        }
        if let polling = loop.pollingSeconds, polling < 0 {
            add(
                .error,
                .invalidDuration,
                "Repeat-until loop '\(key)' polling interval cannot be negative.",
                "\(path).loop.pollingSeconds",
                taskKey: key
            )
        }
        if let onFailure = loop.onFailure?.trimmedForDraftValidation,
           !onFailure.isEmpty,
           !Self.supportedLoopFailurePolicies.contains(onFailure) {
            add(
                .error,
                .invalidLoop,
                "Repeat-until loop '\(key)' onFailure must be failRun, continue, or requireManualApproval.",
                "\(path).loop.onFailure",
                taskKey: key
            )
        }
    }

    private mutating func validateLoopBody(
        _ loop: AutomationWorkflowDraftLoop,
        path: String,
        key: String
    ) {
        guard !loop.tasks.isEmpty else {
            add(.error, .invalidLoop, "Loop task '\(key)' needs at least one body task.", "\(path).loop.tasks", taskKey: key)
            return
        }

        var bodyKeys: Set<String> = []
        for (index, bodyTask) in loop.tasks.enumerated() {
            let bodyPath = "\(path).loop.tasks[\(index)]"
            let bodyKey = bodyTask.key.trimmedForDraftValidation
            if bodyKey.isEmpty {
                add(.error, .emptyTaskKey, "Loop body task key is required.", "\(bodyPath).key", taskKey: key)
            } else if !bodyKeys.insert(bodyKey).inserted {
                add(.error, .duplicateTaskKey, "Loop body task key '\(bodyKey)' is duplicated.", "\(bodyPath).key", taskKey: key)
            }

            if bodyTask.type.trimmedForDraftValidation == "loop" {
                add(.error, .invalidLoop, "Nested loop tasks are not supported in draft v1.", "\(bodyPath).type", taskKey: key)
                continue
            }

            validateTask(bodyTask, path: bodyPath, key: bodyKey)
        }
    }

    private mutating func validateSchedule(_ schedule: AutomationWorkflowDraftSchedule, path: String, taskKey: String) {
        switch schedule.type {
        case "manual":
            return
        case "once":
            if schedule.startAt == nil {
                add(.error, .invalidSchedule, "Once schedule needs startAt.", "\(path).startAt", taskKey: taskKey)
            }
        case "repeating":
            if schedule.startAt == nil {
                add(.error, .invalidSchedule, "Repeating schedule needs startAt.", "\(path).startAt", taskKey: taskKey)
            }
            if (schedule.every ?? 0) < 1 {
                add(.error, .invalidSchedule, "Repeating schedule needs every >= 1.", "\(path).every", taskKey: taskKey)
            }
            if !["minutes", "hours", "days", "weeks"].contains(schedule.unit ?? "") {
                add(.error, .invalidSchedule, "Repeating schedule unit must be minutes, hours, days, or weeks.", "\(path).unit", taskKey: taskKey)
            }
        default:
            add(.error, .invalidSchedule, "Schedule type '\(schedule.type)' is not supported.", "\(path).type", taskKey: taskKey)
        }
    }

    private mutating func validateDependencies(taskKeys: Set<String>) {
        var edges: Set<String> = []
        var adjacency: [String: [String]] = [:]

        for (index, dependency) in document.workflow.dependencies.enumerated() {
            let path = "$.workflow.dependencies[\(index)]"
            let dependencyKey = dependency.key ?? "\(dependency.from)->\(dependency.to):\(dependency.trigger)"
            let from = dependency.from.trimmedForDraftValidation
            let to = dependency.to.trimmedForDraftValidation

            if !taskKeys.contains(from) {
                add(.error, .missingDependencyEndpoint, "Dependency source '\(dependency.from)' does not match a task key.", "\(path).from", dependencyKey: dependencyKey)
            }
            if !taskKeys.contains(to) {
                add(.error, .missingDependencyEndpoint, "Dependency target '\(dependency.to)' does not match a task key.", "\(path).to", dependencyKey: dependencyKey)
            }
            if !from.isEmpty, from == to {
                add(.error, .selfDependency, "Dependency cannot point to the same task.", path, dependencyKey: dependencyKey)
            }

            let trigger = dependency.trigger.trimmedForDraftValidation
            if !Self.supportedTriggers.contains(trigger) {
                add(.error, .unsupportedTrigger, "Dependency trigger '\(dependency.trigger)' is not supported.", "\(path).trigger", dependencyKey: dependencyKey)
            }

            if let delay = dependency.delaySeconds, delay < 0 {
                add(.error, .invalidDuration, "Dependency delay cannot be negative.", "\(path).delaySeconds", dependencyKey: dependencyKey)
            }

            let edgeKey = "\(from)->\(to):\(trigger)"
            if !from.isEmpty, !to.isEmpty, !edges.insert(edgeKey).inserted {
                add(.warning, .duplicateDependency, "Dependency '\(edgeKey)' is duplicated.", path, dependencyKey: dependencyKey)
            }

            if taskKeys.contains(from), taskKeys.contains(to), from != to {
                adjacency[from, default: []].append(to)
            }
        }

        validateCycles(adjacency: adjacency)
        validateTimeoutBranches()
    }

    private mutating func validateCycles(adjacency: [String: [String]]) {
        var visiting: Set<String> = []
        var visited: Set<String> = []

        func visit(_ key: String) -> String? {
            if visiting.contains(key) {
                return key
            }
            if visited.contains(key) {
                return nil
            }

            visiting.insert(key)
            for next in adjacency[key] ?? [] {
                if let cycle = visit(next) {
                    return cycle
                }
            }
            visiting.remove(key)
            visited.insert(key)
            return nil
        }

        for key in adjacency.keys.sorted() {
            if let cycleKey = visit(key) {
                add(.error, .cycleDetected, "Workflow dependencies contain a cycle at task '\(cycleKey)'.", "$.workflow.dependencies", taskKey: cycleKey)
                return
            }
        }
    }

    private mutating func validateTimeoutBranches() {
        let outgoingTimeouts = Set(document.workflow.dependencies
            .filter { ($0.enabled ?? true) && $0.trigger.trimmedForDraftValidation == "timeout" }
            .map { $0.from.trimmedForDraftValidation })

        for (index, task) in document.workflow.tasks.enumerated()
            where task.type.trimmedForDraftValidation == "condition" {
            guard task.timeoutSeconds != nil else {
                continue
            }
            let key = task.key.trimmedForDraftValidation
            guard !outgoingTimeouts.contains(key) else {
                continue
            }
            add(
                .warning,
                .missingTimeoutBranch,
                "Condition task '\(key)' has a timeout but no timeout branch.",
                "$.workflow.tasks[\(index)]",
                taskKey: key
            )
        }
    }

    private mutating func add(
        _ severity: AutomationWorkflowDraftIssueSeverity,
        _ code: AutomationWorkflowDraftIssueCode,
        _ message: String,
        _ path: String,
        taskKey: String? = nil,
        dependencyKey: String? = nil,
        candidates: [UUID] = []
    ) {
        issues.append(AutomationWorkflowDraftIssue(
            severity: severity,
            code: code,
            message: message,
            path: path,
            taskKey: taskKey,
            dependencyKey: dependencyKey,
            candidates: candidates
        ))
    }
}

private extension String {
    var trimmedForDraftValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedForDraftLoopExpansion: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfEmptyForDraftLoopExpansion: String? {
        isEmpty ? nil : self
    }
}
