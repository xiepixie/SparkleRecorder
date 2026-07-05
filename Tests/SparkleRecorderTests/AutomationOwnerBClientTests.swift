import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Owner B Client Tests")
struct AutomationOwnerBClientTests {
    @Test("Resource arbiter allows one foreground input lease and releases idempotently")
    func resourceArbiterForegroundInputLeaseIsExclusive() async throws {
        let store = AutomationResourceLeaseStore()
        let firstLeaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let client = AutomationResourceArbiterClient.live(store: store, leaseID: { firstLeaseID })
        let firstRunID = UUID()
        let secondRunID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 100)

        let first = await client.acquire(AutomationResourceRequest(
            runID: firstRunID,
            resource: .foregroundInput,
            requestedAt: requestedAt
        ))
        let firstLease = try #require(first.lease)
        let second = await client.acquire(AutomationResourceRequest(
            runID: secondRunID,
            resource: .foregroundInput,
            requestedAt: requestedAt.addingTimeInterval(1)
        ))

        #expect(firstLease.id == firstLeaseID)
        #expect(firstLease.runID == firstRunID)
        #expect(second.deniedResource == .foregroundInput)

        await client.release(firstLease.id)
        await client.release(firstLease.id)

        let third = await client.acquire(AutomationResourceRequest(
            runID: secondRunID,
            resource: .foregroundInput,
            requestedAt: requestedAt.addingTimeInterval(2)
        ))
        let thirdLease = try #require(third.lease)

