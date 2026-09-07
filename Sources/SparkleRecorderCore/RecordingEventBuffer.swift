import Foundation
import os

private struct RecordingEventBufferState: Sendable {
    var pendingPlayableEvents: [RecordedEvent] = []
    var pendingEvidenceSamples: [RecordingEvidenceSample] = []
    var pendingPlayableEvidenceLinks: [RecordingPlayableEvidenceLink] = []
    var pendingOmittedEvidenceSampleCount = 0
    var registry = RecordingSurfaceRegistry()
}

public final class RecordingEventBuffer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: RecordingEventBufferState())

    public init() {}

    public func reset() {
        lock.withLock {
            $0 = RecordingEventBufferState()
        }
    }

    public func drainPending() -> RecordingSessionTrackSnapshot {
        lock.withLock {
            let snapshot = RecordingSessionTrackSnapshot(
                playableEvents: $0.pendingPlayableEvents,
                evidenceSamples: $0.pendingEvidenceSamples,
                playableEvidenceLinks: $0.pendingPlayableEvidenceLinks,
                omittedEvidenceSampleCount: $0.pendingOmittedEvidenceSampleCount,
                surfaces: $0.registry.activeSurfaces
            )
            $0.pendingPlayableEvents.removeAll(keepingCapacity: true)
            $0.pendingEvidenceSamples.removeAll(keepingCapacity: true)
            $0.pendingPlayableEvidenceLinks.removeAll(keepingCapacity: true)
            $0.pendingOmittedEvidenceSampleCount = 0
            return snapshot
        }
    }

    public func store(
        registry: RecordingSurfaceRegistry,
        playableEvents: [RecordedEvent],
        evidenceSamples: [RecordingEvidenceSample],
        playableEvidenceLinks: [RecordingPlayableEvidenceLink],
        omittedEvidenceSampleCount: Int = 0
    ) {
        guard !playableEvents.isEmpty || !evidenceSamples.isEmpty ||
                !playableEvidenceLinks.isEmpty || omittedEvidenceSampleCount > 0 else { return }
        lock.withLock {
            $0.registry = registry
            $0.pendingPlayableEvents.append(contentsOf: playableEvents)
            $0.pendingEvidenceSamples.append(contentsOf: evidenceSamples)
            $0.pendingPlayableEvidenceLinks.append(contentsOf: playableEvidenceLinks)
            $0.pendingOmittedEvidenceSampleCount += max(0, omittedEvidenceSampleCount)
        }
    }

    /// Compatibility helper for direct buffer tests and non-session callers.
    /// RecordingSessionProcessor uses the explicit dual-track store above.
    public func store(_ outputs: [RecordingPipelineOutput]) {
        guard !outputs.isEmpty else { return }
        lock.withLock {
            for output in outputs {
                $0.registry = output.registry
                $0.pendingPlayableEvents.append(output.event)
            }
        }
    }

    public func store(
        registry: RecordingSurfaceRegistry,
        event: RecordedEvent
    ) {
        lock.withLock {
            $0.registry = registry
            $0.pendingPlayableEvents.append(event)
        }
    }
}
