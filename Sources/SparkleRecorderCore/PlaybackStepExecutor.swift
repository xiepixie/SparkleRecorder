import CoreGraphics
import Foundation

public enum PlaybackStepExecutionOutcome: Equatable, Sendable {
    case posted(CGPoint)
    case skippedSemanticEvent(RecordedEvent.Kind)
}

public enum PlaybackStepExecutionError: Error, Sendable {
    case pointResolve(PointResolveError)
}

public struct PlaybackStepExecutor: Sendable {
    public var pointResolver: PointResolver
    public var eventPoster: EventPosterClient

    public init(
        pointResolver: PointResolver = PointResolver(),
        eventPoster: EventPosterClient = .none
    ) {
        self.pointResolver = pointResolver
        self.eventPoster = eventPoster
    }

    public func execute(
        _ step: PlaybackStep,
        context: PlaybackContext
    ) -> Result<PlaybackStepExecutionOutcome, PlaybackStepExecutionError> {
        let event = step.event
        guard event.kind.postsInputEvent else {
            return .success(.skippedSemanticEvent(event.kind))
        }

        // Keyboard input does not consume a screen point. Resolving its recorded
        // placeholder location against a moved window can turn (0, 0) into an
        // out-of-bounds point and abort playback before the key is posted.
        if event.kind.isKey {
            let point = event.location
            eventPoster.post(event, point)
            return .success(.posted(point))
        }

        switch pointResolver.resolve(event, context: context) {
        case .success(let point):
            eventPoster.post(event, point)
            return .success(.posted(point))
        case .failure(let error):
            return .failure(.pointResolve(error))
        }
    }
}
