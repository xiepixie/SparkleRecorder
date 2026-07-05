import CoreGraphics
import Foundation
import SparkleRecorderCore

struct LivePlaybackRunStepClient: Sendable {
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

    func makeClient() -> PlaybackRunStepClient {
        let locatorCache = PlaybackLocatorCache()
        return PlaybackRunStepClient { request in
            await Self.run(
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
    ) async -> PlaybackRunStepResult {
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
                let locator = LocatorEngine()
                while playbackClock.now() - startPoll < timeout {
                    if Task.isCancelled {
                        return .succeeded(.semanticWaitCompleted)
                    }
                    let found: Bool
                    do {
                        _ = try await locator.locate(
                            event: event,
                            context: runningContext,
                            strategies: [.ocr(anchor)]
                        )
                        found = true
                    } catch {
                        found = false
                    }
                    if found == mustExist {
                        matched = true
                        break
                    }
                    await playbackClock.sleep(0.5)
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
                let locator = LocatorEngine()
                do {
                    _ = try await locator.locate(
                        event: event,
                        context: runningContext,
                        strategies: [.ocr(anchor)]
                    )
                    found = true
                } catch {}
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
                let locator = LocatorEngine()
                var strategies: [LocatorStrategy] = []
                if let anchor = event.textAnchor {
                    strategies.append(.ocr(anchor))
                }

                do {
                    point = try await locateWithOptionalWait(
                        locator: locator,
                        event: event,
                        context: runningContext,
                        strategies: strategies,
                        clock: playbackClock
                    )
                    locatorCache.store(
                        point: point,
                        for: cacheKey,
                        loopIndex: request.loopIndex,
                        eventTime: event.time
                    )
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

    @available(macOS 14.0, *)
    static func locateWithOptionalWait(
        locator: LocatorEngine,
        event: RecordedEvent,
        context: PlaybackContext,
        strategies: [LocatorStrategy],
        clock: PlaybackClockClient = .live
    ) async throws -> CGPoint {
        guard event.kind.isMouse,
              event.textAnchor != nil,
              let timeout = event.textTimeout,
              timeout > 0 else {
            return try await locator.locate(event: event, context: context, strategies: strategies)
        }

        let startedAt = clock.now()
        var lastError: Error = VisionDetectorError.textNotMatched
        while clock.now() - startedAt < timeout {
            do {
                return try await locator.locate(event: event, context: context, strategies: strategies)
            } catch {
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
