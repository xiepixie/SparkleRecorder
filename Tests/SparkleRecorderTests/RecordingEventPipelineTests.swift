import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Event Pipeline Tests")
struct RecordingEventPipelineTests {
    @Test("Disabled mouse moves are filtered before they set the recording clock")
    func disabledMouseMovesAreFilteredBeforeSettingClock() throws {
        var pipeline = RecordingEventPipeline(recordMouseMoves: false)

        let moveOutputs = pipeline.process(
            RawInputEvent(
                kind: .mouseMoved,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 5, y: 6)
            ),
            trackedActiveSurface: nil
        )

        #expect(moveOutputs.isEmpty)
        #expect(pipeline.baseTimestamp == nil)

        let downOutputs = pipeline.process(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 2_000_000_000,
                location: CGPoint(x: 10, y: 12),
                mouseButton: 0,
                clickCount: 1
            ),
            trackedActiveSurface: nil
        )
        let event = try #require(downOutputs.first?.event)

        #expect(event.kind == .leftMouseDown)
        #expect(event.time == 0)
        #expect(event.coordinateBinding == .unbound)
    }

    @Test("Ignored key events are dropped while preserving clock alignment")
    func ignoredKeyEventsAreDroppedWhilePreservingClockAlignment() throws {
        var pipeline = RecordingEventPipeline(ignoredKeyCodes: [49])

        let keyOutputs = pipeline.process(
            RawInputEvent(
                kind: .keyDown,
                timestamp: 1_000_000_000,
                location: .zero,
                keyCode: 49,
                unicodeString: " "
            ),
            trackedActiveSurface: nil
        )

        #expect(keyOutputs.isEmpty)
        #expect(pipeline.baseTimestamp == 1_000_000_000)

        let downOutputs = pipeline.process(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 2_000_000_000,
                location: CGPoint(x: 40, y: 50)
            ),
            trackedActiveSurface: nil
        )
        let event = try #require(downOutputs.first?.event)

        #expect(event.time == 1.0)
    }

    @Test("Mouse input records target surface and local coordinate fields")
    func mouseInputRecordsTargetSurfaceAndLocalCoordinateFields() throws {
        var pipeline = RecordingEventPipeline()
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 200, height: 100),
            recordedContentFrame: RectValue(x: 100, y: 120, width: 200, height: 80)
        )

        let outputs = pipeline.process(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 150, y: 160),
                mouseButton: 0,
                clickCount: 1
            ),
            trackedActiveSurface: surface
        )
        let output = try #require(outputs.first)
        let event = output.event

        #expect(outputs.count == 1)
        #expect(event.surfaceId == "surface-1")
        #expect(event.coordinateBinding == .targetWindow)
        #expect(event.windowLocalX == 50)
        #expect(event.windowLocalY == 40)
        #expect(event.contentLocalX == 50)
        #expect(event.contentLocalY == 40)
        #expect(output.registry.activeSurfaces["surface-1"] == surface)
    }

    @Test("Scroll input builds payload and playback deltas from the raw sample")
    func scrollInputBuildsPayloadAndPlaybackDeltas() throws {
        var pipeline = RecordingEventPipeline()
        let outputs = pipeline.process(
            RawInputEvent(
                kind: .scrollWheel,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 11, y: 22),
                scrollSample: RecordingScrollSample(
                    pointDeltaX: 0,
                    pointDeltaY: 0,
                    lineDeltaX: 2,
                    lineDeltaY: -3,
                    phase: 1,
                    momentumPhase: 0,
                    fixedRawX: 65_536,
                    fixedRawY: -131_072,
                    isContinuous: true
                )
            ),
            trackedActiveSurface: nil
        )
        let event = try #require(outputs.first?.event)
        let payload = try #require(event.scrollPayload)

        #expect(event.scrollDeltaX == 24)
        #expect(event.scrollDeltaY == -36)
        #expect(payload.lineDeltaX == 2)
        #expect(payload.lineDeltaY == -3)
        #expect(payload.fixedDeltaX == 1.0)
        #expect(payload.fixedDeltaY == -2.0)
        #expect(payload.isContinuous)
    }

    @Test("Dropped drag sample is emitted before mouse up")
    func droppedDragSampleIsEmittedBeforeMouseUp() throws {
        var pipeline = RecordingEventPipeline()

        _ = pipeline.process(
            RawInputEvent(kind: .leftMouseDown, timestamp: 0, location: .zero),
            trackedActiveSurface: nil
        )
        let firstDrag = pipeline.process(
            RawInputEvent(
                kind: .leftMouseDragged,
                timestamp: 20_000_000,
                location: CGPoint(x: 10, y: 0)
            ),
            trackedActiveSurface: nil
        )
        let droppedDrag = pipeline.process(
            RawInputEvent(
                kind: .leftMouseDragged,
                timestamp: 21_000_000,
                location: CGPoint(x: 10.5, y: 0)
            ),
            trackedActiveSurface: nil
        )
        let mouseUp = pipeline.process(
            RawInputEvent(
                kind: .leftMouseUp,
                timestamp: 30_000_000,
                location: CGPoint(x: 11, y: 0)
            ),
            trackedActiveSurface: nil
        )

        #expect(firstDrag.count == 1)
        #expect(droppedDrag.isEmpty)
        #expect(mouseUp.count == 2)
        #expect(mouseUp[0].event.kind == .leftMouseDragged)
        #expect(mouseUp[0].event.x == 10.5)
        #expect(abs(mouseUp[0].event.time - 0.021) < 0.000_001)
        #expect(mouseUp[1].event.kind == .leftMouseUp)
        #expect(abs(mouseUp[1].event.time - 0.030) < 0.000_001)
    }
}
