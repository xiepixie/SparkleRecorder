import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Quick Schedule Tests")
struct AutomationQuickScheduleTests {
  @Test("Quick schedule creates one enabled macro task with the selected once schedule")
  func createsSingleScheduledMacroWorkflow() throws {
    let macroID = UUID()
    let workflowID = UUID()
    let taskID = UUID()
    let now = Date(timeIntervalSince1970: 10_000)
    let startAt = Date(timeIntervalSince1970: 20_000)
    let macro = SavedMacro(id: macroID, name: "Daily report", events: [])
    let draft = AutomationQuickScheduleDraft(
      workflowName: "  Morning report  ",
      mode: .once,
      startAt: startAt
    )

    let workflow = draft.makeWorkflow(
      for: macro,
      workflowID: workflowID,
      taskID: taskID,
      now: now
    )
    let task = try #require(workflow.tasks.first)

    #expect(workflow.id == workflowID)
    #expect(workflow.name == "Morning report")
    #expect(workflow.createdAt == now)
    #expect(workflow.modifiedAt == now)
    #expect(workflow.tasks.count == 1)
    #expect(task.id == taskID)
    #expect(task.name == macro.name)
    #expect(task.kind == .macro(macroID: macroID))
    #expect(task.schedule == .once(startAt))
    #expect(task.resourceRequirement == .foregroundInput)
    #expect(task.isEnabled)
    #expect(task.targetApplicationPolicy == .launchIfNeeded)
    #expect(task.targetApplicationReadyDelay == 2)
    #expect(task.targetApplicationCleanupPolicy == .quitIfLaunched)
    #expect(task.targetApplicationQuitTimeout == 5)
    #expect(task.targetApplicationForceQuitOnTimeout)
    #expect(task.playbackLoops == 1)
    #expect(task.missedRunPolicy == .latestOnly)
  }

  @Test("Legacy tasks default to activating only already-running applications")
  func legacyTaskDecodingDefaultsTargetApplicationPolicy() throws {
    let task = AutomationTask(
      name: "Legacy",
      kind: .macro(macroID: UUID())
    )
    let encoded = try JSONEncoder().encode(task)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "targetApplicationPolicy")
    object.removeValue(forKey: "targetApplicationReadyDelay")
    object.removeValue(forKey: "targetApplicationCleanupPolicy")
    object.removeValue(forKey: "targetApplicationQuitTimeout")
    object.removeValue(forKey: "targetApplicationForceQuitOnTimeout")
    object.removeValue(forKey: "playbackLoops")
    object.removeValue(forKey: "missedRunPolicy")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(AutomationTask.self, from: legacyData)

