import Foundation

public struct PlaybackConflictClient: Sendable {
    public var hasConflict: @Sendable () -> Bool

    public init(hasConflict: @escaping @Sendable () -> Bool) {
        self.hasConflict = hasConflict
    }

    public static let never = PlaybackConflictClient(hasConflict: { false })
}

public enum PlaybackRunStepTiming: Equatable, Sendable {
    case unchanged
    case resetToCurrentClock
    case catchUpIfLate(threshold: TimeInterval)
}

public struct PlaybackRunStepSuccess: Equatable, Sendable {
    public var timing: PlaybackRunStepTiming
    public var publishesProgress: Bool

    public init(
        timing: PlaybackRunStepTiming,
        publishesProgress: Bool
    ) {
        self.timing = timing
        self.publishesProgress = publishesProgress
    }

    public static let postedInput = PlaybackRunStepSuccess(
        timing: .catchUpIfLate(threshold: 0.04),
        publishesProgress: true
    )

    public static let semanticWaitCompleted = PlaybackRunStepSuccess(
        timing: .resetToCurrentClock,
        publishesProgress: false
    )

    public static let semanticVerificationCompleted = PlaybackRunStepSuccess(
        timing: .catchUpIfLate(threshold: 0.04),
        publishesProgress: false
    )
}

public enum PlaybackRunStepResult: Equatable, Sendable {
    case succeeded(PlaybackRunStepSuccess)
    case failed(reason: String)
}

public struct PlaybackRunStepRequest: Sendable {
    public var loopIndex: Int
    public var step: PlaybackStep
    public var context: PlaybackContext
    public var targetSurfaceId: String
    public var scheduledTime: TimeInterval

    public init(
        loopIndex: Int,
        step: PlaybackStep,
        context: PlaybackContext,
        targetSurfaceId: String,
        scheduledTime: TimeInterval
    ) {
        self.loopIndex = loopIndex
        self.step = step
        self.context = context
        self.targetSurfaceId = targetSurfaceId
        self.scheduledTime = scheduledTime
    }
}

public struct PlaybackRunStepClient: Sendable {
    public var run: @Sendable (PlaybackRunStepRequest) async -> PlaybackRunStepResult

    public init(run: @escaping @Sendable (PlaybackRunStepRequest) async -> PlaybackRunStepResult) {
        self.run = run
    }

    public static func inputOnly(
        executor: PlaybackStepExecutor = PlaybackStepExecutor()
    ) -> PlaybackRunStepClient {
        PlaybackRunStepClient { request in
            switch executor.execute(request.step, context: request.context) {
            case .success:
                return .succeeded(.postedInput)
            case .failure(.pointResolve(let error)):
                return .failed(reason: "\(error)")
            }
        }
    }
}

public struct PlaybackRunEngineCallbacks: Sendable {
    public var loopStarted: @Sendable (Int) async -> Void
    public var progressChanged: @Sendable (Double) async -> Void

    public init(
        loopStarted: @escaping @Sendable (Int) async -> Void = { _ in },
        progressChanged: @escaping @Sendable (Double) async -> Void = { _ in }
    ) {
        self.loopStarted = loopStarted
        self.progressChanged = progressChanged
    }

    public static let none = PlaybackRunEngineCallbacks()
}

public struct PlaybackRunEngineResult: Equatable, Sendable {
    public var didAbort: Bool
    public var failureEvidence: PlaybackFailureEvidence?

    public init(
        didAbort: Bool,
        failureEvidence: PlaybackFailureEvidence? = nil
    ) {
        self.didAbort = didAbort
        self.failureEvidence = failureEvidence
    }
}

public struct PlaybackRunEngine: Sendable {
    public var plan: PlaybackPlan
    public var context: PlaybackContext
    public var macroID: UUID?
    public var runID: UUID
    public var startedAt: Date
    public var startedClock: TimeInterval
    public var clock: PlaybackClockClient
    public var windowContext: WindowContextClient
    public var conflict: PlaybackConflictClient
    public var stepClient: PlaybackRunStepClient
    public var waitStrategy: PlaybackWaitStrategy
    public var activationDelay: TimeInterval
    public var progressThrottleInterval: TimeInterval

