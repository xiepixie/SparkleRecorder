import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Reducer Tests")
struct AutomationReducerTests {
    @Test("Manual start creates an independent run and requests foreground resource")
    func manualStartCreatesRunAndRequestsResource() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let task = macroTask(id: ids.taskA, macroID: ids.macroA)
        let state = AutomationRunState(workflows: [
            AutomationWorkflow(id: ids.workflow, name: "Workflow", tasks: [task])
        ])

        let result = AutomationReducer.reduce(
            state: state,
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: environment(ids.runA)
        )

        let run = try #require(result.state.run(id: ids.runA))
        #expect(run.executionID == ids.runA)
        #expect(run.taskID == ids.taskA)
        #expect(run.macroID == ids.macroA)
        #expect(run.status == .waitingForResource)
        #expect(run.scheduledStartTime == start)
        #expect(result.effects == [
            .requestResource(runID: ids.runA, requirement: .foregroundInput)
        ])
    }

    @Test("Resource lease acquired starts Player through an effect")
    func resourceLeaseAcquiredStartsPlayerThroughEffect() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let playerStartedAt = Date(timeIntervalSince1970: 101)
        let lease = AutomationResourceLease(
            id: ids.leaseA,
            runID: ids.runA,
            resource: .foregroundInput,
            acquiredAt: start
        )
        let task = macroTask(id: ids.taskA, macroID: ids.macroA)
        let initial = AutomationRunState(workflows: [
            AutomationWorkflow(id: ids.workflow, name: "Workflow", tasks: [task])
        ])
        let started = AutomationReducer.reduce(
            state: initial,
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: environment(ids.runA)
        )

        let acquired = AutomationReducer.reduce(
            state: started.state,
            action: .resourceLeaseAcquired(runID: ids.runA, lease: lease, at: start),
            environment: environment()
        )

        #expect(acquired.state.leases == [lease])
        #expect(acquired.state.run(id: ids.runA)?.leaseID == ids.leaseA)
        #expect(acquired.state.run(id: ids.runA)?.status == .queued)
        #expect(acquired.effects == [
            .startPlayer(runID: ids.runA, workflowID: ids.workflow, taskID: ids.taskA, macroID: ids.macroA)
        ])

        let playerStarted = AutomationReducer.reduce(
            state: acquired.state,
            action: .playerStarted(runID: ids.runA, at: playerStartedAt),
            environment: environment()
        )

        let run = try #require(playerStarted.state.run(id: ids.runA))
        #expect(run.status == .running)
        #expect(run.actualStartTime == playerStartedAt)
        #expect(playerStarted.effects.isEmpty)
    }

    @Test("Batch resource leases start once and release all leases on terminal outcome")
    func batchResourceLeasesStartOnceAndReleaseAllOnTerminalOutcome() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 200)
        let completedAt = Date(timeIntervalSince1970: 205)
        let requirement = AutomationResourceRequirement(resources: [.foregroundInput, .screenCapture])
        let foregroundLease = AutomationResourceLease(
            id: ids.leaseA,
            runID: ids.runA,
            resource: .foregroundInput,
            acquiredAt: start
        )
        let screenLease = AutomationResourceLease(
            id: ids.leaseB,
            runID: ids.runA,
            resource: .screenCapture,
            acquiredAt: start
        )
        let task = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: requirement
        )
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [
                AutomationWorkflow(id: ids.workflow, name: "Workflow", tasks: [task])
            ]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: environment(ids.runA)
        )

        let acquired = AutomationReducer.reduce(
            state: started.state,
            action: .resourceLeasesAcquired(
                runID: ids.runA,
                leases: [screenLease, foregroundLease],
                at: start
            ),
            environment: environment()
        )
        let running = AutomationReducer.reduce(
            state: acquired.state,
            action: .playerStarted(runID: ids.runA, at: start),
            environment: environment()
        )
        let completed = AutomationReducer.reduce(
            state: running.state,
            action: .playerFinished(runID: ids.runA, outcome: .succeeded(report: nil), at: completedAt),
            environment: environment()
        )

        let acquiredLeaseIDs = acquired.state.leases
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        let expectedLeaseIDs = [
            foregroundLease.id,
            screenLease.id
        ].sorted { $0.uuidString < $1.uuidString }

        #expect(started.effects == [.requestResource(runID: ids.runA, requirement: requirement)])
        #expect(acquiredLeaseIDs == expectedLeaseIDs)
        #expect(acquired.state.run(id: ids.runA)?.leaseID == ids.leaseA)
        #expect(acquired.state.run(id: ids.runA)?.status == .queued)
        #expect(acquired.effects == [
            .startPlayer(runID: ids.runA, workflowID: ids.workflow, taskID: ids.taskA, macroID: ids.macroA)
        ])
        #expect(completed.state.leases.isEmpty)
        #expect(completed.effects.contains(.releaseResource(runID: ids.runA, lease: foregroundLease)))
        #expect(completed.effects.contains(.releaseResource(runID: ids.runA, lease: screenLease)))
    }

    @Test("Successful terminal outcome releases lease before downstream resolution and cascades start time")
    func successReleasesLeaseBeforeDownstreamCascade() throws {
        let ids = TestIDs()
        let scheduled = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 140)
        let lease = AutomationResourceLease(
            id: ids.leaseA,
            runID: ids.runA,
            resource: .foregroundInput,
            acquiredAt: scheduled
        )
        let upstream = macroTask(id: ids.taskA, macroID: ids.macroA)
        let downstream = macroTask(
            id: ids.taskB,
            macroID: ids.macroB,
            schedule: .once(scheduled)
        )
        let dependency = AutomationDependency(
            id: ids.dependencySuccess,
            fromTaskID: ids.taskA,
            toTaskID: ids.taskB,
            trigger: .onSuccess
        )
        let initial = AutomationRunState(workflows: [
            AutomationWorkflow(
                id: ids.workflow,
                name: "Workflow",
                tasks: [upstream, downstream],
                dependencies: [dependency]
            )
        ])
        let env = environment(ids.runA, ids.runB)
        var result = AutomationReducer.reduce(
            state: initial,
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: scheduled),
            environment: env
        )
        result = AutomationReducer.reduce(
            state: result.state,
            action: .resourceLeaseAcquired(runID: ids.runA, lease: lease, at: scheduled),
            environment: env
        )
        result = AutomationReducer.reduce(
            state: result.state,
            action: .playerStarted(runID: ids.runA, at: scheduled),
            environment: env
        )

        let completed = AutomationReducer.reduce(
            state: result.state,
            action: .playerFinished(runID: ids.runA, outcome: .succeeded(report: nil), at: completedAt),
            environment: env
        )

        let downstreamRun = try #require(completed.state.run(id: ids.runB))
        #expect(completed.effects.first == .releaseResource(runID: ids.runA, lease: lease))
        #expect(completed.effects.contains(.requestResource(runID: ids.runB, requirement: .foregroundInput)))
        #expect(completed.state.leases.isEmpty)
        #expect(completed.state.run(id: ids.runA)?.leaseID == nil)
        #expect(downstreamRun.executionID == ids.runA)
        #expect(downstreamRun.upstreamRunIDs == [ids.runA])
        #expect(downstreamRun.earliestStartTime == completedAt)
        #expect(downstreamRun.status == .waitingForResource)
    }

    @Test("Failed outcome only triggers failure and always branches")
    func failedOutcomeTriggersFailureAndAlwaysBranches() {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let failedAt = Date(timeIntervalSince1970: 105)
        let taskA = macroTask(id: ids.taskA, macroID: ids.macroA, resourceRequirement: .none)
        let successTask = delayTask(id: ids.taskB)
        let failureTask = delayTask(id: ids.taskC)
        let alwaysTask = delayTask(id: ids.taskD)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Branches",
            tasks: [taskA, successTask, failureTask, alwaysTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onSuccess),
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskC, trigger: .onFailure),
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskD, trigger: .always)
            ]
        )
        let env = environment(ids.runA, ids.runC, ids.runD)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let failed = AutomationReducer.reduce(
            state: started.state,
            action: .playerFinished(runID: ids.runA, outcome: .failed(report: nil), at: failedAt),
            environment: env
        )

        #expect(failed.state.runs.contains { $0.taskID == ids.taskC })
        #expect(failed.state.runs.contains { $0.taskID == ids.taskD })
        #expect(!failed.state.runs.contains { $0.taskID == ids.taskB })
    }

    @Test("Timed out outcome triggers timeout branch")
    func timedOutOutcomeTriggersTimeoutBranch() {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let timeoutAt = Date(timeIntervalSince1970: 130)
        let taskA = macroTask(id: ids.taskA, macroID: ids.macroA, resourceRequirement: .none)
        let timeoutTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Timeout",
            tasks: [taskA, timeoutTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onTimeout)
            ]
        )
        let env = environment(ids.runA, ids.runB)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let timedOut = AutomationReducer.reduce(
            state: started.state,
            action: .playerFinished(runID: ids.runA, outcome: .timedOut(deadline: timeoutAt), at: timeoutAt),
            environment: env
        )

        #expect(timedOut.state.run(id: ids.runB)?.taskID == ids.taskB)
        #expect(timedOut.state.run(id: ids.runB)?.upstreamRunIDs == [ids.runA])
    }

    @Test("Cancel releases lease and triggers cancel branch")
    func cancelReleasesLeaseAndTriggersCancelBranch() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let cancelAt = Date(timeIntervalSince1970: 103)
        let lease = AutomationResourceLease(id: ids.leaseA, runID: ids.runA, resource: .foregroundInput, acquiredAt: start)
        let taskA = macroTask(id: ids.taskA, macroID: ids.macroA)
        let cancelTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Cancel",
            tasks: [taskA, cancelTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onCancelled)
            ]
        )
        let env = environment(ids.runA, ids.runB)
        var result = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )
        result = AutomationReducer.reduce(
            state: result.state,
            action: .resourceLeaseAcquired(runID: ids.runA, lease: lease, at: start),
            environment: env
        )

        let cancelled = AutomationReducer.reduce(
            state: result.state,
            action: .cancelRun(runID: ids.runA, at: cancelAt),
            environment: env
        )

        let run = try #require(cancelled.state.run(id: ids.runA))
        #expect(cancelled.effects.first == .cancelPlayer(runID: ids.runA))
        #expect(cancelled.effects.contains(.releaseResource(runID: ids.runA, lease: lease)))
        #expect(cancelled.state.leases.isEmpty)
        #expect(run.leaseID == nil)
        #expect(run.outcome == .cancelled(reason: "User cancelled"))
        #expect(cancelled.state.run(id: ids.runB)?.taskID == ids.taskB)
    }

    @Test("Resource denied completes as resource conflict")
    func resourceDeniedCompletesAsResourceConflict() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let deniedAt = Date(timeIntervalSince1970: 101)
        let task = macroTask(id: ids.taskA, macroID: ids.macroA)
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Resource", tasks: [task])
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: environment(ids.runA)
        )

        let denied = AutomationReducer.reduce(
            state: started.state,
            action: .resourceLeaseDenied(runID: ids.runA, resource: .foregroundInput, at: deniedAt),
            environment: environment()
        )

        let run = try #require(denied.state.run(id: ids.runA))
        #expect(run.status == .completed)
        #expect(run.outcome == .resourceConflict(resource: .foregroundInput))
        #expect(run.completedAt == deniedAt)
        #expect(denied.effects.contains(.persistRun(run)))
    }

    @Test("Condition matched and not matched trigger separate branches")
    func conditionMatchedAndNotMatchedTriggerSeparateBranches() {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let conditionTask = AutomationTask(
            id: ids.taskA,
            name: "Check text",
            kind: .condition(AutomationConditionSpec(
                name: "Success",
                kind: .ocrText(AutomationOCRCondition(text: "Done"))
            )),
            resourceRequirement: .none
        )
        let matchedTask = delayTask(id: ids.taskB)
        let notMatchedTask = delayTask(id: ids.taskC)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Condition",
            tasks: [conditionTask, matchedTask, notMatchedTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onConditionMatched),
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskC, trigger: .onConditionNotMatched)
            ]
        )

        let matchedEnv = environment(ids.runA, ids.runB)
        let matchedStart = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: matchedEnv
        )
        let matched = AutomationReducer.reduce(
            state: matchedStart.state,
            action: .conditionEvaluated(runID: ids.runA, outcome: .conditionMatched, at: start),
            environment: matchedEnv
        )
        #expect(matched.state.runs.contains { $0.taskID == ids.taskB })
        #expect(!matched.state.runs.contains { $0.taskID == ids.taskC })

        let notMatchedEnv = environment(ids.runA, ids.runC)
        let notMatchedStart = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: notMatchedEnv
        )
        let notMatched = AutomationReducer.reduce(
            state: notMatchedStart.state,
            action: .conditionEvaluated(runID: ids.runA, outcome: .conditionNotMatched, at: start),
            environment: notMatchedEnv
        )
        #expect(!notMatched.state.runs.contains { $0.taskID == ids.taskB })
        #expect(notMatched.state.runs.contains { $0.taskID == ids.taskC })
    }

    @Test("Condition effect includes completed upstream outcomes")
    func conditionEffectIncludesCompletedUpstreamOutcomes() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 104)
        let upstreamTask = macroTask(id: ids.taskA, macroID: ids.macroA, resourceRequirement: .none)
        let condition = AutomationConditionSpec(
            name: "Previous succeeded",
            kind: .previousOutcome(.success)
        )
        let conditionTask = AutomationTask(
            id: ids.taskB,
            name: "Check previous",
            kind: .condition(condition),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Previous outcome",
            tasks: [upstreamTask, conditionTask],
            dependencies: [
                AutomationDependency(
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskB,
                    trigger: .onSuccess
                )
            ]
        )
        let env = environment(ids.runA, ids.runB)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let completed = AutomationReducer.reduce(
            state: started.state,
            action: .playerFinished(runID: ids.runA, outcome: .succeeded(report: nil), at: completedAt),
            environment: env
        )

        let run = try #require(completed.state.run(id: ids.runB))
        #expect(run.upstreamRunIDs == [ids.runA])
        #expect(completed.effects.contains(.evaluateCondition(
            runID: ids.runB,
            workflowID: ids.workflow,
            taskID: ids.taskB,
            condition: condition,
            previousOutcomes: [.succeeded(report: nil)]
        )))
    }

    @Test("Workflow edit actions mutate static workflows and persist through effects")
    func workflowEditActionsPersistStaticWorkflows() throws {
        let ids = TestIDs()
        let createdAt = Date(timeIntervalSince1970: 90)
        let editedAt = Date(timeIntervalSince1970: 100)
        let dependencyID = UUID(uuidString: "00000000-0000-0000-0000-000000000015")!
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Editable",
            createdAt: createdAt,
            modifiedAt: createdAt
        )

        let insertedWorkflow = AutomationReducer.reduce(
            state: AutomationRunState(),
            action: .upsertWorkflow(workflow, at: editedAt)
        )
        let savedWorkflow = try #require(insertedWorkflow.state.workflow(id: ids.workflow))

        #expect(savedWorkflow.modifiedAt == editedAt)
        #expect(insertedWorkflow.effects == [.persistWorkflows([savedWorkflow])])

        let firstTask = delayTask(id: ids.taskA)
        let taskInserted = AutomationReducer.reduce(
            state: insertedWorkflow.state,
            action: .upsertTask(workflowID: ids.workflow, task: firstTask, at: editedAt)
        )
        let workflowWithTask = try #require(taskInserted.state.workflow(id: ids.workflow))

        #expect(workflowWithTask.tasks == [firstTask])
        #expect(taskInserted.effects == [.persistWorkflows([workflowWithTask])])

        let secondTask = delayTask(id: ids.taskB)
        let secondInserted = AutomationReducer.reduce(
            state: taskInserted.state,
            action: .upsertTask(workflowID: ids.workflow, task: secondTask, at: editedAt)
        )
        let dependency = AutomationDependency(
            id: dependencyID,
            fromTaskID: ids.taskA,
            toTaskID: ids.taskB,
            trigger: .onSuccess
        )
        let dependencyInserted = AutomationReducer.reduce(
            state: secondInserted.state,
            action: .upsertDependency(workflowID: ids.workflow, dependency: dependency, at: editedAt)
        )
        let workflowWithDependency = try #require(dependencyInserted.state.workflow(id: ids.workflow))

        #expect(workflowWithDependency.dependencies == [dependency])
        #expect(dependencyInserted.effects == [.persistWorkflows([workflowWithDependency])])

        let taskDeleted = AutomationReducer.reduce(
            state: dependencyInserted.state,
            action: .deleteTask(workflowID: ids.workflow, taskID: ids.taskA, at: editedAt)
        )
        let workflowAfterDelete = try #require(taskDeleted.state.workflow(id: ids.workflow))

        #expect(workflowAfterDelete.tasks.map(\.id) == [ids.taskB])
        #expect(workflowAfterDelete.dependencies.isEmpty)
        #expect(taskDeleted.effects == [.persistWorkflows([workflowAfterDelete])])
    }

    @Test("Workflow edit actions reject invalid dependency graphs")
    func workflowEditActionsRejectInvalidDependencyGraphs() {
        let ids = TestIDs()
        let editedAt = Date(timeIntervalSince1970: 100)
        let task = delayTask(id: ids.taskA)
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Invalid Graph", tasks: [task])
        let state = AutomationRunState(workflows: [workflow])
        let invalidDependency = AutomationDependency(
            id: ids.dependencySuccess,
            fromTaskID: ids.taskA,
            toTaskID: ids.taskA,
            trigger: .always
        )

        let result = AutomationReducer.reduce(
            state: state,
            action: .upsertDependency(workflowID: ids.workflow, dependency: invalidDependency, at: editedAt)
        )

        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test("Task move action persists graph position")
    func taskMoveActionPersistsGraphPosition() throws {
        let ids = TestIDs()
        let movedAt = Date(timeIntervalSince1970: 120)
        let task = delayTask(id: ids.taskA)
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Movable", tasks: [task])
        let position = AutomationGraphPoint(x: 144, y: 96)

        let result = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .moveTask(workflowID: ids.workflow, taskID: ids.taskA, position: position, at: movedAt)
        )
        let savedWorkflow = try #require(result.state.workflow(id: ids.workflow))

        #expect(savedWorkflow.tasks.first?.graphPosition == position)
        #expect(savedWorkflow.modifiedAt == movedAt)
        #expect(result.effects == [.persistWorkflows([savedWorkflow])])
    }

    @Test("Projection exposes stable task and dependency status")
    func projectionExposesStableStatus() {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let taskA = macroTask(id: ids.taskA, macroID: ids.macroA, resourceRequirement: .none)
        let taskB = delayTask(id: ids.taskB)
        let dependency = AutomationDependency(
            id: ids.dependencySuccess,
            fromTaskID: ids.taskA,
            toTaskID: ids.taskB,
            trigger: .onSuccess
        )
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Projection",
            tasks: [taskA, taskB],
            dependencies: [dependency]
        )
        let env = environment(ids.runA, ids.runB)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )
        let completed = AutomationReducer.reduce(
            state: started.state,
            action: .playerFinished(runID: ids.runA, outcome: .succeeded(report: nil), at: start),
            environment: env
        )

        let projection = AutomationViewProjection.overview(from: completed.state)
        #expect(projection.workflows.first?.nodes.count == 2)
        #expect(projection.workflows.first?.nodes.first { $0.taskID == ids.taskA }?.status == .completed)
        #expect(projection.workflows.first?.edges.first?.status == .satisfied)
    }

    private func environment(_ ids: UUID...) -> AutomationReducerEnvironment {
        let sequence = UUIDSequence(ids)
        return AutomationReducerEnvironment(makeRunID: {
            sequence.next()
        })
    }

    private func macroTask(
        id: UUID,
        macroID: UUID,
        schedule: AutomationSchedule? = nil,
        resourceRequirement: AutomationResourceRequirement = .foregroundInput
    ) -> AutomationTask {
        AutomationTask(
            id: id,
            name: "Macro \(id.uuidString.prefix(4))",
            kind: .macro(macroID: macroID),
            schedule: schedule,
            resourceRequirement: resourceRequirement
        )
    }

    private func delayTask(id: UUID) -> AutomationTask {
        AutomationTask(
            id: id,
            name: "Delay \(id.uuidString.prefix(4))",
            kind: .delay(0),
            resourceRequirement: .none
        )
    }
}

private final class UUIDSequence: @unchecked Sendable {
    private var ids: [UUID]

    init(_ ids: [UUID]) {
        self.ids = ids
    }

    func next() -> UUID {
        guard !ids.isEmpty else {
            return UUID()
        }
        return ids.removeFirst()
    }
}

private struct TestIDs {
    let workflow = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let taskA = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let taskB = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let taskC = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    let taskD = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    let macroA = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    let macroB = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    let runA = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    let runB = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    let runC = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let runD = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    let leaseA = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    let leaseB = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
    let dependencySuccess = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
}
