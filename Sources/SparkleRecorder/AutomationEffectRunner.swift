import Foundation

public struct AutomationConditionEvaluationRequest: Sendable {
    public var runID: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var condition: AutomationConditionSpec
    public var previousOutcomes: [AutomationOutcome]

    public init(
        runID: UUID,
        workflowID: UUID,
        taskID: UUID,
        condition: AutomationConditionSpec,
        previousOutcomes: [AutomationOutcome] = []
    ) {
        self.runID = runID
        self.workflowID = workflowID
        self.taskID = taskID
        self.condition = condition
        self.previousOutcomes = previousOutcomes
    }
}

public struct AutomationExternalSignalClient: Sendable {
    public var isActive: @Sendable (_ signalName: String) async -> Bool

    public init(isActive: @escaping @Sendable (_ signalName: String) async -> Bool) {
        self.isActive = isActive
    }

    public static let inactive = AutomationExternalSignalClient { _ in false }

    public static func constant(_ isActive: Bool) -> AutomationExternalSignalClient {
        AutomationExternalSignalClient { _ in isActive }
    }
}

public struct AutomationManualApprovalClient: Sendable {
    public var requestApproval: @Sendable (_ request: AutomationConditionEvaluationRequest) async -> Bool

    public init(
        requestApproval: @escaping @Sendable (_ request: AutomationConditionEvaluationRequest) async -> Bool
    ) {
        self.requestApproval = requestApproval
    }

    public static let rejecting = AutomationManualApprovalClient { _ in false }
}

public struct AutomationConditionEvaluatorClient: Sendable {
    public var evaluate: @Sendable (AutomationConditionEvaluationRequest) async -> AutomationOutcome

    public init(
        evaluate: @escaping @Sendable (AutomationConditionEvaluationRequest) async -> AutomationOutcome
    ) {
        self.evaluate = evaluate
    }

    public static func constant(_ outcome: AutomationOutcome) -> AutomationConditionEvaluatorClient {
        AutomationConditionEvaluatorClient { _ in outcome }
    }

    public static func contextual(
        externalSignal: AutomationExternalSignalClient = .inactive,
        manualApproval: AutomationManualApprovalClient = .rejecting,
        ocrText: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ condition: AutomationOCRCondition
        ) async -> AutomationOutcome = { _, _ in .conditionNotMatched }
    ) -> AutomationConditionEvaluatorClient {
        AutomationConditionEvaluatorClient { request in
            switch request.condition.kind {
            case .ocrText(let condition):
                return await ocrText(request, condition)

            case .previousOutcome(let predicate):
                return request.previousOutcomes.contains(where: predicate.matches)
                    ? .conditionMatched
                    : .conditionNotMatched

            case .externalSignal(let signalName):
                return await externalSignal.isActive(signalName)
                    ? .conditionMatched
                    : .conditionNotMatched

            case .manualApproval:
                return await manualApproval.requestApproval(request)
                    ? .conditionMatched
                    : .conditionNotMatched
            }
        }
    }
}

public struct AutomationNotificationRequest: Sendable {
    public var runID: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var notification: AutomationNotificationSpec

    public init(
        runID: UUID,
        workflowID: UUID,
        taskID: UUID,
        notification: AutomationNotificationSpec
    ) {
        self.runID = runID
        self.workflowID = workflowID
        self.taskID = taskID
        self.notification = notification
    }
}

public struct AutomationNotificationClient: Sendable {
    public var send: @Sendable (AutomationNotificationRequest) async throws -> Void

    public init(
        send: @escaping @Sendable (AutomationNotificationRequest) async throws -> Void
    ) {
        self.send = send
    }

    public static let noop = AutomationNotificationClient { _ in }
}

public struct AutomationEffectRunner: Sendable {
    public var resourceArbiter: AutomationResourceArbiterClient
    public var player: AutomationPlayerClient
    public var conditionEvaluator: AutomationConditionEvaluatorClient
    public var repository: AutomationRepositoryClient
    public var notificationClient: AutomationNotificationClient
    public var loadMacro: @Sendable (_ macroID: UUID) async throws -> SavedMacro?
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (_ duration: TimeInterval) async -> Void

