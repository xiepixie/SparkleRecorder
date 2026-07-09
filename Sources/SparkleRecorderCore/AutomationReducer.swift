import Foundation

public struct AutomationReducerEnvironment: Sendable {
    public var makeRunID: @Sendable () -> UUID

    public init(makeRunID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.makeRunID = makeRunID
    }

    public static let live = AutomationReducerEnvironment()
}

public struct AutomationReducerResult: Equatable, Sendable {
    public var state: AutomationRunState
    public var effects: [AutomationEffect]

    public init(state: AutomationRunState, effects: [AutomationEffect]) {
        self.state = state
        self.effects = effects
    }
}

public enum AutomationEffect: Codable, Equatable, Sendable {
    case requestResource(runID: UUID, requirement: AutomationResourceRequirement)
    case releaseResource(runID: UUID, lease: AutomationResourceLease)
    case startPlayer(runID: UUID, workflowID: UUID, taskID: UUID, macroID: UUID)
    case cancelPlayer(runID: UUID)
    case evaluateCondition(
        runID: UUID,
        workflowID: UUID,
        taskID: UUID,
        condition: AutomationConditionSpec,
        previousOutcomes: [AutomationOutcome]
    )
    case wait(runID: UUID, workflowID: UUID, taskID: UUID, duration: TimeInterval)
    case sendNotification(runID: UUID, workflowID: UUID, taskID: UUID, notification: AutomationNotificationSpec)
    case persistWorkflows([AutomationWorkflow])
    case persistRun(AutomationTaskRun)
}

public enum AutomationReducer {
    private struct DependencyResolution {
        var isSatisfied: Bool
        var earliestStartTime: Date?
        var upstreamRunIDs: [UUID]
    }

    private struct DependencyMatch {
        var dependency: AutomationDependency
        var run: AutomationTaskRun
        var readyAt: Date
    }

    public static func reduce(
        state: AutomationRunState,
        action: AutomationAction,
        environment: AutomationReducerEnvironment = .live
    ) -> AutomationReducerResult {
        var nextState = state
        let effects = reduce(into: &nextState, action: action, environment: environment)
        return AutomationReducerResult(state: nextState, effects: effects)
    }

