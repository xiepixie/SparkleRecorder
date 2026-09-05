import Foundation
import SparkleRecorderCore

enum LivePlaybackTextObservation {
    static let client = PlaybackTextObservationClient { event, context in
        guard let anchor = event.textAnchor else { return .unavailable("Missing text anchor") }
        do {
            _ = try await LocatorEngine().locate(event: event, context: context, strategies: [.ocr(anchor)])
            return .found
        } catch VisionDetectorError.textNotMatched {
            return .absent
        } catch VisionDetectorError.noTextFound {
            return .absent
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    static func run(
        event: RecordedEvent, context: PlaybackContext, clock: PlaybackClockClient,
        client: PlaybackTextObservationClient,
        cancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) async -> PlaybackRunStepResult {
        guard event.textAnchor != nil else { return .failed(reason: "Missing text anchor") }
        let outcome: PlaybackTextObservationOutcome
        if event.kind == .verifyText {
            if cancelled() { return .failed(reason: "Text verification cancelled") }
            let observed = await client.observe(event, context)
            if cancelled() { return .failed(reason: "Text verification cancelled") }
            switch observed {
            case .unavailable(let reason): outcome = .unavailable(reason)
            default: outcome = observed == ((event.verifyMustExist ?? true) ? .found : .absent) ? .matched : .timedOut
            }
        } else {
            outcome = await PlaybackTextObservationEvaluator.wait(
                mustExist: event.verifyMustExist ?? true, timeout: event.textTimeout ?? 10,
                clock: clock, cancelled: cancelled, observe: { await client.observe(event, context) }
            )
        }
        switch outcome {
        case .matched:
            return .succeeded(event.kind == .verifyText ? .semanticVerificationCompleted : .semanticWaitCompleted)
        case .unavailable(let reason): return .failed(reason: "Text observation unavailable: \(reason)")
        case .cancelled: return .failed(reason: "Text observation cancelled")
        case .invalidPolicy: return .failed(reason: "Invalid text observation timeout")
        case .timedOut: return .failed(reason: "Text condition not met: \(event.textAnchor?.text ?? "")")
        }
    }
}
