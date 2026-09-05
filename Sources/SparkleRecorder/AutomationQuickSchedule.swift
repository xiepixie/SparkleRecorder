import Foundation
import SparkleRecorderCore

enum AutomationQuickScheduleMode: String, CaseIterable, Identifiable {
  case daily
  case weekly
  case once
  case custom

  var id: Self { self }

  var title: String {
    switch self {
    case .daily:
      return String(localized: "Every day", table: "Automation")
    case .weekly:
      return String(localized: "Every week", table: "Automation")
    case .once:
      return String(localized: "Once", table: "Common")
    case .custom:
      return String(localized: "Interval", table: "Automation")
    }
  }
}

struct AutomationQuickScheduleDraft: Equatable {
  var workflowName: String
  var mode: AutomationQuickScheduleMode
  var startAt: Date
  var repeatEvery: Int
  var repeatUnit: AutomationTimelineRepeatUnit
  var weeklyWeekday: Int
  var targetApplicationPolicy: AutomationTargetApplicationPolicy
  var targetApplicationReadyDelay: TimeInterval
  var targetApplicationCleanupPolicy: AutomationTargetApplicationCleanupPolicy
  var targetApplicationQuitTimeout: TimeInterval
  var targetApplicationForceQuitOnTimeout: Bool

  init(
    workflowName: String,
    mode: AutomationQuickScheduleMode = .daily,
    startAt: Date,
    repeatEvery: Int = 1,
    repeatUnit: AutomationTimelineRepeatUnit = .days,
    weeklyWeekday: Int? = nil,
    targetApplicationPolicy: AutomationTargetApplicationPolicy = .launchIfNeeded,
    targetApplicationReadyDelay: TimeInterval = 2,
    targetApplicationCleanupPolicy: AutomationTargetApplicationCleanupPolicy = .quitIfLaunched,
    targetApplicationQuitTimeout: TimeInterval = 5,
    targetApplicationForceQuitOnTimeout: Bool = true
  ) {
    self.workflowName = workflowName
    self.mode = mode
    self.startAt = startAt
    self.repeatEvery = repeatEvery
    self.repeatUnit = repeatUnit
    self.weeklyWeekday = weeklyWeekday ?? Calendar.current.component(.weekday, from: startAt)
    self.targetApplicationPolicy = targetApplicationPolicy
    self.targetApplicationReadyDelay = min(60, max(0, targetApplicationReadyDelay))
    self.targetApplicationCleanupPolicy = targetApplicationCleanupPolicy
    self.targetApplicationQuitTimeout = min(60, max(1, targetApplicationQuitTimeout))
    self.targetApplicationForceQuitOnTimeout = targetApplicationForceQuitOnTimeout
  }

  init(
    workflowName: String,
    task: AutomationTask,
    fallbackStartAt: Date = Date().addingTimeInterval(3_600)
  ) {
    let scheduleValues = Self.scheduleValues(
      from: task.schedule,
      fallbackStartAt: fallbackStartAt
    )
    self.init(
      workflowName: workflowName,
      mode: scheduleValues.mode,
      startAt: scheduleValues.startAt,
      repeatEvery: scheduleValues.repeatEvery,
      repeatUnit: scheduleValues.repeatUnit,
      weeklyWeekday: scheduleValues.weeklyWeekday,
      targetApplicationPolicy: task.targetApplicationPolicy,
      targetApplicationReadyDelay: task.targetApplicationReadyDelay,
      targetApplicationCleanupPolicy: task.targetApplicationCleanupPolicy,
      targetApplicationQuitTimeout: task.targetApplicationQuitTimeout,
      targetApplicationForceQuitOnTimeout: task.targetApplicationForceQuitOnTimeout
    )
  }

