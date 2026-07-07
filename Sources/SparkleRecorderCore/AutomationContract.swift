import Foundation

public struct AutomationWorkflow: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var version: Int
    public var name: String
    public var tasks: [AutomationTask]
    public var dependencies: [AutomationDependency]
    public var visualAssets: AutomationWorkflowDraftVisualAssets?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        version: Int = 1,
        name: String,
        tasks: [AutomationTask] = [],
        dependencies: [AutomationDependency] = [],
        visualAssets: AutomationWorkflowDraftVisualAssets? = nil,
        createdAt: Date = Date.now,
        modifiedAt: Date = Date.now
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.tasks = tasks
        self.dependencies = dependencies
        self.visualAssets = visualAssets?.isEmpty == true ? nil : visualAssets
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public func task(id taskID: UUID) -> AutomationTask? {
        tasks.first { $0.id == taskID }
    }

    public func dependencies(from taskID: UUID) -> [AutomationDependency] {
        dependencies.filter { $0.isEnabled && $0.fromTaskID == taskID }
    }

    public func dependencies(to taskID: UUID) -> [AutomationDependency] {
        dependencies.filter { $0.isEnabled && $0.toTaskID == taskID }
    }

    public func validationIssues() -> [AutomationWorkflowValidationIssue] {
        var issues: [AutomationWorkflowValidationIssue] = []
        let taskIDs = tasks.map(\.id)
        let dependencyIDs = dependencies.map(\.id)
        let taskIDSet = Set(taskIDs)

        issues.append(contentsOf: duplicateValues(taskIDs).map { .duplicateTaskID($0) })
        issues.append(contentsOf: duplicateValues(dependencyIDs).map { .duplicateDependencyID($0) })

        for dependency in dependencies {
            if dependency.fromTaskID == dependency.toTaskID {
                issues.append(.selfDependency(dependencyID: dependency.id, taskID: dependency.fromTaskID))
            }
            if !taskIDSet.contains(dependency.fromTaskID) {
                issues.append(.missingDependencySource(dependencyID: dependency.id, taskID: dependency.fromTaskID))
            }
            if !taskIDSet.contains(dependency.toTaskID) {
                issues.append(.missingDependencyTarget(dependencyID: dependency.id, taskID: dependency.toTaskID))
            }
        }

        issues.append(contentsOf: cycleIssues(taskIDs: taskIDSet, dependencies: dependencies.filter(\.isEnabled)))
        return issues
    }
}

public enum AutomationWorkflowValidationIssue: Codable, Equatable, Sendable {
    case duplicateTaskID(UUID)
    case duplicateDependencyID(UUID)
    case missingDependencySource(dependencyID: UUID, taskID: UUID)
    case missingDependencyTarget(dependencyID: UUID, taskID: UUID)
    case selfDependency(dependencyID: UUID, taskID: UUID)
    case cycleDetected(taskID: UUID)
}

public enum AutomationJoinPolicy: String, Codable, Equatable, Sendable {
    case all
    case any
    case firstMatched
}

public struct AutomationTask: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: AutomationTaskKind
    public var schedule: AutomationSchedule?
    public var resourceRequirement: AutomationResourceRequirement
    public var timeout: TimeInterval?
    public var retryPolicy: AutomationRetryPolicy
    public var joinPolicy: AutomationJoinPolicy
    public var isEnabled: Bool
    public var graphPosition: AutomationGraphPoint?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AutomationTaskKind,
        schedule: AutomationSchedule? = nil,
        resourceRequirement: AutomationResourceRequirement = .foregroundInput,
        timeout: TimeInterval? = nil,
        retryPolicy: AutomationRetryPolicy = .none,
        joinPolicy: AutomationJoinPolicy = .all,
        isEnabled: Bool = true,
        graphPosition: AutomationGraphPoint? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.schedule = schedule
        self.resourceRequirement = resourceRequirement
        self.timeout = timeout.map { max(0, $0) }
        self.retryPolicy = retryPolicy
        self.joinPolicy = joinPolicy
        self.isEnabled = isEnabled
        self.graphPosition = graphPosition
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case schedule
        case resourceRequirement
        case timeout
        case retryPolicy
        case joinPolicy
        case isEnabled
        case graphPosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(AutomationTaskKind.self, forKey: .kind)
        self.schedule = try container.decodeIfPresent(AutomationSchedule.self, forKey: .schedule)
        self.resourceRequirement = try container.decodeIfPresent(
            AutomationResourceRequirement.self,
            forKey: .resourceRequirement
        ) ?? .foregroundInput
        self.timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout).map { max(0, $0) }
        self.retryPolicy = try container.decodeIfPresent(AutomationRetryPolicy.self, forKey: .retryPolicy) ?? .none
        self.joinPolicy = try container.decodeIfPresent(AutomationJoinPolicy.self, forKey: .joinPolicy) ?? .all
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.graphPosition = try container.decodeIfPresent(AutomationGraphPoint.self, forKey: .graphPosition)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(schedule, forKey: .schedule)
        try container.encode(resourceRequirement, forKey: .resourceRequirement)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encode(retryPolicy, forKey: .retryPolicy)
        try container.encode(joinPolicy, forKey: .joinPolicy)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(graphPosition, forKey: .graphPosition)
    }

    public func makeRun(
        workflowID: UUID,
        runID: UUID = UUID(),
        executionID: UUID? = nil,
        scheduledStartTime: Date? = nil,
        earliestStartTime: Date? = nil,
        createdAt: Date = Date.now,
        attempt: Int = 1,
        upstreamRunIDs: [UUID] = []
    ) -> AutomationTaskRun {
        let scheduledStart = scheduledStartTime ?? schedule?.initialScheduledStart
        return AutomationTaskRun(
            id: runID,
            executionID: executionID ?? runID,
            workflowID: workflowID,
            taskID: id,
            macroID: kind.macroID,
            scheduledStartTime: scheduledStart,
            earliestStartTime: earliestStartTime ?? scheduledStart,
            actualStartTime: nil,
            completedAt: nil,
            status: .planned,
            outcome: nil,
            evidenceID: nil,
            leaseID: nil,
            createdAt: createdAt,
            attempt: max(1, attempt),
            upstreamRunIDs: upstreamRunIDs
        )
    }
}