    #expect(decoded.targetApplicationPolicy == .activateIfRunning)
    #expect(decoded.targetApplicationReadyDelay == 0)
    #expect(decoded.targetApplicationCleanupPolicy == .keepOpen)
    #expect(decoded.targetApplicationQuitTimeout == 5)
    #expect(decoded.targetApplicationForceQuitOnTimeout)
    #expect(decoded.playbackLoops == nil)
    #expect(decoded.missedRunPolicy == .catchUp)
  }

  @Test("Workflow draft export and import preserve target application policy")
  func draftRoundTripPreservesTargetApplicationPolicy() throws {
    let macro = SavedMacro(name: "Bound macro", events: [])
    let workflow = AutomationQuickScheduleDraft(
      workflowName: "Scheduled",
      startAt: Date(timeIntervalSince1970: 50_000),
      targetApplicationPolicy: .launchIfNeeded
    ).makeWorkflow(for: macro)
    let catalog = AutomationWorkflowDraftMacroCatalogEntry(
      id: macro.id,
      name: macro.name
    )

    let exported = AutomationWorkflowDraftExporter.export(
      workflow,
      options: AutomationWorkflowDraftExportOptions(macroCatalog: [catalog])
    )
    let imported = AutomationWorkflowDraftImporter.compile(
      exported.document,
      context: AutomationWorkflowDraftValidationContext(macroCatalog: [catalog]),
      options: AutomationWorkflowDraftImportOptions(mode: .confirm)
    )
    let importedTask = try #require(imported.workflow?.tasks.first)

    #expect(exported.document.workflow.tasks.first?.targetApplicationPolicy == "launchIfNeeded")
    #expect(exported.document.workflow.tasks.first?.targetApplicationReadyDelay == 2)
    #expect(
      exported.document.workflow.tasks.first?.targetApplicationCleanupPolicy == "quitIfLaunched")
    #expect(exported.document.workflow.tasks.first?.targetApplicationQuitTimeout == 5)
    #expect(exported.document.workflow.tasks.first?.targetApplicationForceQuitOnTimeout == true)
    #expect(exported.document.workflow.tasks.first?.playbackLoops == 1)
    #expect(exported.document.workflow.tasks.first?.missedRunPolicy == "latestOnly")
    #expect(importedTask.targetApplicationPolicy == .launchIfNeeded)
    #expect(importedTask.targetApplicationReadyDelay == 2)
    #expect(importedTask.targetApplicationCleanupPolicy == .quitIfLaunched)
    #expect(importedTask.targetApplicationQuitTimeout == 5)
    #expect(importedTask.targetApplicationForceQuitOnTimeout)
    #expect(importedTask.playbackLoops == 1)
    #expect(importedTask.missedRunPolicy == .latestOnly)
  }

  @Test("Repeating quick schedule preview uses core occurrence semantics")
  func previewsRepeatingOccurrences() {
    let startAt = Date(timeIntervalSince1970: 30_000)
    let draft = AutomationQuickScheduleDraft(
      workflowName: "Cleanup",
      mode: .custom,
      startAt: startAt,
      repeatEvery: 2,
      repeatUnit: .hours
    )

    let preview = draft.previewOccurrences(onOrAfter: startAt)

    #expect(preview.map(\.occurrenceIndex) == [0, 1, 2])
    #expect(
      preview.map(\.scheduledAt) == [
        startAt,
        startAt.addingTimeInterval(7_200),
        startAt.addingTimeInterval(14_400),
      ])
  }

  @Test("Quick schedule defaults to running the complete macro every day")
  func defaultsToDailySchedule() throws {
    let startAt = Date(timeIntervalSince1970: 60_000)
    let macro = SavedMacro(name: "Daily claim", events: [])
    let draft = AutomationQuickScheduleDraft(
      workflowName: macro.name,
      startAt: startAt
    )

    let task = try #require(
      draft.makeWorkflow(
        for: macro,
        now: startAt.addingTimeInterval(-1)
      ).tasks.first)
    let expected = AutomationSchedule.repeating(
      AutomationRepeatRule(
        anchor: startAt,
        interval: .days(1)
      ))

    #expect(draft.mode == .daily)
    #expect(task.schedule == expected)
    #expect(task.kind == .macro(macroID: macro.id))
  }

  @Test("Weekly schedule anchors to the selected local weekday and time")
  func weeklyScheduleUsesSelectedWeekday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let startAt = try #require(
      calendar.date(
        from: DateComponents(
          year: 2026, month: 7, day: 15, hour: 9, minute: 30
        )))
    let draft = AutomationQuickScheduleDraft(
      workflowName: "Weekly claim",
      mode: .weekly,
      startAt: startAt,
      weeklyWeekday: 2
    )

    let anchor = draft.weeklyAnchor
    let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: anchor)

    #expect(components.weekday == 2)
    #expect(components.hour == 9)
    #expect(components.minute == 30)
    #expect(anchor >= startAt)
  }

  @Test("Daily schedule saved after today's selected time starts tomorrow")
  func pastDailyTimeAnchorsToNextDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let selectedTime = try #require(
      calendar.date(
        from: DateComponents(
          year: 2026, month: 7, day: 15, hour: 9, minute: 0
        )))
    let savedAt = try #require(
      calendar.date(
        from: DateComponents(
          year: 2026, month: 7, day: 15, hour: 10, minute: 0
        )))
    let expected = try #require(
      calendar.date(
        from: DateComponents(
          year: 2026, month: 7, day: 16, hour: 9, minute: 0
        )))
    let macro = SavedMacro(name: "Daily", events: [])
    let task = try #require(
      AutomationQuickScheduleDraft(
        workflowName: macro.name,
        mode: .daily,
        startAt: selectedTime
      ).makeWorkflow(for: macro, now: savedAt).tasks.first)

    #expect(
      task.schedule
        == .repeating(
          AutomationRepeatRule(
            anchor: expected,
            interval: .days(1)
          )))
  }

  @Test("Editing an existing weekly schedule restores timing and application behavior")
  func existingWeeklyScheduleRestoresDraft() {
    let anchor = Date(timeIntervalSince1970: 70_000)
    let task = AutomationTask(
      name: "Weekly claim",
      kind: .macro(macroID: UUID()),
      schedule: .repeating(AutomationRepeatRule(anchor: anchor, interval: .weeks(1))),
      targetApplicationPolicy: .activateIfRunning,
      targetApplicationReadyDelay: 10,
      targetApplicationCleanupPolicy: .keepOpen,
      targetApplicationQuitTimeout: 30,
      targetApplicationForceQuitOnTimeout: false,
      playbackLoops: 1
    )

    let draft = AutomationQuickScheduleDraft(
      workflowName: "Weekly claim",
      task: task
    )

    #expect(draft.mode == .weekly)
    #expect(draft.startAt == anchor)
    #expect(draft.weeklyWeekday == Calendar.current.component(.weekday, from: anchor))
    #expect(draft.targetApplicationPolicy == .activateIfRunning)
    #expect(draft.targetApplicationReadyDelay == 10)
    #expect(draft.targetApplicationCleanupPolicy == .keepOpen)
    #expect(draft.targetApplicationQuitTimeout == 30)
    #expect(!draft.targetApplicationForceQuitOnTimeout)
  }

  @Test("Automatic run summaries expose the earliest next run and duplicate schedules")
  func summariesChooseEarliestNextRunAndCountDuplicates() throws {
    let macroID = UUID()
    let reference = Date(timeIntervalSince1970: 80_000)
    let later = AutomationWorkflow(
      name: "Later",
      tasks: [
        AutomationTask(
          name: "Claim",
          kind: .macro(macroID: macroID),
          schedule: .once(reference.addingTimeInterval(600)),
          playbackLoops: 1
        )
      ]
    )
    let earlier = AutomationWorkflow(
      name: "Earlier",
      tasks: [
        AutomationTask(
          name: "Claim",
          kind: .macro(macroID: macroID),
          schedule: .once(reference.addingTimeInterval(300)),
          playbackLoops: 1
        )
      ]
    )
    let summary = try #require(
      AutomationMacroScheduleSummary.summaries(
        from: AutomationRunState(workflows: [later, earlier]),
        onOrAfter: reference
      )[macroID])

    #expect(summary.workflowID == earlier.id)
    #expect(summary.nextRun == reference.addingTimeInterval(300))
    #expect(summary.duplicateCount == 1)
    #expect(Set(summary.matchingWorkflowIDs) == Set([later.id, earlier.id]))
  }

  @Test("Paused automatic runs remain discoverable without claiming a next run")
  func pausedSummaryHasNoNextRun() throws {
    let macroID = UUID()
    let task = AutomationTask(
      name: "Paused",
      kind: .macro(macroID: macroID),
      schedule: .once(Date(timeIntervalSince1970: 100_000)),
      isEnabled: false,
      playbackLoops: 1
    )
    let workflow = AutomationWorkflow(name: "Paused", tasks: [task])
    let summary = try #require(
      AutomationMacroScheduleSummary.summaries(
        from: AutomationRunState(workflows: [workflow]),
        onOrAfter: Date(timeIntervalSince1970: 90_000)
      )[macroID])

    #expect(!summary.isEnabled)
    #expect(summary.nextRun == nil)
  }

  @Test("Quick schedule rejects empty names and repeat counts below one")
  func validatesUserInput() {
    let startAt = Date(timeIntervalSince1970: 40_000)
    let emptyName = AutomationQuickScheduleDraft(
      workflowName: "  ",
      startAt: startAt
    )
    let invalidRepeat = AutomationQuickScheduleDraft(
      workflowName: "Valid name",
      mode: .custom,
      startAt: startAt,
      repeatEvery: 0
    )
    let dailyIgnoresUnusedRepeatCount = AutomationQuickScheduleDraft(
      workflowName: "Daily",
      mode: .daily,
      startAt: startAt,
      repeatEvery: 0
    )
    let pastOnce = AutomationQuickScheduleDraft(
      workflowName: "Once",
      mode: .once,
      startAt: startAt
    )

    #expect(!emptyName.isValid)
    #expect(!invalidRepeat.isValid)
    #expect(dailyIgnoresUnusedRepeatCount.isValid)
    #expect(pastOnce.validationMessage(onOrAfter: startAt.addingTimeInterval(1)) != nil)
  }
}
