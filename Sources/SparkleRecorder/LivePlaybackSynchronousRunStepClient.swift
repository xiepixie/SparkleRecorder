import CoreGraphics
import Foundation
import SparkleRecorderCore

private struct SynchronousPlaybackPointResolution: Sendable {
    var point: CGPoint?
    var failureReason: String?

    static func success(_ point: CGPoint) -> SynchronousPlaybackPointResolution {
        SynchronousPlaybackPointResolution(point: point, failureReason: nil)
    }

    static func failure(_ reason: String) -> SynchronousPlaybackPointResolution {
        SynchronousPlaybackPointResolution(point: nil, failureReason: reason)
    }
}

private final class SynchronousLockedValueBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct LivePlaybackSynchronousRunStepClient: Sendable {
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

    func makeClient() -> PlaybackSynchronousRunStepClient {
        let locatorCache = PlaybackLocatorCache()
        return PlaybackSynchronousRunStepClient { request in
            Self.run(
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
    ) -> PlaybackRunStepResult {
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
            return Self.awaitSynchronously { await LivePlaybackTextObservation.run(
                    event: event, context: runningContext, clock: playbackClock, client: textObservationClient, cancelled: cancelled
                ) }
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
                let contextSnapshot = runningContext
                let resolution = awaitSynchronously {
                    do {
                        let resolvedPoint: CGPoint
                        if let locatorClient {
                            resolvedPoint = try await locatorClient(event, contextSnapshot, playbackClock)
                        } else {
                            resolvedPoint = try await LocatorEngine().locateTextTarget(
                                event: event,
                                context: contextSnapshot,
                                clock: playbackClock,
                                cancelled: cancelled
                            )
                        }
                        return SynchronousPlaybackPointResolution.success(resolvedPoint)
                    } catch {
                        if event.locatorFallbackPolicy == .allowCoordinateFallback {
                            switch PlaybackLocatorFallback.resolve(
                                event: event,
                                surfaceId: targetSurfaceId,
                                context: contextSnapshot,
                                pointResolver: pointResolver
                            ) {
                            case .success(let pt):
                                return SynchronousPlaybackPointResolution.success(pt)
                            case .failure(let fallbackError):
                                return SynchronousPlaybackPointResolution.failure(String(describing: fallbackError))
                            }
                        }

                        return SynchronousPlaybackPointResolution.failure(String(describing: error))
                    }
                }
                guard let resolvedPoint = resolution.point else {
                    let reason = resolution.failureReason ?? "locator resolution failed"
                    #if DEBUG
                    NSLog("SparkleRecorder: locator resolution error: \(reason)")
                    #endif
                    return .failed(reason: reason)
                }
                point = resolvedPoint
                locatorCache.store(
                    point: point,
                    for: cacheKey,
                    loopIndex: request.loopIndex,
                    event: event
                )
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

    private static func awaitSynchronously<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value
    ) -> Value {
        let semaphore = DispatchSemaphore(value: 0)
        let result = SynchronousLockedValueBox<Value?>(nil)
        Task.detached(priority: .userInitiated) {
            result.set(await operation())
            semaphore.signal()
        }
        semaphore.wait()
        guard let value = result.get() else {
            fatalError("SparkleRecorder: synchronous async bridge completed without a result")
        }
        return value
    }
}