public enum AutomationTaskKind: Codable, Equatable, Sendable {
    case macro(macroID: UUID)
    case condition(AutomationConditionSpec)
    case delay(TimeInterval)
    case notification(AutomationNotificationSpec)

    public var macroID: UUID? {
        if case .macro(let macroID) = self {
            return macroID
        }
        return nil
    }
}

public enum AutomationSchedule: Codable, Equatable, Sendable {
    case manual
    case once(Date)
    case repeating(AutomationRepeatRule)

    public var initialScheduledStart: Date? {
        switch self {
        case .manual:
            return nil
        case .once(let date):
            return date
        case .repeating(let rule):
            return rule.anchor
        }
    }
}

public struct AutomationRepeatRule: Codable, Equatable, Sendable {
    public var anchor: Date
    public var interval: AutomationRepeatInterval
    public var end: AutomationScheduleEnd
    public var timeZoneIdentifier: String

    public init(
        anchor: Date,
        interval: AutomationRepeatInterval,
        end: AutomationScheduleEnd = .never,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.anchor = anchor
        self.interval = interval
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public enum AutomationRepeatInterval: Codable, Equatable, Sendable {
    case minutes(Int)
    case hours(Int)
    case days(Int)
    case weeks(Int)
}

public enum AutomationScheduleEnd: Codable, Equatable, Sendable {
    case never
    case afterOccurrences(Int)
    case at(Date)
}

public struct AutomationRetryPolicy: Codable, Equatable, Sendable {
    public static let none = AutomationRetryPolicy(maxAttempts: 1, backoff: .none)

    public var maxAttempts: Int
    public var backoff: AutomationRetryBackoff

    public init(maxAttempts: Int, backoff: AutomationRetryBackoff = .none) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoff = backoff
    }
}

public enum AutomationRetryBackoff: Codable, Equatable, Sendable {
    case none
    case fixed(TimeInterval)
    case exponential(initial: TimeInterval, multiplier: Double, maximum: TimeInterval)
}

public struct AutomationResourceRequirement: Codable, Equatable, Sendable {
    public static let none = AutomationResourceRequirement(resources: [])
    public static let foregroundInput = AutomationResourceRequirement(resources: [.foregroundInput])
    public static let backgroundReadOnly = AutomationResourceRequirement(resources: [.screenCapture])

    public var resources: Set<AutomationResource>
    public var priority: AutomationResourcePriority
    public var leaseTimeout: TimeInterval?
    public var maxWaitDuration: TimeInterval?

    public init(
        resources: Set<AutomationResource>,
        priority: AutomationResourcePriority = .normal,
        leaseTimeout: TimeInterval? = nil,
        maxWaitDuration: TimeInterval? = nil
    ) {
        self.resources = resources
        self.priority = priority
        self.leaseTimeout = leaseTimeout.map { max(0, $0) }
        self.maxWaitDuration = maxWaitDuration.map { max(0, $0) }
    }

    public var requiresForegroundInput: Bool {
        resources.contains(.foregroundInput)
    }
}

public enum AutomationResource: String, Codable, Equatable, Hashable, Sendable {
    case foregroundInput
    case screenCapture
    case accessibility
    case network
}

public enum AutomationResourcePriority: String, Codable, Equatable, Sendable {
    case low
    case normal
    case high
}

public struct AutomationResourceLease: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var runID: UUID
    public var resource: AutomationResource
    public var acquiredAt: Date
    public var expiresAt: Date?

    public init(
        id: UUID = UUID(),
        runID: UUID,
        resource: AutomationResource,
        acquiredAt: Date = Date.now,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.runID = runID
        self.resource = resource
        self.acquiredAt = acquiredAt
        self.expiresAt = expiresAt
    }
}

public struct AutomationConditionSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: AutomationConditionKind
    public var timeout: TimeInterval?
    public var pollingInterval: TimeInterval

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AutomationConditionKind,
        timeout: TimeInterval? = nil,
        pollingInterval: TimeInterval = 0.25
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.timeout = timeout.map { max(0, $0) }
        self.pollingInterval = max(0.05, pollingInterval)
    }
}

public enum AutomationConditionKind: Codable, Equatable, Sendable {
    case ocrText(AutomationOCRCondition)
    case visual(AutomationVisualCondition)
    case previousOutcome(AutomationOutcomePredicate)
    case externalSignal(String)
    case manualApproval
}

public enum AutomationOCRSearchRegionSpace: String, CaseIterable, Codable, Equatable, Sendable {
    case automatic
    case displayAbsolute
    case displayNormalized
    case windowLocal
    case windowNormalized
    case contentLocal
    case contentNormalized
}

public struct AutomationOCRSearchRegionContext: Equatable, Sendable {
    public var displayBounds: RectValue
    public var windowFrame: RectValue?
    public var contentFrame: RectValue?

    public init(
        displayBounds: RectValue,
        windowFrame: RectValue? = nil,
        contentFrame: RectValue? = nil
    ) {
        self.displayBounds = displayBounds
        self.windowFrame = windowFrame
        self.contentFrame = contentFrame
    }
}

public enum AutomationOCRSearchRegionResolution: Equatable, Sendable {
    case unrestricted
    case resolved(RectValue)
    case unavailable
}

public struct AutomationOCRSearchRegionSelection: Equatable, Sendable {
    public var displayBounds: RectValue
    public var selectedDisplayRegion: RectValue
    public var windowFrame: RectValue?
    public var contentFrame: RectValue?

