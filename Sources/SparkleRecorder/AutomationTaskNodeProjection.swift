import Foundation

public struct AutomationTimeoutCountdownProjection: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var deadline: Date
    public var timeout: TimeInterval
    public var remaining: TimeInterval
    public var elapsedFraction: Double

    public init(
        startedAt: Date,
        deadline: Date,
        timeout: TimeInterval,
        remaining: TimeInterval,
        elapsedFraction: Double
    ) {
        self.startedAt = startedAt
        self.deadline = deadline
        self.timeout = timeout
        self.remaining = remaining
        self.elapsedFraction = elapsedFraction
    }
}

public struct AutomationRetryAttemptSummary: Codable, Equatable, Sendable {
    public var currentAttempt: Int
    public var maxAttempts: Int
    public var remainingAttempts: Int
    public var nextRetryAt: Date?
    public var label: String

    public init(
        currentAttempt: Int,
        maxAttempts: Int,
        remainingAttempts: Int,
        nextRetryAt: Date? = nil,
        label: String
    ) {
        self.currentAttempt = currentAttempt
        self.maxAttempts = maxAttempts
        self.remainingAttempts = remainingAttempts
        self.nextRetryAt = nextRetryAt
        self.label = label
    }
}

public struct AutomationResourceBlockerProjection: Codable, Equatable, Sendable {
    public var resource: AutomationResource
    public var resourceLabel: String
    public var runID: UUID
    public var taskID: UUID?
    public var taskTitle: String?
    public var leaseExpiresAt: Date?

    public init(
        resource: AutomationResource,
        resourceLabel: String,
        runID: UUID,
        taskID: UUID? = nil,
        taskTitle: String? = nil,
        leaseExpiresAt: Date? = nil
    ) {
        self.resource = resource
        self.resourceLabel = resourceLabel
        self.runID = runID
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.leaseExpiresAt = leaseExpiresAt
    }
}

public struct AutomationResourceWaitingProjection: Codable, Equatable, Sendable {
    public var detail: String
    public var resources: [AutomationResource]
    public var resourceLabels: [String]
    public var priority: AutomationResourcePriority
    public var priorityLabel: String
    public var waitingSince: Date
    public var waitedDuration: TimeInterval
    public var maxWaitDuration: TimeInterval?
    public var deadline: Date?
    public var remainingDuration: TimeInterval?
    public var elapsedFraction: Double?
    public var blockers: [AutomationResourceBlockerProjection]

    public init(
        detail: String,
        resources: [AutomationResource],
        resourceLabels: [String],
        priority: AutomationResourcePriority,
        priorityLabel: String,
        waitingSince: Date,
        waitedDuration: TimeInterval,
        maxWaitDuration: TimeInterval? = nil,
        deadline: Date? = nil,
        remainingDuration: TimeInterval? = nil,
        elapsedFraction: Double? = nil,
        blockers: [AutomationResourceBlockerProjection] = []
    ) {
        self.detail = detail
        self.resources = resources
        self.resourceLabels = resourceLabels
        self.priority = priority
        self.priorityLabel = priorityLabel
        self.waitingSince = waitingSince
        self.waitedDuration = waitedDuration
        self.maxWaitDuration = maxWaitDuration.map { max(0, $0) }
        self.deadline = deadline
        self.remainingDuration = remainingDuration.map { max(0, $0) }
        self.elapsedFraction = elapsedFraction.map { min(max($0, 0), 1) }
        self.blockers = blockers
    }
}

public enum AutomationConditionProgressKind: String, Codable, Equatable, Sendable {
    case ocrText
    case regionChanged
    case imageAppeared
    case imageDisappeared
    case pixelMatched
    case previousOutcome
    case externalSignal
    case manualApproval
}

