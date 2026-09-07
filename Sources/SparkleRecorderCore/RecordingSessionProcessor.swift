import Foundation
import os

private struct RecordingSessionProcessorState: Sendable {
    var pipeline: RecordingEventPipeline
    var scrollCompactor: ScrollGestureCompactor
    var nextEvidenceSampleIndex = 0
    var nextPlayableEventIndex = 0
    var retainedEvidenceSampleCount = 0

    mutating func reset(
        recordMouseMoves: Bool,
        ignoredKeyChords: Set<RecordingIgnoredKeyChord>,
        resumeOffsetDuration: TimeInterval
    ) {
        pipeline.reset(
            recordMouseMoves: recordMouseMoves,
            ignoredKeyChords: ignoredKeyChords,
            resumeOffsetDuration: resumeOffsetDuration
        )
        scrollCompactor.reset()
        nextEvidenceSampleIndex = 0
        nextPlayableEventIndex = 0
        retainedEvidenceSampleCount = 0
    }

    mutating func process(
        _ input: RawInputEvent,
        recordMouseMoves: Bool,
        ignoredKeyChords: Set<RecordingIgnoredKeyChord>,
        trackedActiveSurface: PlaybackSurface?,
        maximumEvidenceSamples: Int
    ) -> RecordingSessionProcessorBatch {
        pipeline.recordMouseMoves = recordMouseMoves
        pipeline.ignoredKeyChords = ignoredKeyChords
        let outputs = pipeline.process(input, trackedActiveSurface: trackedActiveSurface)
        var batch = RecordingSessionProcessorBatch(
            rawOutputCount: outputs.count,
            registry: pipeline.registry
        )

        for output in outputs {
            batch.registry = output.registry
            let evidenceIndex = retainEvidenceSample(
                for: output.event,
                maximumEvidenceSamples: maximumEvidenceSamples,
                batch: &batch
            )
            appendPlayable(
                scrollCompactor.process(output.event, evidenceSampleIndex: evidenceIndex),
                to: &batch
            )
        }
        return batch
    }

    mutating func finishPending() -> RecordingSessionProcessorBatch {
        var batch = RecordingSessionProcessorBatch(rawOutputCount: 0, registry: pipeline.registry)
        appendPlayable(scrollCompactor.finish(), to: &batch)
        return batch
    }

    private mutating func retainEvidenceSample(
        for event: RecordedEvent,
        maximumEvidenceSamples: Int,
        batch: inout RecordingSessionProcessorBatch
    ) -> Int? {
        guard event.kind.isMouse else { return nil }
        guard retainedEvidenceSampleCount < maximumEvidenceSamples else {
            batch.omittedEvidenceSampleCount += 1
            return nil
        }
        let index = nextEvidenceSampleIndex
        nextEvidenceSampleIndex += 1
        retainedEvidenceSampleCount += 1
        if let sample = RecordingEvidenceSample.mechanical(index: index, event: event) {
            batch.evidenceSamples.append(sample)
            return index
        }
        return nil
    }

    private mutating func appendPlayable(
        _ outputs: [ScrollGestureCompactionOutput],
        to batch: inout RecordingSessionProcessorBatch
    ) {
        for output in outputs {
            let playableIndex = nextPlayableEventIndex
            nextPlayableEventIndex += 1
            batch.playableEvents.append(output.event)
            if let range = output.evidenceSampleRange {
                batch.playableEvidenceLinks.append(
                    RecordingPlayableEvidenceLink(
                        playableEventIndex: playableIndex,
                        evidenceSampleRange: range
                    )
                )
            }
        }
    }
}

private struct RecordingSessionProcessorBatch: Sendable {
    var rawOutputCount: Int
    var registry: RecordingSurfaceRegistry
    var playableEvents: [RecordedEvent] = []
    var evidenceSamples: [RecordingEvidenceSample] = []
    var playableEvidenceLinks: [RecordingPlayableEvidenceLink] = []
    var omittedEvidenceSampleCount = 0
}

public final class RecordingSessionProcessor: @unchecked Sendable {
    public static let defaultMaximumEvidenceSamples = 100_000

    private let stateLock: OSAllocatedUnfairLock<RecordingSessionProcessorState>
    private let eventBuffer: RecordingEventBuffer
    private let maximumEvidenceSamples: Int

    public init(
        pipeline: RecordingEventPipeline = RecordingEventPipeline(),
        eventBuffer: RecordingEventBuffer = RecordingEventBuffer(),
        scrollCompactor: ScrollGestureCompactor = ScrollGestureCompactor(),
        maximumEvidenceSamples: Int = RecordingSessionProcessor.defaultMaximumEvidenceSamples
    ) {
        self.stateLock = OSAllocatedUnfairLock(initialState: RecordingSessionProcessorState(
            pipeline: pipeline,
            scrollCompactor: scrollCompactor
        ))
        self.eventBuffer = eventBuffer
        self.maximumEvidenceSamples = max(0, maximumEvidenceSamples)
    }

    public func reset(
        recordMouseMoves: Bool,
        ignoredKeyChords: Set<RecordingIgnoredKeyChord>,
        resumeOffsetDuration: TimeInterval
    ) {
        stateLock.withLock {
            $0.reset(
                recordMouseMoves: recordMouseMoves,
                ignoredKeyChords: ignoredKeyChords,
                resumeOffsetDuration: resumeOffsetDuration
            )
        }
        eventBuffer.reset()
    }

    @discardableResult
    public func record(
        _ input: RawInputEvent,
        recordMouseMoves: Bool,
        ignoredKeyChords: Set<RecordingIgnoredKeyChord>,
        trackedActiveSurface: PlaybackSurface?
    ) -> Int {
        let batch = stateLock.withLock {
            $0.process(
                input,
                recordMouseMoves: recordMouseMoves,
                ignoredKeyChords: ignoredKeyChords,
                trackedActiveSurface: trackedActiveSurface,
                maximumEvidenceSamples: maximumEvidenceSamples
            )
        }
        store(batch)
        return batch.rawOutputCount
    }

    /// Flushes the final partial scroll bucket after the input engine has stopped.
    /// Regular UI drains must not call this because timer boundaries are not
    /// gesture boundaries.
    public func finishPending() {
        let batch = stateLock.withLock { $0.finishPending() }
        store(batch)
    }

    public func drainPending() -> RecordingSessionTrackSnapshot {
        eventBuffer.drainPending()
    }

    private func store(_ batch: RecordingSessionProcessorBatch) {
        eventBuffer.store(
            registry: batch.registry,
            playableEvents: batch.playableEvents,
            evidenceSamples: batch.evidenceSamples,
            playableEvidenceLinks: batch.playableEvidenceLinks,
            omittedEvidenceSampleCount: batch.omittedEvidenceSampleCount
        )
    }
}