    public init(
        displayBounds: RectValue,
        selectedDisplayRegion: RectValue,
        windowFrame: RectValue? = nil,
        contentFrame: RectValue? = nil
    ) {
        self.displayBounds = displayBounds
        self.selectedDisplayRegion = selectedDisplayRegion
        self.windowFrame = windowFrame
        self.contentFrame = contentFrame
    }

    public func searchRegion(
        in space: AutomationOCRSearchRegionSpace
    ) -> RectValue? {
        guard let displayRegion = selectedDisplayRegion.intersection(with: displayBounds) else {
            return nil
        }

        switch space {
        case .automatic, .displayAbsolute:
            return displayRegion
        case .displayNormalized:
            return displayRegion.normalized(in: displayBounds)
        case .windowLocal:
            return region(in: windowFrame, normalized: false)
        case .windowNormalized:
            return region(in: windowFrame, normalized: true)
        case .contentLocal:
            return region(in: contentFrame, normalized: false)
        case .contentNormalized:
            return region(in: contentFrame, normalized: true)
        }
    }

    private func region(in frame: RectValue?, normalized: Bool) -> RectValue? {
        guard let frame,
              let clipped = selectedDisplayRegion.intersection(with: frame) else {
            return nil
        }

        return normalized ? clipped.normalized(in: frame) : clipped.local(in: frame)
    }
}

public struct AutomationOCRCondition: Codable, Equatable, Sendable {
    public var text: String
    public var matchMode: TextMatchMode
    public var searchRegion: RectValue?
    public var searchRegionSpace: AutomationOCRSearchRegionSpace
    public var requireVisible: Bool

    public init(
        text: String,
        matchMode: TextMatchMode = .contains,
        searchRegion: RectValue? = nil,
        searchRegionSpace: AutomationOCRSearchRegionSpace = .automatic,
        requireVisible: Bool = true
    ) {
        self.text = text
        self.matchMode = matchMode
        self.searchRegion = searchRegion
        self.searchRegionSpace = searchRegionSpace
        self.requireVisible = requireVisible
    }

    public func searchRegionResolution(
        in context: AutomationOCRSearchRegionContext
    ) -> AutomationOCRSearchRegionResolution {
        guard let searchRegion, searchRegion.width > 0, searchRegion.height > 0 else {
            return .unrestricted
        }

        let resolved: RectValue?
        switch searchRegionSpace {
        case .automatic:
            if searchRegion.x >= 0,
               searchRegion.y >= 0,
               searchRegion.maxX <= 1,
               searchRegion.maxY <= 1 {
                resolved = searchRegion.denormalized(in: context.displayBounds)
            } else {
                resolved = searchRegion
            }

        case .displayAbsolute:
            resolved = searchRegion

        case .displayNormalized:
            resolved = searchRegion.denormalized(in: context.displayBounds)

        case .windowLocal:
            resolved = context.windowFrame.map { searchRegion.offset(by: $0) }

        case .windowNormalized:
            resolved = context.windowFrame.map { searchRegion.denormalized(in: $0) }

        case .contentLocal:
            resolved = context.contentFrame.map { searchRegion.offset(by: $0) }

        case .contentNormalized:
            resolved = context.contentFrame.map { searchRegion.denormalized(in: $0) }
        }

        guard let resolved else {
            return .unavailable
        }

        guard let clamped = resolved.intersection(with: context.displayBounds) else {
            return .unavailable
        }

        return .resolved(clamped)
    }

    public func updatingTextMatchAndSpace(
        text: String,
        matchMode: TextMatchMode,
        searchRegionSpace: AutomationOCRSearchRegionSpace,
        requireVisible: Bool
    ) -> AutomationOCRCondition {
        updatingTextMatchRegionAndSpace(
            text: text,
            matchMode: matchMode,
            searchRegion: searchRegion,
            searchRegionSpace: searchRegionSpace,
            requireVisible: requireVisible
        )
    }

    public func updatingTextMatchRegionAndSpace(
        text: String,
        matchMode: TextMatchMode,
        searchRegion: RectValue?,
        searchRegionSpace: AutomationOCRSearchRegionSpace,
        requireVisible: Bool
    ) -> AutomationOCRCondition {
        AutomationOCRCondition(
            text: text,
            matchMode: matchMode,
            searchRegion: searchRegion,
            searchRegionSpace: searchRegionSpace,
            requireVisible: requireVisible
        )
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case matchMode
        case searchRegion
        case searchRegionSpace
        case requireVisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.matchMode = try container.decodeIfPresent(TextMatchMode.self, forKey: .matchMode) ?? .contains
        self.searchRegion = try container.decodeIfPresent(RectValue.self, forKey: .searchRegion)
        self.searchRegionSpace = try container.decodeIfPresent(
            AutomationOCRSearchRegionSpace.self,
            forKey: .searchRegionSpace
        ) ?? .automatic
        self.requireVisible = try container.decodeIfPresent(Bool.self, forKey: .requireVisible) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(matchMode, forKey: .matchMode)
        try container.encodeIfPresent(searchRegion, forKey: .searchRegion)
        try container.encode(searchRegionSpace, forKey: .searchRegionSpace)
        try container.encode(requireVisible, forKey: .requireVisible)
    }
}

public enum AutomationVisualConditionType: String, Codable, Equatable, Sendable {
    case regionChanged
    case imageAppeared
    case imageDisappeared
    case pixelMatched
}

public struct AutomationVisualCondition: Codable, Equatable, Sendable {
    public static let defaultPixelSampleRadius = 1
    public static let maximumPixelSampleRadius = 8

    public var type: AutomationVisualConditionType
    public var regionRef: String?
    public var searchRegion: RectValue?
    public var searchRegionSpace: AutomationOCRSearchRegionSpace
    public var imageRef: String?
    public var baselineRef: String?
    public var pixel: AutomationGraphPoint?
    public var targetColorHex: String?
    public var pixelSampleRadius: Int?
    public var threshold: Double?
    public var requireVisible: Bool