public struct AutomationConditionProgressProjection: Codable, Equatable, Sendable {
    public var kind: AutomationConditionProgressKind
    public var kindLabel: String
    public var targetLabel: String
    public var detail: String
    public var pollingInterval: TimeInterval
    public var isActivelyPolling: Bool
    public var timeoutCountdown: AutomationTimeoutCountdownProjection?
    public var regionRef: String?
    public var imageRef: String?
    public var baselineRef: String?
    public var pixel: AutomationGraphPoint?
    public var colorHex: String?
    public var threshold: Double?

    public init(
        kind: AutomationConditionProgressKind,
        kindLabel: String,
        targetLabel: String,
        detail: String,
        pollingInterval: TimeInterval,
        isActivelyPolling: Bool,
        timeoutCountdown: AutomationTimeoutCountdownProjection? = nil,
        regionRef: String? = nil,
        imageRef: String? = nil,
        baselineRef: String? = nil,
        pixel: AutomationGraphPoint? = nil,
        colorHex: String? = nil,
        threshold: Double? = nil
    ) {
        self.kind = kind
        self.kindLabel = kindLabel
        self.targetLabel = targetLabel
        self.detail = detail
        self.pollingInterval = pollingInterval
        self.isActivelyPolling = isActivelyPolling
        self.timeoutCountdown = timeoutCountdown
        self.regionRef = regionRef
        self.imageRef = imageRef
        self.baselineRef = baselineRef
        self.pixel = pixel
        self.colorHex = colorHex
        self.threshold = threshold
    }
}

public struct AutomationTaskNodeProjection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { taskID }

    public var workflowID: UUID
    public var taskID: UUID
    public var runID: UUID?
    public var title: String
    public var kindLabel: String
    public var scheduleLabel: String
    public var nextScheduledOccurrence: Date?
    public var resourceLabel: String
    public var incomingDependencyCount: Int
    public var joinPolicy: AutomationJoinPolicy
    public var joinPolicyLabel: String
    public var status: AutomationDisplayStatus
    public var statusDetail: String
    public var resourceWaiting: AutomationResourceWaitingProjection?
    public var timeoutCountdown: AutomationTimeoutCountdownProjection?
    public var retryAttemptSummary: AutomationRetryAttemptSummary?
    public var conditionProgress: AutomationConditionProgressProjection?
    public var hasEvidence: Bool
    public var position: AutomationGraphPoint

    public init(
        workflowID: UUID,
        taskID: UUID,
        runID: UUID? = nil,
        title: String,
        kindLabel: String,
        scheduleLabel: String,
        nextScheduledOccurrence: Date? = nil,
        resourceLabel: String,
        incomingDependencyCount: Int = 0,
        joinPolicy: AutomationJoinPolicy = .all,
        joinPolicyLabel: String = "",
        status: AutomationDisplayStatus,
        statusDetail: String,
        resourceWaiting: AutomationResourceWaitingProjection? = nil,
        timeoutCountdown: AutomationTimeoutCountdownProjection? = nil,
        retryAttemptSummary: AutomationRetryAttemptSummary? = nil,
        conditionProgress: AutomationConditionProgressProjection? = nil,
        hasEvidence: Bool,
        position: AutomationGraphPoint
    ) {
        self.workflowID = workflowID
        self.taskID = taskID
        self.runID = runID
        self.title = title
        self.kindLabel = kindLabel
        self.scheduleLabel = scheduleLabel
        self.nextScheduledOccurrence = nextScheduledOccurrence
        self.resourceLabel = resourceLabel
        self.incomingDependencyCount = incomingDependencyCount
        self.joinPolicy = joinPolicy
        self.joinPolicyLabel = joinPolicyLabel
        self.status = status
        self.statusDetail = statusDetail
        self.resourceWaiting = resourceWaiting
        self.timeoutCountdown = timeoutCountdown
        self.retryAttemptSummary = retryAttemptSummary
        self.conditionProgress = conditionProgress
        self.hasEvidence = hasEvidence
        self.position = position
    }
}