        #expect(thirdLease.runID == secondRunID)
        #expect(await store.allLeases().map(\.runID) == [secondRunID])
    }

    @Test("Resource arbiter panic release clears orphaned leases by run ID")
    func resourceArbiterPanicReleaseClearsRunLeases() async throws {
        let store = AutomationResourceLeaseStore()
        let client = AutomationResourceArbiterClient.live(store: store)
        let runID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 200)

        let lease = try #require(await client.acquire(AutomationResourceRequest(
            runID: runID,
            resource: .foregroundInput,
            requestedAt: requestedAt
        )).lease)

        #expect(lease.runID == runID)

        await client.panicRelease(runID)
        await client.panicRelease(runID)

        #expect(await store.allLeases().isEmpty)
    }

    @Test("Resource arbiter can release expired leases for watchdog paths")
    func resourceArbiterReleasesExpiredLeases() async throws {
        let store = AutomationResourceLeaseStore()
        let leaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let client = AutomationResourceArbiterClient.live(store: store, leaseID: { leaseID })
        let runID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 300)

        let lease = try #require(await client.acquire(AutomationResourceRequest(
            runID: runID,
            resource: .foregroundInput,
            requestedAt: requestedAt,
            leaseTimeout: 5
        )).lease)
        let released = await client.releaseExpired(requestedAt.addingTimeInterval(6))

        #expect(lease.expiresAt == requestedAt.addingTimeInterval(5))
        #expect(released.map(\.id) == [leaseID])
        #expect(await store.allLeases().isEmpty)
    }

    @Test("Player client start and completion results map to reducer actions")
    func playerClientResultsMapToActions() {
        let runID = UUID()
        let at = Date(timeIntervalSince1970: 400)
        let rejected = AutomationOutcome.missingMacro(macroID: UUID())

        #expect(AutomationPlayerStartResult.started.action(runID: runID, at: at) == .playerStarted(runID: runID, at: at))
        #expect(AutomationPlayerStartResult.rejected(rejected).action(runID: runID, at: at) == .playerFinished(runID: runID, outcome: rejected, at: at))
        #expect(AutomationPlayerCompletion.cancelled(reason: "User stopped").action(runID: runID, at: at) == .playerFinished(runID: runID, outcome: .cancelled(reason: "User stopped"), at: at))
    }

    @Test("Scheduler client emits actions without referencing Player")
    func schedulerClientMapsEventsToActions() async {
        let workflowID = UUID()
        let taskID = UUID()
        let tickAt = Date(timeIntervalSince1970: 500)
        let manualAt = Date(timeIntervalSince1970: 501)
        let scheduler = AutomationSchedulerClient.fixed([
            .clockTick(tickAt),
            .manualTrigger(workflowID: workflowID, taskID: taskID, at: manualAt)
        ])

        var actions: [AutomationAction] = []
        for await action in scheduler.actions() {
            actions.append(action)
        }

        #expect(actions == [
            .clockTick(tickAt),
            .manualStart(workflowID: workflowID, taskID: taskID, requestedAt: manualAt)
        ])
    }

    @Test("Repository saves workflows and appends run history in automations JSON")
    func repositorySavesWorkflowsAndAppendsRunHistory() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderAutomationRepository-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let client = AutomationRepositoryClient.fileBacked(directoryURL: directoryURL)
        let workflowID = UUID()
        let macroID = UUID()
        let task = AutomationTask(
            name: "Nightly macro",
            kind: .macro(macroID: macroID),
            schedule: .manual
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Nightly workflow",
            tasks: [task],
            createdAt: Date(timeIntervalSince1970: 600),
            modifiedAt: Date(timeIntervalSince1970: 601)
        )
        let firstRun = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            scheduledStartTime: Date(timeIntervalSince1970: 610),
            createdAt: Date(timeIntervalSince1970: 610)
        )
        let secondRun = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            scheduledStartTime: Date(timeIntervalSince1970: 620),
            createdAt: Date(timeIntervalSince1970: 620)
        )

        try await client.saveWorkflows([workflow])
        try await client.appendRun(firstRun)
        try await client.appendRun(secondRun)

        let loadedWorkflows = try await client.loadWorkflows()
        let runHistory = try await client.loadRunHistory()
        let documentData = try Data(contentsOf: AutomationPersistence.fileURL(in: directoryURL))
        let document = try JSONDecoder().decode(AutomationPersistenceDocument.self, from: documentData)

        #expect(loadedWorkflows == [workflow])
        #expect(runHistory.map(\.id) == [firstRun.id, secondRun.id])
        #expect(Set(runHistory.map(\.macroID)) == [macroID])
        #expect(document.workflows == [workflow])
        #expect(document.runHistory == [firstRun, secondRun])
    }

    @Test("Workflow package round-trips static workflows without run history")
    func workflowPackageRoundTripsStaticWorkflowsWithoutRunHistory() throws {
        let exportedAt = Date(timeIntervalSince1970: 630)
        let workflowID = UUID()
        let task = AutomationTask(
            name: "Exportable task",
            kind: .macro(macroID: UUID()),
            schedule: .manual
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Exportable workflow",
            tasks: [task],
            createdAt: exportedAt,
            modifiedAt: exportedAt
        )
        let run = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            createdAt: exportedAt
        )
        let persistedDocument = AutomationPersistenceDocument(
            workflows: [workflow],
            runHistory: [run]
        )

        let data = try AutomationWorkflowPackage.encode(
            workflows: persistedDocument.workflows,
            exportedAt: exportedAt
        )
        let decoded = try AutomationWorkflowPackage.decode(data)
        let packageText = try #require(String(data: data, encoding: .utf8))

        #expect(AutomationWorkflowPackage.fileExtension == "sparkrec_workflow")
        #expect(AutomationWorkflowPackage.fileURL(in: URL(fileURLWithPath: "/tmp")).lastPathComponent == "workflows.sparkrec_workflow")
        #expect(decoded == AutomationWorkflowPackageDocument(
            exportedAt: exportedAt,
            workflows: [workflow]
        ))
        #expect(!packageText.contains("runHistory"))
        #expect(!packageText.contains(run.id.uuidString))
    }

    @Test("Workflow package import validates version, duplicate IDs, and workflow DAG")
    func workflowPackageValidatesImportBoundaries() throws {
        let exportedAt = Date(timeIntervalSince1970: 640)
        let workflowID = UUID()
        let taskID = UUID()
        let missingTaskID = UUID()
        let dependencyID = UUID()
        let task = AutomationTask(
            id: taskID,
            name: "Invalid package task",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let validWorkflow = AutomationWorkflow(
            id: workflowID,
            name: "Valid package workflow",
            tasks: [task],
            createdAt: exportedAt,
            modifiedAt: exportedAt
        )
        let invalidWorkflow = AutomationWorkflow(
            id: UUID(),
            name: "Invalid package workflow",
            tasks: [task],
            dependencies: [
                AutomationDependency(
                    id: dependencyID,
                    fromTaskID: taskID,
                    toTaskID: missingTaskID,
                    trigger: .always
                )
            ],
            createdAt: exportedAt,
            modifiedAt: exportedAt
        )

        do {
            try AutomationWorkflowPackage.validate(AutomationWorkflowPackageDocument(
                version: 999,
                exportedAt: exportedAt,
                workflows: [validWorkflow]
            ))
            Issue.record("Expected unsupported package version failure")
        } catch let error as AutomationWorkflowPackageError {
            #expect(error == .unsupportedVersion(999))
        } catch {
            Issue.record("Unexpected package version error: \(error)")
        }

        do {
            try AutomationWorkflowPackage.validate(AutomationWorkflowPackageDocument(
                exportedAt: exportedAt,
                workflows: []
            ))
            Issue.record("Expected empty package failure")
        } catch let error as AutomationWorkflowPackageError {
            #expect(error == .emptyPackage)
        } catch {
            Issue.record("Unexpected empty package error: \(error)")
        }

        do {
            try AutomationWorkflowPackage.validate(AutomationWorkflowPackageDocument(
                exportedAt: exportedAt,
                workflows: [validWorkflow, validWorkflow]
            ))
            Issue.record("Expected duplicate workflow ID failure")
        } catch let error as AutomationWorkflowPackageError {
            #expect(error == .duplicateWorkflowIDs([workflowID]))
        } catch {
            Issue.record("Unexpected duplicate workflow ID error: \(error)")
        }

        do {
            try AutomationWorkflowPackage.validate(AutomationWorkflowPackageDocument(
                exportedAt: exportedAt,
                workflows: [invalidWorkflow]
            ))
            Issue.record("Expected invalid workflow failure")
        } catch let error as AutomationWorkflowPackageError {
            #expect(error == .invalidWorkflows([
                AutomationWorkflowPackageValidationFailure(
                    workflowID: invalidWorkflow.id,
                    workflowName: invalidWorkflow.name,
                    issues: [
                        .missingDependencyTarget(
                            dependencyID: dependencyID,
                            taskID: missingTaskID
                        )
                    ]
                )
            ]))
        } catch {
            Issue.record("Unexpected invalid workflow error: \(error)")
        }
    }

    @Test("Repository snapshot client loads workflow and run history into reducer state")
    func repositorySnapshotClientLoadsState() async throws {
        let refreshedAt = Date(timeIntervalSince1970: 650)
        let workflowID = UUID()
        let task = AutomationTask(
            name: "Snapshot task",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Snapshot workflow",
            tasks: [task],
            createdAt: refreshedAt,
            modifiedAt: refreshedAt
        )
        let run = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            createdAt: refreshedAt
        )
        let repository = AutomationRepositoryClient.inMemory(store: AutomationInMemoryRepositoryStore(
            workflows: [workflow],
            runHistory: [run]
        ))
        let snapshotClient = AutomationRepositorySnapshotClient.repositoryBacked(
            repository,
            now: { refreshedAt }
        )

        let result = await snapshotClient.refresh()
        let snapshot = try #require(result.snapshot)
        let state = snapshot.state

        #expect(snapshot.workflows == [workflow])
        #expect(snapshot.runHistory == [run])
        #expect(snapshot.refreshedAt == refreshedAt)
        #expect(state.workflows == [workflow])
        #expect(state.runs == [run])
        #expect(state.now == refreshedAt)
    }

    @Test("Repository snapshot client returns displayable refresh failures")
    func repositorySnapshotClientReturnsFailureResult() async throws {
        struct SnapshotFailure: Error, CustomStringConvertible {
            var description: String { "snapshot failed" }
        }

        let failedAt = Date(timeIntervalSince1970: 660)
        let repository = AutomationRepositoryClient(
            loadWorkflows: { throw SnapshotFailure() },
            saveWorkflows: { _ in },
            loadRunHistory: { [] },
            appendRun: { _ in }
        )
        let snapshotClient = AutomationRepositorySnapshotClient.repositoryBacked(
            repository,
            now: { failedAt }
        )

        let result = await snapshotClient.refresh()
        let failure = try #require(result.failure)

        #expect(failure.message == "snapshot failed")
        #expect(failure.failedAt == failedAt)
        #expect(result.snapshot == nil)
    }

    @Test("Repository refresh client exposes loading and preserves previous snapshot on failure")
    func repositoryRefreshClientExposesLoadingAndPreviousSnapshot() async throws {
        let startedAt = Date(timeIntervalSince1970: 670)
        let failedAt = Date(timeIntervalSince1970: 680)
        let workflowID = UUID()
        let task = AutomationTask(
            name: "Refresh state task",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Refresh state workflow",
            tasks: [task],
            createdAt: startedAt,
            modifiedAt: startedAt
        )
        let run = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            createdAt: startedAt
        )
        let snapshot = AutomationRepositorySnapshot(
            workflows: [workflow],
            runHistory: [run],
            refreshedAt: startedAt
        )
        let stateStore = AutomationRepositoryRefreshStateStore()
        let gate = RepositoryRefreshGate()
        let loadingClient = AutomationRepositoryRefreshClient.stateful(
            snapshotClient: AutomationRepositorySnapshotClient {
                await gate.markStartedAndWait()
                return .loaded(snapshot)
            },
            stateStore: stateStore,
            now: { startedAt }
        )

        #expect(await loadingClient.currentState() == .idle)

        let refreshTask = Task {
            await loadingClient.refresh()
        }
        await gate.waitUntilStarted()

        #expect(await loadingClient.currentState() == .loading(
            startedAt: startedAt,
            previousSnapshot: nil
        ))

        await gate.release()
        let loadedState = await refreshTask.value

        #expect(loadedState == .loaded(snapshot))
        #expect(await loadingClient.currentState() == .loaded(snapshot))

        let failure = AutomationRepositoryRefreshFailure(
            message: "refresh failed",
            failedAt: failedAt
        )
        let failingClient = AutomationRepositoryRefreshClient.stateful(
            snapshotClient: AutomationRepositorySnapshotClient {
                .failed(failure)
            },
            stateStore: stateStore,
            now: { failedAt }
        )

        let failedState = await failingClient.refresh()

        #expect(failedState == .failed(failure, previousSnapshot: snapshot))
        #expect(failedState.snapshot == snapshot)
        #expect(failedState.failure == failure)
        #expect(await failingClient.currentState() == .failed(failure, previousSnapshot: snapshot))
    }

    @Test("Effect runner converts resource requests into resource actions")
    func effectRunnerRequestsResources() async throws {
        let runID = UUID()
        let leaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let requestedAt = Date(timeIntervalSince1970: 700)
        let store = AutomationResourceLeaseStore()
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(store: store, leaseID: { leaseID }),
            now: { requestedAt },
            sleep: { _ in }
        )

        let actions = await runner.run(.requestResource(runID: runID, requirement: .foregroundInput))
        let expectedLease = AutomationResourceLease(
            id: leaseID,
            runID: runID,
            resource: .foregroundInput,
            acquiredAt: requestedAt
        )

        #expect(actions == [.resourceLeaseAcquired(runID: runID, lease: expectedLease, at: requestedAt)])
        #expect(await store.allLeases() == [expectedLease])
    }

    @Test("Effect runner acquires multi-resource requests as one batch action")
    func effectRunnerAcquiresMultiResourceRequests() async {
        let runID = UUID()
        let foregroundLeaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let screenLeaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
        let requestedAt = Date(timeIntervalSince1970: 750)
        let store = AutomationResourceLeaseStore()
        let leaseIDs = LockedUUIDSequence([foregroundLeaseID, screenLeaseID])
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(store: store, leaseID: { leaseIDs.next() }),
            now: { requestedAt },
            sleep: { _ in }
        )
        let requirement = AutomationResourceRequirement(
            resources: [.foregroundInput, .screenCapture]
        )
        let foregroundLease = AutomationResourceLease(
            id: foregroundLeaseID,
            runID: runID,
            resource: .foregroundInput,
            acquiredAt: requestedAt
        )
        let screenLease = AutomationResourceLease(
            id: screenLeaseID,
            runID: runID,
            resource: .screenCapture,
            acquiredAt: requestedAt
        )

        let actions = await runner.run(.requestResource(runID: runID, requirement: requirement))

        #expect(actions == [.resourceLeasesAcquired(
            runID: runID,
            leases: [foregroundLease, screenLease],
            at: requestedAt
        )])
        #expect(await store.allLeases() == [foregroundLease, screenLease])
    }

    @Test("Effect runner releases acquired leases when a later resource is denied")
    func effectRunnerReleasesPartialMultiResourceAcquisition() async {
        let runID = UUID()
        let blockingRunID = UUID()
        let foregroundLeaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000006")!
        let blockingLeaseID = UUID(uuidString: "10000000-0000-0000-0000-000000000007")!
        let requestedAt = Date(timeIntervalSince1970: 760)
        let blockingLease = AutomationResourceLease(
            id: blockingLeaseID,
            runID: blockingRunID,
            resource: .screenCapture,
            acquiredAt: requestedAt.addingTimeInterval(-10)
        )
        let store = AutomationResourceLeaseStore(initialLeases: [blockingLease])
        let leaseIDs = LockedUUIDSequence([foregroundLeaseID])
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(store: store, leaseID: { leaseIDs.next() }),
            now: { requestedAt },
            sleep: { _ in }
        )
        let requirement = AutomationResourceRequirement(
            resources: [.foregroundInput, .screenCapture]
        )

        let actions = await runner.run(.requestResource(runID: runID, requirement: requirement))

        #expect(actions == [.resourceLeaseDenied(runID: runID, resource: .screenCapture, at: requestedAt)])
        #expect(await store.allLeases() == [blockingLease])
    }

    @Test("Effect runner starts player with loaded macro and emits player actions")
    func effectRunnerStartsPlayer() async throws {
        let runID = UUID()
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let startedAt = Date(timeIntervalSince1970: 800)
        let macro = SavedMacro(id: macroID, name: "Playback", events: TestFixtures.clickPair())
        let recorder = PlayerStartRecorder()
        let player = AutomationPlayerClient(
            start: { request in
                await recorder.record(request)
                return .started
            },
            cancel: { _ in }
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: player,
            loadMacro: { id in id == macroID ? macro : nil },
            now: { startedAt },
            sleep: { _ in }
        )

        let actions = await runner.run(.startPlayer(
            runID: runID,
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID
        ))

        #expect(actions == [.playerStarted(runID: runID, at: startedAt)])
        #expect(await recorder.runIDs == [runID])
        #expect(await recorder.macroIDs == [macroID])
    }

    @Test("Effect runner cancels player through PlayerClient")
    func effectRunnerCancelsPlayer() async {
        let runID = UUID()
        let recorder = PlayerCancelRecorder()
        let player = AutomationPlayerClient(
            start: { _ in .started },
            cancel: { runID in await recorder.record(runID) }
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: player,
            sleep: { _ in }
        )

        let actions = await runner.run(.cancelPlayer(runID: runID))

        #expect(actions.isEmpty)
        #expect(await recorder.runIDs == [runID])
    }

    @Test("Effect runner rejects loaded macros with no playable events")
    func effectRunnerRejectsEmptyMacro() async {
        let runID = UUID()
        let macroID = UUID()
        let at = Date(timeIntervalSince1970: 850)
        let macro = SavedMacro(id: macroID, name: "Empty", events: [])
        let recorder = PlayerStartRecorder()
        let player = AutomationPlayerClient(
            start: { request in
                await recorder.record(request)
                return .started
            },
            cancel: { _ in }
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: player,
            loadMacro: { id in id == macroID ? macro : nil },
            now: { at },
            sleep: { _ in }
        )

        let actions = await runner.run(.startPlayer(
            runID: runID,
            workflowID: UUID(),
            taskID: UUID(),
            macroID: macroID
        ))

        #expect(actions == [.playerFinished(runID: runID, outcome: .rejected(reason: "Macro has no playable events"), at: at)])
        #expect(await recorder.runIDs.isEmpty)
        #expect(await recorder.macroIDs.isEmpty)
    }

    @Test("Effect runner maps missing macro to terminal player action")
    func effectRunnerMapsMissingMacro() async {
        let runID = UUID()
        let macroID = UUID()
        let at = Date(timeIntervalSince1970: 900)
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            loadMacro: { _ in nil },
            now: { at },
            sleep: { _ in }
        )

        let actions = await runner.run(.startPlayer(
            runID: runID,
            workflowID: UUID(),
            taskID: UUID(),
            macroID: macroID
        ))

        #expect(actions == [.playerFinished(runID: runID, outcome: .missingMacro(macroID: macroID), at: at)])
    }

    @Test("Effect runner persists completed runs through repository client")
    func effectRunnerPersistsRuns() async {
        let store = AutomationInMemoryRepositoryStore()
        let task = AutomationTask(name: "Delay", kind: .delay(1), resourceRequirement: .none)
        let run = task.makeRun(workflowID: UUID(), runID: UUID())
            .completed(with: .succeeded(report: nil), at: Date(timeIntervalSince1970: 1_000))
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            repository: .inMemory(store: store),
            sleep: { _ in }
        )

        let actions = await runner.run(.persistRun(run))

        #expect(actions.isEmpty)
        #expect(await store.loadRunHistory() == [run])
    }

    @Test("Effect runner persists workflow edits through repository client")
    func effectRunnerPersistsWorkflowEdits() async {
        let store = AutomationInMemoryRepositoryStore()
        let task = AutomationTask(
            name: "Persistable task",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            name: "Persistable workflow",
            tasks: [task]
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            repository: .inMemory(store: store),
            sleep: { _ in }
        )

        let actions = await runner.run(.persistWorkflows([workflow]))

        #expect(actions.isEmpty)
        #expect(await store.loadWorkflows() == [workflow])
    }

    @Test("Contextual condition evaluator resolves previous outcomes and injected providers")
    func contextualConditionEvaluatorUsesContextAndProviders() async {
        let evaluator = AutomationConditionEvaluatorClient.contextual(
            externalSignal: AutomationExternalSignalClient { signalName in
                signalName == "ready"
            },
            manualApproval: AutomationManualApprovalClient { request in
                request.condition.name == "Approve deploy"
            },
            ocrText: { _, condition in
                condition.text == "Done" ? .conditionMatched : .conditionNotMatched
            }
        )
        let matchedPrevious = AutomationConditionEvaluationRequest(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Previous succeeded",
                kind: .previousOutcome(.success)
            ),
            previousOutcomes: [.failed(report: nil), .succeeded(report: nil)]
        )
        let missingPrevious = AutomationConditionEvaluationRequest(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Previous timed out",
                kind: .previousOutcome(.timeout)
            ),
            previousOutcomes: [.succeeded(report: nil)]
        )
        let readySignal = AutomationConditionEvaluationRequest(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Ready signal",
                kind: .externalSignal("ready")
            )
        )
        let approved = AutomationConditionEvaluationRequest(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Approve deploy",
                kind: .manualApproval
            )
        )
        let ocr = AutomationConditionEvaluationRequest(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Done text",
                kind: .ocrText(AutomationOCRCondition(text: "Done"))
            )
        )

        #expect(await evaluator.evaluate(matchedPrevious) == .conditionMatched)
        #expect(await evaluator.evaluate(missingPrevious) == .conditionNotMatched)
        #expect(await evaluator.evaluate(readySignal) == .conditionMatched)
        #expect(await evaluator.evaluate(approved) == .conditionMatched)
        #expect(await evaluator.evaluate(ocr) == .conditionMatched)
    }

    @Test("Effect runner handles wait and condition effects as actions")
    func effectRunnerHandlesWaitAndConditionEffects() async {
        let runID = UUID()
        let conditionRunID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_100)
        let sleeper = SleepRecorder()
        let condition = AutomationConditionSpec(
            name: "Flag",
            kind: .externalSignal("ready")
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            conditionEvaluator: .constant(.conditionMatched),
            now: { completedAt },
            sleep: { duration in await sleeper.record(duration) }
        )

        let waitActions = await runner.run(.wait(
            runID: runID,
            workflowID: UUID(),
            taskID: UUID(),
            duration: 3
        ))
        let conditionActions = await runner.run(.evaluateCondition(
            runID: conditionRunID,
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            previousOutcomes: [.succeeded(report: nil)]
        ))

        #expect(await sleeper.durations == [3])
        #expect(waitActions == [.taskFinished(runID: runID, outcome: .succeeded(report: nil), at: completedAt)])
        #expect(conditionActions == [.conditionEvaluated(runID: conditionRunID, outcome: .conditionMatched, at: completedAt)])
    }

    @Test("Effect runner forwards previous outcomes to condition evaluator")
    func effectRunnerForwardsPreviousOutcomesToConditionEvaluator() async {
        let runID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_120)
        let recorder = ConditionRequestRecorder()
        let condition = AutomationConditionSpec(
            name: "Previous failed",
            kind: .previousOutcome(.failure)
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            conditionEvaluator: AutomationConditionEvaluatorClient { request in
                await recorder.record(request)
                return .conditionNotMatched
            },
            now: { completedAt },
            sleep: { _ in }
        )
        let previousOutcomes: [AutomationOutcome] = [
            .succeeded(report: nil),
            .failed(report: nil)
        ]

        let actions = await runner.run(.evaluateCondition(
            runID: runID,
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            previousOutcomes: previousOutcomes
        ))

        #expect(await recorder.previousOutcomes == [previousOutcomes])
        #expect(actions == [.conditionEvaluated(runID: runID, outcome: .conditionNotMatched, at: completedAt)])
    }
}

