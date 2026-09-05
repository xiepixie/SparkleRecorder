import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Playback action feedback")
struct PlaybackActionFeedbackTests {
    private func key(_ kind: RecordedEvent.Kind, text: String? = nil, flags: UInt64 = 0) -> RecordedEvent {
        RecordedEvent(kind: kind, time: 0, x: 0, y: 0, keyCode: 8, flags: flags,
            mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0, unicodeString: text)
    }

    @Test func printableInputNeverExposesItsKeyOnPressOrRelease() {
        let down = PlaybackActionFeedback(event: key(.keyDown, text: "private-password"), loopNumber: 1, stepNumber: 1, stepCount: 2)
        let up = PlaybackActionFeedback(event: key(.keyUp), loopNumber: 1, stepNumber: 2, stepCount: 2)
        #expect(down.keyCode == nil)
        #expect(up.keyCode == nil)
        let shortcut = PlaybackActionFeedback(event: key(.keyDown, text: "c", flags: 1 << 20), loopNumber: 1, stepNumber: 1, stepCount: 1)
        #expect(shortcut.keyCode == 8)
        #expect(shortcut.modifierFlags == 1 << 20)
    }

    @Test func bothEnginesPublishStepFeedbackBeforeAttemptingEachAction() async {
        let events = [key(.keyDown, text: "secret"), key(.keyUp)]
        let plan = PlaybackPlanner.plan(events: events, loops: 2, speed: 1)
        let asyncLog = FeedbackLog()
        let engine = PlaybackRunEngine(plan: plan, context: .init(), runID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0), startedClock: 0, clock: .immediate(),
            stepClient: .init { _ in asyncLog.executed(); return .succeeded(.postedInput) }, activationDelay: 0)
        _ = await engine.run(callbacks: .init(stepStarted: { asyncLog.started($0) }))
        #expect(asyncLog.order == ["start", "run", "start", "run", "start", "run", "start", "run"])
        #expect(asyncLog.actions.map(\.stepNumber) == [1, 2, 1, 2])
        #expect(asyncLog.actions.map(\.loopNumber) == [1, 1, 2, 2])
        #expect(asyncLog.actions.allSatisfy { $0.stepCount == 2 && $0.keyCode == nil })
        let syncLog = FeedbackLog()
        let synchronous = PlaybackSynchronousRunEngine(plan: plan, context: .init(), runID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0), startedClock: 0, clock: .immediate(),
            stepClient: .init { _ in syncLog.executed(); return .succeeded(.postedInput) }, activationDelay: 0)
        _ = synchronous.run(callbacks: .init(stepStarted: { syncLog.started($0) }))
        #expect(syncLog.actions == asyncLog.actions)
        #expect(syncLog.order == asyncLog.order)
    }

    @Test func conflictDoesNotAnnounceAnActionThatWillNotRun() async {
        let log = FeedbackLog()
        let engine = PlaybackRunEngine(plan: PlaybackPlanner.plan(events: [key(.keyDown)], loops: 1, speed: 1),
            context: .init(), runID: UUID(), startedAt: Date(timeIntervalSince1970: 0), startedClock: 0,
            clock: .immediate(), conflict: .init(hasConflict: { true }),
            stepClient: .init { _ in log.executed(); return .succeeded(.postedInput) }, activationDelay: 0)
        _ = await engine.run(callbacks: .init(stepStarted: { log.started($0) }))
        #expect(log.order.isEmpty)
    }
}

private final class FeedbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedActions: [PlaybackActionFeedback] = []
    private var recordedOrder: [String] = []
    var actions: [PlaybackActionFeedback] { lock.lock(); defer { lock.unlock() }; return recordedActions }
    var order: [String] { lock.lock(); defer { lock.unlock() }; return recordedOrder }
    func started(_ action: PlaybackActionFeedback) {
        lock.lock(); defer { lock.unlock() }
        recordedActions.append(action); recordedOrder.append("start")
    }
    func executed() { lock.lock(); defer { lock.unlock() }; recordedOrder.append("run") }
}
