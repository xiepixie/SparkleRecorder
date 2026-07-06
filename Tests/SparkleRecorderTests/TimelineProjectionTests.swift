import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Timeline Projection Tests")
struct TimelineProjectionTests {
    @Test("Sampler caps long timelines and preserves first and last events")
    func samplerCapsLongTimelines() throws {
        let events = (0..<1_000).map { index in
            RecordedEvent.make(.mouseMoved, time: TimeInterval(index), x: CGFloat(index), y: 0)
        }

        let samples = TimelineProjection.sampleEvents(from: events, maxSamples: 100)

        #expect(samples.count == 100)
        #expect(samples.first?.id == 0)
        #expect(samples.last?.id == 999)

        let ids = samples.map(\TimelineSampledEvent.id)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)

        let last = try #require(samples.last)
        #expect(last.event.time == 999)
    }

    @Test("Sampler keeps short timelines exact")
    func samplerKeepsShortTimelinesExact() {
        let events = TestFixtures.clickPair(downTime: 0, upTime: 0.1)

        let samples = TimelineProjection.sampleEvents(from: events, maxSamples: 800)

        #expect(samples.map(\.id) == [0, 1])
        #expect(samples.map(\.event.kind) == [.leftMouseDown, .leftMouseUp])
    }

    @Test("Selection range spans selected groups")
    func selectionRangeSpansSelectedGroups() throws {
        let first = ActionGroup(kind: .click, eventIndices: [0, 1], startTime: 1, endTime: 1.1, summary: "Click")
        let second = ActionGroup(kind: .scroll, eventIndices: [2], startTime: 3, endTime: 3.4, summary: "Scroll")
        let ignored = ActionGroup(kind: .wait, eventIndices: [], startTime: 5, endTime: 6, summary: "Wait")

        let range = try #require(TimelineProjection.selectedTimeRange(
            selection: [first.id, second.id],
            groups: [first, second, ignored]
        ))

        #expect(range.start == 1)
        #expect(range.end == 3.4)
    }

    @Test("Drag selection returns contained groups or nearest group for tiny ranges")
    func dragSelectionReturnsContainedOrNearestGroups() throws {
        let first = ActionGroup(kind: .click, eventIndices: [0, 1], startTime: 1, endTime: 1.2, summary: "Click")
        let second = ActionGroup(kind: .scroll, eventIndices: [2], startTime: 4, endTime: 4.3, summary: "Scroll")
        let third = ActionGroup(kind: .keyPress, eventIndices: [3, 4], startTime: 8, endTime: 8.1, summary: "Key")
        let groups = [first, second, third]

        let ranged = TimelineProjection.selection(
            dragStartFraction: 0.35,
            dragEndFraction: 0.45,
            totalDuration: 10,
            groups: groups
        )
        #expect(ranged == [second.id])

        let tiny = TimelineProjection.selection(
            dragStartFraction: 0.62,
            dragEndFraction: 0.62,
            totalDuration: 10,
            groups: groups
        )
        #expect(tiny == [third.id])

        let nearest = try #require(TimelineProjection.nearestGroup(to: 7.9, groups: groups))
        #expect(nearest.id == third.id)
    }
}
