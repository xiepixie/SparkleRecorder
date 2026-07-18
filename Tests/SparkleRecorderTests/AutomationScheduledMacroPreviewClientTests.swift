import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Scheduled Macro Preview Client Tests")
struct AutomationScheduledMacroPreviewClientTests {
    @Test("Preview returns only after the matching run succeeds")
    func previewWaitsForMatchingSuccess() async throws {
        let runID = UUID()
        let request = previewRequest(runID: runID)
        let player = AutomationPlayerClient(
            start: { _ in .started },
            cancel: { _ in },
            events: {
                .fixed([
                    .playerFinished(
                        runID: UUID(),
                        outcome: .failed(report: nil),
                        at: Date(timeIntervalSince1970: 1)
                    ),
                    .playerFinished(
                        runID: runID,
                        outcome: .succeeded(report: nil),
                        at: Date(timeIntervalSince1970: 2)
                    ),
                ])
            }
        )

        try await AutomationScheduledMacroPreviewClient(player: player).run(request)
    }

    @Test("Cancelling preview forwards cancellation to the player")
    func cancellationStopsPlayer() async {
        let runID = UUID()
        let request = previewRequest(runID: runID)
        let probe = PreviewCancellationProbe()
        let pair = AsyncStream<AutomationAction>.makeStream()
        let player = AutomationPlayerClient(
            start: { _ in
                await probe.markStarted()
                return .started
            },
            cancel: { cancelledRunID in
                await probe.recordCancellation(cancelledRunID)
                pair.continuation.yield(.playerFinished(
                    runID: cancelledRunID,
                    outcome: .cancelled(reason: "Cancelled by preview"),
                    at: Date(timeIntervalSince1970: 3)
                ))
            },
            events: { pair.stream }
        )
        let task = Task {
            try await AutomationScheduledMacroPreviewClient(player: player).run(request)
        }

        await probe.waitUntilStarted()
        task.cancel()
        await probe.waitUntilCancelled()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.cancelledRunIDs == [runID])
        pair.continuation.finish()
    }

    private func previewRequest(runID: UUID) -> AutomationPlayerStartRequest {
        AutomationPlayerStartRequest(
            runID: runID,
            macro: SavedMacro(name: "Preview", events: [])
        )
    }
}

private actor PreviewCancellationProbe {
    private var didStart = false
    private var didCancel = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    private var recordedCancelledRunIDs: [UUID] = []

    var cancelledRunIDs: [UUID] { recordedCancelledRunIDs }

    func markStarted() {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func recordCancellation(_ runID: UUID) {
        recordedCancelledRunIDs.append(runID)
        didCancel = true
        let waiters = cancelWaiters
        cancelWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        guard !didCancel else { return }
        await withCheckedContinuation { continuation in
            cancelWaiters.append(continuation)
        }
    }
}
