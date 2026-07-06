import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Macro Transformer Timing Tests")
struct MacroTransformerTimingTests {
    @Test("Wait text conversion applies as playable text click events")
    func waitTextConversionAppliesAsPlayableTextClickEvents() throws {
        var wait = RecordedEvent.make(.waitForText, time: 1.0)
        wait.textAnchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24)
        )
        wait.textTimeout = 7.0
        wait.locatorFallbackPolicy = .allowCoordinateFallback
        wait.surfaceId = "checkout"
        let next = RecordedEvent.make(.keyDown, time: 1.05, keyCode: 36)
        var events = [wait, next]
        var liveDuration = 1.2
        let waitGroup = try #require(EventGrouper().group(events, liveDuration: liveDuration).first)

        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: waitGroup,
            events: events,
            liveDuration: liveDuration
        )
        events.applyTextClickConversionPlan(plan)
        if let convertedDuration = plan.liveDurationAfterConversion {
            liveDuration = convertedDuration
        }

        #expect(events.map(\.kind) == [.leftMouseDown, .leftMouseUp, .keyDown])
        #expect(events.map(\.coordinateStrategy) == [.locatorOnly, .locatorOnly, nil])
        #expect(events[0].textAnchor?.text == "Confirm")
        #expect(events[0].textAnchor?.coordinateFallback == PointValue(x: 130, y: 102))
        #expect(events[0].textTimeout == 7.0)
        #expect(events[0].locatorFallbackPolicy == .allowCoordinateFallback)
        #expect(events[0].surfaceId == "checkout")
        #expect(abs(events[2].time - 1.1) < 0.000_001)
        #expect(abs(liveDuration - 1.25) < 0.000_001)

        let groups = EventGrouper().group(events, liveDuration: liveDuration)
        let click = try #require(groups.first)
        #expect(click.kind == .click)
        #expect(click.summary == "Click text: Confirm")
        #expect(click.textTargetReadiness == .ready)
        #expect(!groups.contains { $0.kind == .waitForText })
    }

    @Test("Live duration stretch preserves trailing wait beyond last event")
    func liveDurationStretchPreservesTrailingWaitBeyondLastEvent() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.5, x: 10, y: 10)
        ]

        let stretched = events.liveDurationAfterStretching(2.0, by: 0.5)

        #expect(abs(stretched - 1.0) < 0.000_001)
    }

    @Test("Live duration stretch never falls behind scaled last event")
    func liveDurationStretchNeverFallsBehindScaledLastEvent() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 3.0, x: 10, y: 10)
        ]

        let stretched = events.liveDurationAfterStretching(2.0, by: 2.0)

        #expect(abs(stretched - 6.0) < 0.000_001)
    }
}
