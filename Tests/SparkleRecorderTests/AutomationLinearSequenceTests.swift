import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Linear Sequence Tests")
struct AutomationLinearSequenceTests {
  @Test("Saved linear workflow restores the quick sequence editor without losing OCR or timing")
  func savedWorkflowRestoresSequenceDraft() throws {
    let macros = [
      SavedMacro(name: "Open", events: []),
      SavedMacro(name: "Claim", events: []),
    ]
    var source = AutomationLinearSequenceDraft(
      name: "Daily claim",
      macros: macros,
      scheduleMode: .weekly,
      startAt: Date(timeIntervalSince1970: 1_800_000_000),
      weeklyWeekday: 3
    )
    source.steps[0].continuation = .screenText
    source.targetApplicationReadyDelay = 5
    source.steps[0].screenText = "Ready"
    source.steps[0].ocrMatchMode = .exact
    source.steps[0].ocrSearchRegion = RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.2)
    source.steps[0].ocrSearchRegionSpace = .contentNormalized

    let document = source.makeDocument(onOrAfter: Date(timeIntervalSince1970: 1_799_000_000))
    let catalog = macros.map { AutomationWorkflowDraftMacroCatalogEntry(id: $0.id, name: $0.name) }
    let result = AutomationWorkflowDraftImporter.compile(
      document,
      context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog),
      options: AutomationWorkflowDraftImportOptions(mode: .confirm)
    )
    let workflow = try #require(result.workflow)
    let restored = try #require(AutomationLinearSequenceDraft(workflow: workflow, macros: macros))

    #expect(restored.name == "Daily claim")
    #expect(restored.scheduleMode == .weekly)
    #expect(restored.weeklyWeekday == 3)
    #expect(restored.targetApplicationReadyDelay == 5)
    #expect(restored.steps.map(\.macroID) == macros.map(\.id))
    #expect(restored.steps[0].continuation == .screenText)
    #expect(restored.steps[0].screenText == "Ready")
    #expect(restored.steps[0].ocrMatchMode == .exact)
    #expect(restored.steps[0].ocrSearchRegionSpace == .contentNormalized)
  }

  @Test("Linear sequence compiles delay and OCR gates into existing workflow tasks")
  func compilesSimpleContinuations() throws {
    let macros = [
      SavedMacro(name: "Open rewards", events: []),
      SavedMacro(name: "Claim reward", events: []),
      SavedMacro(name: "Close panel", events: []),
    ]
    let referenceDate = Date(timeIntervalSince1970: 10_000)
    var draft = AutomationLinearSequenceDraft(
      name: "Daily rewards",
      macros: macros,
      scheduleMode: .daily,
      startAt: Date(timeIntervalSince1970: 12_000)
    )
    draft.steps[0].continuation = .delay
    draft.targetApplicationReadyDelay = 10
    draft.steps[0].delaySeconds = 4
    draft.steps[1].continuation = .screenText
    draft.steps[1].screenText = "Claim"
    draft.steps[1].conditionTimeout = 45
    draft.steps[1].ocrMatchMode = .exact
    draft.steps[1].ocrSearchRegion = RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
    draft.steps[1].ocrSearchRegionSpace = .contentNormalized

    let document = draft.makeDocument(onOrAfter: referenceDate)
    let workflowDraft = document.workflow

    #expect(workflowDraft.tasks.map(\.key) == ["macro_1", "macro_2", "gate_2", "macro_3"])
    #expect(
      workflowDraft.dependencies == [
        AutomationWorkflowDraftDependency(
          from: "macro_1",
          to: "macro_2",
          trigger: "success",
          delaySeconds: 4
        ),
        AutomationWorkflowDraftDependency(from: "macro_2", to: "gate_2", trigger: "success"),
        AutomationWorkflowDraftDependency(
          from: "gate_2", to: "macro_3", trigger: "conditionMatched"),
      ])
    let gate = try #require(workflowDraft.tasks.first { $0.key == "gate_2" })
    #expect(gate.condition?.type == "ocrText")
    #expect(gate.condition?.text == "Claim")
    #expect(gate.condition?.matchMode == .exact)
    #expect(gate.condition?.regionRef == "gate_2_region")
    #expect(gate.timeoutSeconds == 45)
    #expect(gate.resource == .screenCapture)
    #expect(
      document.visualAssets?.regions == [
        AutomationWorkflowDraftVisualRegion(
          key: "gate_2_region",
          label: "Claim",
          bounds: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
          space: .contentNormalized
        )
      ])

    let catalog = macros.map {
      AutomationWorkflowDraftMacroCatalogEntry(id: $0.id, name: $0.name)
    }
    let imported = AutomationWorkflowDraftImporter.compile(
      document,
      context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog),
      options: AutomationWorkflowDraftImportOptions(
        mode: .confirm,
        importedAt: referenceDate,
        stableIDNamespace: "linear-sequence-test"
      )
    )
    let workflow = try #require(imported.workflow)
    let macroTasks = workflow.tasks.filter { $0.kind.macroID != nil }

    #expect(macroTasks.count == 3)
    #expect(macroTasks.allSatisfy { $0.playbackLoops == 1 })
    #expect(macroTasks.allSatisfy { $0.targetApplicationPolicy == .launchIfNeeded })
    #expect(macroTasks.first?.targetApplicationReadyDelay == 10)
    #expect(macroTasks.dropFirst().allSatisfy { $0.targetApplicationReadyDelay == 0 })
    #expect(macroTasks.allSatisfy { $0.targetApplicationCleanupPolicy == .keepOpen })
    #expect(macroTasks.allSatisfy { $0.missedRunPolicy == .latestOnly })
    #expect(macroTasks.first?.schedule != nil)
    #expect(macroTasks.dropFirst().allSatisfy { $0.schedule == nil })
    let conditionTask = try #require(
      workflow.tasks.first { task in
        if case .condition = task.kind { return true }
        return false
      })
    guard case .condition(let conditionSpec) = conditionTask.kind,
      case .ocrText(let ocrCondition) = conditionSpec.kind
    else {
      Issue.record("Expected imported OCR condition")
      return
    }
    #expect(ocrCondition.text == "Claim")
    #expect(ocrCondition.matchMode == .exact)
    #expect(ocrCondition.searchRegion == RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
    #expect(ocrCondition.searchRegionSpace == .contentNormalized)
  }

  @Test("Manual sequence attaches a manual schedule only to its first macro")
  func manualScheduleStaysAtSequenceRoot() throws {
    let macros = [
      SavedMacro(name: "First", events: []),
      SavedMacro(name: "Second", events: []),
    ]
    let draft = AutomationLinearSequenceDraft(
      name: "Manual sequence",
      macros: macros,
      scheduleMode: .manual,
      startAt: Date(timeIntervalSince1970: 2_000)
    )

    let tasks = draft.makeDocument(onOrAfter: Date(timeIntervalSince1970: 1_000)).workflow.tasks

    #expect(tasks.first?.schedule == AutomationWorkflowDraftSchedule(type: "manual"))
    #expect(tasks.dropFirst().allSatisfy { $0.schedule == nil })
    #expect(draft.nextRun(onOrAfter: Date(timeIntervalSince1970: 1_000)) == nil)
  }

  @Test("Linear sequence validation rejects incomplete timing and OCR gates")
  func validatesSimpleInputs() {
    let macro = SavedMacro(name: "Claim", events: [])
    let now = Date(timeIntervalSince1970: 1_000)
    var draft = AutomationLinearSequenceDraft(
      name: "",
      macros: [macro, macro],
      scheduleMode: .once,
      startAt: now
    )

    #expect(draft.validationMessage(onOrAfter: now) != nil)
    draft.name = "Claim twice"
    #expect(draft.validationMessage(onOrAfter: now) != nil)
    draft.startAt = now.addingTimeInterval(60)
    draft.steps[0].continuation = .screenText
    #expect(draft.validationMessage(onOrAfter: now) != nil)
    draft.steps[0].screenText = "Ready"
    draft.steps[0].conditionTimeout = 0
    #expect(draft.validationMessage(onOrAfter: now) != nil)
    draft.steps[0].conditionTimeout = 30
    #expect(draft.validationMessage(onOrAfter: now) == nil)
  }

  @Test("Immediate continuation compiles a direct success dependency")
  func compilesImmediateContinuation() {
    let macros = [
      SavedMacro(name: "First", events: []),
      SavedMacro(name: "Second", events: []),
    ]
    let draft = AutomationLinearSequenceDraft(
      name: "Immediate",
      macros: macros,
      scheduleMode: .manual,
      startAt: Date(timeIntervalSince1970: 2_000)
    )

    #expect(
      draft.makeDocument().workflow.dependencies == [
        AutomationWorkflowDraftDependency(
          from: "macro_1",
          to: "macro_2",
          trigger: "success"
        )
      ])
  }

  @Test("Every schedule mode compiles deterministically on the first macro")
  func compilesEveryScheduleMode() throws {
    let start = Date(timeIntervalSince1970: 100_000)
    let reference = Date(timeIntervalSince1970: 90_000)
    let macro = SavedMacro(name: "Scheduled", events: [])

    for mode in AutomationLinearScheduleMode.allCases {
      let draft = AutomationLinearSequenceDraft(
        name: mode.rawValue,
        macros: [macro],
        scheduleMode: mode,
        startAt: start,
        repeatEvery: 3,
        repeatUnit: .hours,
        weeklyWeekday: 3
      )
      let schedule = try #require(
        draft.makeDocument(onOrAfter: reference).workflow.tasks.first?.schedule
      )

      switch mode {
      case .manual:
        #expect(schedule.type == "manual")
      case .daily:
        #expect(schedule.type == "repeating")
        #expect(schedule.every == 1)
        #expect(schedule.unit == "days")
      case .weekly:
        #expect(schedule.type == "repeating")
        #expect(schedule.every == 1)
        #expect(schedule.unit == "weeks")
      case .once:
        #expect(schedule.type == "once")
        #expect(schedule.startAt == start)
      case .interval:
        #expect(schedule.type == "repeating")
        #expect(schedule.every == 3)
        #expect(schedule.unit == "hours")
      }
    }
  }

  @Test("Sequence editor mutations preserve explicit order")
  func editorMutationsPreserveOrder() throws {
    let first = SavedMacro(name: "First", events: [])
    let second = SavedMacro(name: "Second", events: [])
    let third = SavedMacro(name: "Third", events: [])
    var draft = AutomationLinearSequenceDraft(
      name: "Editable",
      macros: [first, second],
      startAt: Date(timeIntervalSince1970: 2_000)
    )

    draft.add(third)
    let thirdStep = try #require(draft.steps.last)
    draft.moveStep(id: thirdStep.id, direction: .earlier)
    draft.removeStep(id: draft.steps[0].id)

    #expect(draft.steps.map(\.macroName) == ["Third", "Second"])
  }

  @Test("Preparation macro inserts before the task steps")
  func preparationMacroInsertsFirst() {
    let task = SavedMacro(name: "Claim", events: [])
    let login = SavedMacro(name: "Sign in", events: [])
    var draft = AutomationLinearSequenceDraft(
      name: "Daily claim",
      macros: [task],
      startAt: Date(timeIntervalSince1970: 2_000)
    )

    draft.addPreparationMacro(login)

    #expect(draft.steps.map(\.macroID) == [login.id, task.id])
  }

  @Test("Save intents keep Library test and advanced navigation distinct")
  func saveIntentsAreDistinct() {
    #expect(!AutomationLinearSequenceSaveIntent.save.opensWorkflow)
    #expect(!AutomationLinearSequenceSaveIntent.save.runsAfterSaving)
    #expect(AutomationLinearSequenceSaveIntent.saveAndTest.runsAfterSaving)
    #expect(!AutomationLinearSequenceSaveIntent.saveAndTest.opensWorkflow)
    #expect(AutomationLinearSequenceSaveIntent.advancedEdit.opensWorkflow)
    #expect(!AutomationLinearSequenceSaveIntent.advancedEdit.runsAfterSaving)
  }
}
