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
        var secondRun = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            scheduledStartTime: Date(timeIntervalSince1970: 620),
            createdAt: Date(timeIntervalSince1970: 620)
        )
        let branchEvidence = AutomationBranchDecisionEvidence(
            sourceRunID: secondRun.id,
            sourceTaskID: task.id,
            dependencyID: UUID(),
            trigger: .always,
            status: .triggered,
            targetTaskID: task.id,
            targetRunID: nil,
            executionID: secondRun.executionID,
            sourceOutcome: .succeeded(report: nil),
            decidedAt: Date(timeIntervalSince1970: 625),
            delay: 0,
            targetJoinPolicy: .all,
            reason: "Repository round trip"
        )
        let conditionEvidence = AutomationConditionEvaluationEvidence(
            runID: secondRun.id,
            workflowID: workflowID,
            taskID: task.id,
            conditionID: UUID(),
            kind: .pixelMatched,
            outcome: .conditionMatched,
            evaluatedAt: Date(timeIntervalSince1970: 625),
            sampleCount: 2,
            displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 800),
            resolvedSearchRegion: RectValue(x: 50, y: 60, width: 70, height: 80),
            searchRegionSpace: .displayAbsolute,
            targetDescription: "#FFCC00",
            observedSummary: "Pixel similarity 0.98",
            score: 0.98,
            threshold: 0.95,
            fields: [
                AutomationConditionDiagnosticField(id: "currentColor", title: "Current color", value: "#FFCD00")
            ]
        )
        secondRun.conditionEvidence = conditionEvidence
        secondRun.branchEvidence = [branchEvidence]

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
        #expect(runHistory.last?.conditionEvidence == conditionEvidence)
        #expect(runHistory.last?.branchEvidence == [branchEvidence])
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
        let visualAssets = AutomationWorkflowDraftVisualAssets(
            images: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "leave_button",
                    path: "assets/leave-button.png"
                )
            ],
            baselines: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "battle_start",
                    path: "baselines/battle-start.png"
                )
            ]
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Exportable workflow",
            tasks: [task],
            visualAssets: visualAssets,
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
        #expect(decoded.workflows.first?.visualAssets == visualAssets)
        #expect(!packageText.contains("runHistory"))
        #expect(!packageText.contains(run.id.uuidString))
    }

    @Test("Visual asset package roots track workflows with package file assets")
    func visualAssetPackageRootsTrackWorkflowsWithPackageFileAssets() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderVisualAssetRoots-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let packageDirectoryURL = directoryURL
            .appendingPathComponent("BattleDraft", isDirectory: true)
        let replacementDirectoryURL = directoryURL
            .appendingPathComponent("ReplacementDraft", isDirectory: true)
        let associatedAt = Date(timeIntervalSince1970: 650)
        let replacementAt = Date(timeIntervalSince1970: 660)
        let workflowID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Battle loop",
            tasks: [
                AutomationTask(
                    name: "Wait icon",
                    kind: .condition(AutomationConditionSpec(
                        name: "Spinner gone",
                        kind: .visual(AutomationVisualCondition(
                            type: .imageDisappeared,
                            imageRef: "spinner"
                        ))
                    ))
                )
            ],
            visualAssets: AutomationWorkflowDraftVisualAssets(
                images: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "spinner",
                        path: "assets/spinner.png"
                    )
                ]
            ),
            createdAt: associatedAt,
            modifiedAt: associatedAt
        )
        let regionOnlyWorkflow = AutomationWorkflow(
            id: UUID(),
            name: "Region only",
            tasks: [],
            visualAssets: AutomationWorkflowDraftVisualAssets(
                regions: [
                    AutomationWorkflowDraftVisualRegion(
                        key: "arena",
                        bounds: RectValue(x: 0, y: 0, width: 10, height: 10),
                        space: .displayAbsolute
                    )
                ]
            ),
            createdAt: associatedAt,
            modifiedAt: associatedAt
        )

        let roots = AutomationVisualAssetPackageRoot.roots(
            for: [workflow, regionOnlyWorkflow],
            packageDirectoryURL: packageDirectoryURL,
            source: .aiDraftImport,
            associatedAt: associatedAt
        )

        #expect(roots == [
            AutomationVisualAssetPackageRoot(
                workflowID: workflowID,
                packageDirectoryPath: packageDirectoryURL.standardizedFileURL.path,
                source: .aiDraftImport,
                associatedAt: associatedAt
            )
        ])

        let client = AutomationVisualAssetPackageRootClient.fileBacked(directoryURL: directoryURL)
        try await client.upsertRoots(roots)
        #expect(try await client.loadRoots() == roots)

        let replacementRoot = AutomationVisualAssetPackageRoot.roots(
            for: [workflow],
            packageDirectoryURL: replacementDirectoryURL,
            source: .workflowPackageImport,
            associatedAt: replacementAt
        )
        try await client.upsertRoots(replacementRoot)
        #expect(try await client.loadRoots() == replacementRoot)

        try await client.removeRoots(Set([workflowID]))
        #expect(try await client.loadRoots().isEmpty)

        let rootData = try Data(contentsOf: AutomationVisualAssetPackageRoots.fileURL(in: directoryURL))
        let document = try JSONDecoder().decode(AutomationVisualAssetPackageRootDocument.self, from: rootData)
        #expect(document.version == AutomationVisualAssetPackageRoots.currentVersion)
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
        let evaluatedAt = Date(timeIntervalSince1970: 1_095)
        let evaluator = AutomationConditionEvaluatorClient.contextual(
            externalSignal: AutomationExternalSignalClient { signalName in
                signalName == "ready"
            },
            manualApproval: AutomationManualApprovalClient { request in
                request.condition.name == "Approve deploy"
            },
            ocrText: { _, condition in
                condition.text == "Done" ? .conditionMatched : .conditionNotMatched
            },
            visual: { _, condition in
                condition.type == .regionChanged ? .conditionMatched : .conditionNotMatched
            },
            now: { evaluatedAt }
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
        let visual = AutomationConditionEvaluationRequest(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Region changed",
                kind: .visual(AutomationVisualCondition(type: .regionChanged, regionRef: "battle_result_area"))
            )
        )

        #expect(await evaluator.evaluate(matchedPrevious) == .conditionMatched)
        #expect(await evaluator.evaluate(missingPrevious) == .conditionNotMatched)
        #expect(await evaluator.evaluate(readySignal) == .conditionMatched)
        #expect(await evaluator.evaluate(approved) == .conditionMatched)
        #expect(await evaluator.evaluate(ocr) == .conditionMatched)
        #expect(await evaluator.evaluate(visual) == .conditionMatched)

        let matchedPreviousResult = await evaluator.evaluateResult(matchedPrevious)
        let missingPreviousResult = await evaluator.evaluateResult(missingPrevious)
        let readySignalResult = await evaluator.evaluateResult(readySignal)
        let approvedResult = await evaluator.evaluateResult(approved)
        let ocrResult = await evaluator.evaluateResult(ocr)
        let visualResult = await evaluator.evaluateResult(visual)

        let matchedPreviousEvidence = matchedPreviousResult.evidence
        let missingPreviousEvidence = missingPreviousResult.evidence
        let readySignalEvidence = readySignalResult.evidence
        let approvedEvidence = approvedResult.evidence

        #expect(matchedPreviousResult.outcome == .conditionMatched)
        #expect(matchedPreviousEvidence != nil)
        #expect(matchedPreviousEvidence?.kind == .previousOutcome)
        #expect(matchedPreviousEvidence?.outcome == .conditionMatched)
        #expect(matchedPreviousEvidence?.evaluatedAt == evaluatedAt)
        #expect(matchedPreviousEvidence?.sampleCount == 2)
        #expect(matchedPreviousEvidence?.fields.contains {
            $0.id == "previousOutcomes" && $0.value.contains("success")
        } == true)

        #expect(missingPreviousResult.outcome == .conditionNotMatched)
        #expect(missingPreviousEvidence != nil)
        #expect(missingPreviousEvidence?.kind == .previousOutcome)
        #expect(missingPreviousEvidence?.outcome == .conditionNotMatched)
        #expect(missingPreviousEvidence?.observedSummary.contains("No upstream outcome") == true)

        #expect(readySignalResult.outcome == .conditionMatched)
        #expect(readySignalEvidence != nil)
        #expect(readySignalEvidence?.kind == .externalSignal)
        #expect(readySignalEvidence?.targetDescription == "ready")
        #expect(readySignalEvidence?.fields.contains {
            $0.id == "signalState" && $0.value == "active"
        } == true)

        #expect(approvedResult.outcome == .conditionMatched)
        #expect(approvedEvidence != nil)
        #expect(approvedEvidence?.kind == .manualApproval)
        #expect(approvedEvidence?.fields.contains {
            $0.id == "approval" && $0.value == "granted"
        } == true)
        #expect(ocrResult.evidence == nil)
        #expect(visualResult.evidence == nil)
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
        #expect(conditionActions == [.conditionEvaluationCompleted(
            runID: conditionRunID,
            result: AutomationConditionEvaluationResult(outcome: .conditionMatched),
            at: completedAt
        )])
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
        #expect(actions == [.conditionEvaluationCompleted(
            runID: runID,
            result: AutomationConditionEvaluationResult(outcome: .conditionNotMatched),
            at: completedAt
        )])
    }

    @Test("Effect runner forwards condition diagnostics through completed result")
    func effectRunnerForwardsConditionDiagnosticsThroughCompletedResult() async {
        let runID = UUID()
        let workflowID = UUID()
        let taskID = UUID()
        let conditionID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_130)
        let condition = AutomationConditionSpec(
            id: conditionID,
            name: "Pixel",
            kind: .visual(AutomationVisualCondition(type: .pixelMatched, targetColorHex: "#FFCC00"))
        )
        let evidence = AutomationConditionEvaluationEvidence(
            runID: runID,
            workflowID: workflowID,
            taskID: taskID,
            conditionID: conditionID,
            kind: .pixelMatched,
            outcome: .conditionMatched,
            evaluatedAt: completedAt,
            sampleCount: 1,
            targetDescription: "#FFCC00",
            observedSummary: "Pixel similarity 0.99",
            score: 0.99,
            threshold: 0.95
        )
        let result = AutomationConditionEvaluationResult(
            outcome: .conditionMatched,
            evidence: evidence
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            conditionEvaluator: AutomationConditionEvaluatorClient(evaluateResult: { _ in result }),
            now: { completedAt },
            sleep: { _ in }
        )

        let actions = await runner.run(.evaluateCondition(
            runID: runID,
            workflowID: workflowID,
            taskID: taskID,
            condition: condition,
            previousOutcomes: []
        ))

        #expect(actions == [.conditionEvaluationCompleted(runID: runID, result: result, at: completedAt)])
    }

    @Test("Runtime handoff commands map to reducer actions")
    func runtimeHandoffCommandsMapToReducerActions() {
        let workflowID = UUID()
        let taskID = UUID()
        let runID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 2_300)

        let startCommand = AutomationRuntimeHandoffCommand(
            kind: .manualStart(workflowID: workflowID, taskID: taskID),
            requestedAt: requestedAt,
            source: "test"
        )
        let cancelCommand = AutomationRuntimeHandoffCommand(
            kind: .cancelRun(runID: runID),
            requestedAt: requestedAt,
            source: "test"
        )

        #expect(startCommand.action == .manualStart(
            workflowID: workflowID,
            taskID: taskID,
            requestedAt: requestedAt
        ))
        #expect(cancelCommand.action == .cancelRun(runID: runID, at: requestedAt))
    }

    @Test("Runtime handoff mailbox queues, sorts, and removes commands")
    func runtimeHandoffMailboxQueuesSortsAndRemovesCommands() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = AutomationRuntimeHandoffStore(directoryURL: directory)
        let client = AutomationRuntimeHandoffClient.fileBacked(directoryURL: directory)
        let later = AutomationRuntimeHandoffCommand(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!,
            kind: .cancelRun(runID: UUID()),
            requestedAt: Date(timeIntervalSince1970: 2_401)
        )
        let earlier = AutomationRuntimeHandoffCommand(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
            kind: .manualStart(workflowID: UUID(), taskID: UUID()),
            requestedAt: Date(timeIntervalSince1970: 2_400)
        )

        _ = try await client.enqueue(later)
        _ = try await client.enqueue(earlier)
        _ = try await client.enqueue(later)

        let loaded = try await client.loadCommands()
        let document = try await store.loadDocument()

        #expect(loaded.map(\.id) == [earlier.id, later.id])
        #expect(document.version == AutomationRuntimeHandoffMailbox.currentVersion)
        #expect(document.commands == loaded)

        let runID = UUID(uuidString: "70000000-0000-0000-0000-000000000003")!
        let receipt = AutomationRuntimeHandoffReceipt(
            command: earlier,
            handledAt: Date(timeIntervalSince1970: 2_402),
            status: .dispatched,
            runIDs: [runID],
            message: "ok"
        )

        try await client.completeCommand(receipt)

        #expect(try await client.loadCommands() == [later])
        #expect(try await client.loadReceipts() == [receipt])
        #expect(try await client.receipt(earlier.id) == receipt)
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
