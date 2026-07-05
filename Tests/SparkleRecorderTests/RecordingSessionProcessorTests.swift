import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Session Processor Tests")
struct RecordingSessionProcessorTests {
    @Test("Recording raw input stores pipeline output in the pending buffer")
    func recordingRawInputStoresPipelineOutputInPendingBuffer() throws {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            resumeOffsetDuration: 0
        )

        let outputCount = processor.record(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 42, y: 84),
                mouseButton: 0,
                clickCount: 1
            ),
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            trackedActiveSurface: nil
        )

        let drained = processor.drainPending()
        let event = try #require(drained.events.first)

        #expect(outputCount == 1)
        #expect(drained.events.count == 1)
        #expect(event.kind == .leftMouseDown)
        #expect(event.x == 42)
        #expect(event.y == 84)
        #expect(event.time == 0)
        #expect(processor.drainPending().events.isEmpty)
    }

    @Test("Disabled mouse move records no pending event")
    func disabledMouseMoveRecordsNoPendingEvent() {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            resumeOffsetDuration: 0
        )

        let outputCount = processor.record(
            RawInputEvent(
                kind: .mouseMoved,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 10, y: 20)
            ),
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            trackedActiveSurface: nil
        )

        #expect(outputCount == 0)
        #expect(processor.drainPending().events.isEmpty)
    }

    @Test("Dynamic ignored key configuration is applied per input")
    func dynamicIgnoredKeyConfigurationIsAppliedPerInput() {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            resumeOffsetDuration: 0
        )
        let keyInput = RawInputEvent(
            kind: .keyDown,
            timestamp: 1_000_000_000,
            location: .zero,
            keyCode: 49,
            unicodeString: " "
        )

        let dropped = processor.record(
            keyInput,
            recordMouseMoves: false,
            ignoredKeyCodes: [49],
            trackedActiveSurface: nil
        )
        let kept = processor.record(
            RawInputEvent(
                kind: .keyDown,
                timestamp: 1_100_000_000,
                location: .zero,
                keyCode: 49,
                unicodeString: " "
            ),
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            trackedActiveSurface: nil
        )

        let drained = processor.drainPending()

        #expect(dropped == 0)
        #expect(kept == 1)
        #expect(drained.events.map(\.keyCode) == [49])
        #expect(drained.events.first?.time == 0.1)
    }

    @Test("Reset clears pending events and resets event time base")
    func resetClearsPendingEventsAndResetsEventTimeBase() throws {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            resumeOffsetDuration: 0
        )
        processor.record(
            RawInputEvent(kind: .leftMouseDown, timestamp: 1_000_000_000, location: .zero),
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            trackedActiveSurface: nil
        )

        processor.reset(
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            resumeOffsetDuration: 0
        )
        processor.record(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 10_000_000_000,
                location: CGPoint(x: 3, y: 4)
            ),
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            trackedActiveSurface: nil
        )

        let drained = processor.drainPending()
        let event = try #require(drained.events.first)

        #expect(drained.events.count == 1)
        #expect(event.time == 0)
        #expect(event.x == 3)
        #expect(event.y == 4)
    }

    @Test("Tracked surface is carried through the pending buffer snapshot")
    func trackedSurfaceIsCarriedThroughPendingBufferSnapshot() {
        let processor = RecordingSessionProcessor()
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 300, height: 200),
            recordedContentFrame: RectValue(x: 100, y: 124, width: 300, height: 176)
        )

        processor.reset(
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            resumeOffsetDuration: 0
        )
        processor.record(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 150, y: 150)
            ),
            recordMouseMoves: false,
            ignoredKeyCodes: [],
            trackedActiveSurface: surface
        )

        let drained = processor.drainPending()

        #expect(drained.events.first?.surfaceId == "surface-1")
        #expect(drained.events.first?.coordinateBinding == .targetWindow)
        #expect(drained.surfaces["surface-1"] == surface)
    }
}
