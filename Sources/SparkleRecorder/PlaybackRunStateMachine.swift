import Foundation

public struct PlaybackRunSnapshot: Equatable, Sendable {
    public var generation: UInt64
    public var isPlaying: Bool
    public var currentLoop: Int
    public var totalLoops: Int
    public var progress: Double

    public init(
        generation: UInt64,
        isPlaying: Bool,
        currentLoop: Int,
        totalLoops: Int,
        progress: Double
    ) {
        self.generation = generation
        self.isPlaying = isPlaying
        self.currentLoop = max(0, currentLoop)
        self.totalLoops = max(1, totalLoops)
        self.progress = Self.clampedProgress(progress)
    }

    public static func idle(generation: UInt64 = 0) -> PlaybackRunSnapshot {
        PlaybackRunSnapshot(
            generation: generation,
            isPlaying: false,
            currentLoop: 0,
            totalLoops: 1,
            progress: 0
        )
    }

    private static func clampedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else {
            return 0
        }
        return min(1, max(0, progress))
    }
}

public struct PlaybackRunCompletion: Equatable, Sendable {
    public var didFinishNaturally: Bool
    public var automationCompletion: AutomationPlayerCompletion

    public init(
        didFinishNaturally: Bool,
        automationCompletion: AutomationPlayerCompletion
    ) {
        self.didFinishNaturally = didFinishNaturally
        self.automationCompletion = automationCompletion
    }
}

public struct PlaybackRunStateMachine: Equatable, Sendable {
    public private(set) var snapshot: PlaybackRunSnapshot

    public init(snapshot: PlaybackRunSnapshot = .idle()) {
        self.snapshot = snapshot
    }

    public mutating func start(totalLoops: Int) -> PlaybackRunSnapshot {
        let nextGeneration = snapshot.generation &+ 1
        snapshot = PlaybackRunSnapshot(
            generation: nextGeneration,
            isPlaying: true,
            currentLoop: 0,
            totalLoops: totalLoops,
            progress: 0
        )
        return snapshot
    }

    public mutating func stop() -> PlaybackRunSnapshot {
        let nextGeneration = snapshot.generation &+ 1
        snapshot = .idle(generation: nextGeneration)
        return snapshot
    }

    public mutating func updateCurrentLoop(
        _ loop: Int,
        generation expectedGeneration: UInt64
    ) -> PlaybackRunSnapshot? {
        guard snapshot.generation == expectedGeneration, snapshot.isPlaying else {
            return nil
        }
        snapshot.currentLoop = max(0, loop)
        return snapshot
    }

    public mutating func updateProgress(
        _ progress: Double,
        generation expectedGeneration: UInt64
    ) -> PlaybackRunSnapshot? {
        guard snapshot.generation == expectedGeneration, snapshot.isPlaying else {
            return nil
        }
        snapshot.progress = PlaybackRunSnapshot(
            generation: snapshot.generation,
            isPlaying: snapshot.isPlaying,
            currentLoop: snapshot.currentLoop,
            totalLoops: snapshot.totalLoops,
            progress: progress
        ).progress
        return snapshot
    }

    public mutating func finish(
        generation expectedGeneration: UInt64
    ) -> PlaybackRunSnapshot? {
        guard snapshot.generation == expectedGeneration else {
            return nil
        }
        snapshot = .idle(generation: expectedGeneration)
        return snapshot
    }

    public static func completion(
        runID: UUID,
        startedAt: Date,
        duration: TimeInterval,
        didAbort: Bool,
        wasCancelled: Bool,
        failureEvidence: PlaybackFailureEvidence?
    ) -> PlaybackRunCompletion {
        if wasCancelled {
            return PlaybackRunCompletion(
                didFinishNaturally: false,
                automationCompletion: .cancelled(reason: "Playback cancelled")
            )
        }

        if didAbort {
            return PlaybackRunCompletion(
                didFinishNaturally: false,
                automationCompletion: .failed(report: failureEvidence?.report ?? RunReport(
                    runID: runID,
                    startTime: startedAt,
                    duration: duration,
                    isSuccess: false,
                    errorMessage: "Playback aborted"
                ))
            )
        }

        return PlaybackRunCompletion(
            didFinishNaturally: true,
            automationCompletion: .succeeded(report: RunReport(
                runID: runID,
                startTime: startedAt,
                duration: duration,
                isSuccess: true
            ))
        )
    }
}