    public init(
        type: AutomationVisualConditionType,
        regionRef: String? = nil,
        searchRegion: RectValue? = nil,
        searchRegionSpace: AutomationOCRSearchRegionSpace = .automatic,
        imageRef: String? = nil,
        baselineRef: String? = nil,
        pixel: AutomationGraphPoint? = nil,
        targetColorHex: String? = nil,
        pixelSampleRadius: Int? = nil,
        threshold: Double? = nil,
        requireVisible: Bool = true
    ) {
        self.type = type
        self.regionRef = regionRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForAutomationCondition
        self.searchRegion = searchRegion
        self.searchRegionSpace = searchRegionSpace
        self.imageRef = imageRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForAutomationCondition
        self.baselineRef = baselineRef?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForAutomationCondition
        self.pixel = pixel
        self.targetColorHex = targetColorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForAutomationCondition
        self.pixelSampleRadius = pixelSampleRadius.map(Self.clampedPixelSampleRadius)
        self.threshold = threshold.map { min(max($0, 0), 1) }
        self.requireVisible = requireVisible
    }

    public static func clampedPixelSampleRadius(_ radius: Int) -> Int {
        min(max(radius, 0), maximumPixelSampleRadius)
    }

    public func searchRegionResolution(
        in context: AutomationOCRSearchRegionContext
    ) -> AutomationOCRSearchRegionResolution {
        AutomationOCRCondition(
            text: "",
            searchRegion: searchRegion,
            searchRegionSpace: searchRegionSpace
        )
        .searchRegionResolution(in: context)
    }
}

private extension String {
    var nilIfEmptyForAutomationCondition: String? {
        isEmpty ? nil : self
    }

    var nilIfEmptyForDynamicDependencyDelay: String? {
        isEmpty ? nil : self
    }
}

private extension RectValue {
    var maxX: CGFloat {
        x + width
    }

    var maxY: CGFloat {
        y + height
    }

    func offset(by frame: RectValue) -> RectValue {
        RectValue(
            x: frame.x + x,
            y: frame.y + y,
            width: width,
            height: height
        )
    }

    func denormalized(in frame: RectValue) -> RectValue {
        RectValue(
            x: frame.x + x * frame.width,
            y: frame.y + y * frame.height,
            width: width * frame.width,
            height: height * frame.height
        )
    }

    func intersection(with frame: RectValue) -> RectValue? {
        let left = max(x, frame.x)
        let top = max(y, frame.y)
        let right = min(maxX, frame.maxX)
        let bottom = min(maxY, frame.maxY)
        guard right > left, bottom > top else {
            return nil
        }
        return RectValue(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }

    func local(in frame: RectValue) -> RectValue {
        RectValue(
            x: x - frame.x,
            y: y - frame.y,
            width: width,
            height: height
        )
    }

    func normalized(in frame: RectValue) -> RectValue {
        RectValue(
            x: frame.width > 0 ? (x - frame.x) / frame.width : 0,
            y: frame.height > 0 ? (y - frame.y) / frame.height : 0,
            width: frame.width > 0 ? width / frame.width : 0,
            height: frame.height > 0 ? height / frame.height : 0
        )
    }
}

public enum AutomationOutcomePredicate: String, Codable, Equatable, Sendable {
    case success
    case failure
    case timeout
    case cancelled
    case conditionMatched
    case conditionNotMatched
    case anyTerminal

    public func matches(_ outcome: AutomationOutcome) -> Bool {
        switch (self, outcome) {
        case (.anyTerminal, _):
            return true
        case (.success, .succeeded):
            return true
        case (.failure, .failed), (.failure, .resourceConflict), (.failure, .permissionDenied), (.failure, .missingMacro), (.failure, .rejected):
            return true
        case (.timeout, .timedOut):
            return true
        case (.cancelled, .cancelled):
            return true
        case (.conditionMatched, .conditionMatched):
            return true
        case (.conditionNotMatched, .conditionNotMatched):
            return true
        default:
            return false
        }
    }
}

public struct AutomationNotificationSpec: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var severity: AutomationNotificationSeverity

    public init(
        title: String,
        body: String,
        severity: AutomationNotificationSeverity = .info
    ) {
        self.title = title
        self.body = body
        self.severity = severity
    }
}

public enum AutomationNotificationSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public enum AutomationDependencyDynamicDelaySource: String, Codable, Equatable, Sendable {
    case conditionEvidenceDuration
}

public struct AutomationDependencyDynamicDelay: Codable, Equatable, Sendable {
    public var source: AutomationDependencyDynamicDelaySource
    public var sourceFieldID: String?
    public var fallbackDelay: TimeInterval?
    public var minimumDelay: TimeInterval?
    public var maximumDelay: TimeInterval?

    public init(
        source: AutomationDependencyDynamicDelaySource = .conditionEvidenceDuration,
        sourceFieldID: String? = nil,
        fallbackDelay: TimeInterval? = nil,
        minimumDelay: TimeInterval? = nil,
        maximumDelay: TimeInterval? = nil
    ) {
        self.source = source
        self.sourceFieldID = sourceFieldID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForDynamicDependencyDelay
        self.fallbackDelay = fallbackDelay.map { max(0, $0) }
        self.minimumDelay = minimumDelay.map { max(0, $0) }
        self.maximumDelay = maximumDelay.map { max(0, $0) }
    }

    public func normalizedDelay(_ delay: TimeInterval) -> (delay: TimeInterval, wasClamped: Bool) {
        var normalized = max(0, delay)
        var wasClamped = false
        if let minimumDelay, normalized < minimumDelay {
            normalized = minimumDelay
            wasClamped = true
        }
        if let maximumDelay, normalized > maximumDelay {
            normalized = maximumDelay
            wasClamped = true
        }
        return (normalized, wasClamped)
    }
}

public enum AutomationDependencyDelayResolutionSource: String, Codable, Equatable, Sendable {
    case fixed
    case recognizedDuration
    case fallback
}

