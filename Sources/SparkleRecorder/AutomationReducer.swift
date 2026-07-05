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
            var effects = createDueScheduledRuns(in: &state, now: now, environment: environment)
            effects.append(contentsOf: refreshDueRuns(in: &state, now: now))
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
            guard let index = state.runs.firstIndex(where: { $0.id == runID }), !state.runs[index].isTerminal else {
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
            guard let index = state.runs.firstIndex(where: { $0.id == runID }), !state.runs[index].isTerminal else {
                return []
            }
            state.runs[index].leaseID = sortedLeases.first?.id
            return startTask(runID: runID, in: &state, now: at)

        case .resourceLeaseDenied(let runID, let resource, let at):
            state.now = at
            return completeRun(
                runID: runID,
                outcome: .resourceConflict(resource: resource),
                at: at,
                in: &state,
                environment: environment
            )

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
            return releaseLeases(runID: runID, in: &state)
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

    private static func createDueScheduledRuns(
        in state: inout AutomationRunState,
        now: Date,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        var effects: [AutomationEffect] = []

        for workflow in state.workflows {
            for task in workflow.tasks where task.isEnabled {
                guard let scheduledStart = task.schedule?.initialScheduledStart, scheduledStart <= now else {
                    continue
                }
                guard !state.runs.contains(where: {
                    $0.workflowID == workflow.id &&
                    $0.taskID == task.id &&
                    $0.scheduledStartTime == scheduledStart
                }) else {
                    continue
                }

                effects.append(contentsOf: createRun(
                    workflowID: workflow.id,
                    taskID: task.id,
                    scheduledStartTime: scheduledStart,
                    earliestStartTime: scheduledStart,
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

    private static func createRun(
        workflowID: UUID,
        taskID: UUID,
        scheduledStartTime: Date?,
        earliestStartTime: Date?,
        createdAt: Date,
        executionID: UUID?,
        upstreamRunIDs: [UUID],
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
            let resolution = dependencyResolution(
                for: task,
                in: workflow,
                executionID: state.runs[index].executionID,
                state: state
            )
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
        in state: inout AutomationRunState,
        environment: AutomationReducerEnvironment
    ) -> [AutomationEffect] {
        guard let index = state.runs.firstIndex(where: { $0.id == runID }), !state.runs[index].isTerminal else {
            return []
        }

        var effects = releaseLeases(runID: runID, in: &state)

        var completedRun = state.runs[index].completed(with: outcome, at: completedAt)
        if completedRun.actualStartTime == nil {
            completedRun.actualStartTime = completedAt
        }
        state.runs[index] = completedRun

        effects.append(.persistRun(completedRun))
        effects.append(contentsOf: resolveDownstream(
            from: completedRun,
            outcome: outcome,
            completedAt: completedAt,
            in: &state,
            environment: environment
        ))
        return effects
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

        for targetTaskID in targetTaskIDs {
            guard let task = workflow.task(id: targetTaskID), task.isEnabled else {
                continue
            }

            let resolution = dependencyResolution(
                for: task,
                in: workflow,
                executionID: completedRun.executionID,
                state: state
            )
            let earliestStartTime = maxDate(task.schedule?.initialScheduledStart, resolution.earliestStartTime)

            if let existingIndex = state.runs.firstIndex(where: {
                !$0.isTerminal &&
                $0.workflowID == workflow.id &&
                $0.taskID == targetTaskID &&
                $0.executionID == completedRun.executionID
            }) {
                state.runs[existingIndex].earliestStartTime = maxDate(state.runs[existingIndex].earliestStartTime, earliestStartTime)
                state.runs[existingIndex].upstreamRunIDs = resolution.upstreamRunIDs
                effects.append(contentsOf: prepareRun(runID: state.runs[existingIndex].id, in: &state, now: completedAt))
                continue
            }

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
    ) -> (isSatisfied: Bool, earliestStartTime: Date?, upstreamRunIDs: [UUID]) {
        let dependencies = workflow.dependencies(to: task.id)
        guard !dependencies.isEmpty else {
            return (true, nil, [])
        }

        var earliestStartTime: Date?
        var upstreamRunIDs: [UUID] = []

        for dependency in dependencies {
            let matchingRun = state.runs
                .filter {
                    $0.workflowID == workflow.id &&
                    $0.taskID == dependency.fromTaskID &&
                    $0.executionID == executionID &&
                    $0.outcome.map(dependency.fires(for:)) == true &&
                    $0.completedAt != nil
                }
                .max { lhs, rhs in
                    (lhs.completedAt ?? .distantPast) < (rhs.completedAt ?? .distantPast)
                }

            guard let matchingRun, let completedAt = matchingRun.completedAt else {
                return (false, earliestStartTime, upstreamRunIDs)
            }

            upstreamRunIDs.append(matchingRun.id)
            earliestStartTime = maxDate(earliestStartTime, completedAt.addingTimeInterval(dependency.delay))
        }

        return (true, earliestStartTime, upstreamRunIDs)
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
