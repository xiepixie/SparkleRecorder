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

    init(
        playbackClock: PlaybackClockClient,
        pointResolver: PointResolver = PointResolver(),
        eventPoster: EventPosterClient
    ) {
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
                locatorCache: locatorCache
            )
        }
    }

    private static func run(
        request: PlaybackRunStepRequest,
        playbackClock: PlaybackClockClient,
        pointResolver: PointResolver,
        eventPoster: EventPosterClient,
        stepExecutor: PlaybackStepExecutor,
        locatorCache: PlaybackLocatorCache
    ) -> PlaybackRunStepResult {
        let step = request.step
        let event = step.event
        let runningContext = request.context
        let targetSurfaceId = request.targetSurfaceId

        if event.kind == .waitForText, let anchor = event.textAnchor {
            let text = anchor.text
            let timeout = event.textTimeout ?? 10.0
            let mustExist = event.verifyMustExist ?? true
            let startPoll = playbackClock.now()
            var matched = false
            if #available(macOS 14.0, *) {
                let contextSnapshot = runningContext
                matched = awaitSynchronously {
                    let locator = LocatorEngine()
                    while playbackClock.now() - startPoll < timeout {
                        let found: Bool
                        do {
                            _ = try await locator.locate(
                                event: event,
                                context: contextSnapshot,
                                strategies: [.ocr(anchor)]
                            )
                            found = true
                        } catch {
                            found = false
                        }
                        if found == mustExist {
                            return true
                        }
                        await playbackClock.sleep(0.5)
                    }
                    return false
                }
            }
            guard matched else {
                return .failed(reason: "waitForText timeout: '\(text)' mustExist=\(mustExist)")
            }
            return .succeeded(.semanticWaitCompleted)
        }

        if event.kind == .verifyText, let anchor = event.textAnchor {
            let text = anchor.text
            let mustExist = event.verifyMustExist ?? true
            var found = false
            if #available(macOS 14.0, *) {
                let contextSnapshot = runningContext
                found = awaitSynchronously {
                    let locator = LocatorEngine()
                    do {
                        _ = try await locator.locate(
                            event: event,
                            context: contextSnapshot,
                            strategies: [.ocr(anchor)]
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            guard found == mustExist else {
                return .failed(reason: "verifyText failed: '\(text)' mustExist=\(mustExist)")
            }
            return .succeeded(.semanticVerificationCompleted)
        }

        if #available(macOS 14.0, *), (event.coordinateStrategy == .locatorOnly || event.textAnchor != nil) {
            let point: CGPoint
            let cacheKey = PlaybackLocatorCacheKey.key(for: event, surfaceId: targetSurfaceId)
            if let cached = locatorCache.point(
                for: cacheKey,
                loopIndex: request.loopIndex,
                eventTime: event.time
            ) {
                point = cached
            } else {
                let contextSnapshot = runningContext
                let resolution = awaitSynchronously {
                    let locator = LocatorEngine()
                    var strategies: [LocatorStrategy] = []
                    if let anchor = event.textAnchor {
                        strategies.append(.ocr(anchor))
                    }
                    do {
                        let resolvedPoint = try await LivePlaybackRunStepClient.locateWithOptionalWait(
                            locator: locator,
                            event: event,
                            context: contextSnapshot,
                            strategies: strategies,
                            clock: playbackClock
                        )
                        return SynchronousPlaybackPointResolution.success(resolvedPoint)
                    } catch {
                        if event.locatorFallbackPolicy == .allowCoordinateFallback {
                            if let fallbackPoint = LivePlaybackRunStepClient.coordinateFallbackPoint(
                                for: event,
                                surfaceId: targetSurfaceId,
                                context: contextSnapshot
                            ) {
                                return SynchronousPlaybackPointResolution.success(fallbackPoint)
                            }
                            switch pointResolver.resolve(event, context: contextSnapshot) {
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
                    eventTime: event.time
                )
            }
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
