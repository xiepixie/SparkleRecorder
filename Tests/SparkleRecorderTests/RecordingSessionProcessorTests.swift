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
            ignoredKeyChords: [],
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
            ignoredKeyChords: [],
            trackedActiveSurface: nil
        )

        let drained = processor.drainPending()
        let event = try #require(drained.playableEvents.first)

        #expect(outputCount == 1)
        #expect(drained.playableEvents.count == 1)
        #expect(event.kind == .leftMouseDown)
        #expect(event.x == 42)
        #expect(event.y == 84)
        #expect(event.time == 0)
        #expect(processor.drainPending().playableEvents.isEmpty)
    }

    @Test("Disabled mouse move records no pending event")
    func disabledMouseMoveRecordsNoPendingEvent() {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyChords: [],
            resumeOffsetDuration: 0
        )

        let outputCount = processor.record(
            RawInputEvent(
                kind: .mouseMoved,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 10, y: 20)
            ),
            recordMouseMoves: false,
            ignoredKeyChords: [],
            trackedActiveSurface: nil
        )

        #expect(outputCount == 0)
        #expect(processor.drainPending().playableEvents.isEmpty)
    }

    @Test("Dynamic ignored key configuration is applied per input")
    func dynamicIgnoredKeyConfigurationIsAppliedPerInput() {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyChords: [],
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
            ignoredKeyChords: [RecordingIgnoredKeyChord(keyCode: 49, modifiers: 0)],
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
            ignoredKeyChords: [],
            trackedActiveSurface: nil
        )

        let drained = processor.drainPending()

        #expect(dropped == 0)
        #expect(kept == 1)
        #expect(drained.playableEvents.map(\.keyCode) == [49])
        #expect(drained.playableEvents.first?.time == 0.1)
    }

    @Test("Reset clears pending events and resets event time base")
    func resetClearsPendingEventsAndResetsEventTimeBase() throws {
        let processor = RecordingSessionProcessor()
        processor.reset(
            recordMouseMoves: false,
            ignoredKeyChords: [],
            resumeOffsetDuration: 0
        )
        processor.record(
            RawInputEvent(kind: .leftMouseDown, timestamp: 1_000_000_000, location: .zero),
            recordMouseMoves: false,
            ignoredKeyChords: [],
            trackedActiveSurface: nil
        )

        processor.reset(
            recordMouseMoves: false,
            ignoredKeyChords: [],
            resumeOffsetDuration: 0
        )
        processor.record(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 10_000_000_000,
                location: CGPoint(x: 3, y: 4)
            ),
            recordMouseMoves: false,
            ignoredKeyChords: [],
            trackedActiveSurface: nil
        )

        let drained = processor.drainPending()
        let event = try #require(drained.playableEvents.first)

        #expect(drained.playableEvents.count == 1)
        #expect(event.time == 0)
        #expect(event.x == 3)
        #expect(event.y == 4)
    }

    @Test("Scroll recording keeps compact playable events and high-resolution evidence across drains")
    func scrollTracksStaySeparateAcrossDrains() {
        let processor = RecordingSessionProcessor(
            scrollCompactor: ScrollGestureCompactor(
                configuration: .init(sampleInterval: 0.05, maximumContinuousGap: 0.2)
            )
        )
        processor.reset(recordMouseMoves: false, ignoredKeyChords: [], resumeOffsetDuration: 0)

        func input(_ index: Int) -> RawInputEvent {
            RawInputEvent(
                kind: .scrollWheel,
                timestamp: UInt64(index) * 10_000_000,
                location: CGPoint(x: 100, y: 200),
                scrollSample: RecordingScrollSample(
                    pointDeltaX: 0,
                    pointDeltaY: -1,
                    lineDeltaX: 0,
                    lineDeltaY: 0,
                    phase: 1,
                    momentumPhase: 0,
                    fixedRawX: 0,
                    fixedRawY: -65_536,
                    isContinuous: true
                )
            )
        }

        for index in 0..<5 {
            processor.record(input(index), recordMouseMoves: false, ignoredKeyChords: [], trackedActiveSurface: nil)
        }
        let firstDrain = processor.drainPending()
        for index in 5..<10 {
            processor.record(input(index), recordMouseMoves: false, ignoredKeyChords: [], trackedActiveSurface: nil)
        }
        processor.finishPending()
        let secondDrain = processor.drainPending()

        let playable = firstDrain.playableEvents + secondDrain.playableEvents
        let evidence = firstDrain.evidenceSamples + secondDrain.evidenceSamples
        let links = firstDrain.playableEvidenceLinks + secondDrain.playableEvidenceLinks

        #expect(firstDrain.evidenceSamples.count == 5)
        #expect(firstDrain.playableEvents.count == 1)
        #expect(evidence.map(\.index) == Array(0..<10))
        #expect(evidence.count == 10)
        #expect(playable.count < evidence.count)
        #expect(playable.reduce(Int64(0)) { $0 + Int64($1.scrollDeltaY) } == -10)
        #expect(links.map(\.evidenceSampleRange) == [0...0, 1...5, 6...9])
    }

    @Test("Mechanical evidence is bounded and does not duplicate readable key input")
    func evidenceTrackIsBoundedAndMechanicalOnly() {
        let processor = RecordingSessionProcessor(maximumEvidenceSamples: 2)
        processor.reset(recordMouseMoves: false, ignoredKeyChords: [], resumeOffsetDuration: 0)

        for index in 0..<3 {
            processor.record(
                RawInputEvent(
                    kind: .scrollWheel,
                    timestamp: UInt64(index) * 10_000_000,
                    location: CGPoint(x: 10, y: 20),
                    scrollSample: RecordingScrollSample(
                        pointDeltaX: 0,
                        pointDeltaY: -1,
                        lineDeltaX: 0,
                        lineDeltaY: 0,
                        phase: 1,
                        momentumPhase: 0,
                        fixedRawX: 0,
                        fixedRawY: -65_536,
                        isContinuous: true
                    )
                ),
                recordMouseMoves: false,
                ignoredKeyChords: [],
                trackedActiveSurface: nil
            )
        }
        processor.record(
            RawInputEvent(
                kind: .keyDown,
                timestamp: 40_000_000,
                location: .zero,
                keyCode: 0,
                unicodeString: "secret"
            ),
            recordMouseMoves: false,
            ignoredKeyChords: [],
            trackedActiveSurface: nil
        )
        processor.finishPending()
        let drained = processor.drainPending()

        #expect(drained.evidenceSamples.count == 2)
        #expect(drained.evidenceSamples.allSatisfy { $0.kind == .scrollWheel })
        #expect(drained.omittedEvidenceSampleCount == 1)
        #expect(drained.playableEvents.contains { $0.kind == .keyDown && $0.unicodeString == "secret" })
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
            ignoredKeyChords: [],
            resumeOffsetDuration: 0
        )
        processor.record(
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 150, y: 150)
            ),
            recordMouseMoves: false,
            ignoredKeyChords: [],
            trackedActiveSurface: surface
        )

        let drained = processor.drainPending()

        #expect(drained.playableEvents.first?.surfaceId == "surface-1")
        #expect(drained.playableEvents.first?.coordinateBinding == .targetWindow)
        #expect(drained.surfaces["surface-1"] == surface)
    }
}
