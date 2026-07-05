import Foundation
import os

public final class RecordingSessionProcessor: @unchecked Sendable {
    private let pipelineLock: OSAllocatedUnfairLock<RecordingEventPipeline>
    private let eventBuffer: RecordingEventBuffer

    public init(
        pipeline: RecordingEventPipeline = RecordingEventPipeline(),
        eventBuffer: RecordingEventBuffer = RecordingEventBuffer()
    ) {
        self.pipelineLock = OSAllocatedUnfairLock(initialState: pipeline)
        self.eventBuffer = eventBuffer
    }

    public func reset(
        recordMouseMoves: Bool,
        ignoredKeyCodes: Set<UInt16>,
        resumeOffsetDuration: TimeInterval
    ) {
        pipelineLock.withLock {
            $0.reset(
                recordMouseMoves: recordMouseMoves,
                ignoredKeyCodes: ignoredKeyCodes,
                resumeOffsetDuration: resumeOffsetDuration
            )
        }
        eventBuffer.reset()
    }

    @discardableResult
    public func record(
        _ input: RawInputEvent,
        recordMouseMoves: Bool,
        ignoredKeyCodes: Set<UInt16>,
        trackedActiveSurface: PlaybackSurface?
    ) -> Int {
        let outputs = pipelineLock.withLock {
            $0.recordMouseMoves = recordMouseMoves
            $0.ignoredKeyCodes = ignoredKeyCodes
            return $0.process(input, trackedActiveSurface: trackedActiveSurface)
        }
        eventBuffer.store(outputs)
        return outputs.count
    }

    public func drainPending() -> RecordingEventBufferSnapshot {
        eventBuffer.drainPending()
    }
}
