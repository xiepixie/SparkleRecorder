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

        switch pointResolver.resolve(event, context: context) {
        case .success(let point):
            eventPoster.post(event, point)
            return .success(.posted(point))
        case .failure(let error):
            return .failure(.pointResolve(error))
        }
    }
}