    public static func reduce(
        into state: inout AutomationRunState,
        action: AutomationAction,
        environment: AutomationReducerEnvironment = .live
    ) -> [AutomationEffect] {
        switch action {
        case .clockTick(let now):
            state.now = now
            var effects = expireTimedOutRuns(in: &state, now: now, environment: environment)
            effects.append(contentsOf: expireResourceWaits(in: &state, now: now, environment: environment))
            effects.append(contentsOf: refreshWaitingResourceRuns(in: &state, now: now))
            effects.append(contentsOf: refreshDueRuns(in: &state, now: now))
            effects.append(contentsOf: createDueScheduledRuns(in: &state, now: now, environment: environment))
            return effects

        case .manualStart(let workflowID, let taskID, let requestedAt):
            state.now = requestedAt
            return createRun(
                workflowID: workflowID,
                taskID: taskID,
                scheduledStartTime: requestedAt,
                earliestStartTime: requestedAt,
                createdAt: requestedAt,
                executionID: nil,
                upstreamRunIDs: [],
                in: &state,
                environment: environment
            )

        case .scheduledStartDue(let workflowID, let taskID, let scheduledAt):
            state.now = scheduledAt
            return createRun(
                workflowID: workflowID,
                taskID: taskID,
                scheduledStartTime: scheduledAt,
                earliestStartTime: scheduledAt,
                createdAt: scheduledAt,
                executionID: nil,
                upstreamRunIDs: [],
                in: &state,
                environment: environment
            )

        case .upsertWorkflow(let workflow, let at):
            state.now = at
            return upsertWorkflow(workflow, at: at, in: &state)

        case .deleteWorkflow(let workflowID, let at):
            state.now = at
            return deleteWorkflow(workflowID: workflowID, in: &state)

        case .upsertTask(let workflowID, let task, let at):
            state.now = at
            return upsertTask(workflowID: workflowID, task: task, at: at, in: &state)

        case .deleteTask(let workflowID, let taskID, let at):
            state.now = at
            return deleteTask(workflowID: workflowID, taskID: taskID, at: at, in: &state)

        case .moveTask(let workflowID, let taskID, let position, let at):
            state.now = at
            return moveTask(workflowID: workflowID, taskID: taskID, position: position, at: at, in: &state)

        case .upsertDependency(let workflowID, let dependency, let at):
            state.now = at
            return upsertDependency(workflowID: workflowID, dependency: dependency, at: at, in: &state)

        case .deleteDependency(let workflowID, let dependencyID, let at):
            state.now = at
            return deleteDependency(workflowID: workflowID, dependencyID: dependencyID, at: at, in: &state)

        case .runCreated(let run):
            if state.runs.contains(where: { $0.id == run.id }) {
                return []
            }
            state.runs.append(run)
            let now = state.now ?? run.createdAt
            return prepareRun(runID: run.id, in: &state, now: now)

        case .resourceLeaseAcquired(let runID, let lease, let at):
            state.now = at
            if !state.leases.contains(where: { $0.id == lease.id }) {
                state.leases.append(lease)
            }
            guard let index = state.runs.firstIndex(where: { $0.id == runID }),
                  !state.runs[index].isTerminal,
                  state.runs[index].status == .waitingForResource else {
                return []
            }
            state.runs[index].leaseID = lease.id
            return startTask(runID: runID, in: &state, now: at)

        case .resourceLeasesAcquired(let runID, let leases, let at):
            state.now = at
            let sortedLeases = leases.sorted { $0.resource.rawValue < $1.resource.rawValue }
            guard !sortedLeases.isEmpty else {
                return []
            }
            for lease in sortedLeases where !state.leases.contains(where: { $0.id == lease.id }) {
                state.leases.append(lease)
            }
            guard let index = state.runs.firstIndex(where: { $0.id == runID }),
                  !state.runs[index].isTerminal,
                  state.runs[index].status == .waitingForResource else {
                return []
            }
            state.runs[index].leaseID = sortedLeases.first?.id
            return startTask(runID: runID, in: &state, now: at)

        case .resourceLeaseDenied(let runID, _, let at):
            state.now = at
            guard let index = state.runs.firstIndex(where: { $0.id == runID }), !state.runs[index].isTerminal else {
                return []
            }
            state.runs[index].status = .waitingForResource
            state.runs[index].leaseID = nil
            if let deadline = resourceWaitDeadline(for: state.runs[index], in: state),
               deadline <= at {
                return completeRun(
                    runID: runID,
                    outcome: .timedOut(deadline: deadline),
                    at: at,
                    in: &state,
                    environment: environment
                )
            }
            return []

        case .playerStarted(let runID, let at):
            state.now = at
            guard let index = state.runs.firstIndex(where: { $0.id == runID }), !state.runs[index].isTerminal else {
                return []
            }
            state.runs[index] = state.runs[index].started(at: at, leaseID: state.runs[index].leaseID)
            return []

        case .playerFinished(let runID, let outcome, let at),
             .conditionEvaluated(let runID, let outcome, let at),
             .taskFinished(let runID, let outcome, let at):
            state.now = at
            return completeRun(runID: runID, outcome: outcome, at: at, in: &state, environment: environment)

        case .conditionEvaluationCompleted(let runID, let result, let at):
            state.now = at
            return completeRun(
                runID: runID,
                outcome: result.outcome,
                at: at,
                conditionEvidence: result.evidence,
                in: &state,
                environment: environment
            )

        case .cancelRun(let runID, let at):
            state.now = at
            var effects = cancelLiveWork(runID: runID, in: state)
            effects.append(contentsOf: completeRun(
                runID: runID,
                outcome: .cancelled(reason: "User cancelled"),
                at: at,
                in: &state,
                environment: environment
            ))
            return effects

        case .panicRelease(let runID, let at):
            state.now = at
            var effects = releaseLeases(runID: runID, in: &state)
            effects.append(contentsOf: refreshWaitingResourceRuns(in: &state, now: at))
            return effects
        }
    }

    private static func upsertWorkflow(
        _ workflow: AutomationWorkflow,
        at date: Date,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        var candidate = workflow
        candidate.modifiedAt = date
        guard candidate.validationIssues().isEmpty else {
            return []
        }

        if let index = state.workflows.firstIndex(where: { $0.id == candidate.id }) {
            state.workflows[index] = candidate
        } else {
            state.workflows.append(candidate)
        }
        return [.persistWorkflows(state.workflows)]
    }

    private static func deleteWorkflow(
        workflowID: UUID,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        guard state.workflows.contains(where: { $0.id == workflowID }) else {
            return []
        }
        state.workflows.removeAll { $0.id == workflowID }
        return [.persistWorkflows(state.workflows)]
    }

    private static func upsertTask(
        workflowID: UUID,
        task: AutomationTask,
        at date: Date,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        guard let workflowIndex = state.workflows.firstIndex(where: { $0.id == workflowID }) else {
            return []
        }

        var workflow = state.workflows[workflowIndex]
        if let taskIndex = workflow.tasks.firstIndex(where: { $0.id == task.id }) {
            workflow.tasks[taskIndex] = task
        } else {
            workflow.tasks.append(task)
        }
        workflow.modifiedAt = date

        guard workflow.validationIssues().isEmpty else {
            return []
        }

        state.workflows[workflowIndex] = workflow
        return [.persistWorkflows(state.workflows)]
    }