    public init(
        plan: PlaybackPlan,
        context: PlaybackContext,
        macroID: UUID? = nil,
        runID: UUID,
        startedAt: Date,
        startedClock: TimeInterval,
        clock: PlaybackClockClient = .live,
        windowContext: WindowContextClient = .none,
        conflict: PlaybackConflictClient = .never,
        stepClient: PlaybackRunStepClient,
        waitStrategy: PlaybackWaitStrategy = .precise,
        activationDelay: TimeInterval = 0.2,
        progressThrottleInterval: TimeInterval = 0.033
    ) {
        self.plan = plan
        self.context = context
        self.macroID = macroID
        self.runID = runID
        self.startedAt = startedAt
        self.startedClock = startedClock
        self.clock = clock
        self.windowContext = windowContext
        self.conflict = conflict
        self.stepClient = stepClient
        self.waitStrategy = waitStrategy
        self.activationDelay = activationDelay
        self.progressThrottleInterval = max(0, progressThrottleInterval)
    }

    public func run(callbacks: PlaybackRunEngineCallbacks = .none) async -> PlaybackRunEngineResult {
        let infinite = plan.loopMode.isContinuous
        let total = plan.loopMode.displayLoopCount
        var loopIndex = 0
        var lastProgressPush = 0.0
        var runningContext = context

        while !Task.isCancelled {
            if !infinite, loopIndex >= total { break }
            loopIndex += 1
            await callbacks.loopStarted(loopIndex)

            windowContext.activateAll(runningContext.surfaces.values)
            await clock.sleep(activationDelay)
            windowContext.refreshResolvedFrames(in: &runningContext)

            var scheduledTime = clock.now()
            for step in plan.steps {
                if Task.isCancelled {
                    return PlaybackRunEngineResult(didAbort: false)
                }

                scheduledTime += step.deltaFromPrevious
                await clock.wait(until: scheduledTime, strategy: waitStrategy)

                if Task.isCancelled {
                    return PlaybackRunEngineResult(didAbort: false)
                }
                if conflict.hasConflict() {
                    return PlaybackRunEngineResult(didAbort: true)
                }

                let targetSurfaceId = PlaybackPlanner.targetSurfaceId(
                    for: step.event,
                    context: runningContext
                )

                refreshMissingSurfaceFrame(
                    targetSurfaceId,
                    context: &runningContext
                )

                let request = PlaybackRunStepRequest(
                    loopIndex: loopIndex,
                    step: step,
                    context: runningContext,
                    targetSurfaceId: targetSurfaceId,
                    scheduledTime: scheduledTime
                )

                switch await stepClient.run(request) {
                case .succeeded(let success):
                    let observedClock = clock.now()
                    scheduledTime = updatedScheduledTime(
                        scheduledTime,
                        timing: success.timing,
                        observedClock: observedClock
                    )
                    if success.publishesProgress,
                       plan.rawDuration > 0,
                       observedClock - lastProgressPush > progressThrottleInterval {
                        lastProgressPush = observedClock
                        await callbacks.progressChanged(step.progress)
                    }
                case .failed(let reason):
                    return abortResult(
                        reason: reason,
                        step: step,
                        context: runningContext,
                        targetSurfaceId: targetSurfaceId
                    )
                }
            }
        }

        return PlaybackRunEngineResult(didAbort: false)
    }

    private func refreshMissingSurfaceFrame(
        _ targetSurfaceId: String,
        context runningContext: inout PlaybackContext
    ) {
        guard runningContext.currentSurfaceFrames[targetSurfaceId] == nil,
              let surface = runningContext.surfaces[targetSurfaceId] else {
            return
        }

        let resolvedSurfaceIds = windowContext.refreshResolvedFrames(
            in: &runningContext,
            surfaces: [targetSurfaceId: surface],
            resetExisting: false
        )
        if resolvedSurfaceIds.contains(targetSurfaceId) {
            windowContext.activateSurface(surface)
        }
    }

    private func updatedScheduledTime(
        _ scheduledTime: TimeInterval,
        timing: PlaybackRunStepTiming,
        observedClock: TimeInterval
    ) -> TimeInterval {
        switch timing {
        case .unchanged:
            return scheduledTime
        case .resetToCurrentClock:
            return observedClock
        case .catchUpIfLate(let threshold):
            return observedClock - scheduledTime > threshold ? observedClock : scheduledTime
        }
    }

    private func abortResult(
        reason: String,
        step: PlaybackStep,
        context runningContext: PlaybackContext,
        targetSurfaceId: String
    ) -> PlaybackRunEngineResult {
        let failureEvidence = PlaybackFailureEvidenceBuilder.makeFailureEvidence(
            macroID: macroID,
            runID: runID,
            startTime: startedAt,
            duration: clock.now() - startedClock,
            step: step,
            context: runningContext,
            targetSurfaceId: targetSurfaceId,
            reason: reason
        )
        return PlaybackRunEngineResult(didAbort: true, failureEvidence: failureEvidence)
    }
}
