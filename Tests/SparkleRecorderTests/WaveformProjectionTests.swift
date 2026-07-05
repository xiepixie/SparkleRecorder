import Testing
@testable import SparkleRecorderCore

@Suite("Waveform Projection Tests")
struct WaveformProjectionTests {
    @Test("Indexed bars preserve event order and use stable fractions")
    func indexedBarsPreserveOrder() {
        let events = [
            RecordedEvent.make(.mouseMoved, time: 0),
            RecordedEvent.make(.leftMouseDown, time: 0.1),
            RecordedEvent.make(.scrollWheel, time: 0.2)
        ]

        let bars = WaveformProjection.indexedBars(from: events)

        #expect(bars.map(\.id) == [0, 1, 2])
        #expect(bars.map(\.kind) == [.mouseMoved, .leftMouseDown, .scrollWheel])
        #expect(bars.map(\.positionFraction) == [0, 1.0 / 3.0, 2.0 / 3.0])
        #expect(bars.map(\.isImpact) == [false, true, true])
    }

    @Test("Timed bars cap long waveforms and preserve endpoints")
    func timedBarsCapLongWaveforms() {
        let events = (0..<1_000).map { index in
            RecordedEvent.make(.mouseMoved, time: Double(index))
        }

        let bars = WaveformProjection.timedBars(from: events, maxBars: 60)

        #expect(bars.count == 60)
        #expect(bars.first?.id == 0)
        #expect(bars.last?.id == 999)
        #expect(bars.first?.positionFraction == 0)
        #expect(bars.last?.positionFraction == 1)

        let ids = bars.map(\.id)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
    }

    @Test("Timed bars clamp fractions to the drawing range")
    func timedBarsClampFractions() {
        let events = [
            RecordedEvent.make(.keyDown, time: -1),
            RecordedEvent.make(.keyUp, time: 3)
        ]

        let bars = WaveformProjection.timedBars(from: events, maxBars: 10, duration: 2)

        #expect(bars.map(\.positionFraction) == [0, 1])
    }
}