    private static func deleteTask(
        workflowID: UUID,
        taskID: UUID,
        at date: Date,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        guard let workflowIndex = state.workflows.firstIndex(where: { $0.id == workflowID }) else {
            return []
        }

        var workflow = state.workflows[workflowIndex]
        guard workflow.tasks.contains(where: { $0.id == taskID }) else {
            return []
        }

        workflow.tasks.removeAll { $0.id == taskID }
        workflow.dependencies.removeAll { $0.fromTaskID == taskID || $0.toTaskID == taskID }
        workflow.modifiedAt = date
        state.workflows[workflowIndex] = workflow
        return [.persistWorkflows(state.workflows)]
    }

    private static func moveTask(
        workflowID: UUID,
        taskID: UUID,
        position: AutomationGraphPoint,
        at date: Date,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        guard let workflowIndex = state.workflows.firstIndex(where: { $0.id == workflowID }) else {
            return []
        }

        var workflow = state.workflows[workflowIndex]
        guard let taskIndex = workflow.tasks.firstIndex(where: { $0.id == taskID }) else {
            return []
        }

        workflow.tasks[taskIndex].graphPosition = AutomationGraphPoint(
            x: max(0, position.x),
            y: max(0, position.y)
        )
        workflow.modifiedAt = date
        state.workflows[workflowIndex] = workflow
        return [.persistWorkflows(state.workflows)]
    }

    private static func upsertDependency(
        workflowID: UUID,
        dependency: AutomationDependency,
        at date: Date,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        guard let workflowIndex = state.workflows.firstIndex(where: { $0.id == workflowID }) else {
            return []
        }

        var workflow = state.workflows[workflowIndex]
        if let dependencyIndex = workflow.dependencies.firstIndex(where: { $0.id == dependency.id }) {
            workflow.dependencies[dependencyIndex] = dependency
        } else {
            workflow.dependencies.append(dependency)
        }
        workflow.modifiedAt = date

        guard workflow.validationIssues().isEmpty else {
            return []
        }

        state.workflows[workflowIndex] = workflow
        return [.persistWorkflows(state.workflows)]
    }

    private static func deleteDependency(
        workflowID: UUID,
        dependencyID: UUID,
        at date: Date,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        guard let workflowIndex = state.workflows.firstIndex(where: { $0.id == workflowID }) else {
            return []
        }

        var workflow = state.workflows[workflowIndex]
        guard workflow.dependencies.contains(where: { $0.id == dependencyID }) else {
            return []
        }

        workflow.dependencies.removeAll { $0.id == dependencyID }
        workflow.modifiedAt = date
        state.workflows[workflowIndex] = workflow
        return [.persistWorkflows(state.workflows)]
    }

    private static func cancelLiveWork(
        runID: UUID,
        in state: AutomationRunState
    ) -> [AutomationEffect] {
        guard
            let run = state.run(id: runID),
            !run.isTerminal,
            run.status == .queued || run.status == .running,
            let workflow = state.workflow(id: run.workflowID),
            let task = workflow.task(id: run.taskID),
            case .macro = task.kind
        else {
            return []
        }

        return [.cancelPlayer(runID: runID)]
    }

