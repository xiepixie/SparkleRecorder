import CoreGraphics
import Foundation
import SparkleRecorderCore

@available(macOS 14.0, *)
final class LocatorEngine: @unchecked Sendable {
    private let textTargetResolver = PlaybackTextTargetResolver()

    /// Resolves a text-backed mouse target. Polling belongs here so both live
    /// playback adapters share one locator timing policy instead of duplicating it.
    func locateTextTarget(
        event: RecordedEvent,
        context: PlaybackContext,
        clock: PlaybackClockClient,
        cancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) async throws -> CGPoint {
        guard let anchor = event.textAnchor else {
            throw VisionDetectorError.textNotMatched
        }
        if cancelled() { throw CancellationError() }

        guard event.kind.isMouse,
              let timeout = event.textTimeout,
              timeout.isFinite,
              timeout > 0 else {
            return try await textTargetResolver
                .resolve(event: event, context: context, anchor: anchor)
                .center.cgPoint
        }

        let startedAt = clock.now()
        guard startedAt.isFinite, (startedAt + timeout).isFinite else {
            throw VisionDetectorError.textNotMatched
        }
        var lastError: Error = VisionDetectorError.textNotMatched
        while clock.now() - startedAt < timeout {
            if cancelled() { throw CancellationError() }
            do {
                return try await textTargetResolver
                    .resolve(event: event, context: context, anchor: anchor)
                    .center.cgPoint
            } catch {
                if cancelled() || error is CancellationError { throw CancellationError() }
                lastError = error
                await clock.sleep(0.25)
            }
        }
        throw lastError
    }
}