    public init(
        resourceArbiter: AutomationResourceArbiterClient,
        player: AutomationPlayerClient = .rejecting(.rejected(reason: "Player client is not configured")),
        conditionEvaluator: AutomationConditionEvaluatorClient = .constant(.conditionNotMatched),
        repository: AutomationRepositoryClient = .inMemory(),
        notificationClient: AutomationNotificationClient = .noop,
        loadMacro: @escaping @Sendable (_ macroID: UUID) async throws -> SavedMacro? = { _ in nil },
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (_ duration: TimeInterval) async -> Void = { duration in
            guard duration > 0 else { return }
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.resourceArbiter = resourceArbiter
        self.player = player
        self.conditionEvaluator = conditionEvaluator
        self.repository = repository
        self.notificationClient = notificationClient
        self.loadMacro = loadMacro
        self.now = now
        self.sleep = sleep
    }

    public func run(_ effect: AutomationEffect) async -> [AutomationAction] {
        switch effect {
        case .requestResource(let runID, let requirement):
            return await requestResources(runID: runID, requirement: requirement)

        case .releaseResource(_, let lease):
            await resourceArbiter.release(lease.id)
            return []

        case .startPlayer(let runID, _, _, let macroID):
            return await startPlayer(runID: runID, macroID: macroID)

        case .cancelPlayer(let runID):
            await player.cancel(runID)
            return []

        case .evaluateCondition(let runID, let workflowID, let taskID, let condition, let previousOutcomes):
            let request = AutomationConditionEvaluationRequest(
                runID: runID,
                workflowID: workflowID,
                taskID: taskID,
                condition: condition,
                previousOutcomes: previousOutcomes
            )
            let outcome = await conditionEvaluator.evaluate(request)
            return [.conditionEvaluated(runID: runID, outcome: outcome, at: now())]

        case .wait(let runID, _, _, let duration):
            await sleep(max(0, duration))
            return [.taskFinished(runID: runID, outcome: .succeeded(report: nil), at: now())]

        case .sendNotification(let runID, let workflowID, let taskID, let notification):
            do {
                try await notificationClient.send(AutomationNotificationRequest(
                    runID: runID,
                    workflowID: workflowID,
                    taskID: taskID,
                    notification: notification
                ))
                return [.taskFinished(runID: runID, outcome: .succeeded(report: nil), at: now())]
            } catch {
                return [.taskFinished(runID: runID, outcome: .failed(report: nil), at: now())]
            }

        case .persistWorkflows(let workflows):
            try? await repository.saveWorkflows(workflows)
            return []

        case .persistRun(let run):
            try? await repository.appendRun(run)
            return []
        }
    }

    public func playerActions() -> AsyncStream<AutomationAction> {
        player.events()
    }

    private func requestResources(
        runID: UUID,
        requirement: AutomationResourceRequirement
    ) async -> [AutomationAction] {
        let resources = requirement.resources.sorted { $0.rawValue < $1.rawValue }
        guard !resources.isEmpty else {
            return []
        }

        let requestedAt = now()
        var acquiredLeases: [AutomationResourceLease] = []

        for resource in resources {
            let request = AutomationResourceRequest(
                runID: runID,
                resource: resource,
                requestedAt: requestedAt,
                leaseTimeout: requirement.leaseTimeout
            )
            let result = await resourceArbiter.acquire(request)
            switch result {
            case .acquired(let lease):
                acquiredLeases.append(lease)
            case .denied(let deniedResource):
                for lease in acquiredLeases {
                    await resourceArbiter.release(lease.id)
                }
                return [.resourceLeaseDenied(runID: runID, resource: deniedResource, at: requestedAt)]
            }
        }

        if let lease = acquiredLeases.first, acquiredLeases.count == 1 {
            return [.resourceLeaseAcquired(runID: runID, lease: lease, at: requestedAt)]
        }

        return [.resourceLeasesAcquired(runID: runID, leases: acquiredLeases, at: requestedAt)]
    }

    private func startPlayer(runID: UUID, macroID: UUID) async -> [AutomationAction] {
        let startedAt = now()
        do {
            guard let macro = try await loadMacro(macroID) else {
                return [.playerFinished(runID: runID, outcome: .missingMacro(macroID: macroID), at: startedAt)]
            }
            guard !PlaybackPlanner.plan(events: macro.events, loops: macro.loops, speed: macro.speed).steps.isEmpty else {
                return [.playerFinished(
                    runID: runID,
                    outcome: .rejected(reason: "Macro has no playable events"),
                    at: startedAt
                )]
            }

            let request = AutomationPlayerStartRequest(runID: runID, macro: macro)
            let result = await player.start(request)
            return [result.action(runID: runID, at: startedAt)]
        } catch {
            return [.playerFinished(runID: runID, outcome: .rejected(reason: String(describing: error)), at: startedAt)]
        }
    }
}
