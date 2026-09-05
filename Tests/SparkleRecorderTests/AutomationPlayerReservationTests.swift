import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Shared automation player reservation")
struct AutomationPlayerReservationTests {
    @Test @MainActor
    func separateClientsCannotPrepareTheSamePlayerConcurrently() async {
        let player = Player(eventPoster: .none, canPostEvents: { true })
        let gate = ReservationPreparationGate()
        let targets = AutomationTargetApplicationClient(prepare: { _, _ in
            await gate.suspend()
            return .success(.init())
        }, cleanup: { _, _, _, _ in .init() })
        let first = AutomationPlayerClient.live(player: player, targetApplications: targets)
        let second = AutomationPlayerClient.live(player: player, targetApplications: targets)
        let firstRequest = request()
        let start = Task { await first.start(firstRequest) }
        await gate.waitForEntry()
        #expect(player.ownsAutomationRun(firstRequest.runID))
        #expect(await second.start(request()) == .rejected(.rejected(reason: "Player is already running")))
        await first.cancel(firstRequest.runID)
        await gate.release()
        #expect(await start.value == .rejected(.cancelled(reason: "Automation cancelled during startup preparation")))
        #expect(!player.ownsAutomationRun(firstRequest.runID))
        #expect(!player.isPlaying)
    }

    @Test @MainActor
    func globalStopDuringPreparationPreventsLatePlayback() async {
        let player = Player(eventPoster: .none, canPostEvents: { true })
        let gate = ReservationPreparationGate()
        let client = AutomationPlayerClient.live(player: player,
            targetApplications: .init(prepare: { _, _ in
                await gate.suspend()
                return .success(.init())
            }, cleanup: { _, _, _, _ in .init() }))
        let request = request()
        let task = Task { await client.start(request) }
        await gate.waitForEntry()
        player.stop()
        await gate.release()
        #expect(await task.value == .rejected(.cancelled(reason: "Automation cancelled during startup preparation")))
        #expect(!player.isPlaying)
    }

    @Test @MainActor
    func staleCancellationCannotReleaseAnotherRunAndManualPlayRespectsReservation() async {
        let player = Player(eventPoster: .none, canPostEvents: { true })
        let oldClient = AutomationPlayerClient.live(player: player,
            targetApplications: .init(prepare: { _, _ in .success(.init()) }, cleanup: { _, _, _, _ in .init() }))
        let current = UUID()
        #expect(player.reserveAutomationRun(current))
        await oldClient.cancel(UUID())
        #expect(player.ownsAutomationRun(current))
        #expect(!player.play(events: TestFixtures.clickPair(), runID: UUID()))
        #expect(!player.isPlaying)
        #expect(!player.stop(runID: UUID()))
        #expect(player.ownsAutomationRun(current))
        #expect(player.stop(runID: current))
        #expect(player.ownsAutomationRun(current))
        #expect(!player.canStartAutomationRun(current))
        player.releaseAutomationRun(current)
        #expect(!player.ownsAutomationRun(current))
    }

    @Test @MainActor
    func reservationSurvivesCancellationUntilCleanupFinishes() async {
        let player = Player(eventPoster: .none, canPostEvents: { true })
        let preparation = ReservationPreparationGate()
        let cleanup = ReservationPreparationGate()
        let first = AutomationPlayerClient.live(player: player, targetApplications: .init(prepare: { _, _ in
            await preparation.suspend()
            return .success(.init())
        }, cleanup: { _, _, _, _ in await cleanup.suspend(); return .init() }))
        let second = AutomationPlayerClient.live(player: player, targetApplications: .init(
            prepare: { _, _ in .success(.init()) }, cleanup: { _, _, _, _ in .init() }))
        let run = request()
        let task = Task { await first.start(run) }
        await preparation.waitForEntry()
        player.stop()
        await preparation.release()
        await cleanup.waitForEntry()
        #expect(player.ownsAutomationRun(run.runID))
        #expect(await second.start(request()) == .rejected(.rejected(reason: "Player is already running")))
        let cancellation = Task { await first.cancel(run.runID) }
        await cleanup.release()
        _ = await task.value
        await cancellation.value
        #expect(!player.ownsAutomationRun(run.runID))
    }

    @MainActor private func request() -> AutomationPlayerStartRequest {
        .init(runID: UUID(), macro: SavedMacro(name: "Fixture", events: TestFixtures.clickPair()),
              targetApplicationPolicy: .doNotActivate)
    }
}

private actor ReservationPreparationGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters = []
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }
    func release() { continuation?.resume(); continuation = nil }
}