  var normalizedWorkflowName: String {
    workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isValid: Bool {
    !normalizedWorkflowName.isEmpty && (mode != .custom || repeatEvery >= 1)
  }

  func validationMessage(onOrAfter referenceDate: Date = Date()) -> String? {
    if normalizedWorkflowName.isEmpty {
      return String(
        localized: "The macro needs a name before it can be scheduled.", table: "Automation")
    }
    if mode == .custom, repeatEvery < 1 {
      return String(localized: "The interval must be at least 1.", table: "Automation")
    }
    if mode == .once, startAt <= referenceDate {
      return String(localized: "Choose a future time for a one-time run.", table: "Automation")
    }
    return nil
  }

  var schedule: AutomationSchedule {
    resolvedSchedule(onOrAfter: startAt)
  }

  func resolvedSchedule(onOrAfter referenceDate: Date) -> AutomationSchedule {
    switch mode {
    case .daily:
      return .repeating(
        AutomationRepeatRule(
          anchor: dailyAnchor(onOrAfter: referenceDate),
          interval: .days(1)
        ))
    case .weekly:
      return .repeating(
        AutomationRepeatRule(
          anchor: weeklyAnchor(onOrAfter: referenceDate),
          interval: .weeks(1)
        ))
    case .once:
      return .once(startAt)
    case .custom:
      return .repeating(
        AutomationRepeatRule(
          anchor: startAt,
          interval: repeatUnit.interval(count: repeatEvery)
        ))
    }
  }

  var weeklyAnchor: Date {
    weeklyAnchor(onOrAfter: startAt)
  }

  func dailyAnchor(onOrAfter referenceDate: Date) -> Date {
    nextWallClockAnchor(
      onOrAfter: referenceDate,
      weekday: nil
    )
  }

  func weeklyAnchor(onOrAfter referenceDate: Date) -> Date {
    nextWallClockAnchor(
      onOrAfter: referenceDate,
      weekday: min(7, max(1, weeklyWeekday))
    )
  }

  private func nextWallClockAnchor(
    onOrAfter referenceDate: Date,
    weekday: Int?
  ) -> Date {
    var calendar = Calendar.current
    calendar.timeZone = .current
    let components = calendar.dateComponents([.hour, .minute], from: startAt)
    var matching = DateComponents()
    matching.weekday = weekday
    matching.hour = components.hour
    matching.minute = components.minute
    matching.second = 0
    return calendar.nextDate(
      after: referenceDate.addingTimeInterval(-1),
      matching: matching,
      matchingPolicy: .nextTime,
      repeatedTimePolicy: .first,
      direction: .forward
    ) ?? startAt
  }

  func previewOccurrences(
    onOrAfter referenceDate: Date = Date(),
    limit: Int = 3
  ) -> [AutomationScheduledOccurrence] {
    resolvedSchedule(onOrAfter: referenceDate)
      .previewOccurrences(startingAt: referenceDate, limit: limit)
  }

  func makeWorkflow(
    for macro: SavedMacro,
    workflowID: UUID = UUID(),
    taskID: UUID = UUID(),
    now: Date = Date()
  ) -> AutomationWorkflow {
    let task = AutomationTask(
      id: taskID,
      name: macro.name,
      kind: .macro(macroID: macro.id),
      schedule: resolvedSchedule(onOrAfter: now),
      resourceRequirement: .foregroundInput,
      isEnabled: true,
      targetApplicationPolicy: targetApplicationPolicy,
      targetApplicationReadyDelay: targetApplicationReadyDelay,
      targetApplicationCleanupPolicy: targetApplicationCleanupPolicy,
      targetApplicationQuitTimeout: targetApplicationQuitTimeout,
      targetApplicationForceQuitOnTimeout: targetApplicationForceQuitOnTimeout,
      playbackLoops: 1,
      missedRunPolicy: .latestOnly,
      graphPosition: AutomationGraphPoint(x: 120, y: 120)
    )
    return AutomationWorkflow(
      id: workflowID,
      name: normalizedWorkflowName,
      tasks: [task],
      createdAt: now,
      modifiedAt: now
    )
  }

  private static func scheduleValues(
    from schedule: AutomationSchedule?,
    fallbackStartAt: Date
  ) -> (
    mode: AutomationQuickScheduleMode,
    startAt: Date,
    repeatEvery: Int,
    repeatUnit: AutomationTimelineRepeatUnit,
    weeklyWeekday: Int
  ) {
    switch schedule {
    case .once(let date):
      return (.once, date, 1, .days, Calendar.current.component(.weekday, from: date))
    case .repeating(let rule):
      let weekday = Calendar.current.component(.weekday, from: rule.anchor)
      switch rule.interval {
      case .days(1):
        return (.daily, rule.anchor, 1, .days, weekday)
      case .weeks(1):
        return (.weekly, rule.anchor, 1, .weeks, weekday)
      case .minutes(let count):
        return (.custom, rule.anchor, count, .minutes, weekday)
      case .hours(let count):
        return (.custom, rule.anchor, count, .hours, weekday)
      case .days(let count):
        return (.custom, rule.anchor, count, .days, weekday)
      case .weeks(let count):
        return (.custom, rule.anchor, count, .weeks, weekday)
      }
    case .manual, nil:
      return (
        .daily,
        fallbackStartAt,
        1,
        .days,
        Calendar.current.component(.weekday, from: fallbackStartAt)
      )
    }
  }
}

struct AutomationMacroScheduleSummary: Equatable, Identifiable {
  var workflowID: UUID
  var task: AutomationTask
  var nextRun: Date?
  var matchingWorkflowIDs: [UUID]
  var statusText: String

