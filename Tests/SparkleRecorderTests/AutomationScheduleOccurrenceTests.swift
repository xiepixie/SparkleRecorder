import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Schedule Occurrence Tests")
struct AutomationScheduleOccurrenceTests {
    @Test("Represented schedule index separates many task histories in one pass")
    func representedScheduleIndexSeparatesTasks() {
        let workflowID = UUID()
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let start = Date(timeIntervalSince1970: 6_000)
        let runs = (0..<10_000).map { index in
            AutomationTaskRun(
                workflowID: workflowID,
                taskID: index.isMultiple(of: 2) ? firstTaskID : secondTaskID,
                scheduledStartTime: start.addingTimeInterval(TimeInterval(index)),
                createdAt: start
            )
        }

        let index = AutomationRepresentedScheduleIndex(runs: runs)
        let firstStarts = index.startTimes(workflowID: workflowID, taskID: firstTaskID)
        let secondStarts = index.startTimes(workflowID: workflowID, taskID: secondTaskID)

        #expect(firstStarts.count == 5_000)
        #expect(secondStarts.count == 5_000)
        #expect(firstStarts.isDisjoint(with: secondStarts))
        #expect(index.startTimes(workflowID: UUID(), taskID: firstTaskID).isEmpty)
    }

    @Test("Upcoming once schedule returns its date unless already represented by a run")
    func onceScheduleReturnsDateUntilRepresented() throws {
        let scheduledAt = Date(timeIntervalSince1970: 7_000)
        let schedule = AutomationSchedule.once(scheduledAt)

        let occurrence = try #require(schedule.nextOccurrence(
            onOrAfter: scheduledAt.addingTimeInterval(-10)
        ))
        let excluded = schedule.nextOccurrence(
            onOrAfter: scheduledAt.addingTimeInterval(-10),
            excludingScheduledStartTimes: [scheduledAt]
        )

        #expect(occurrence.occurrenceIndex == 0)
        #expect(occurrence.scheduledAt == scheduledAt)
        #expect(excluded == nil)
    }

    @Test("Past one-time schedule has no upcoming occurrence")
    func pastOnceScheduleHasNoUpcomingOccurrence() {
        let scheduledAt = Date(timeIntervalSince1970: 1_000)
        let schedule = AutomationSchedule.once(scheduledAt)

        #expect(schedule.nextOccurrence(onOrAfter: scheduledAt.addingTimeInterval(1)) == nil)
    }

    @Test("Repeating schedule finds the next unrepresented occurrence")
    func repeatingScheduleFindsNextUnrepresentedOccurrence() throws {
        let anchor = Date(timeIntervalSince1970: 8_000)
        let schedule = AutomationSchedule.repeating(AutomationRepeatRule(
            anchor: anchor,
            interval: .minutes(15)
        ))
        let firstFuture = anchor.addingTimeInterval(15 * 60 * 2)
        let secondFuture = anchor.addingTimeInterval(15 * 60 * 3)

        let occurrence = try #require(schedule.nextOccurrence(
            onOrAfter: anchor.addingTimeInterval(15 * 60 + 1),
            excludingScheduledStartTimes: [firstFuture]
        ))

        #expect(occurrence.occurrenceIndex == 3)
        #expect(occurrence.scheduledAt == secondFuture)
    }

    @Test("Repeating schedule respects occurrence and date end rules")
    func repeatingScheduleRespectsEndRules() throws {
        let anchor = Date(timeIntervalSince1970: 9_000)
        let afterTwo = AutomationSchedule.repeating(AutomationRepeatRule(
            anchor: anchor,
            interval: .hours(1),
            end: .afterOccurrences(2)
        ))
        let endingAtAnchor = AutomationSchedule.repeating(AutomationRepeatRule(
            anchor: anchor,
            interval: .hours(1),
            end: .at(anchor)
        ))

        let second = try #require(afterTwo.nextOccurrence(onOrAfter: anchor.addingTimeInterval(1)))
        let third = afterTwo.nextOccurrence(onOrAfter: anchor.addingTimeInterval(2 * 3_600))
        let afterDateEnd = endingAtAnchor.nextOccurrence(onOrAfter: anchor.addingTimeInterval(1))

        #expect(second.occurrenceIndex == 1)
        #expect(second.scheduledAt == anchor.addingTimeInterval(3_600))
        #expect(third == nil)
        #expect(afterDateEnd == nil)
    }

    @Test("Due occurrence returns earliest unrepresented scheduled time at or before reference")
    func dueOccurrenceReturnsEarliestUnrepresentedPastOccurrence() throws {
        let anchor = Date(timeIntervalSince1970: 10_000)
        let second = anchor.addingTimeInterval(60)
        let third = anchor.addingTimeInterval(120)
        let fourth = anchor.addingTimeInterval(180)
        let schedule = AutomationSchedule.repeating(AutomationRepeatRule(
            anchor: anchor,
            interval: .minutes(1)
        ))

        let occurrence = try #require(schedule.nextDueOccurrence(
            onOrBefore: fourth,
            excludingScheduledStartTimes: [anchor, second]
        ))

        #expect(occurrence.occurrenceIndex == 2)
        #expect(occurrence.scheduledAt == third)
    }

    @Test("Due occurrence does not return future or ended occurrences")
    func dueOccurrenceDoesNotReturnFutureOrEndedOccurrences() {
        let anchor = Date(timeIntervalSince1970: 11_000)
        let futureOnce = AutomationSchedule.once(anchor.addingTimeInterval(60))
        let endedRepeating = AutomationSchedule.repeating(AutomationRepeatRule(
            anchor: anchor,
            interval: .minutes(1),
            end: .afterOccurrences(1)
        ))

        let future = futureOnce.nextDueOccurrence(onOrBefore: anchor)
        let ended = endedRepeating.nextDueOccurrence(
            onOrBefore: anchor.addingTimeInterval(120),
            excludingScheduledStartTimes: [anchor]
        )

        #expect(future == nil)
        #expect(ended == nil)
    }
}