public struct AutomationDependencyDelayResolution: Codable, Equatable, Sendable {
    public var delay: TimeInterval
    public var source: AutomationDependencyDelayResolutionSource
    public var observedText: String?
    public var reason: String?
    public var wasClamped: Bool

    public init(
        delay: TimeInterval,
        source: AutomationDependencyDelayResolutionSource,
        observedText: String? = nil,
        reason: String? = nil,
        wasClamped: Bool = false
    ) {
        self.delay = max(0, delay)
        self.source = source
        self.observedText = observedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForDynamicDependencyDelay
        self.reason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForDynamicDependencyDelay
        self.wasClamped = wasClamped
    }
}

public struct AutomationDependency: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var fromTaskID: UUID
    public var toTaskID: UUID
    public var trigger: AutomationDependencyTrigger
    public var delay: TimeInterval
    public var dynamicDelay: AutomationDependencyDynamicDelay?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        fromTaskID: UUID,
        toTaskID: UUID,
        trigger: AutomationDependencyTrigger,
        delay: TimeInterval = 0,
        dynamicDelay: AutomationDependencyDynamicDelay? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.fromTaskID = fromTaskID
        self.toTaskID = toTaskID
        self.trigger = trigger
        self.delay = max(0, delay)
        self.dynamicDelay = dynamicDelay
        self.isEnabled = isEnabled
    }

    public func fires(for outcome: AutomationOutcome) -> Bool {
        trigger.matches(outcome)
    }
}

public enum AutomationDependencyTrigger: Codable, Equatable, Sendable {
    case onSuccess
    case onFailure
    case onTimeout
    case onCancelled
    case onConditionMatched
    case onConditionNotMatched
    case onOutcome(AutomationOutcomePredicate)
    case always

    public func matches(_ outcome: AutomationOutcome) -> Bool {
        switch self {
        case .always:
            return true
        case .onSuccess:
            return AutomationOutcomePredicate.success.matches(outcome)
        case .onFailure:
            return AutomationOutcomePredicate.failure.matches(outcome)
        case .onTimeout:
            return AutomationOutcomePredicate.timeout.matches(outcome)
        case .onCancelled:
            return AutomationOutcomePredicate.cancelled.matches(outcome)
        case .onConditionMatched:
            return AutomationOutcomePredicate.conditionMatched.matches(outcome)
        case .onConditionNotMatched:
            return AutomationOutcomePredicate.conditionNotMatched.matches(outcome)
        case .onOutcome(let predicate):
            return predicate.matches(outcome)
        }
    }
}

public enum AutomationOutcome: Codable, Equatable, Sendable {
    case succeeded(report: RunReport?)
    case failed(report: RunReport?)
    case cancelled(reason: String?)
    case timedOut(deadline: Date?)
    case resourceConflict(resource: AutomationResource?)
    case permissionDenied(permission: AutomationPermission, message: String)
    case conditionMatched
    case conditionNotMatched
    case missingMacro(macroID: UUID)
    case rejected(reason: String)

    public var isTerminal: Bool { true }
}

public enum AutomationPermission: String, Codable, Equatable, Sendable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case automation
    case postEvents
}

public enum AutomationTaskRunStatus: Codable, Equatable, Sendable {
    case planned
    case waitingForDependencies
    case waitingForResource
    case queued
    case running
    case completed
}

public enum AutomationBranchDecisionStatus: String, Codable, Equatable, Hashable, Sendable {
    case waiting
    case triggered
    case skipped
    case disabled

    public var label: String {
        switch self {
        case .waiting:
            return NSLocalizedString("Waiting", comment: "")
        case .triggered:
            return NSLocalizedString("Triggered", comment: "")
        case .skipped:
            return NSLocalizedString("Skipped", comment: "")
        case .disabled:
            return NSLocalizedString("Disabled", comment: "")
        }
    }
}

public struct AutomationBranchDecisionEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { dependencyID }

    public var sourceRunID: UUID
    public var sourceTaskID: UUID
    public var dependencyID: UUID
    public var trigger: AutomationDependencyTrigger
    public var status: AutomationBranchDecisionStatus
    public var targetTaskID: UUID
    public var targetRunID: UUID?
    public var executionID: UUID
    public var sourceOutcome: AutomationOutcome
    public var decidedAt: Date
    public var delay: TimeInterval
    public var targetJoinPolicy: AutomationJoinPolicy?
    public var reason: String

    public init(
        sourceRunID: UUID,
        sourceTaskID: UUID,
        dependencyID: UUID,
        trigger: AutomationDependencyTrigger,
        status: AutomationBranchDecisionStatus,
        targetTaskID: UUID,
        targetRunID: UUID? = nil,
        executionID: UUID,
        sourceOutcome: AutomationOutcome,
        decidedAt: Date,
        delay: TimeInterval = 0,
        targetJoinPolicy: AutomationJoinPolicy? = nil,
        reason: String
    ) {
        self.sourceRunID = sourceRunID
        self.sourceTaskID = sourceTaskID
        self.dependencyID = dependencyID
        self.trigger = trigger
        self.status = status
        self.targetTaskID = targetTaskID
        self.targetRunID = targetRunID
        self.executionID = executionID
        self.sourceOutcome = sourceOutcome
        self.decidedAt = decidedAt
        self.delay = max(0, delay)
        self.targetJoinPolicy = targetJoinPolicy
        self.reason = reason
    }
}

public enum AutomationConditionEvidenceKind: String, Codable, Equatable, Sendable {
    case ocrText
    case regionChanged
    case imageAppeared
    case imageDisappeared
    case pixelMatched
    case previousOutcome
    case externalSignal
    case manualApproval
}

