import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Runtime Session Tests")
struct AutomationRuntimeSessionTests {
    @Test("Session loads persisted workflows and run history before starting scheduler actions")
    func sessionLoadsRepositoryAndRunsScheduler() async throws {
        let workflowID = UUID()
        let scheduledTaskID = UUID()
        let oldTaskID = UUID()
        let tickAt = Date(timeIntervalSince1970: 2_000)
        let completedAt = Date(timeIntervalSince1970: 2_001)
        let scheduledTask = AutomationTask(
            id: scheduledTaskID,
            name: "Scheduled delay",
            kind: .delay(0),
            schedule: .once(tickAt),
            resourceRequirement: .none
        )
        let oldTask = AutomationTask(
            id: oldTaskID,
            name: "Old delay",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Session workflow",
            tasks: [scheduledTask, oldTask],
            createdAt: tickAt,
            modifiedAt: tickAt
        )
        let oldRun = oldTask.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            createdAt: tickAt.addingTimeInterval(-60)
        )
        .completed(with: .succeeded(report: nil), at: tickAt.addingTimeInterval(-55))
        let store = AutomationInMemoryRepositoryStore(
            workflows: [workflow],
            runHistory: [oldRun]
        )
        let repository = AutomationRepositoryClient.inMemory(store: store)
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            repository: repository,
            now: { completedAt },
            sleep: { _ in }
        )
        let session = AutomationRuntimeSession(
            repository: repository,
            scheduler: .fixed([.clockTick(tickAt)]),
            effectRunner: runner
        )

        let initialState = try await session.start()
        let schedulerProcessed = await eventually {
            guard let state = await session.currentState() else {
                return false
            }
            return state.runs.count == 2 && state.runs.contains {
                $0.taskID == scheduledTaskID && $0.outcome == .succeeded(report: nil)
            }
        }
        let state = try #require(await session.currentState())
        let persistedRuns = await store.loadRunHistory()

        #expect(initialState.workflows == [workflow])
        #expect(initialState.runs == [oldRun])
        #expect(schedulerProcessed)
        #expect(Set(state.runs.map(\.taskID)) == [oldTaskID, scheduledTaskID])
        #expect(persistedRuns.count == 2)
        #expect(persistedRuns.first == oldRun)

        await session.stop()
        #expect(await session.lifecycleStatus() == .stopped)
    }

    @Test("Session consumes Player completion events in the background")
    func sessionConsumesPlayerCompletionEvents() async throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let expectedRunID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let requestedAt = Date(timeIntervalSince1970: 2_100)
        let finishedAt = Date(timeIntervalSince1970: 2_104)
        let macro = SavedMacro(id: macroID, name: "Session macro", events: TestFixtures.clickPair())
        let task = AutomationTask(
            id: taskID,
            name: "Macro",
            kind: .macro(macroID: macroID),
            schedule: .manual,
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Player event workflow",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let store = AutomationInMemoryRepositoryStore(workflows: [workflow])
        let repository = AutomationRepositoryClient.inMemory(store: store)
        let playerEvents = ActionStreamProbe()
        let recorder = RuntimeSessionPlayerStartRecorder()
        let player = AutomationPlayerClient(
            start: { request in
                await recorder.record(request)
                return .started
            },
            cancel: { _ in },
            events: {
                playerEvents.stream()
            }
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: player,
            repository: repository,
            loadMacro: { id in id == macroID ? macro : nil },
            now: { requestedAt },
            sleep: { _ in }
        )
        let session = AutomationRuntimeSession(
            repository: repository,
            scheduler: .fixed([]),
            reducerEnvironment: AutomationReducerEnvironment(makeRunID: { expectedRunID }),
            effectRunner: runner
        )

        try await session.start()
        try await session.dispatch(.manualStart(
            workflowID: workflowID,
            taskID: taskID,
            requestedAt: requestedAt
        ))

        let playerStarted = await eventually {
            await recorder.runIDs == [expectedRunID] && playerEvents.isReady
        }
        playerEvents.yield(.playerFinished(
            runID: expectedRunID,
            outcome: .succeeded(report: nil),
            at: finishedAt
        ))
        let playerCompleted = await eventually {
            guard let run = await session.currentState()?.runs.first(where: { $0.id == expectedRunID }) else {
                return false
            }
            return run.outcome == .succeeded(report: nil)
        }
        let persistedRun = try #require(await store.loadRunHistory().first)

        #expect(playerStarted)
        #expect(playerCompleted)
        #expect(await recorder.macroIDs == [macroID])
        #expect(persistedRun.id == expectedRunID)
        #expect(persistedRun.completedAt == finishedAt)

        playerEvents.finish()
        await session.stop()
    }

    @Test("Session stop cancels active macro runs, releases leases, and persists cancellation")
    func sessionStopCancelsActiveRuns() async throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let expectedRunID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        let leaseID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
        let requestedAt = Date(timeIntervalSince1970: 2_200)
        let stoppedAt = Date(timeIntervalSince1970: 2_205)
        let macro = SavedMacro(id: macroID, name: "Long macro", events: TestFixtures.clickPair())
        let task = AutomationTask(
            id: taskID,
            name: "Macro",
            kind: .macro(macroID: macroID),
            schedule: .manual,
            resourceRequirement: .foregroundInput
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Stop workflow",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let repositoryStore = AutomationInMemoryRepositoryStore(workflows: [workflow])
        let repository = AutomationRepositoryClient.inMemory(store: repositoryStore)
        let leaseStore = AutomationResourceLeaseStore()
        let cancelRecorder = RuntimeSessionPlayerCancelRecorder()
        let player = AutomationPlayerClient(
            start: { _ in .started },
            cancel: { runID in await cancelRecorder.record(runID) },
            events: { .finished }
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(store: leaseStore, leaseID: { leaseID }),
            player: player,
            repository: repository,
            loadMacro: { id in id == macroID ? macro : nil },
            now: { requestedAt },
            sleep: { _ in }
        )
        let session = AutomationRuntimeSession(
            repository: repository,
            scheduler: .fixed([]),
            reducerEnvironment: AutomationReducerEnvironment(makeRunID: { expectedRunID }),
            effectRunner: runner
        )

        try await session.start()
        try await session.dispatch(.manualStart(
            workflowID: workflowID,
            taskID: taskID,
            requestedAt: requestedAt
        ))
        let runningRun = try #require(await session.currentState()?.run(id: expectedRunID))
        #expect(runningRun.status == .running)

        await session.stop(at: stoppedAt)

        let state = try #require(await session.currentState())
        let run = try #require(state.run(id: expectedRunID))
        let persistedRun = try #require(await repositoryStore.loadRunHistory().first)

        #expect(await cancelRecorder.runIDs == [expectedRunID])
        #expect(await leaseStore.allLeases().isEmpty)
        #expect(run.status == .completed)
        #expect(run.outcome == .cancelled(reason: "User cancelled"))
        #expect(run.completedAt == stoppedAt)
        #expect(persistedRun.id == expectedRunID)
        #expect(persistedRun.outcome == .cancelled(reason: "User cancelled"))
        #expect(await session.lifecycleStatus() == .stopped)
    }
}

private func eventually(
    attempts: Int = 100,
    delayNanoseconds: UInt64 = 10_000_000,
    _ condition: () async -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
    return false
}

private actor RuntimeSessionPlayerStartRecorder {
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

private actor RuntimeSessionPlayerCancelRecorder {
    private var recordedRunIDs: [UUID] = []

    var runIDs: [UUID] {
        recordedRunIDs
    }

    func record(_ runID: UUID) {
        recordedRunIDs.append(runID)
    }
}

private final class ActionStreamProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AutomationAction>.Continuation?

    var isReady: Bool {
        lock.lock()
        let ready = continuation != nil
        lock.unlock()
        return ready
    }

    func stream() -> AsyncStream<AutomationAction> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func yield(_ action: AutomationAction) {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(action)
    }

    func finish() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}
