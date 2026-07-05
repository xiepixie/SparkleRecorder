import Foundation

public struct AutomationWorkflow: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var version: Int
    public var name: String
    public var tasks: [AutomationTask]
    public var dependencies: [AutomationDependency]
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        version: Int = 1,
        name: String,
        tasks: [AutomationTask] = [],
        dependencies: [AutomationDependency] = [],
        createdAt: Date = Date.now,
        modifiedAt: Date = Date.now
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.tasks = tasks
        self.dependencies = dependencies
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

public struct AutomationTask: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: AutomationTaskKind
    public var schedule: AutomationSchedule?
    public var resourceRequirement: AutomationResourceRequirement
    public var timeout: TimeInterval?
    public var retryPolicy: AutomationRetryPolicy
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
        self.isEnabled = isEnabled
        self.graphPosition = graphPosition
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

    public init(
        resources: Set<AutomationResource>,
        priority: AutomationResourcePriority = .normal,
        leaseTimeout: TimeInterval? = nil
    ) {
        self.resources = resources
        self.priority = priority
        self.leaseTimeout = leaseTimeout.map { max(0, $0) }
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

public struct AutomationDependency: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var fromTaskID: UUID
    public var toTaskID: UUID
    public var trigger: AutomationDependencyTrigger
    public var delay: TimeInterval
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        fromTaskID: UUID,
        toTaskID: UUID,
        trigger: AutomationDependencyTrigger,
        delay: TimeInterval = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.fromTaskID = fromTaskID
        self.toTaskID = toTaskID
        self.trigger = trigger
        self.delay = max(0, delay)
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
        upstreamRunIDs: [UUID] = []
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

    public func completed(with outcome: AutomationOutcome, at completedAt: Date, evidenceID: UUID? = nil) -> AutomationTaskRun {
        var copy = self
        copy.completedAt = completedAt
        copy.outcome = outcome
        copy.evidenceID = evidenceID ?? self.evidenceID
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
