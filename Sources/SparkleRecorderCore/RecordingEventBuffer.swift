import Foundation
import os

public struct RecordingEventBufferSnapshot: Equatable, Sendable {
    public var events: [RecordedEvent]
    public var surfaces: [String: PlaybackSurface]

    public init(events: [RecordedEvent], surfaces: [String: PlaybackSurface]) {
        self.events = events
        self.surfaces = surfaces
    }
}

private struct RecordingEventBufferState: Sendable {
    var pending: [RecordedEvent] = []
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

    public func drainPending() -> RecordingEventBufferSnapshot {
        lock.withLock {
            let events = $0.pending
            $0.pending.removeAll()
            return RecordingEventBufferSnapshot(
                events: events,
                surfaces: $0.registry.activeSurfaces
            )
        }
    }

    public func store(_ outputs: [RecordingPipelineOutput]) {
        guard !outputs.isEmpty else { return }
        lock.withLock {
            for output in outputs {
                $0.registry = output.registry
                $0.pending.append(output.event)
            }
        }
    }

    public func store(
        registry: RecordingSurfaceRegistry,
        event: RecordedEvent
    ) {
        lock.withLock {
            $0.registry = registry
            $0.pending.append(event)
        }
    }
}
