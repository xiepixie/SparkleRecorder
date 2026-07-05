import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Event Buffer Tests")
struct RecordingEventBufferTests {
    @Test("Drain returns pending events and keeps latest surfaces for later empty drains")
    func drainReturnsPendingEventsAndKeepsLatestSurfaces() throws {
        let buffer = RecordingEventBuffer()
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 400, height: 300)
        )
        var registry = RecordingSurfaceRegistry()
        registry.activeSurfaces["surface-1"] = surface

        let first = RecordedEvent.make(.leftMouseDown, time: 0, x: 120, y: 140)
        let second = RecordedEvent.make(.leftMouseUp, time: 0.1, x: 120, y: 140)

        buffer.store(registry: registry, event: first)
        buffer.store(registry: registry, event: second)

        let drained = buffer.drainPending()
        let empty = buffer.drainPending()

        #expect(drained.events == [first, second])
        #expect(drained.surfaces == ["surface-1": surface])
        #expect(empty.events.isEmpty)
        #expect(empty.surfaces == ["surface-1": surface])
    }

    @Test("Reset clears pending events and surface registry")
    func resetClearsPendingEventsAndSurfaceRegistry() {
        let buffer = RecordingEventBuffer()
        var registry = RecordingSurfaceRegistry()
        registry.activeSurfaces["surface-1"] = TestFixtures.surface()

        buffer.store(
            registry: registry,
            event: RecordedEvent.make(.leftMouseDown, time: 0, x: 1, y: 2)
        )
        buffer.reset()

        let drained = buffer.drainPending()
        #expect(drained.events.isEmpty)
        #expect(drained.surfaces.isEmpty)
    }

    @Test("Store outputs appends in order and tracks the latest registry")
    func storeOutputsAppendsInOrderAndTracksLatestRegistry() {
        let buffer = RecordingEventBuffer()
        let firstSurface = TestFixtures.surface(windowTitle: "First")
        let secondSurface = TestFixtures.surface(windowTitle: "Second")
        var firstRegistry = RecordingSurfaceRegistry()
        firstRegistry.activeSurfaces["surface-1"] = firstSurface
        var secondRegistry = firstRegistry
        secondRegistry.activeSurfaces["surface-2"] = secondSurface

        let first = RecordedEvent.make(.leftMouseDown, time: 0, x: 10, y: 20)
        let second = RecordedEvent.make(.leftMouseUp, time: 0.2, x: 10, y: 20)

        buffer.store([
            RecordingPipelineOutput(registry: firstRegistry, event: first),
            RecordingPipelineOutput(registry: secondRegistry, event: second)
        ])

        let drained = buffer.drainPending()
        #expect(drained.events == [first, second])
        #expect(drained.surfaces["surface-1"] == firstSurface)
        #expect(drained.surfaces["surface-2"] == secondSurface)
    }
}
