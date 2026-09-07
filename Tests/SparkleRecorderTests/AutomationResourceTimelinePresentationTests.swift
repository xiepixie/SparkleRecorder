import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Resource Timeline Presentation Tests")
struct AutomationResourceTimelinePresentationTests {
    @Test("Timeline presentation sorts once into stable chronological order")
    func sortsIntoStableChronologicalOrder() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let late = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "Late",
            start: base.addingTimeInterval(20)
        )
        let beta = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Beta",
            start: base
        )
        let alpha = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Alpha",
            start: base
        )

        let presentation = AutomationResourceTimelinePresentation.make(
            items: [late, beta, alpha]
        )

        #expect(presentation.items.map(\.id) == [alpha.id, beta.id, late.id])
    }

    @Test("Optimized conflict sweep matches the original pairwise semantics")
    func optimizedConflictSweepMatchesPairwiseSemantics() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var items: [AutomationResourceTimelineItem] = []

        for index in 0..<120 {
            let start = base.addingTimeInterval(Double((index * 7) % 43) * 0.45)
            let duration = Double((index % 6) + 1) * 0.7
            let resources: [String]
            switch index % 5 {
            case 0:
                resources = ["foregroundInput", "accessibility"]
            case 1:
                resources = ["screenCapture"]
            case 2:
                resources = ["foregroundInput"]
            case 3:
                resources = ["network"]
            default:
                resources = []
            }
            items.append(
                makeItem(
                    title: "Run \(index)",
                    start: start,
                    duration: duration,
                    resourceKeys: resources,
                    status: index % 17 == 0 ? .running : .completed
                )
            )
        }

        let presentation = AutomationResourceTimelinePresentation.make(items: items)
        let expected = bruteForceConflictIDs(in: presentation.items)

        #expect(presentation.conflictIDs == expected)
    }

    @Test("Different exclusive resources do not conflict")
    func differentResourcesDoNotConflict() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let foreground = makeItem(
            title: "Foreground",
            start: base,
            duration: 10,
            resourceKeys: ["foregroundInput"]
        )
        let capture = makeItem(
            title: "Capture",
            start: base.addingTimeInterval(1),
            duration: 10,
            resourceKeys: ["screenCapture"]
        )

        let presentation = AutomationResourceTimelinePresentation.make(
            items: [foreground, capture]
        )

        #expect(presentation.conflictIDs.isEmpty)
    }

    @Test("Running resource ownership conflicts with later work on the same resource")
    func runningResourceConflictsWithLaterWork() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let running = makeItem(
            title: "Running",
            start: base,
            resourceKeys: ["foregroundInput"],
            status: .running
        )
        let later = makeItem(
            title: "Later",
            start: base.addingTimeInterval(120),
            resourceKeys: ["foregroundInput"]
        )

        let presentation = AutomationResourceTimelinePresentation.make(
            items: [later, running]
        )

        #expect(presentation.conflictIDs == Set([running.id, later.id]))
    }

    @Test("Ten thousand timeline items remain a bounded pure projection")
    func tenThousandItemsRemainBounded() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<10_000).map { index in
            makeItem(
                title: "Run \(index)",
                start: base.addingTimeInterval(Double(index) * 2),
                duration: 0.25,
                resourceKeys: ["foregroundInput"]
            )
        }.reversed()

        let presentation = AutomationResourceTimelinePresentation.make(
            items: Array(items)
        )

        #expect(presentation.items.count == 10_000)
        #expect(presentation.items.first?.title == "Run 0")
        #expect(presentation.items.last?.title == "Run 9999")
        #expect(presentation.conflictIDs.isEmpty)
    }

    private func makeItem(
        id: UUID = UUID(),
        title: String,
        start: Date,
        duration: TimeInterval = 0.5,
        resourceKeys: [String] = ["foregroundInput"],
        status: AutomationDisplayStatus = .completed
    ) -> AutomationResourceTimelineItem {
        AutomationResourceTimelineItem(
            id: id,
            workflowID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            taskID: UUID(),
            runID: UUID(),
            title: title,
            lane: .foregroundInput,
            status: status,
            resourceLabel: "Needs mouse and keyboard",
            resourceKeys: resourceKeys,
            startedAt: start,
            completedAt: status == .running ? nil : start.addingTimeInterval(duration),
            createdAt: start,
            hasEvidence: false
        )
    }

    private func bruteForceConflictIDs(
        in items: [AutomationResourceTimelineItem]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        for leftIndex in items.indices {
            for rightIndex in items.indices where rightIndex > leftIndex {
                let left = items[leftIndex]
                let right = items[rightIndex]
                guard sharesExclusiveResource(left, right), intervalsOverlap(left, right) else {
                    continue
                }
                result.insert(left.id)
                result.insert(right.id)
            }
        }
        return result
    }

    private func sharesExclusiveResource(
        _ left: AutomationResourceTimelineItem,
        _ right: AutomationResourceTimelineItem
    ) -> Bool {
        let leftKeys = Set(left.resourceKeys ?? [])
        let rightKeys = Set(right.resourceKeys ?? [])
        return !leftKeys.isEmpty && !leftKeys.intersection(rightKeys).isEmpty
    }

    private func intervalsOverlap(
        _ left: AutomationResourceTimelineItem,
        _ right: AutomationResourceTimelineItem
    ) -> Bool {
        guard let leftInterval = interval(for: left),
              let rightInterval = interval(for: right) else {
            return false
        }
        let startsTogether = abs(leftInterval.start.timeIntervalSince(rightInterval.start)) < 1
        let overlaps = leftInterval.start < rightInterval.end && rightInterval.start < leftInterval.end
        return startsTogether || overlaps
    }

    private func interval(
        for item: AutomationResourceTimelineItem
    ) -> (start: Date, end: Date)? {
        guard let start = timelineStart(for: item) else {
            return nil
        }
        if item.status == .running {
            return (start, .distantFuture)
        }
        return (start, max(start, item.completedAt ?? start))
    }

    private func timelineStart(
        for item: AutomationResourceTimelineItem
    ) -> Date? {
        item.startedAt
            ?? item.earliestStartAt
            ?? item.scheduledAt
            ?? item.createdAt
            ?? item.completedAt
    }
}
