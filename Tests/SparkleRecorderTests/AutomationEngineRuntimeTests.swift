import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Engine Runtime Tests")
struct AutomationEngineRuntimeTests {
    @Test("Runtime sends manual starts and scheduler ticks through the same reducer/effect path")
    func runtimeHandlesManualAndScheduledStarts() async {
        let workflowID = UUID()
        let manualTaskID = UUID()
        let scheduledTaskID = UUID()
        let tickAt = Date(timeIntervalSince1970: 1_200)
        let completedAt = Date(timeIntervalSince1970: 1_201)
        let manualTask = AutomationTask(
            id: manualTaskID,
            name: "Manual delay",
            kind: .delay(0),
            schedule: .manual,
            resourceRequirement: .none
        )
        let scheduledTask = AutomationTask(
            id: scheduledTaskID,
            name: "Scheduled delay",
            kind: .delay(0),
            schedule: .once(tickAt),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Runtime workflow",
            tasks: [manualTask, scheduledTask],
            createdAt: tickAt,
            modifiedAt: tickAt
        )
        let store = AutomationInMemoryRepositoryStore()
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            repository: .inMemory(store: store),
            now: { completedAt },
            sleep: { _ in }
        )
        let runtime = AutomationEngineRuntime(
            initialState: AutomationRunState(workflows: [workflow]),
            effectRunner: runner
        )

        await runtime.dispatch(.manualStart(
            workflowID: workflowID,
            taskID: manualTaskID,
            requestedAt: tickAt
        ))
        await runtime.runScheduler(.fixed([
            .clockTick(tickAt)
        ]))

        let state = await runtime.currentState()
        let runs = state.runs.sorted { $0.createdAt < $1.createdAt }
        let persistedRuns = await store.loadRunHistory()

        #expect(runs.count == 2)
        #expect(Set(runs.map(\.taskID)) == [manualTaskID, scheduledTaskID])
        #expect(runs.allSatisfy { $0.isTerminal })
        #expect(runs.allSatisfy { $0.outcome == .succeeded(report: nil) })
        let persistedRunIDs = persistedRuns.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let stateRunIDs = runs.map(\.id).sorted { $0.uuidString < $1.uuidString }
        #expect(persistedRunIDs == stateRunIDs)
    }

    @Test("Runtime starts macro tasks through AutomationPlayerClient")
    func runtimeStartsMacroThroughPlayerClient() async throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 1_300)
        let macro = SavedMacro(id: macroID, name: "Runtime macro", events: TestFixtures.clickPair())
        let recorder = RuntimePlayerStartRecorder()
        let player = AutomationPlayerClient(
            start: { request in
                await recorder.record(request)
                return .started
            },
            cancel: { _ in }
        )
        let task = AutomationTask(
            id: taskID,
            name: "Macro",
            kind: .macro(macroID: macroID),
            schedule: .manual,
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Player workflow",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: player,
            loadMacro: { id in id == macroID ? macro : nil },
            now: { requestedAt },
            sleep: { _ in }
        )
        let runtime = AutomationEngineRuntime(
            initialState: AutomationRunState(workflows: [workflow]),
            effectRunner: runner
        )

        await runtime.dispatch(.manualStart(
            workflowID: workflowID,
            taskID: taskID,
            requestedAt: requestedAt
        ))

        let state = await runtime.currentState()
        let run = try #require(state.runs.first)

        #expect(await recorder.runIDs == state.runs.map(\.id))
        #expect(await recorder.macroIDs == [macroID])
        #expect(run.status == .running)
        #expect(run.outcome == nil)
    }

    @Test("Runtime consumes PlayerClient completion events as reducer actions")
    func runtimeConsumesPlayerCompletionEvents() async throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 1_400)
        let finishedAt = Date(timeIntervalSince1970: 1_405)
        let macro = SavedMacro(id: macroID, name: "Completing macro", events: TestFixtures.clickPair())
        let store = AutomationInMemoryRepositoryStore()
        let expectedRunID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let player = AutomationPlayerClient(
            start: { _ in .started },
            cancel: { _ in },
            events: {
                .fixed([
                    .playerFinished(runID: expectedRunID, outcome: .succeeded(report: nil), at: finishedAt)
                ])
            }
        )
        let task = AutomationTask(
            id: taskID,
            name: "Macro",
            kind: .macro(macroID: macroID),
            schedule: .manual,
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Completion workflow",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let runner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: player,
            repository: .inMemory(store: store),
            loadMacro: { id in id == macroID ? macro : nil },
            now: { requestedAt },
            sleep: { _ in }
        )
        let runtime = AutomationEngineRuntime(
            initialState: AutomationRunState(workflows: [workflow]),
            reducerEnvironment: AutomationReducerEnvironment(makeRunID: {
                expectedRunID
            }),
            effectRunner: runner
        )

        await runtime.dispatch(.manualStart(
            workflowID: workflowID,
            taskID: taskID,
            requestedAt: requestedAt
        ))
        await runtime.runPlayerEvents()

        let state = await runtime.currentState()
        let run = try #require(state.runs.first)
        let persistedRun = try #require(await store.loadRunHistory().first)

        #expect(run.id == expectedRunID)
        #expect(run.status == .completed)
        #expect(run.outcome == .succeeded(report: nil))
        #expect(run.completedAt == finishedAt)
        #expect(persistedRun.id == expectedRunID)
        #expect(persistedRun.outcome == .succeeded(report: nil))
    }
}

private actor RuntimePlayerStartRecorder {
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