public struct AutomationConditionDiagnosticField: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var value: String

    public init(id: String, title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

public enum AutomationConditionDiagnosticArtifactKind: String, Codable, Equatable, Sendable {
    case displaySampleImage
    case regionSampleImage
    case templateImage
    case baselineImage
}

public struct AutomationConditionDiagnosticArtifact: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var kind: AutomationConditionDiagnosticArtifactKind
    public var relativePath: String
    public var contentType: String
    public var pixelBounds: RectValue?
    public var createdAt: Date?

    public init(
        id: String,
        title: String,
        kind: AutomationConditionDiagnosticArtifactKind,
        relativePath: String,
        contentType: String = "image/png",
        pixelBounds: RectValue? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.relativePath = relativePath
        self.contentType = contentType
        self.pixelBounds = pixelBounds
        self.createdAt = createdAt
    }

    public var normalizedRelativePath: String? {
        Self.normalizedRelativePath(relativePath)
    }

    public func resolvedURL(relativeTo baseDirectory: URL) -> URL? {
        guard let normalizedRelativePath else {
            return nil
        }

        var url = baseDirectory.standardizedFileURL
        for component in normalizedRelativePath.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: false)
        }
        return url.standardizedFileURL
    }

    public static func normalizedRelativePath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
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

public struct AutomationConditionEvaluationEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { runID }

    public var runID: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var conditionID: UUID
    public var kind: AutomationConditionEvidenceKind
    public var outcome: AutomationOutcome
    public var evaluatedAt: Date
    public var firstSampleAt: Date?
    public var lastSampleAt: Date?
    public var sampleCount: Int
    public var displayBounds: RectValue?
    public var resolvedSearchRegion: RectValue?
    public var searchRegionSpace: AutomationOCRSearchRegionSpace?
    public var targetDescription: String
    public var observedSummary: String
    public var score: Double?
    public var threshold: Double?
    public var fields: [AutomationConditionDiagnosticField]
    public var artifacts: [AutomationConditionDiagnosticArtifact]

    public init(
        runID: UUID,
        workflowID: UUID,
        taskID: UUID,
        conditionID: UUID,
        kind: AutomationConditionEvidenceKind,
        outcome: AutomationOutcome,
        evaluatedAt: Date,
        firstSampleAt: Date? = nil,
        lastSampleAt: Date? = nil,
        sampleCount: Int = 0,
        displayBounds: RectValue? = nil,
        resolvedSearchRegion: RectValue? = nil,
        searchRegionSpace: AutomationOCRSearchRegionSpace? = nil,
        targetDescription: String,
        observedSummary: String,
        score: Double? = nil,
        threshold: Double? = nil,
        fields: [AutomationConditionDiagnosticField] = [],
        artifacts: [AutomationConditionDiagnosticArtifact] = []
    ) {
        self.runID = runID
        self.workflowID = workflowID
        self.taskID = taskID
        self.conditionID = conditionID
        self.kind = kind
        self.outcome = outcome
        self.evaluatedAt = evaluatedAt
        self.firstSampleAt = firstSampleAt
        self.lastSampleAt = lastSampleAt
        self.sampleCount = max(0, sampleCount)
        self.displayBounds = displayBounds
        self.resolvedSearchRegion = resolvedSearchRegion
        self.searchRegionSpace = searchRegionSpace
        self.targetDescription = targetDescription
        self.observedSummary = observedSummary
        self.score = score.map { min(max($0, 0), 1) }
        self.threshold = threshold.map { min(max($0, 0), 1) }
        self.fields = fields
        self.artifacts = artifacts
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case workflowID
        case taskID
        case conditionID
        case kind
        case outcome
        case evaluatedAt
        case firstSampleAt
        case lastSampleAt
        case sampleCount
        case displayBounds
        case resolvedSearchRegion
        case searchRegionSpace
        case targetDescription
        case observedSummary
        case score
        case threshold
        case fields
        case artifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            runID: try container.decode(UUID.self, forKey: .runID),
            workflowID: try container.decode(UUID.self, forKey: .workflowID),
            taskID: try container.decode(UUID.self, forKey: .taskID),
            conditionID: try container.decode(UUID.self, forKey: .conditionID),
            kind: try container.decode(AutomationConditionEvidenceKind.self, forKey: .kind),
            outcome: try container.decode(AutomationOutcome.self, forKey: .outcome),
            evaluatedAt: try container.decode(Date.self, forKey: .evaluatedAt),
            firstSampleAt: try container.decodeIfPresent(Date.self, forKey: .firstSampleAt),
            lastSampleAt: try container.decodeIfPresent(Date.self, forKey: .lastSampleAt),
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0,
            displayBounds: try container.decodeIfPresent(RectValue.self, forKey: .displayBounds),
            resolvedSearchRegion: try container.decodeIfPresent(RectValue.self, forKey: .resolvedSearchRegion),
            searchRegionSpace: try container.decodeIfPresent(
                AutomationOCRSearchRegionSpace.self,
                forKey: .searchRegionSpace
            ),
            targetDescription: try container.decode(String.self, forKey: .targetDescription),
            observedSummary: try container.decode(String.self, forKey: .observedSummary),
            score: try container.decodeIfPresent(Double.self, forKey: .score),
            threshold: try container.decodeIfPresent(Double.self, forKey: .threshold),
            fields: try container.decodeIfPresent(
                [AutomationConditionDiagnosticField].self,
                forKey: .fields
            ) ?? [],
            artifacts: try container.decodeIfPresent(
                [AutomationConditionDiagnosticArtifact].self,
                forKey: .artifacts
            ) ?? []
        )
    }
}

public struct AutomationConditionEvaluationResult: Codable, Equatable, Sendable {
    public var outcome: AutomationOutcome
    public var evidence: AutomationConditionEvaluationEvidence?

    public init(
        outcome: AutomationOutcome,
        evidence: AutomationConditionEvaluationEvidence? = nil
    ) {
        self.outcome = outcome
        self.evidence = evidence
    }
}

public enum AutomationConditionEvidenceDurationParser {
    public struct ParsedDuration: Equatable, Sendable {
        public var duration: TimeInterval
        public var sourceText: String

