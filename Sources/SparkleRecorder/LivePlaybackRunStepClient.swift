import CoreGraphics
import Foundation
import SparkleRecorderCore

struct LivePlaybackRunStepClient: Sendable {
    var playbackClock: PlaybackClockClient
    var pointResolver: PointResolver
    var eventPoster: EventPosterClient
    var stepExecutor: PlaybackStepExecutor
    var textObservationClient: PlaybackTextObservationClient
    var locatorClient: (@Sendable (RecordedEvent, PlaybackContext, PlaybackClockClient) async throws -> CGPoint)?
    var cancelled: @Sendable () -> Bool

    init(
        playbackClock: PlaybackClockClient,
        pointResolver: PointResolver = PointResolver(),
        eventPoster: EventPosterClient,
        textObservationClient: PlaybackTextObservationClient = LivePlaybackTextObservation.client,
        locatorClient: (@Sendable (RecordedEvent, PlaybackContext, PlaybackClockClient) async throws -> CGPoint)? = nil,
        cancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) {
        self.locatorClient = locatorClient
        self.cancelled = cancelled
        self.textObservationClient = textObservationClient
        self.playbackClock = playbackClock
        self.pointResolver = pointResolver
        self.eventPoster = eventPoster
        self.stepExecutor = PlaybackStepExecutor(
            pointResolver: pointResolver,
            eventPoster: eventPoster
        )
    }

    func makeClient() -> PlaybackRunStepClient {
        let locatorCache = PlaybackLocatorCache()
        return PlaybackRunStepClient { request in
            await Self.run(
                request: request,
                playbackClock: playbackClock,
                pointResolver: pointResolver,
                eventPoster: eventPoster,
                stepExecutor: stepExecutor,
                locatorCache: locatorCache,
                textObservationClient: textObservationClient,
                locatorClient: locatorClient,
                cancelled: cancelled
            )
        }
    }

    private static func run(
        request: PlaybackRunStepRequest,
        playbackClock: PlaybackClockClient,
        pointResolver: PointResolver,
        eventPoster: EventPosterClient,
        stepExecutor: PlaybackStepExecutor,
        locatorCache: PlaybackLocatorCache,
        textObservationClient: PlaybackTextObservationClient,
        locatorClient: (@Sendable (RecordedEvent, PlaybackContext, PlaybackClockClient) async throws -> CGPoint)?,
        cancelled: @escaping @Sendable () -> Bool
    ) async -> PlaybackRunStepResult {
        if cancelled() { return .failed(reason: "Playback cancelled") }
        let step = request.step
        let event = step.event
        let runningContext = request.context
        let targetSurfaceId = request.targetSurfaceId
        switch event.kind {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: break
        default: locatorCache.invalidate()
        }

        if event.kind == .waitForText || event.kind == .verifyText {
            return await LivePlaybackTextObservation.run(
                    event: event, context: runningContext, clock: playbackClock, client: textObservationClient, cancelled: cancelled
                )
        }

        if #available(macOS 14.0, *), (event.coordinateStrategy == .locatorOnly || event.textAnchor != nil) {
            let point: CGPoint
            let cacheKey = PlaybackLocatorCacheKey.key(for: event, surfaceId: targetSurfaceId)
            if let cached = locatorCache.point(
                for: cacheKey,
                loopIndex: request.loopIndex,
                event: event
            ) {
                point = cached
            } else {
                do {
                    if let locatorClient {
                        point = try await locatorClient(event, runningContext, playbackClock)
                    } else {
                        point = try await locate(event: event, context: runningContext, clock: playbackClock, cancelled: cancelled)
                    }
                } catch {
                    if event.locatorFallbackPolicy == .allowCoordinateFallback {
                        if let fallbackPoint = coordinateFallbackPoint(
                            for: event,
                            surfaceId: targetSurfaceId,
                            context: runningContext
                        ) {
                            point = fallbackPoint
                        } else {
                            let resolvedResult = pointResolver.resolve(event, context: runningContext)
                            switch resolvedResult {
                            case .success(let pt):
                                point = pt
                            case .failure(let fallbackError):
                                #if DEBUG
                                NSLog("SparkleRecorder: locator fallback error: \(fallbackError)")
                                #endif
                                return .failed(reason: "\(fallbackError)")
                            }
                        }
                    } else {
                        #if DEBUG
                        NSLog("SparkleRecorder: locator engine error: \(error)")
                        #endif
                        return .failed(reason: "\(error)")
                    }
                }
            }
            if event.kind == .leftMouseDown || event.kind == .rightMouseDown || event.kind == .otherMouseDown {
                locatorCache.store(point: point, for: cacheKey, loopIndex: request.loopIndex, event: event)
            }
            if cancelled() { return .failed(reason: "Playback cancelled") }
            eventPoster.post(event, point)
            return .succeeded(.postedInput)
        }

        switch stepExecutor.execute(step, context: runningContext) {
        case .success(.posted), .success(.skippedSemanticEvent):
            return .succeeded(.postedInput)
        case .failure(.pointResolve(let error)):
            #if DEBUG
            NSLog("SparkleRecorder: point resolve error: \(error)")
            #endif
            return .failed(reason: "\(error)")
        }
    }

    static func locate(event: RecordedEvent, context: PlaybackContext, clock: PlaybackClockClient,
                       cancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) async throws -> CGPoint {
        let strategies: [LocatorStrategy] = event.textAnchor.map { [.ocr($0)] } ?? []
        return try await locateWithOptionalWait(locator: LocatorEngine(), event: event,
            context: context, strategies: strategies, clock: clock, cancelled: cancelled)
    }

    @available(macOS 14.0, *)
    static func locateWithOptionalWait(
        locator: LocatorEngine,
        event: RecordedEvent,
        context: PlaybackContext,
        strategies: [LocatorStrategy],
        clock: PlaybackClockClient = .live,
        cancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) async throws -> CGPoint {
        if cancelled() { throw CancellationError() }
        guard event.kind.isMouse,
              event.textAnchor != nil,
              let timeout = event.textTimeout,
              timeout > 0 else {
            return try await locator.locate(event: event, context: context, strategies: strategies)
        }

        let startedAt = clock.now()
        var lastError: Error = VisionDetectorError.textNotMatched
        while clock.now() - startedAt < timeout {
            if cancelled() { throw CancellationError() }
            do {
                return try await locator.locate(event: event, context: context, strategies: strategies)
            } catch {
                if cancelled() || error is CancellationError { throw CancellationError() }
                lastError = error
                await clock.sleep(0.25)
            }
        }
        throw lastError
    }

    static func coordinateFallbackPoint(
        for event: RecordedEvent,
        surfaceId: String,
        context: PlaybackContext
    ) -> CGPoint? {
        guard let anchor = event.textAnchor,
              let windowFrame = context.currentSurfaceFrames[surfaceId] else { return nil }

        let point: CGPoint?
        if let normalized = anchor.coordinateFallbackContentNormalized,
           let contentFrame = context.currentContentFrames[surfaceId] {
            point = CGPoint(
                x: contentFrame.x + normalized.x * contentFrame.width,
                y: contentFrame.y + normalized.y * contentFrame.height
            )
        } else if let fallback = anchor.coordinateFallback {
            point = CGPoint(x: fallback.x, y: fallback.y)
        } else {
            point = nil
        }

        guard let point,
              CoordinateMapper().assertPointIsInsideWindow(point, in: windowFrame) else {
            return nil
        }
        return point
    }
}