private actor PlayerStartRecorder {
    private var recordedRunIDs: [UUID] = []
    private var recordedMacroIDs: [UUID] = []

    var runIDs: [UUID] {
        recordedRunIDs
    }

    var macroIDs: [UUID] {
        recordedMacroIDs
    }

    func record(_ request: AutomationPlayerStartRequest) {
        recordedRunIDs.append(request.runID)
        recordedMacroIDs.append(request.macro.id)
    }
}

private actor PlayerCancelRecorder {
    private var recordedRunIDs: [UUID] = []

    var runIDs: [UUID] {
        recordedRunIDs
    }

    func record(_ runID: UUID) {
        recordedRunIDs.append(runID)
    }
}

private actor SleepRecorder {
    private var recordedDurations: [TimeInterval] = []

    var durations: [TimeInterval] {
        recordedDurations
    }

    func record(_ duration: TimeInterval) {
        recordedDurations.append(duration)
    }
}

private actor ConditionRequestRecorder {
    private var recordedPreviousOutcomes: [[AutomationOutcome]] = []

    var previousOutcomes: [[AutomationOutcome]] {
        recordedPreviousOutcomes
    }

    func record(_ request: AutomationConditionEvaluationRequest) {
        recordedPreviousOutcomes.append(request.previousOutcomes)
    }
}

private actor RepositoryRefreshGate {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func markStartedAndWait() async {
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if releaseContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class LockedUUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID]

    init(_ ids: [UUID]) {
        self.ids = ids
    }

    func next() -> UUID {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !ids.isEmpty else {
            return UUID()
        }
        return ids.removeFirst()
    }
}
