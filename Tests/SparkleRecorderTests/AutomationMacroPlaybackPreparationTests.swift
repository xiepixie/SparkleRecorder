import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Macro Playback Preparation Tests")
struct AutomationMacroPlaybackPreparationTests {
    @Test("Explicit global-screen pointer input remains global")
    func explicitGlobalScreenInputIsPreserved() {
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
            recordedContentFrame: RectValue(x: 100, y: 132, width: 800, height: 568)
        )
        var event = TestFixtures.clickEvent(time: 0, x: 300, y: 300)
        event.coordinateBinding = .globalScreen
        event.surfaceId = nil
        let macro = SavedMacro(
            name: "Explicit global",
            events: [event],
            surfaces: [TestFixtures.surfaceId: surface],
            followWindowOffset: true
        )

        let prepared = AutomationMacroPlaybackPreparation.prepare(macro)

        #expect(prepared.events == macro.events)
        #expect(prepared.events[0].coordinateBinding == .globalScreen)
        #expect(prepared.events[0].surfaceId == nil)
    }

    @Test("Legacy input without recorded content geometry is not guessed")
    func missingContentGeometryStaysUnbound() {
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
            recordedContentFrame: nil
        )
        var event = TestFixtures.clickEvent(time: 0, x: 300, y: 300)
        event.coordinateBinding = nil
        event.surfaceId = nil
        let macro = SavedMacro(
            name: "Incomplete legacy geometry",
            events: [event],
            surfaces: [TestFixtures.surfaceId: surface],
            followWindowOffset: true
        )

        let prepared = AutomationMacroPlaybackPreparation.prepare(macro)

        #expect(prepared == macro)
    }

    @Test("Ambiguous legacy pointer input is not guessed across overlapping surfaces")
    func ambiguousLegacyInputStaysUnbound() {
        let frame = RectValue(x: 100, y: 100, width: 800, height: 600)
        let first = TestFixtures.surface(recordedFrame: frame, recordedContentFrame: frame)
        let second = TestFixtures.surface(recordedFrame: frame, recordedContentFrame: frame)
        var event = TestFixtures.clickEvent(time: 0, x: 300, y: 300)
        event.coordinateBinding = nil
        event.surfaceId = nil
        let macro = SavedMacro(
            name: "Ambiguous legacy",
            events: [event],
            surfaces: ["surface-1": first, "surface-2": second],
            followWindowOffset: true
        )

        let prepared = AutomationMacroPlaybackPreparation.prepare(macro)

        #expect(prepared.events == macro.events)
        #expect(prepared.events[0].coordinateBinding == nil)
        #expect(prepared.events[0].surfaceId == nil)
    }
}