        public init(duration: TimeInterval, sourceText: String) {
            self.duration = max(0, duration)
            self.sourceText = sourceText
        }
    }

    public static func duration(
        in evidence: AutomationConditionEvaluationEvidence,
        sourceFieldID: String? = nil
    ) -> ParsedDuration? {
        let candidates: [String]
        if let sourceFieldID = sourceFieldID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForDynamicDependencyDelay {
            candidates = evidence.fields
                .filter { $0.id == sourceFieldID }
                .map(\.value)
        } else {
            candidates = [evidence.observedSummary] + evidence.fields.map(\.value)
        }

        var seen = Set<String>()
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            if let parsed = duration(in: trimmed) {
                return parsed
            }
        }
        return nil
    }

    public static func duration(in text: String) -> ParsedDuration? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
        let segments = durationSegments(in: normalized)
        for segment in segments {
            if let parsed = unitDuration(in: segment) {
                return parsed
            }
            if let parsed = colonDuration(in: segment) {
                return parsed
            }
        }
        return nil
    }

    private static func durationSegments(in text: String) -> [String] {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = text
            .split(whereSeparator: { character in
                character == "\n" || character == "\r" || character == "|" || character == ";"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ([whole] + pieces).filter { !$0.isEmpty }
    }

    private static func unitDuration(in text: String) -> ParsedDuration? {
        let days = firstNumericValue(
            in: text,
            pattern: #"(\d+(?:[\.,]\d+)?)\s*(?:d|day|days|天|日)"#
        ) ?? 0
        let hours = firstNumericValue(
            in: text,
            pattern: #"(\d+(?:[\.,]\d+)?)\s*(?:h|hr|hrs|hour|hours|小时|小時|时|時)"#
        ) ?? 0
        let minutes = firstNumericValue(
            in: text,
            pattern: #"(\d+(?:[\.,]\d+)?)\s*(?:m|min|mins|minute|minutes|分钟|分鐘|分)"#
        ) ?? 0
        let seconds = firstNumericValue(
            in: text,
            pattern: #"(\d+(?:[\.,]\d+)?)\s*(?:s|sec|secs|second|seconds|秒)"#
        ) ?? 0
        let total = days * 86_400 + hours * 3_600 + minutes * 60 + seconds
        guard total > 0 else {
            return nil
        }
        return ParsedDuration(duration: total, sourceText: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func colonDuration(in text: String) -> ParsedDuration? {
        let pattern = #"(^|[^\d])(\d{1,2}):(\d{2})(?::(\d{2}))?($|[^\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let first = doubleValue(in: nsText, match: match, group: 2),
              let second = doubleValue(in: nsText, match: match, group: 3) else {
            return nil
        }

        let total: TimeInterval
        if let third = doubleValue(in: nsText, match: match, group: 4) {
            total = first * 3_600 + second * 60 + third
        } else {
            total = first * 60 + second
        }
        guard total > 0 else {
            return nil
        }
        return ParsedDuration(duration: total, sourceText: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstNumericValue(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return doubleValue(in: nsText, match: match, group: 1)
    }

    private static func doubleValue(in text: NSString, match: NSTextCheckingResult, group: Int) -> Double? {
        guard group < match.numberOfRanges else {
            return nil
        }
        let range = match.range(at: group)
        guard range.location != NSNotFound, range.length > 0 else {
            return nil
        }
        let value = text.substring(with: range).replacingOccurrences(of: ",", with: ".")
        return Double(value)
    }
}

public extension AutomationDependency {
    func delayResolution(after sourceRun: AutomationTaskRun) -> AutomationDependencyDelayResolution {
        guard let dynamicDelay else {
            return AutomationDependencyDelayResolution(delay: delay, source: .fixed)
        }

        switch dynamicDelay.source {
        case .conditionEvidenceDuration:
            guard let evidence = sourceRun.conditionEvidence else {
                return fallbackDelayResolution(dynamicDelay, reason: "No condition evidence")
            }
            guard let parsed = AutomationConditionEvidenceDurationParser.duration(
                in: evidence,
                sourceFieldID: dynamicDelay.sourceFieldID
            ) else {
                return fallbackDelayResolution(dynamicDelay, reason: "No recognizable duration")
            }
            let normalized = dynamicDelay.normalizedDelay(parsed.duration)
            return AutomationDependencyDelayResolution(
                delay: normalized.delay,
                source: .recognizedDuration,
                observedText: parsed.sourceText,
                wasClamped: normalized.wasClamped
            )
        }
    }

    private func fallbackDelayResolution(
        _ dynamicDelay: AutomationDependencyDynamicDelay,
        reason: String
    ) -> AutomationDependencyDelayResolution {
        let normalized = dynamicDelay.normalizedDelay(dynamicDelay.fallbackDelay ?? delay)
        return AutomationDependencyDelayResolution(
            delay: normalized.delay,
            source: .fallback,
            reason: reason,
            wasClamped: normalized.wasClamped
        )
    }
}

public struct AutomationTaskRun: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var executionID: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var macroID: UUID?
    public var scheduledStartTime: Date?
    public var earliestStartTime: Date?
    public var actualStartTime: Date?
    public var completedAt: Date?
    public var status: AutomationTaskRunStatus
    public var outcome: AutomationOutcome?
    public var evidenceID: UUID?
    public var leaseID: UUID?
    public var createdAt: Date
    public var attempt: Int
    public var upstreamRunIDs: [UUID]
    public var conditionEvidence: AutomationConditionEvaluationEvidence?
    public var branchEvidence: [AutomationBranchDecisionEvidence]?

    public init(
        id: UUID = UUID(),
        executionID: UUID? = nil,
        workflowID: UUID,
        taskID: UUID,
        macroID: UUID? = nil,
        scheduledStartTime: Date? = nil,
        earliestStartTime: Date? = nil,
        actualStartTime: Date? = nil,
        completedAt: Date? = nil,
        status: AutomationTaskRunStatus = .planned,
        outcome: AutomationOutcome? = nil,
        evidenceID: UUID? = nil,
        leaseID: UUID? = nil,
        createdAt: Date = Date.now,
        attempt: Int = 1,
        upstreamRunIDs: [UUID] = [],
        conditionEvidence: AutomationConditionEvaluationEvidence? = nil,
        branchEvidence: [AutomationBranchDecisionEvidence]? = nil
    ) {
        self.id = id
        self.executionID = executionID ?? id
        self.workflowID = workflowID
        self.taskID = taskID
        self.macroID = macroID
        self.scheduledStartTime = scheduledStartTime
        self.earliestStartTime = earliestStartTime
        self.actualStartTime = actualStartTime
        self.completedAt = completedAt
        self.status = status
        self.outcome = outcome
        self.evidenceID = evidenceID
        self.leaseID = leaseID
        self.createdAt = createdAt
        self.attempt = max(1, attempt)
        self.upstreamRunIDs = upstreamRunIDs
        self.conditionEvidence = conditionEvidence
        self.branchEvidence = branchEvidence?.isEmpty == true ? nil : branchEvidence
    }

    public var isTerminal: Bool {
        outcome != nil
    }

    public func started(at startTime: Date, leaseID: UUID? = nil) -> AutomationTaskRun {
        var copy = self
        copy.actualStartTime = startTime
        copy.leaseID = leaseID
        copy.status = .running
        return copy
    }

    public func completed(
        with outcome: AutomationOutcome,
        at completedAt: Date,
        evidenceID: UUID? = nil,
        conditionEvidence: AutomationConditionEvaluationEvidence? = nil
    ) -> AutomationTaskRun {
        var copy = self
        copy.completedAt = completedAt
        copy.outcome = outcome
        copy.evidenceID = evidenceID ?? self.evidenceID
        copy.conditionEvidence = conditionEvidence ?? self.conditionEvidence
        copy.leaseID = nil
        copy.status = .completed
        return copy
    }
}

public enum AutomationAction: Codable, Equatable, Sendable {
    case clockTick(Date)
    case manualStart(workflowID: UUID, taskID: UUID, requestedAt: Date)
    case scheduledStartDue(workflowID: UUID, taskID: UUID, scheduledAt: Date)
    case upsertWorkflow(AutomationWorkflow, at: Date)
    case deleteWorkflow(workflowID: UUID, at: Date)
    case upsertTask(workflowID: UUID, task: AutomationTask, at: Date)
    case deleteTask(workflowID: UUID, taskID: UUID, at: Date)
    case moveTask(workflowID: UUID, taskID: UUID, position: AutomationGraphPoint, at: Date)
    case upsertDependency(workflowID: UUID, dependency: AutomationDependency, at: Date)
    case deleteDependency(workflowID: UUID, dependencyID: UUID, at: Date)
    case runCreated(AutomationTaskRun)
    case resourceLeaseAcquired(runID: UUID, lease: AutomationResourceLease, at: Date)
    case resourceLeasesAcquired(runID: UUID, leases: [AutomationResourceLease], at: Date)
    case resourceLeaseDenied(runID: UUID, resource: AutomationResource, at: Date)
    case playerStarted(runID: UUID, at: Date)
    case playerFinished(runID: UUID, outcome: AutomationOutcome, at: Date)
    case conditionEvaluated(runID: UUID, outcome: AutomationOutcome, at: Date)
    case conditionEvaluationCompleted(runID: UUID, result: AutomationConditionEvaluationResult, at: Date)
    case taskFinished(runID: UUID, outcome: AutomationOutcome, at: Date)
    case cancelRun(runID: UUID, at: Date)
    case panicRelease(runID: UUID, at: Date)
}

public struct AutomationRunState: Codable, Equatable, Sendable {
    public var workflows: [AutomationWorkflow]
    public var runs: [AutomationTaskRun]
    public var leases: [AutomationResourceLease]
    public var now: Date?

    public init(
        workflows: [AutomationWorkflow] = [],
        runs: [AutomationTaskRun] = [],
        leases: [AutomationResourceLease] = [],
        now: Date? = nil
    ) {
        self.workflows = workflows
        self.runs = runs
        self.leases = leases
        self.now = now
    }

    public func workflow(id workflowID: UUID) -> AutomationWorkflow? {
        workflows.first { $0.id == workflowID }
    }

    public func run(id runID: UUID) -> AutomationTaskRun? {
        runs.first { $0.id == runID }
    }

    public func runs(forTaskID taskID: UUID) -> [AutomationTaskRun] {
        runs.filter { $0.taskID == taskID }
    }
}

private func duplicateValues<T: Hashable>(_ values: [T]) -> [T] {
    var seen: Set<T> = []
    var duplicates: Set<T> = []
    for value in values {
        if !seen.insert(value).inserted {
            duplicates.insert(value)
        }
    }
    return Array(duplicates)
}

private func cycleIssues(
    taskIDs: Set<UUID>,
    dependencies: [AutomationDependency]
) -> [AutomationWorkflowValidationIssue] {
    var adjacency: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, []) })
    for dependency in dependencies where taskIDs.contains(dependency.fromTaskID) && taskIDs.contains(dependency.toTaskID) {
        adjacency[dependency.fromTaskID, default: []].append(dependency.toTaskID)
    }

    enum VisitState {
        case visiting
        case visited
    }

    var states: [UUID: VisitState] = [:]
    var issues: [AutomationWorkflowValidationIssue] = []

    func visit(_ taskID: UUID) {
        if states[taskID] == .visiting {
            issues.append(.cycleDetected(taskID: taskID))
            return
        }
        if states[taskID] == .visited {
            return
        }

        states[taskID] = .visiting
        for nextID in adjacency[taskID, default: []] {
            visit(nextID)
        }
        states[taskID] = .visited
    }

    for taskID in taskIDs {
        visit(taskID)
    }

    return issues
}