  var id: UUID { task.id }
  var isEnabled: Bool { task.isEnabled }
  var duplicateCount: Int { max(0, matchingWorkflowIDs.count - 1) }

  private static func makeStatusText(isEnabled: Bool, nextRun: Date?) -> String {
    guard isEnabled else {
      return String(localized: "Automatic run paused", table: "Automation")
    }
    guard let nextRun else {
      return String(localized: "No upcoming run", table: "Automation")
    }
    return String(
      format: String(localized: "Next: %@", table: "Automation"),
      nextRun.formatted(date: .abbreviated, time: .shortened)
    )
  }

  static func summaries(
    from state: AutomationRunState?,
    onOrAfter referenceDate: Date = Date()
  ) -> [UUID: AutomationMacroScheduleSummary] {
    guard let state else { return [:] }

    let candidates = state.workflows.compactMap {
      workflow -> (UUID, AutomationWorkflow, AutomationTask, Date?)? in
      guard workflow.tasks.count == 1,
        let task = workflow.tasks.first,
        let macroID = task.kind.macroID,
        let schedule = task.schedule,
        schedule != .manual
      else {
        return nil
      }
      let nextRun =
        task.isEnabled
        ? schedule.nextOccurrence(onOrAfter: referenceDate)?.scheduledAt
        : nil
      return (macroID, workflow, task, nextRun)
    }

    return Dictionary(grouping: candidates, by: \.0).mapValues { matches in
      let sorted = matches.sorted { lhs, rhs in
        switch (lhs.3, rhs.3) {
        case (let left?, let right?): return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs.1.modifiedAt > rhs.1.modifiedAt
        }
      }
      let selected = sorted[0]
      return AutomationMacroScheduleSummary(
        workflowID: selected.1.id,
        task: selected.2,
        nextRun: selected.3,
        matchingWorkflowIDs: sorted.map { $0.1.id },
        statusText: makeStatusText(
          isEnabled: selected.2.isEnabled,
          nextRun: selected.3
        )
      )
    }
  }
}

extension AutomationTargetApplicationPolicy {
  var title: String {
    switch self {
    case .doNotActivate:
      return String(localized: "Do not switch apps", table: "Automation")
    case .activateIfRunning:
      return String(localized: "Activate if running", table: "Automation")
    case .launchIfNeeded:
      return String(localized: "Open if needed", table: "Automation")
    }
  }

  var detail: String {
    switch self {
    case .doNotActivate:
      return String(localized: "Keep the current application in front.", table: "Automation")
    case .activateIfRunning:
      return String(
        localized: "Bring the bound application forward only when it is already open.",
        table: "Automation")
    case .launchIfNeeded:
      return String(
        localized: "Open the bound application and wait for its window before running.",
        table: "Automation")
    }
  }
}

extension AutomationTargetApplicationCleanupPolicy {
  var title: String {
    switch self {
    case .keepOpen:
      return String(localized: "Keep open after running", table: "Automation")
    case .quitIfLaunched:
      return String(localized: "Close only if opened for this run", table: "Automation")
    }
  }
}

extension AutomationSchedule {
  func previewOccurrences(startingAt referenceDate: Date, limit: Int = 3)
    -> [AutomationScheduledOccurrence]
  {
    guard limit > 0 else {
      return []
    }

    var occurrences: [AutomationScheduledOccurrence] = []
    var excludedStarts = Set<Date>()
    while occurrences.count < limit,
      let occurrence = nextOccurrence(
        onOrAfter: referenceDate,
        excludingScheduledStartTimes: excludedStarts
      )
    {
      occurrences.append(occurrence)
      excludedStarts.insert(occurrence.scheduledAt)
    }
    return occurrences
  }
}
