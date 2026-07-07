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

    @Test("Clock tick creates the next due repeating scheduled run once per represented occurrence")
    func clockTickCreatesNextDueRepeatingScheduledRun() throws {
        let ids = TestIDs()
        let anchor = Date(timeIntervalSince1970: 1_000)
        let secondOccurrence = anchor.addingTimeInterval(3_600)
        let tickAt = secondOccurrence.addingTimeInterval(30)
        let task = AutomationTask(
            id: ids.taskA,
            name: "Hourly delay",
            kind: .delay(0),
            schedule: .repeating(AutomationRepeatRule(
                anchor: anchor,
                interval: .hours(1)
            )),
            resourceRequirement: .none
        )
        let representedFirstRun = task.makeRun(
            workflowID: ids.workflow,
            runID: ids.runA,
            scheduledStartTime: anchor,
            createdAt: anchor
        )
        .completed(with: .succeeded(report: nil), at: anchor.addingTimeInterval(1))
        let state = AutomationRunState(
            workflows: [
                AutomationWorkflow(id: ids.workflow, name: "Scheduled", tasks: [task])
            ],
            runs: [representedFirstRun]
        )

        let result = AutomationReducer.reduce(
            state: state,
            action: .clockTick(tickAt),
            environment: environment(ids.runB)
        )

        let run = try #require(result.state.run(id: ids.runB))
        #expect(run.executionID == ids.runB)
        #expect(run.scheduledStartTime == secondOccurrence)
        #expect(run.earliestStartTime == secondOccurrence)
        #expect(run.createdAt == tickAt)
        #expect(run.actualStartTime == tickAt)
        #expect(run.status == .running)
        #expect(result.effects == [
            .wait(runID: ids.runB, workflowID: ids.workflow, taskID: ids.taskA, duration: 0)
        ])

        let duplicateTick = AutomationReducer.reduce(
            state: result.state,
            action: .clockTick(tickAt),
            environment: environment(ids.runC)
        )

        #expect(duplicateTick.state.runs.count == 2)
        #expect(duplicateTick.effects.isEmpty)
    }

    @Test("Clock tick does not create repeating runs after schedule end")
    func clockTickDoesNotCreateRepeatingRunAfterScheduleEnd() {
        let ids = TestIDs()
        let anchor = Date(timeIntervalSince1970: 2_000)
        let secondOccurrence = anchor.addingTimeInterval(60)
        let tickAt = anchor.addingTimeInterval(120)
        let task = AutomationTask(
            id: ids.taskA,
            name: "Two occurrences",
            kind: .delay(0),
            schedule: .repeating(AutomationRepeatRule(
                anchor: anchor,
                interval: .minutes(1),
                end: .afterOccurrences(2)
            )),
            resourceRequirement: .none
        )
        let firstRun = task.makeRun(
            workflowID: ids.workflow,
            runID: ids.runA,
            scheduledStartTime: anchor,
            createdAt: anchor
        )
        .completed(with: .succeeded(report: nil), at: anchor.addingTimeInterval(1))
        let secondRun = task.makeRun(
            workflowID: ids.workflow,
            runID: ids.runB,
            scheduledStartTime: secondOccurrence,
            createdAt: secondOccurrence
        )
        .completed(with: .succeeded(report: nil), at: secondOccurrence.addingTimeInterval(1))
        let state = AutomationRunState(
            workflows: [
                AutomationWorkflow(id: ids.workflow, name: "Ended", tasks: [task])
            ],
            runs: [firstRun, secondRun]
        )

        let result = AutomationReducer.reduce(
            state: state,
            action: .clockTick(tickAt),
            environment: environment(ids.runC)
        )

        #expect(result.state.runs == [firstRun, secondRun])
        #expect(result.effects.isEmpty)
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

    @Test("Failed playback report binds run evidence id")
    func failedPlaybackReportBindsRunEvidenceID() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let failedAt = Date(timeIntervalSince1970: 105)
        let report = RunReport(
            runID: ids.runA,
            startTime: start,
            duration: 5,
            isSuccess: false,
            failedEventIndex: 2,
            errorMessage: "Target text did not appear"
        )
        let task = macroTask(id: ids.taskA, macroID: ids.macroA, resourceRequirement: .none)
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Evidence", tasks: [task])
        let env = environment(ids.runA)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let failed = AutomationReducer.reduce(
            state: started.state,
            action: .playerFinished(runID: ids.runA, outcome: .failed(report: report), at: failedAt),
            environment: env
        )

        let run = try #require(failed.state.run(id: ids.runA))
        #expect(run.evidenceID == ids.runA)
        #expect(run.outcome == .failed(report: report))
        #expect(failed.effects.contains { effect in
            guard case .persistRun(let persistedRun) = effect else {
                return false
            }
            return persistedRun.id == ids.runA && persistedRun.evidenceID == ids.runA
        })
    }

    @Test("Terminal run persists durable branch decision evidence")
    func terminalRunPersistsDurableBranchDecisionEvidence() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let failedAt = Date(timeIntervalSince1970: 108)
        let failureDependencyID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let alwaysDependencyID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let disabledDependencyID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let taskA = macroTask(id: ids.taskA, macroID: ids.macroA, resourceRequirement: .none)
        let successTask = delayTask(id: ids.taskB)
        let failureTask = delayTask(id: ids.taskC)
        let alwaysTask = delayTask(id: ids.taskD)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Branch evidence",
            tasks: [taskA, successTask, failureTask, alwaysTask],
            dependencies: [
                AutomationDependency(
                    id: ids.dependencySuccess,
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskB,
                    trigger: .onSuccess
                ),
                AutomationDependency(
                    id: failureDependencyID,
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskC,
                    trigger: .onFailure,
                    delay: 2
                ),
                AutomationDependency(
                    id: alwaysDependencyID,
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskD,
                    trigger: .always
                ),
                AutomationDependency(
                    id: disabledDependencyID,
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskB,
                    trigger: .onTimeout,
                    isEnabled: false
                )
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
        let completedRun = try #require(failed.state.run(id: ids.runA))
        let branchEvidence = try #require(completedRun.branchEvidence)
        let evidenceByDependencyID = Dictionary(uniqueKeysWithValues: branchEvidence.map { ($0.dependencyID, $0) })
        let successEvidence = try #require(evidenceByDependencyID[ids.dependencySuccess])
        let failureEvidence = try #require(evidenceByDependencyID[failureDependencyID])
        let alwaysEvidence = try #require(evidenceByDependencyID[alwaysDependencyID])
        let disabledEvidence = try #require(evidenceByDependencyID[disabledDependencyID])

        #expect(branchEvidence.count == 4)
        #expect(successEvidence.status == .skipped)
        #expect(successEvidence.targetRunID == nil)
        #expect(successEvidence.reason == "Skipped after Failure")
        #expect(failureEvidence.status == .triggered)
        #expect(failureEvidence.targetRunID == ids.runC)
        #expect(failureEvidence.delay == 2)
        #expect(failureEvidence.targetJoinPolicy == .all)
        #expect(failureEvidence.reason == "Triggered after Failure")
        #expect(alwaysEvidence.status == .triggered)
        #expect(alwaysEvidence.targetRunID == ids.runD)
        #expect(disabledEvidence.status == .disabled)
        #expect(disabledEvidence.targetRunID == nil)
        #expect(disabledEvidence.reason == "Dependency disabled")
        #expect(branchEvidence.allSatisfy { evidence in
            evidence.sourceRunID == ids.runA &&
                evidence.sourceTaskID == ids.taskA &&
                evidence.executionID == ids.runA &&
                evidence.sourceOutcome == .failed(report: nil) &&
                evidence.decidedAt == failedAt
        })
        #expect(!failed.state.runs.contains { $0.taskID == ids.taskB })
        #expect(failed.effects.contains(.persistRun(completedRun)))
    }

    @Test("Retryable terminal run does not persist branch evidence until final attempt")
    func retryableTerminalRunDoesNotPersistBranchEvidenceUntilFinalAttempt() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let failedAt = Date(timeIntervalSince1970: 105)
        let taskA = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: .none,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 2)
        )
        let failureTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Retry branch evidence",
            tasks: [taskA, failureTask],
            dependencies: [
                AutomationDependency(
                    id: ids.dependencySuccess,
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskB,
                    trigger: .onFailure
                )
            ]
        )
        let env = environment(ids.runA, ids.runB)
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
        let firstAttempt = try #require(failed.state.run(id: ids.runA))

        #expect(firstAttempt.branchEvidence == nil)
        #expect(failed.state.run(id: ids.runB)?.attempt == 2)
        #expect(!failed.state.runs.contains { $0.taskID == ids.taskB && $0.id != ids.runB })
        #expect(failed.effects.contains(.persistRun(firstAttempt)))
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

    @Test("All join waits for every incoming dependency")
    func allJoinWaitsForEveryIncomingDependency() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let firstCompletedAt = Date(timeIntervalSince1970: 110)
        let secondCompletedAt = Date(timeIntervalSince1970: 120)
        let first = delayTask(id: ids.taskB)
        let second = delayTask(id: ids.taskC)
        let joined = delayTask(id: ids.taskD)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "All join",
            tasks: [first, second, joined],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskB, toTaskID: ids.taskD, trigger: .onSuccess),
                AutomationDependency(fromTaskID: ids.taskC, toTaskID: ids.taskD, trigger: .onSuccess)
            ]
        )
        let initial = AutomationRunState(
            workflows: [workflow],
            runs: [
                AutomationTaskRun(
                    id: ids.runB,
                    executionID: ids.runA,
                    workflowID: ids.workflow,
                    taskID: ids.taskB,
                    actualStartTime: start,
                    status: .running,
                    createdAt: start
                ),
                AutomationTaskRun(
                    id: ids.runC,
                    executionID: ids.runA,
                    workflowID: ids.workflow,
                    taskID: ids.taskC,
                    actualStartTime: start,
                    status: .running,
                    createdAt: start
                )
            ]
        )
        let env = environment(ids.runD)

        let firstCompleted = AutomationReducer.reduce(
            state: initial,
            action: .taskFinished(runID: ids.runB, outcome: .succeeded(report: nil), at: firstCompletedAt),
            environment: env
        )

        let waitingJoin = try #require(firstCompleted.state.run(id: ids.runD))
        #expect(waitingJoin.status == .waitingForDependencies)
        #expect(waitingJoin.upstreamRunIDs == [ids.runB])
        #expect(!firstCompleted.effects.contains(.wait(runID: ids.runD, workflowID: ids.workflow, taskID: ids.taskD, duration: 0)))

        let secondCompleted = AutomationReducer.reduce(
            state: firstCompleted.state,
            action: .taskFinished(runID: ids.runC, outcome: .succeeded(report: nil), at: secondCompletedAt),
            environment: env
        )

        let startedJoin = try #require(secondCompleted.state.run(id: ids.runD))
        #expect(startedJoin.status == .running)
        #expect(startedJoin.actualStartTime == secondCompletedAt)
        #expect(startedJoin.upstreamRunIDs == [ids.runB, ids.runC])
        #expect(secondCompleted.effects.contains(.wait(runID: ids.runD, workflowID: ids.workflow, taskID: ids.taskD, duration: 0)))
    }

    @Test("Any join uses the earliest ready incoming dependency")
    func anyJoinUsesEarliestReadyIncomingDependency() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let firstCompletedAt = Date(timeIntervalSince1970: 100)
        let secondCompletedAt = Date(timeIntervalSince1970: 110)
        let first = delayTask(id: ids.taskB)
        let second = delayTask(id: ids.taskC)
        let joined = delayTask(id: ids.taskD, joinPolicy: .any)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Any join",
            tasks: [first, second, joined],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskB, toTaskID: ids.taskD, trigger: .onSuccess, delay: 60),
                AutomationDependency(fromTaskID: ids.taskC, toTaskID: ids.taskD, trigger: .onSuccess)
            ]
        )
        let initial = AutomationRunState(
            workflows: [workflow],
            runs: [
                AutomationTaskRun(
                    id: ids.runB,
                    executionID: ids.runA,
                    workflowID: ids.workflow,
                    taskID: ids.taskB,
                    actualStartTime: start,
                    status: .running,
                    createdAt: start
                ),
                AutomationTaskRun(
                    id: ids.runC,
                    executionID: ids.runA,
                    workflowID: ids.workflow,
                    taskID: ids.taskC,
                    actualStartTime: start,
                    status: .running,
                    createdAt: start
                )
            ]
        )
        let env = environment(ids.runD)

        let firstCompleted = AutomationReducer.reduce(
            state: initial,
            action: .taskFinished(runID: ids.runB, outcome: .succeeded(report: nil), at: firstCompletedAt),
            environment: env
        )

        let plannedJoin = try #require(firstCompleted.state.run(id: ids.runD))
        #expect(plannedJoin.status == .planned)
        #expect(plannedJoin.earliestStartTime == firstCompletedAt.addingTimeInterval(60))
        #expect(plannedJoin.upstreamRunIDs == [ids.runB])

        let secondCompleted = AutomationReducer.reduce(
            state: firstCompleted.state,
            action: .taskFinished(runID: ids.runC, outcome: .succeeded(report: nil), at: secondCompletedAt),
            environment: env
        )

        let startedJoin = try #require(secondCompleted.state.run(id: ids.runD))
        #expect(startedJoin.status == .running)
        #expect(startedJoin.actualStartTime == secondCompletedAt)
        #expect(startedJoin.earliestStartTime == secondCompletedAt)
        #expect(startedJoin.upstreamRunIDs == [ids.runC])
        #expect(secondCompleted.state.runs.filter { $0.taskID == ids.taskD }.count == 1)
        #expect(secondCompleted.effects.contains(.wait(runID: ids.runD, workflowID: ids.workflow, taskID: ids.taskD, duration: 0)))
    }

    @Test("First matched join locks the first completed incoming dependency")
    func firstMatchedJoinLocksFirstCompletedIncomingDependency() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let firstCompletedAt = Date(timeIntervalSince1970: 100)
        let secondCompletedAt = Date(timeIntervalSince1970: 110)
        let dueAt = firstCompletedAt.addingTimeInterval(60)
        let first = delayTask(id: ids.taskB)
        let second = delayTask(id: ids.taskC)
        let joined = delayTask(id: ids.taskD, joinPolicy: .firstMatched)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "First matched join",
            tasks: [first, second, joined],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskB, toTaskID: ids.taskD, trigger: .onSuccess, delay: 60),
                AutomationDependency(fromTaskID: ids.taskC, toTaskID: ids.taskD, trigger: .onSuccess)
            ]
        )
        let initial = AutomationRunState(
            workflows: [workflow],
            runs: [
                AutomationTaskRun(
                    id: ids.runB,
                    executionID: ids.runA,
                    workflowID: ids.workflow,
                    taskID: ids.taskB,
                    actualStartTime: start,
                    status: .running,
                    createdAt: start
                ),
                AutomationTaskRun(
                    id: ids.runC,
                    executionID: ids.runA,
                    workflowID: ids.workflow,
                    taskID: ids.taskC,
                    actualStartTime: start,
                    status: .running,
                    createdAt: start
                )
            ]
        )
        let env = environment(ids.runD)

        let firstCompleted = AutomationReducer.reduce(
            state: initial,
            action: .taskFinished(runID: ids.runB, outcome: .succeeded(report: nil), at: firstCompletedAt),
            environment: env
        )
        let secondCompleted = AutomationReducer.reduce(
            state: firstCompleted.state,
            action: .taskFinished(runID: ids.runC, outcome: .succeeded(report: nil), at: secondCompletedAt),
            environment: env
        )

        let lockedJoin = try #require(secondCompleted.state.run(id: ids.runD))
        #expect(lockedJoin.status == .planned)
        #expect(lockedJoin.earliestStartTime == dueAt)
        #expect(lockedJoin.upstreamRunIDs == [ids.runB])
        #expect(!secondCompleted.effects.contains(.wait(runID: ids.runD, workflowID: ids.workflow, taskID: ids.taskD, duration: 0)))

        let due = AutomationReducer.reduce(
            state: secondCompleted.state,
            action: .clockTick(dueAt),
            environment: env
        )

        let startedJoin = try #require(due.state.run(id: ids.runD))
        #expect(startedJoin.status == .running)
        #expect(startedJoin.actualStartTime == dueAt)
        #expect(startedJoin.upstreamRunIDs == [ids.runB])
        #expect(due.effects.contains(.wait(runID: ids.runD, workflowID: ids.workflow, taskID: ids.taskD, duration: 0)))
    }

    @Test("Clock tick times out running macro, cancels player, releases lease, and triggers timeout branch")
    func clockTickTimesOutRunningMacroAndTriggersTimeoutBranch() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let playerStartedAt = Date(timeIntervalSince1970: 101)
        let tickAt = Date(timeIntervalSince1970: 107)
        let deadline = Date(timeIntervalSince1970: 106)
        let lease = AutomationResourceLease(
            id: ids.leaseA,
            runID: ids.runA,
            resource: .foregroundInput,
            acquiredAt: start
        )
        let taskA = macroTask(id: ids.taskA, macroID: ids.macroA, timeout: 5)
        let timeoutTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Timeout watchdog",
            tasks: [taskA, timeoutTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onTimeout)
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
        result = AutomationReducer.reduce(
            state: result.state,
            action: .playerStarted(runID: ids.runA, at: playerStartedAt),
            environment: env
        )

        let timedOut = AutomationReducer.reduce(
            state: result.state,
            action: .clockTick(tickAt),
            environment: env
        )

        let timedOutRun = try #require(timedOut.state.run(id: ids.runA))
        let downstreamRun = try #require(timedOut.state.run(id: ids.runB))
        #expect(timedOutRun.status == .completed)
        #expect(timedOutRun.outcome == .timedOut(deadline: deadline))
        #expect(timedOutRun.completedAt == tickAt)
        #expect(timedOutRun.actualStartTime == playerStartedAt)
        #expect(timedOutRun.leaseID == nil)
        #expect(timedOut.state.leases.isEmpty)
        #expect(downstreamRun.taskID == ids.taskB)
        #expect(downstreamRun.executionID == ids.runA)
        #expect(downstreamRun.upstreamRunIDs == [ids.runA])
        #expect(downstreamRun.actualStartTime == tickAt)
        #expect(timedOut.effects == [
            .cancelPlayer(runID: ids.runA),
            .releaseResource(runID: ids.runA, lease: lease),
            .persistRun(timedOutRun),
            .wait(runID: ids.runB, workflowID: ids.workflow, taskID: ids.taskB, duration: 0)
        ])
    }

    @Test("Clock tick times out queued macro when Player has not reported start")
    func clockTickTimesOutQueuedMacroBeforePlayerStarts() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 200)
        let tickAt = Date(timeIntervalSince1970: 206)
        let deadline = Date(timeIntervalSince1970: 205)
        let task = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: .none,
            timeout: 5
        )
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Queued timeout", tasks: [task])
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: environment(ids.runA)
        )

        #expect(started.state.run(id: ids.runA)?.status == .queued)
        #expect(started.state.run(id: ids.runA)?.actualStartTime == start)
        #expect(started.effects == [
            .startPlayer(runID: ids.runA, workflowID: ids.workflow, taskID: ids.taskA, macroID: ids.macroA)
        ])

        let timedOut = AutomationReducer.reduce(
            state: started.state,
            action: .clockTick(tickAt),
            environment: environment()
        )

        let timedOutRun = try #require(timedOut.state.run(id: ids.runA))
        #expect(timedOutRun.status == .completed)
        #expect(timedOutRun.outcome == .timedOut(deadline: deadline))
        #expect(timedOutRun.completedAt == tickAt)
        #expect(timedOutRun.actualStartTime == start)
        #expect(timedOut.effects == [
            .cancelPlayer(runID: ids.runA),
            .persistRun(timedOutRun)
        ])
    }

    @Test("Clock tick does not apply task timeout while run is waiting for resource")
    func clockTickDoesNotTimeoutWhileWaitingForResource() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 300)
        let tickAt = Date(timeIntervalSince1970: 310)
        let task = macroTask(id: ids.taskA, macroID: ids.macroA, timeout: 5)
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Resource wait is not task timeout", tasks: [task])
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: environment(ids.runA)
        )

        let ticked = AutomationReducer.reduce(
            state: started.state,
            action: .clockTick(tickAt),
            environment: environment()
        )

        let run = try #require(ticked.state.run(id: ids.runA))
        #expect(run.status == .waitingForResource)
        #expect(run.outcome == nil)
        #expect(run.completedAt == nil)
        #expect(run.actualStartTime == nil)
        #expect(ticked.effects == [
            .requestResource(runID: ids.runA, requirement: .foregroundInput)
        ])
    }

    @Test("Retryable failure creates next attempt and delays failure branch until attempts are exhausted")
    func retryableFailureCreatesNextAttemptBeforeFailureBranch() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 400)
        let firstFailedAt = Date(timeIntervalSince1970: 405)
        let secondFailedAt = Date(timeIntervalSince1970: 410)
        let taskA = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: .none,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 2)
        )
        let failureTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Retry failure",
            tasks: [taskA, failureTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onFailure)
            ]
        )
        let env = environment(ids.runA, ids.runB, ids.runC)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let firstFailure = AutomationReducer.reduce(
            state: started.state,
            action: .playerFinished(runID: ids.runA, outcome: .failed(report: nil), at: firstFailedAt),
            environment: env
        )

        let firstAttempt = try #require(firstFailure.state.run(id: ids.runA))
        let retryRun = try #require(firstFailure.state.run(id: ids.runB))
        #expect(firstAttempt.status == .completed)
        #expect(firstAttempt.outcome == .failed(report: nil))
        #expect(retryRun.taskID == ids.taskA)
        #expect(retryRun.executionID == ids.runA)
        #expect(retryRun.attempt == 2)
        #expect(retryRun.status == .queued)
        #expect(retryRun.earliestStartTime == firstFailedAt)
        #expect(retryRun.actualStartTime == firstFailedAt)
        #expect(!firstFailure.state.runs.contains { $0.taskID == ids.taskB })
        #expect(firstFailure.effects == [
            .persistRun(firstAttempt),
            .startPlayer(runID: ids.runB, workflowID: ids.workflow, taskID: ids.taskA, macroID: ids.macroA)
        ])

        let finalFailure = AutomationReducer.reduce(
            state: firstFailure.state,
            action: .playerFinished(runID: ids.runB, outcome: .failed(report: nil), at: secondFailedAt),
            environment: env
        )

        let retryAttempt = try #require(finalFailure.state.run(id: ids.runB))
        let downstreamRun = try #require(finalFailure.state.run(id: ids.runC))
        #expect(retryAttempt.status == .completed)
        #expect(retryAttempt.outcome == .failed(report: nil))
        #expect(downstreamRun.taskID == ids.taskB)
        #expect(downstreamRun.executionID == ids.runA)
        #expect(downstreamRun.upstreamRunIDs == [ids.runB])
        #expect(downstreamRun.actualStartTime == secondFailedAt)
        #expect(finalFailure.effects == [
            .persistRun(retryAttempt),
            .wait(runID: ids.runC, workflowID: ids.workflow, taskID: ids.taskB, duration: 0)
        ])
    }

    @Test("Retry backoff keeps next attempt planned until its retry time")
    func retryBackoffPlansNextAttemptUntilDue() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 500)
        let failedAt = Date(timeIntervalSince1970: 505)
        let dueAt = Date(timeIntervalSince1970: 515)
        let task = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: .none,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 2, backoff: .fixed(10))
        )
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Retry backoff", tasks: [task])
        let env = environment(ids.runA, ids.runB)
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

        let failedRun = try #require(failed.state.run(id: ids.runA))
        let retryRun = try #require(failed.state.run(id: ids.runB))
        #expect(retryRun.status == .planned)
        #expect(retryRun.attempt == 2)
        #expect(retryRun.earliestStartTime == dueAt)
        #expect(retryRun.actualStartTime == nil)
        #expect(failed.effects == [
            .persistRun(failedRun)
        ])

        let earlyTick = AutomationReducer.reduce(
            state: failed.state,
            action: .clockTick(dueAt.addingTimeInterval(-1)),
            environment: env
        )
        #expect(earlyTick.state.run(id: ids.runB)?.status == .planned)
        #expect(earlyTick.effects.isEmpty)

        let dueTick = AutomationReducer.reduce(
            state: earlyTick.state,
            action: .clockTick(dueAt),
            environment: env
        )
        #expect(dueTick.state.run(id: ids.runB)?.status == .queued)
        #expect(dueTick.state.run(id: ids.runB)?.actualStartTime == dueAt)
        #expect(dueTick.effects == [
            .startPlayer(runID: ids.runB, workflowID: ids.workflow, taskID: ids.taskA, macroID: ids.macroA)
        ])
    }

    @Test("Timeout retry suppresses timeout branch until final attempt")
    func timeoutRetrySuppressesTimeoutBranchUntilFinalAttempt() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 600)
        let firstTick = Date(timeIntervalSince1970: 606)
        let secondTick = Date(timeIntervalSince1970: 612)
        let taskA = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: .none,
            timeout: 5,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 2)
        )
        let timeoutTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Retry timeout",
            tasks: [taskA, timeoutTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskB, trigger: .onTimeout)
            ]
        )
        let env = environment(ids.runA, ids.runB, ids.runC)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let firstTimeout = AutomationReducer.reduce(
            state: started.state,
            action: .clockTick(firstTick),
            environment: env
        )

        let firstAttempt = try #require(firstTimeout.state.run(id: ids.runA))
        let retryRun = try #require(firstTimeout.state.run(id: ids.runB))
        #expect(firstAttempt.outcome == .timedOut(deadline: start.addingTimeInterval(5)))
        #expect(retryRun.taskID == ids.taskA)
        #expect(retryRun.attempt == 2)
        #expect(retryRun.status == .queued)
        #expect(retryRun.actualStartTime == firstTick)
        #expect(!firstTimeout.state.runs.contains { $0.taskID == ids.taskB })
        #expect(firstTimeout.effects == [
            .cancelPlayer(runID: ids.runA),
            .persistRun(firstAttempt),
            .startPlayer(runID: ids.runB, workflowID: ids.workflow, taskID: ids.taskA, macroID: ids.macroA)
        ])

        let finalTimeout = AutomationReducer.reduce(
            state: firstTimeout.state,
            action: .clockTick(secondTick),
            environment: env
        )

        let finalAttempt = try #require(finalTimeout.state.run(id: ids.runB))
        let downstreamRun = try #require(finalTimeout.state.run(id: ids.runC))
        #expect(finalAttempt.outcome == .timedOut(deadline: firstTick.addingTimeInterval(5)))
        #expect(downstreamRun.taskID == ids.taskB)
        #expect(downstreamRun.executionID == ids.runA)
        #expect(downstreamRun.upstreamRunIDs == [ids.runB])
        #expect(finalTimeout.effects == [
            .cancelPlayer(runID: ids.runB),
            .persistRun(finalAttempt),
            .wait(runID: ids.runC, workflowID: ids.workflow, taskID: ids.taskB, duration: 0)
        ])
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

    @Test("Resource denied keeps run waiting without terminal failure")
    func resourceDeniedKeepsRunWaitingWithoutTerminalFailure() throws {
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
        #expect(run.status == .waitingForResource)
        #expect(run.outcome == nil)
        #expect(run.completedAt == nil)
        #expect(run.leaseID == nil)
        #expect(denied.effects.isEmpty)
    }

    @Test("Resource release retries waiting runs before new downstream work")
    func resourceReleaseRetriesWaitingRunsBeforeDownstreamWork() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 200)
        let completedAt = Date(timeIntervalSince1970: 205)
        let deniedAt = Date(timeIntervalSince1970: 201)
        let lease = AutomationResourceLease(
            id: ids.leaseA,
            runID: ids.runA,
            resource: .foregroundInput,
            acquiredAt: start
        )
        let activeTask = macroTask(id: ids.taskA, macroID: ids.macroA)
        let waitingTask = macroTask(id: ids.taskB, macroID: ids.macroB)
        let downstreamTask = macroTask(id: ids.taskC, macroID: ids.macroB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Resource queue",
            tasks: [activeTask, waitingTask, downstreamTask],
            dependencies: [
                AutomationDependency(fromTaskID: ids.taskA, toTaskID: ids.taskC, trigger: .onSuccess)
            ]
        )
        let env = environment(ids.runA, ids.runB, ids.runC)
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
        result = AutomationReducer.reduce(
            state: result.state,
            action: .playerStarted(runID: ids.runA, at: start),
            environment: env
        )
        result = AutomationReducer.reduce(
            state: result.state,
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskB, requestedAt: start.addingTimeInterval(1)),
            environment: env
        )
        result = AutomationReducer.reduce(
            state: result.state,
            action: .resourceLeaseDenied(runID: ids.runB, resource: .foregroundInput, at: deniedAt),
            environment: env
        )

        let completed = AutomationReducer.reduce(
            state: result.state,
            action: .playerFinished(runID: ids.runA, outcome: .succeeded(report: nil), at: completedAt),
            environment: env
        )

        let waitingRun = try #require(completed.state.run(id: ids.runB))
        let downstreamRun = try #require(completed.state.run(id: ids.runC))
        let activeCompletedRun = try #require(completed.state.run(id: ids.runA))
        #expect(waitingRun.status == .waitingForResource)
        #expect(waitingRun.outcome == nil)
        #expect(downstreamRun.status == .waitingForResource)
        #expect(Array(completed.effects.prefix(3)) == [
            .releaseResource(runID: ids.runA, lease: lease),
            .persistRun(activeCompletedRun),
            .requestResource(runID: ids.runB, requirement: .foregroundInput)
        ])
        #expect(completed.effects.contains(.requestResource(runID: ids.runC, requirement: .foregroundInput)))
    }

    @Test("Clock tick retries runs waiting for resources")
    func clockTickRetriesRunsWaitingForResources() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 300)
        let deniedAt = Date(timeIntervalSince1970: 301)
        let tickAt = Date(timeIntervalSince1970: 330)
        let task = macroTask(id: ids.taskA, macroID: ids.macroA)
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Retry resource", tasks: [task])
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

        let retried = AutomationReducer.reduce(
            state: denied.state,
            action: .clockTick(tickAt),
            environment: environment(ids.runB)
        )

        let run = try #require(retried.state.run(id: ids.runA))
        #expect(run.status == .waitingForResource)
        #expect(run.outcome == nil)
        #expect(retried.effects == [
            .requestResource(runID: ids.runA, requirement: .foregroundInput)
        ])
    }

    @Test("Clock tick times out resource waits after max wait duration and triggers timeout branch")
    func clockTickTimesOutResourceWaitAfterMaxWaitDuration() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 400)
        let deniedAt = Date(timeIntervalSince1970: 401)
        let tickAt = Date(timeIntervalSince1970: 406)
        let requirement = AutomationResourceRequirement(
            resources: [.foregroundInput],
            maxWaitDuration: 5
        )
        let waitingTask = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: requirement
        )
        let timeoutTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Resource wait timeout",
            tasks: [waitingTask, timeoutTask],
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
        let denied = AutomationReducer.reduce(
            state: started.state,
            action: .resourceLeaseDenied(runID: ids.runA, resource: .foregroundInput, at: deniedAt),
            environment: env
        )

        let timedOut = AutomationReducer.reduce(
            state: denied.state,
            action: .clockTick(tickAt),
            environment: env
        )

        let completedRun = try #require(timedOut.state.run(id: ids.runA))
        let timeoutRun = try #require(timedOut.state.run(id: ids.runB))
        let deadline = start.addingTimeInterval(5)
        #expect(completedRun.outcome == .timedOut(deadline: deadline))
        #expect(completedRun.completedAt == tickAt)
        #expect(timeoutRun.status == .running)
        #expect(timeoutRun.upstreamRunIDs == [ids.runA])
        #expect(timedOut.effects == [
            .persistRun(completedRun),
            .wait(runID: ids.runB, workflowID: ids.workflow, taskID: ids.taskB, duration: 0)
        ])
    }

    @Test("Late resource denial times out an already expired resource wait")
    func resourceLeaseDeniedTimesOutExpiredResourceWaitImmediately() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 500)
        let deniedAt = Date(timeIntervalSince1970: 506)
        let requirement = AutomationResourceRequirement(
            resources: [.foregroundInput],
            maxWaitDuration: 5
        )
        let task = macroTask(
            id: ids.taskA,
            macroID: ids.macroA,
            resourceRequirement: requirement
        )
        let workflow = AutomationWorkflow(id: ids.workflow, name: "Late denial", tasks: [task])
        let env = environment(ids.runA)
        let started = AutomationReducer.reduce(
            state: AutomationRunState(workflows: [workflow]),
            action: .manualStart(workflowID: ids.workflow, taskID: ids.taskA, requestedAt: start),
            environment: env
        )

        let denied = AutomationReducer.reduce(
            state: started.state,
            action: .resourceLeaseDenied(runID: ids.runA, resource: .foregroundInput, at: deniedAt),
            environment: env
        )

        let completedRun = try #require(denied.state.run(id: ids.runA))
        #expect(completedRun.outcome == .timedOut(deadline: start.addingTimeInterval(5)))
        #expect(completedRun.completedAt == deniedAt)
        #expect(denied.effects == [.persistRun(completedRun)])
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

    @Test("Condition evaluation result persists diagnostics before branch resolution")
    func conditionEvaluationResultPersistsDiagnosticsBeforeBranchResolution() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 104)
        let conditionID = UUID(uuidString: "00000000-0000-0000-0000-000000000016")!
        let condition = AutomationConditionSpec(
            id: conditionID,
            name: "Watch leave button",
            kind: .visual(AutomationVisualCondition(
                type: .imageAppeared,
                imageRef: "leave_button_template",
                threshold: 0.92
            ))
        )
        let conditionTask = AutomationTask(
            id: ids.taskA,
            name: "Watch leave button",
            kind: .condition(condition),
            resourceRequirement: .none
        )
        let targetTask = delayTask(id: ids.taskB)
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Condition evidence",
            tasks: [conditionTask, targetTask],
            dependencies: [
                AutomationDependency(
                    fromTaskID: ids.taskA,
                    toTaskID: ids.taskB,
                    trigger: .onConditionMatched
                )
            ]
        )
        let evidence = AutomationConditionEvaluationEvidence(
            runID: ids.runA,
            workflowID: ids.workflow,
            taskID: ids.taskA,
            conditionID: conditionID,
            kind: .imageAppeared,
            outcome: .conditionMatched,
            evaluatedAt: completedAt,
            firstSampleAt: start,
            lastSampleAt: completedAt,
            sampleCount: 4,
            displayBounds: RectValue(x: 0, y: 0, width: 1_440, height: 900),
            resolvedSearchRegion: RectValue(x: 200, y: 300, width: 180, height: 90),
            searchRegionSpace: .displayAbsolute,
            targetDescription: "leave_button_template",
            observedSummary: "Template similarity 0.96",
            score: 0.96,
            threshold: 0.92,
            fields: [
                AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: "leave_button_template")
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
            action: .conditionEvaluationCompleted(
                runID: ids.runA,
                result: AutomationConditionEvaluationResult(outcome: .conditionMatched, evidence: evidence),
                at: completedAt
            ),
            environment: env
        )

        let completedRun = try #require(completed.state.run(id: ids.runA))
        #expect(completedRun.conditionEvidence == evidence)
        #expect(completedRun.outcome == .conditionMatched)
        #expect(completed.state.runs.contains { $0.id == ids.runB && $0.taskID == ids.taskB })
        #expect(completed.effects.contains { effect in
            if case .persistRun(let persistedRun) = effect {
                return persistedRun.id == ids.runA &&
                    persistedRun.conditionEvidence == evidence &&
                    persistedRun.outcome == .conditionMatched
            }
            return false
        })
    }

    @Test("Dynamic dependency delay schedules downstream from condition evidence duration")
    func dynamicDependencyDelaySchedulesDownstreamFromConditionEvidenceDuration() throws {
        let ids = TestIDs()
        let start = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 104)
        let conditionID = UUID(uuidString: "00000000-0000-0000-0000-000000000017")!
        let condition = AutomationConditionSpec(
            id: conditionID,
            name: "Read crop timer",
            kind: .ocrText(AutomationOCRCondition(text: "mature"))
        )
        let conditionTask = AutomationTask(
            id: ids.taskA,
            name: "Read crop timer",
            kind: .condition(condition),
            resourceRequirement: .none
        )
        let targetTask = delayTask(id: ids.taskB)
        let dependency = AutomationDependency(
            fromTaskID: ids.taskA,
            toTaskID: ids.taskB,
            trigger: .onConditionMatched,
            delay: 30,
            dynamicDelay: AutomationDependencyDynamicDelay(
                fallbackDelay: 30,
                maximumDelay: 7_200
            )
        )
        let workflow = AutomationWorkflow(
            id: ids.workflow,
            name: "Crop timer",
            tasks: [conditionTask, targetTask],
            dependencies: [dependency]
        )
        let evidence = AutomationConditionEvaluationEvidence(
            runID: ids.runA,
            workflowID: ids.workflow,
            taskID: ids.taskA,
            conditionID: conditionID,
            kind: .ocrText,
            outcome: .conditionMatched,
            evaluatedAt: completedAt,
            targetDescription: "Crop timer",
            observedSummary: "Detected text: mature in 1h 30m",
            fields: [
                AutomationConditionDiagnosticField(id: "lastTexts", title: "Last texts", value: "1h 30m")
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
            action: .conditionEvaluationCompleted(
                runID: ids.runA,
                result: AutomationConditionEvaluationResult(outcome: .conditionMatched, evidence: evidence),
                at: completedAt
            ),
            environment: env
        )

        let downstreamRun = try #require(completed.state.run(id: ids.runB))
        let sourceRun = try #require(completed.state.run(id: ids.runA))
        let branchEvidence = try #require(sourceRun.branchEvidence?.first)
        #expect(downstreamRun.status == .planned)
        #expect(downstreamRun.earliestStartTime == completedAt.addingTimeInterval(5_400))
        #expect(downstreamRun.upstreamRunIDs == [ids.runA])
        #expect(branchEvidence.delay == 5_400)
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
        var expectedState = state
        expectedState.now = editedAt

        #expect(result.state == expectedState)
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
        resourceRequirement: AutomationResourceRequirement = .foregroundInput,
        timeout: TimeInterval? = nil,
        retryPolicy: AutomationRetryPolicy = .none
    ) -> AutomationTask {
        AutomationTask(
            id: id,
            name: "Macro \(id.uuidString.prefix(4))",
            kind: .macro(macroID: macroID),
            schedule: schedule,
            resourceRequirement: resourceRequirement,
            timeout: timeout,
            retryPolicy: retryPolicy
        )
    }

    private func delayTask(id: UUID, joinPolicy: AutomationJoinPolicy = .all) -> AutomationTask {
        AutomationTask(
            id: id,
            name: "Delay \(id.uuidString.prefix(4))",
            kind: .delay(0),
            resourceRequirement: .none,
            joinPolicy: joinPolicy
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
