import Foundation

public struct AutomationScheduledOccurrence: Codable, Equatable, Sendable {
    public var occurrenceIndex: Int
    public var scheduledAt: Date

    public init(occurrenceIndex: Int, scheduledAt: Date) {
        self.occurrenceIndex = occurrenceIndex
        self.scheduledAt = scheduledAt
    }
}

public extension AutomationSchedule {
    func nextOccurrence(
        onOrAfter referenceDate: Date,
        excludingScheduledStartTimes excludedStarts: Set<Date> = []
    ) -> AutomationScheduledOccurrence? {
        switch self {
        case .manual:
            return nil

        case .once(let date):
            guard !excludedStarts.contains(date) else {
                return nil
            }
            return AutomationScheduledOccurrence(occurrenceIndex: 0, scheduledAt: date)

        case .repeating(let rule):
            return rule.nextOccurrence(
                onOrAfter: referenceDate,
                excludingScheduledStartTimes: excludedStarts
            )
        }
    }

    func nextDueOccurrence(
        onOrBefore referenceDate: Date,
        excludingScheduledStartTimes excludedStarts: Set<Date> = []
    ) -> AutomationScheduledOccurrence? {
        switch self {
        case .manual:
            return nil

        case .once(let date):
            guard date <= referenceDate, !excludedStarts.contains(date) else {
                return nil
            }
            return AutomationScheduledOccurrence(occurrenceIndex: 0, scheduledAt: date)

        case .repeating(let rule):
            return rule.nextDueOccurrence(
                onOrBefore: referenceDate,
                excludingScheduledStartTimes: excludedStarts
            )
        }
    }
}

public extension AutomationRepeatRule {
    func nextOccurrence(
        onOrAfter referenceDate: Date,
        excludingScheduledStartTimes excludedStarts: Set<Date> = []
    ) -> AutomationScheduledOccurrence? {
        let step = interval.timeInterval
        guard step > 0 else {
            return nil
        }

        var index = firstCandidateIndex(onOrAfter: referenceDate, step: step)
        while occurrenceIsAllowed(index) {
            let scheduledAt = anchor.addingTimeInterval(Double(index) * step)
            if !excludedStarts.contains(scheduledAt) {
                return AutomationScheduledOccurrence(
                    occurrenceIndex: index,
                    scheduledAt: scheduledAt
                )
            }
            index += 1
        }
        return nil
    }

    func nextDueOccurrence(
        onOrBefore referenceDate: Date,
        excludingScheduledStartTimes excludedStarts: Set<Date> = []
    ) -> AutomationScheduledOccurrence? {
        let step = interval.timeInterval
        guard step > 0, referenceDate >= anchor else {
            return nil
        }

        let lastDueIndex = min(lastCandidateIndex(onOrBefore: referenceDate, step: step), lastAllowedIndex())
        guard lastDueIndex >= 0 else {
            return nil
        }

        for index in 0...lastDueIndex {
            let scheduledAt = anchor.addingTimeInterval(Double(index) * step)
            if !excludedStarts.contains(scheduledAt) {
                return AutomationScheduledOccurrence(
                    occurrenceIndex: index,
                    scheduledAt: scheduledAt
                )
            }
        }
        return nil
    }

    private func firstCandidateIndex(onOrAfter referenceDate: Date, step: TimeInterval) -> Int {
        guard referenceDate > anchor else {
            return 0
        }
        let elapsed = referenceDate.timeIntervalSince(anchor)
        return max(0, Int(ceil(elapsed / step)))
    }

    private func lastCandidateIndex(onOrBefore referenceDate: Date, step: TimeInterval) -> Int {
        guard referenceDate >= anchor else {
            return -1
        }
        let elapsed = referenceDate.timeIntervalSince(anchor)
        return max(0, Int(floor(elapsed / step)))
    }

    private func occurrenceIsAllowed(_ index: Int) -> Bool {
        guard index >= 0 else {
            return false
        }

        switch end {
        case .never:
            return true
        case .afterOccurrences(let count):
            return index < max(0, count)
        case .at(let endDate):
            return anchor.addingTimeInterval(Double(index) * interval.timeInterval) <= endDate
        }
    }

    private func lastAllowedIndex() -> Int {
        switch end {
        case .never:
            return Int.max
        case .afterOccurrences(let count):
            return max(-1, max(0, count) - 1)
        case .at(let endDate):
            return lastCandidateIndex(onOrBefore: endDate, step: interval.timeInterval)
        }
    }
}

public extension AutomationRepeatInterval {
    var timeInterval: TimeInterval {
        switch self {
        case .minutes(let count):
            return TimeInterval(max(1, count) * 60)
        case .hours(let count):
            return TimeInterval(max(1, count) * 3_600)
        case .days(let count):
            return TimeInterval(max(1, count) * 86_400)
        case .weeks(let count):
            return TimeInterval(max(1, count) * 604_800)
        }
    }
}