    private static func expireTimedOutRuns(
        in state: inout AutomationRunState,
        now: Date,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        let timedOutRuns = state.runs.compactMap { run -> (runID: UUID, deadline: Date, createdAt: Date)? in
            guard
                !run.isTerminal,
                run.status == .queued || run.status == .running,
                let deadline = timeoutDeadline(for: run, in: state),
                deadline <= now
            else {
                return nil
            }

            return (run.id, deadline, run.createdAt)
        }
        .sorted { lhs, rhs in
            if lhs.deadline != rhs.deadline {
                return lhs.deadline < rhs.deadline
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.runID.uuidString < rhs.runID.uuidString
        }

        var effects: [AutomationEffect] = []
        for timedOutRun in timedOutRuns {
            guard
                let run = state.run(id: timedOutRun.runID),
                !run.isTerminal,
                let deadline = timeoutDeadline(for: run, in: state),
                deadline <= now
            else {
                continue
            }

            effects.append(contentsOf: cancelLiveWork(runID: timedOutRun.runID, in: state))
            effects.append(contentsOf: completeRun(
                runID: timedOutRun.runID,
                outcome: .timedOut(deadline: deadline),
                at: now,
                in: &state,
                environment: environment
            ))
        }

        return effects
    }

    private static func timeoutDeadline(
        for run: AutomationTaskRun,
        in state: AutomationRunState
    ) -> Date? {
        guard
            let workflow = state.workflow(id: run.workflowID),
            let task = workflow.task(id: run.taskID),
            let timeout = task.timeout,
            let startedAt = run.actualStartTime
        else {
            return nil
        }

        return startedAt.addingTimeInterval(timeout)
    }

    private static func expireResourceWaits(
        in state: inout AutomationRunState,
        now: Date,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        let expiredWaits = state.runs.compactMap { run -> (runID: UUID, deadline: Date, createdAt: Date)? in
            guard
                !run.isTerminal,
                run.status == .waitingForResource,
                let deadline = resourceWaitDeadline(for: run, in: state),
                deadline <= now
            else {
                return nil
            }

            return (run.id, deadline, run.createdAt)
        }
        .sorted { lhs, rhs in
            if lhs.deadline != rhs.deadline {
                return lhs.deadline < rhs.deadline
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.runID.uuidString < rhs.runID.uuidString
        }

        var effects: [AutomationEffect] = []
        for expiredWait in expiredWaits {
            guard
                let run = state.run(id: expiredWait.runID),
                !run.isTerminal,
                run.status == .waitingForResource,
                let deadline = resourceWaitDeadline(for: run, in: state),
                deadline <= now
            else {
                continue
            }

            effects.append(contentsOf: completeRun(
                runID: expiredWait.runID,
                outcome: .timedOut(deadline: deadline),
                at: now,
                in: &state,
                environment: environment
            ))
        }

        return effects
    }

    private static func resourceWaitDeadline(
        for run: AutomationTaskRun,
        in state: AutomationRunState
    ) -> Date? {
        guard
            let workflow = state.workflow(id: run.workflowID),
            let task = workflow.task(id: run.taskID),
            let maxWaitDuration = task.resourceRequirement.maxWaitDuration
        else {
            return nil
        }

        let waitingStart = resourceWaitingStart(for: run)
        return waitingStart.addingTimeInterval(maxWaitDuration)
    }

    private static func resourceWaitingStart(for run: AutomationTaskRun) -> Date {
        run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    private static func createDueScheduledRuns(
        in state: inout AutomationRunState,
        now: Date,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        var effects: [AutomationEffect] = []

        for workflow in state.workflows {
            for task in workflow.tasks where task.isEnabled {
                guard let schedule = task.schedule else {
                    continue
                }
                let representedScheduledStarts = Set(state.runs.compactMap { run -> Date? in
                    guard run.workflowID == workflow.id, run.taskID == task.id else {
                        return nil
                    }
                    return run.scheduledStartTime
                })
                guard let occurrence = schedule.nextDueOccurrence(
                    onOrBefore: now,
                    excludingScheduledStartTimes: representedScheduledStarts
                ) else {
                    continue
                }

                effects.append(contentsOf: createRun(
                    workflowID: workflow.id,
                    taskID: task.id,
                    scheduledStartTime: occurrence.scheduledAt,
                    earliestStartTime: occurrence.scheduledAt,
                    createdAt: now,
                    executionID: nil,
                    upstreamRunIDs: [],
                    in: &state,
                    environment: environment
                ))
            }
        }

        return effects
    }

    private static func refreshDueRuns(
        in state: inout AutomationRunState,
        now: Date
    ) -> [AutomationEffect] {
        let dueRunIDs = state.runs.compactMap { run -> UUID? in
            guard !run.isTerminal, run.status == .planned else { return nil }
            let dueAt = run.earliestStartTime ?? run.scheduledStartTime
            guard let dueAt, dueAt <= now else { return nil }
            return run.id
        }

        return dueRunIDs.flatMap { runID in
            prepareRun(runID: runID, in: &state, now: now)
        }
    }

    private static func refreshWaitingResourceRuns(
        in state: inout AutomationRunState,
        now: Date
    ) -> [AutomationEffect] {
        let waitingRunIDs = state.runs
            .filter { run in
                guard !run.isTerminal, run.status == .waitingForResource else {
                    return false
                }
                return !state.leases.contains { $0.runID == run.id }
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id)

        return waitingRunIDs.flatMap { runID in
            prepareRun(runID: runID, in: &state, now: now)
        }
    }

    private static func createRun(
        workflowID: UUID,
        taskID: UUID,
        scheduledStartTime: Date?,
        earliestStartTime: Date?,
        createdAt: Date,
        executionID: UUID?,
        upstreamRunIDs: [UUID],
        attempt: Int = 1,
        in state: inout AutomationRunState,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        guard
            let workflow = state.workflow(id: workflowID),
            let task = workflow.task(id: taskID),
            task.isEnabled
        else {
            return []
        }

        let run = task.makeRun(
            workflowID: workflowID,
            runID: environment.makeRunID(),
            executionID: executionID,
            scheduledStartTime: scheduledStartTime,
            earliestStartTime: earliestStartTime,
            createdAt: createdAt,
            attempt: attempt,
            upstreamRunIDs: upstreamRunIDs
        )
        state.runs.append(run)
        return prepareRun(runID: run.id, in: &state, now: createdAt)
    }

    private static func prepareRun(
        runID: UUID,
        in state: inout AutomationRunState,
        now: Date
    ) -> [AutomationEffect] {
        guard
            let index = state.runs.firstIndex(where: { $0.id == runID }),
            !state.runs[index].isTerminal,
            let workflow = state.workflow(id: state.runs[index].workflowID),
            let task = workflow.task(id: state.runs[index].taskID)
        else {
            return []
        }

        if !workflow.dependencies(to: task.id).isEmpty {
            let resolution: DependencyResolution
            if task.joinPolicy == .firstMatched, !state.runs[index].upstreamRunIDs.isEmpty {
                resolution = lockedFirstMatchedDependencyResolution(
                    for: task,
                    in: workflow,
                    upstreamRunIDs: state.runs[index].upstreamRunIDs,
                    state: state
                )
            } else {
                resolution = dependencyResolution(
                    for: task,
                    in: workflow,
                    executionID: state.runs[index].executionID,
                    state: state
                )
            }
            guard resolution.isSatisfied else {
                state.runs[index].status = .waitingForDependencies
                state.runs[index].upstreamRunIDs = resolution.upstreamRunIDs
                return []
            }
            state.runs[index].earliestStartTime = maxDate(state.runs[index].earliestStartTime, resolution.earliestStartTime)
            state.runs[index].upstreamRunIDs = resolution.upstreamRunIDs
        }

        let dueAt = state.runs[index].earliestStartTime ?? state.runs[index].scheduledStartTime ?? now
        guard dueAt <= now else {
            state.runs[index].status = .planned
            return []
        }

        if !task.resourceRequirement.resources.isEmpty && !state.leases.contains(where: { $0.runID == runID }) {
            state.runs[index].status = .waitingForResource
            return [.requestResource(runID: runID, requirement: task.resourceRequirement)]
        }

        return startTask(runID: runID, in: &state, now: now)
    }

    private static func startTask(
        runID: UUID,
        in state: inout AutomationRunState,
        now: Date
    ) -> [AutomationEffect] {
        guard
            let index = state.runs.firstIndex(where: { $0.id == runID }),
            !state.runs[index].isTerminal,
            let workflow = state.workflow(id: state.runs[index].workflowID),
            let task = workflow.task(id: state.runs[index].taskID)
        else {
            return []
        }

        switch task.kind {
        case .macro(let macroID):
            if state.runs[index].actualStartTime == nil {
                state.runs[index].actualStartTime = now
            }
            state.runs[index].status = .queued
            return [.startPlayer(runID: runID, workflowID: workflow.id, taskID: task.id, macroID: macroID)]

        case .condition(let condition):
            if state.runs[index].actualStartTime == nil {
                state.runs[index].actualStartTime = now
            }
            state.runs[index].status = .running
            let previousOutcomes = state.runs[index].upstreamRunIDs.compactMap { upstreamRunID in
                state.run(id: upstreamRunID)?.outcome
            }
            return [.evaluateCondition(
                runID: runID,
                workflowID: workflow.id,
                taskID: task.id,
                condition: condition,
                previousOutcomes: previousOutcomes
            )]

        case .delay(let duration):
            if state.runs[index].actualStartTime == nil {
                state.runs[index].actualStartTime = now
            }
            state.runs[index].status = .running
            return [.wait(runID: runID, workflowID: workflow.id, taskID: task.id, duration: max(0, duration))]

        case .notification(let notification):
            if state.runs[index].actualStartTime == nil {
                state.runs[index].actualStartTime = now
            }
            state.runs[index].status = .running
            return [.sendNotification(runID: runID, workflowID: workflow.id, taskID: task.id, notification: notification)]
        }
    }

    private static func completeRun(
        runID: UUID,
        outcome: AutomationOutcome,
        at completedAt: Date,
        conditionEvidence: AutomationConditionEvaluationEvidence? = nil,
        in state: inout AutomationRunState,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        guard let index = state.runs.firstIndex(where: { $0.id == runID }), !state.runs[index].isTerminal else {
            return []
        }

        var effects = releaseLeases(runID: runID, in: &state)

        var completedRun = state.runs[index].completed(
            with: outcome,
            at: completedAt,
            evidenceID: evidenceID(for: outcome),
            conditionEvidence: conditionEvidence
        )
        if completedRun.actualStartTime == nil {
            completedRun.actualStartTime = completedAt
        }
        state.runs[index] = completedRun

        let waitingResourceEffects = refreshWaitingResourceRuns(in: &state, now: completedAt)
        if let retryEffects = createRetryAttemptIfNeeded(
            from: completedRun,
            outcome: outcome,
            completedAt: completedAt,
            in: &state,
            environment: environment
        ) {
            effects.append(.persistRun(completedRun))
            effects.append(contentsOf: waitingResourceEffects)
            effects.append(contentsOf: retryEffects)
            return effects
        }
        let downstreamEffects = resolveDownstream(
            from: completedRun,
            outcome: outcome,
            completedAt: completedAt,
            in: &state,
            environment: environment
        )
        let branchEvidence = branchDecisionEvidence(
            for: completedRun,
            outcome: outcome,
            completedAt: completedAt,
            in: state
        )
        if !branchEvidence.isEmpty {
            completedRun.branchEvidence = branchEvidence
            if let completedIndex = state.runs.firstIndex(where: { $0.id == completedRun.id }) {
                state.runs[completedIndex].branchEvidence = branchEvidence
            }
        }

        effects.append(.persistRun(completedRun))
        effects.append(contentsOf: waitingResourceEffects)
        effects.append(contentsOf: downstreamEffects)
        return effects
    }

    private static func branchDecisionEvidence(
        for completedRun: AutomationTaskRun,
        outcome: AutomationOutcome,
        completedAt: Date,
        in state: AutomationRunState
    ) -> [AutomationBranchDecisionEvidence] {
        guard let workflow = state.workflow(id: completedRun.workflowID) else {
            return []
        }

        return workflow.dependencies
            .filter { $0.fromTaskID == completedRun.taskID }
            .sorted { left, right in
                if left.toTaskID.uuidString != right.toTaskID.uuidString {
                    return left.toTaskID.uuidString < right.toTaskID.uuidString
                }
                return left.id.uuidString < right.id.uuidString
            }
            .map { dependency in
                let targetTask = workflow.task(id: dependency.toTaskID)
                let targetRunID = downstreamRunID(
                    for: dependency,
                    sourceRun: completedRun,
                    in: state
                )
                let status: AutomationBranchDecisionStatus
                let reason: String
                if !dependency.isEnabled {
                    status = .disabled
                    reason = String(localized: "Dependency disabled", table: "Common")
                } else if dependency.fires(for: outcome) {
                    status = .triggered
                    reason = String(
                        format: String(localized: "Triggered after %@", table: "Common"),
                        outcomeLabel(for: outcome)
                    )
                } else {
                    status = .skipped
                    reason = String(
                        format: String(localized: "Skipped after %@", table: "Common"),
                        outcomeLabel(for: outcome)
                    )
                }

                let delay = status == .triggered
                    ? dependency.delayResolution(after: completedRun).delay
                    : dependency.delay
                return AutomationBranchDecisionEvidence(
                    sourceRunID: completedRun.id,
                    sourceTaskID: completedRun.taskID,
                    dependencyID: dependency.id,
                    trigger: dependency.trigger,
                    status: status,
                    targetTaskID: dependency.toTaskID,
                    targetRunID: targetRunID,
                    executionID: completedRun.executionID,
                    sourceOutcome: outcome,
                    decidedAt: completedAt,
                    delay: delay,
                    targetJoinPolicy: targetTask?.joinPolicy,
                    reason: reason
                )
            }
    }

    private static func downstreamRunID(
        for dependency: AutomationDependency,
        sourceRun: AutomationTaskRun,
        in state: AutomationRunState
    ) -> UUID? {
        state.runs
            .filter { run in
                run.workflowID == sourceRun.workflowID &&
                    run.taskID == dependency.toTaskID &&
                    run.executionID == sourceRun.executionID &&
                    run.upstreamRunIDs.contains(sourceRun.id)
            }
            .max { left, right in
                runSortDate(left) < runSortDate(right)
            }?
            .id
    }

    private static func runSortDate(_ run: AutomationTaskRun) -> Date {
        run.completedAt ?? run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    private static func outcomeLabel(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return String(localized: "Success", table: "Common")
        case .failed:
            return String(localized: "Failure", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .timedOut:
            return String(localized: "Timeout", table: "Common")
        case .resourceConflict:
            return String(localized: "Resource conflict", table: "Common")
        case .permissionDenied:
            return String(localized: "Permission denied", table: "Settings")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .missingMacro:
            return String(localized: "Missing macro", table: "EditorUX")
        case .rejected:
            return String(localized: "Rejected", table: "Common")
        }
    }

    private static func createRetryAttemptIfNeeded(
        from completedRun: AutomationTaskRun,
        outcome: AutomationOutcome,
        completedAt: Date,
        in state: inout AutomationRunState,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect]? {
        guard
            isRetryableOutcome(outcome),
            let workflow = state.workflow(id: completedRun.workflowID),
            let task = workflow.task(id: completedRun.taskID),
            task.isEnabled,
            completedRun.attempt < task.retryPolicy.maxAttempts
        else {
            return nil
        }

        let delay = retryDelay(
            for: task.retryPolicy,
            completedAttempt: completedRun.attempt
        )
        let retryStartTime = completedAt.addingTimeInterval(delay)
        return createRun(
            workflowID: completedRun.workflowID,
            taskID: completedRun.taskID,
            scheduledStartTime: completedRun.scheduledStartTime,
            earliestStartTime: retryStartTime,
            createdAt: completedAt,
            executionID: completedRun.executionID,
            upstreamRunIDs: completedRun.upstreamRunIDs,
            attempt: completedRun.attempt + 1,
            in: &state,
            environment: environment
        )
    }

    private static func isRetryableOutcome(_ outcome: AutomationOutcome) -> Bool {
        AutomationOutcomePredicate.failure.matches(outcome) ||
            AutomationOutcomePredicate.timeout.matches(outcome)
    }

    private static func evidenceID(for outcome: AutomationOutcome) -> UUID? {
        switch outcome {
        case .failed(let report):
            return report?.runID
        case .succeeded, .cancelled, .timedOut, .resourceConflict, .permissionDenied,
             .conditionMatched, .conditionNotMatched, .missingMacro, .rejected:
            return nil
        }
    }

    private static func retryDelay(
        for policy: AutomationRetryPolicy,
        completedAttempt: Int
    ) -> TimeInterval {
        switch policy.backoff {
        case .none:
            return 0
        case .fixed(let delay):
            return finiteNonNegative(delay)
        case .exponential(let initial, let multiplier, let maximum):
            let base = finiteNonNegative(initial)
            let cap = finiteNonNegative(maximum)
            let safeMultiplier = multiplier.isFinite && multiplier > 0 ? multiplier : 1
            let exponent = max(0, completedAttempt - 1)
            let uncapped = base * pow(safeMultiplier, Double(exponent))
            guard uncapped.isFinite else {
                return cap
            }
            return min(uncapped, cap)
        }
    }

    private static func finiteNonNegative(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else {
            return 0
        }
        return max(0, value)
    }

    private static func releaseLeases(
        runID: UUID,
        in state: inout AutomationRunState
    ) -> [AutomationEffect] {
        let leases = state.leases.filter { $0.runID == runID }
        guard !leases.isEmpty else {
            if let index = state.runs.firstIndex(where: { $0.id == runID }) {
                state.runs[index].leaseID = nil
            }
            return []
        }

        state.leases.removeAll { $0.runID == runID }
        if let index = state.runs.firstIndex(where: { $0.id == runID }) {
            state.runs[index].leaseID = nil
        }

        return leases.map { .releaseResource(runID: runID, lease: $0) }
    }

    private static func resolveDownstream(
        from completedRun: AutomationTaskRun,
        outcome: AutomationOutcome,
        completedAt: Date,
        in state: inout AutomationRunState,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        guard let workflow = state.workflow(id: completedRun.workflowID) else {
            return []
        }

        var effects: [AutomationEffect] = []
        let targetTaskIDs = Set(workflow.dependencies(from: completedRun.taskID)
            .filter { $0.fires(for: outcome) }
            .map(\.toTaskID))

        for targetTaskID in targetTaskIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let task = workflow.task(id: targetTaskID), task.isEnabled else {
                continue
            }

            if let existingIndex = state.runs.firstIndex(where: {
                $0.workflowID == workflow.id &&
                $0.taskID == targetTaskID &&
                $0.executionID == completedRun.executionID
            }) {
                guard !state.runs[existingIndex].isTerminal else {
                    continue
                }
                guard state.runs[existingIndex].status == .planned ||
                        state.runs[existingIndex].status == .waitingForDependencies else {
                    continue
                }
                if task.joinPolicy == .firstMatched, !state.runs[existingIndex].upstreamRunIDs.isEmpty {
                    effects.append(contentsOf: prepareRun(runID: state.runs[existingIndex].id, in: &state, now: completedAt))
                    continue
                }

                let resolution = dependencyResolution(
                    for: task,
                    in: workflow,
                    executionID: completedRun.executionID,
                    state: state
                )
                let earliestStartTime = maxDate(task.schedule?.initialScheduledStart, resolution.earliestStartTime)
                switch task.joinPolicy {
                case .all:
                    state.runs[existingIndex].earliestStartTime = maxDate(
                        state.runs[existingIndex].earliestStartTime,
                        earliestStartTime
                    )
                case .any, .firstMatched:
                    state.runs[existingIndex].earliestStartTime = earliestStartTime
                }
                state.runs[existingIndex].upstreamRunIDs = resolution.upstreamRunIDs
                effects.append(contentsOf: prepareRun(runID: state.runs[existingIndex].id, in: &state, now: completedAt))
                continue
            }

            let resolution = dependencyResolution(
                for: task,
                in: workflow,
                executionID: completedRun.executionID,
                state: state
            )
            let earliestStartTime = maxDate(task.schedule?.initialScheduledStart, resolution.earliestStartTime)
            effects.append(contentsOf: createRun(
                workflowID: workflow.id,
                taskID: targetTaskID,
                scheduledStartTime: task.schedule?.initialScheduledStart,
                earliestStartTime: earliestStartTime,
                createdAt: completedAt,
                executionID: completedRun.executionID,
                upstreamRunIDs: resolution.upstreamRunIDs,
                in: &state,
                environment: environment
            ))
        }

        return effects
    }

    private static func dependencyResolution(
        for task: AutomationTask,
        in workflow: AutomationWorkflow,
        executionID: UUID,
        state: AutomationRunState
    ) -> DependencyResolution {
        let dependencies = workflow.dependencies(to: task.id)
        guard !dependencies.isEmpty else {
            return DependencyResolution(isSatisfied: true, earliestStartTime: nil, upstreamRunIDs: [])
        }

        switch task.joinPolicy {
        case .all:
            return allDependencyResolution(
                dependencies: dependencies,
                workflow: workflow,
                executionID: executionID,
                state: state
            )
        case .any, .firstMatched:
            return singleDependencyResolution(
                dependencies: dependencies,
                workflow: workflow,
                executionID: executionID,
                state: state
            )
        }
    }

    private static func allDependencyResolution(
        dependencies: [AutomationDependency],
        workflow: AutomationWorkflow,
        executionID: UUID,
        state: AutomationRunState
    ) -> DependencyResolution {
        var earliestStartTime: Date?
        var upstreamRunIDs: [UUID] = []

        for dependency in dependencies {
            guard let match = dependencyMatch(
                for: dependency,
                workflow: workflow,
                executionID: executionID,
                state: state
            ) else {
                return DependencyResolution(
                    isSatisfied: false,
                    earliestStartTime: earliestStartTime,
                    upstreamRunIDs: upstreamRunIDs
                )
            }

            upstreamRunIDs.append(match.run.id)
            earliestStartTime = maxDate(earliestStartTime, match.readyAt)
        }

        return DependencyResolution(isSatisfied: true, earliestStartTime: earliestStartTime, upstreamRunIDs: upstreamRunIDs)
    }

    private static func singleDependencyResolution(
        dependencies: [AutomationDependency],
        workflow: AutomationWorkflow,
        executionID: UUID,
        state: AutomationRunState
    ) -> DependencyResolution {
        let matches = dependencies.compactMap {
            dependencyMatch(for: $0, workflow: workflow, executionID: executionID, state: state)
        }
        guard let match = firstReadyMatch(matches) else {
            return DependencyResolution(isSatisfied: false, earliestStartTime: nil, upstreamRunIDs: [])
        }
        return DependencyResolution(isSatisfied: true, earliestStartTime: match.readyAt, upstreamRunIDs: [match.run.id])
    }

    private static func lockedFirstMatchedDependencyResolution(
        for task: AutomationTask,
        in workflow: AutomationWorkflow,
        upstreamRunIDs: [UUID],
        state: AutomationRunState
    ) -> DependencyResolution {
        let dependencies = workflow.dependencies(to: task.id)
        let matches = upstreamRunIDs.compactMap { upstreamRunID -> DependencyMatch? in
            guard let run = state.run(id: upstreamRunID),
                  run.workflowID == workflow.id,
                  let completedAt = run.completedAt,
                  let outcome = run.outcome,
                  let dependency = dependencies.first(where: {
                      $0.fromTaskID == run.taskID && $0.fires(for: outcome)
                  }) else {
                return nil
            }
            let delayResolution = dependency.delayResolution(after: run)
            return DependencyMatch(
                dependency: dependency,
                run: run,
                readyAt: completedAt.addingTimeInterval(delayResolution.delay)
            )
        }
        guard !matches.isEmpty else {
            return DependencyResolution(isSatisfied: false, earliestStartTime: nil, upstreamRunIDs: upstreamRunIDs)
        }
        let earliestStartTime = matches.reduce(nil as Date?) { partial, match in
            maxDate(partial, match.readyAt)
        }
        return DependencyResolution(
            isSatisfied: true,
            earliestStartTime: earliestStartTime,
            upstreamRunIDs: upstreamRunIDs
        )
    }

    private static func dependencyMatch(
        for dependency: AutomationDependency,
        workflow: AutomationWorkflow,
        executionID: UUID,
        state: AutomationRunState
    ) -> DependencyMatch? {
        guard let matchingRun = state.runs
            .filter({
                $0.workflowID == workflow.id &&
                    $0.taskID == dependency.fromTaskID &&
                    $0.executionID == executionID &&
                    $0.outcome.map(dependency.fires(for:)) == true &&
                    $0.completedAt != nil
            })
            .max(by: { lhs, rhs in
                (lhs.completedAt ?? .distantPast) < (rhs.completedAt ?? .distantPast)
            }),
            let completedAt = matchingRun.completedAt else {
            return nil
        }
        let delayResolution = dependency.delayResolution(after: matchingRun)
        return DependencyMatch(
            dependency: dependency,
            run: matchingRun,
            readyAt: completedAt.addingTimeInterval(delayResolution.delay)
        )
    }

    private static func firstReadyMatch(_ matches: [DependencyMatch]) -> DependencyMatch? {
        matches.min { lhs, rhs in
            if lhs.readyAt != rhs.readyAt {
                return lhs.readyAt < rhs.readyAt
            }
            let lhsCompletedAt = lhs.run.completedAt ?? .distantPast
            let rhsCompletedAt = rhs.run.completedAt ?? .distantPast
            if lhsCompletedAt != rhsCompletedAt {
                return lhsCompletedAt < rhsCompletedAt
            }
            return lhs.dependency.id.uuidString < rhs.dependency.id.uuidString
        }
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.some(let lhs), .some(let rhs)):
            return max(lhs, rhs)
        }
    }
}
