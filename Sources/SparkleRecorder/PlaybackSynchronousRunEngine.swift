import Foundation

public struct PlaybackSynchronousRunStepClient: Sendable {
    public var run: @Sendable (PlaybackRunStepRequest) -> PlaybackRunStepResult

    public init(run: @escaping @Sendable (PlaybackRunStepRequest) -> PlaybackRunStepResult) {
        self.run = run
    }

    public static func inputOnly(
        executor: PlaybackStepExecutor = PlaybackStepExecutor()
    ) -> PlaybackSynchronousRunStepClient {
        PlaybackSynchronousRunStepClient { request in
            switch executor.execute(request.step, context: request.context) {
            case .success:
                return .succeeded(.postedInput)
            case .failure(.pointResolve(let error)):
                return .failed(reason: "\(error)")
            }
        }
    }
}

public struct PlaybackSynchronousRunEngineCallbacks: Sendable {
    public var loopStarted: @Sendable (Int) -> Void
    public var progressChanged: @Sendable (Double) -> Void

    public init(
        loopStarted: @escaping @Sendable (Int) -> Void = { _ in },
        progressChanged: @escaping @Sendable (Double) -> Void = { _ in }
    ) {
        self.loopStarted = loopStarted
        self.progressChanged = progressChanged
    }

    public static let none = PlaybackSynchronousRunEngineCallbacks()
}

public struct PlaybackSynchronousRunEngine: Sendable {
    public var plan: PlaybackPlan
    public var context: PlaybackContext
    public var macroID: UUID?
    public var runID: UUID
    public var startedAt: Date
    public var startedClock: TimeInterval
    public var clock: PlaybackClockClient
    public var windowContext: WindowContextClient
    public var conflict: PlaybackConflictClient
    public var stepClient: PlaybackSynchronousRunStepClient
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
        stepClient: PlaybackSynchronousRunStepClient,
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

    public func run(callbacks: PlaybackSynchronousRunEngineCallbacks = .none) -> PlaybackRunEngineResult {
        let total = plan.loopMode.displayLoopCount
        guard total > 0 else {
            return PlaybackRunEngineResult(didAbort: false)
        }
        var lastProgressPush = 0.0
        var runningContext = context
        var loopIndex = 0

        while loopIndex < total {
            loopIndex += 1
            callbacks.loopStarted(loopIndex)

            windowContext.activateAll(runningContext.surfaces.values)
            clock.sleepSynchronously(activationDelay)
            windowContext.refreshResolvedFrames(in: &runningContext)

            var scheduledTime = clock.now()
            for step in plan.steps {
                scheduledTime += step.deltaFromPrevious
                clock.waitSynchronously(until: scheduledTime, strategy: waitStrategy)

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

                switch stepClient.run(request) {
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
                        callbacks.progressChanged(step.progress)
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
