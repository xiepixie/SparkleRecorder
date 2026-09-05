import Foundation
import Testing

@testable import SparkleRecorderCore

@Suite("Automation Catalog Projection Tests")
struct AutomationCatalogProjectionTests {
  @Test("Catalog classifies single macro, linear sequence, and advanced workflow")
  func classifiesAuthoringTiers() {
    let single = AutomationWorkflow(
      name: "Daily claim",
      tasks: [AutomationTask(name: "Claim", kind: .macro(macroID: UUID()))]
    )

    let first = linearMacroTask(name: "Open")
    let gate = AutomationTask(
      name: "Wait for Ready",
      kind: .condition(
        AutomationConditionSpec(
          name: "Ready",
          kind: .ocrText(AutomationOCRCondition(text: "Ready"))
        ))
    )
    let second = linearMacroTask(name: "Claim")
    let linear = AutomationWorkflow(
      name: "Claim sequence",
      tasks: [first, gate, second],
      dependencies: [
        AutomationDependency(fromTaskID: first.id, toTaskID: gate.id, trigger: .onSuccess),
        AutomationDependency(
          fromTaskID: gate.id, toTaskID: second.id, trigger: .onConditionMatched),
      ]
    )

    let success = AutomationTask(name: "Success", kind: .macro(macroID: UUID()))
    let failure = AutomationTask(
      name: "Failure",
      kind: .notification(.init(title: "Failed", body: "Claim failed"))
    )
    let advanced = AutomationWorkflow(
      name: "Branched",
      tasks: [first, success, failure],
      dependencies: [
        AutomationDependency(fromTaskID: first.id, toTaskID: success.id, trigger: .onSuccess),
        AutomationDependency(fromTaskID: first.id, toTaskID: failure.id, trigger: .onFailure),
      ]
    )

    #expect(AutomationCatalogProjection.tier(for: single) == .singleMacro)
    #expect(AutomationCatalogProjection.tier(for: linear) == .linearSequence)
    #expect(AutomationCatalogProjection.tier(for: advanced) == .advancedWorkflow)
  }

  @Test("Catalog projects workflow-level status, schedule, and evidence")
  func projectsOperationalSummary() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let macroID = UUID()
    let task = AutomationTask(
      name: "Claim",
      kind: .macro(macroID: macroID),
      schedule: .once(now.addingTimeInterval(3_600))
    )
    let workflow = AutomationWorkflow(name: "Daily claim", tasks: [task])
    let run = AutomationTaskRun(
      workflowID: workflow.id,
      taskID: task.id,
      macroID: macroID,
      completedAt: now,
      status: .completed,
      outcome: .succeeded(report: nil),
      evidenceID: UUID(),
      createdAt: now.addingTimeInterval(-10)
    )
    let state = AutomationRunState(workflows: [workflow], runs: [run])
    let overview = AutomationViewProjection.overview(from: state)

    let catalog = AutomationCatalogProjection.make(state: state, overview: overview)
    let item = try #require(catalog.items.first)

    #expect(item.workflowID == workflow.id)
    #expect(item.tier == AutomationAuthoringTier.singleMacro)
    #expect(item.macroCount == 1)
    #expect(item.stepCount == 1)
    #expect(item.isEnabled)
    #expect(item.hasSchedule)
    #expect(item.nextScheduledOccurrence == now.addingTimeInterval(3_600))
    #expect(item.status == AutomationDisplayStatus.completed)
    #expect(item.latestActivityAt == now)
    #expect(item.hasEvidence)
    #expect(catalog.enabledCount == 1)
    #expect(catalog.scheduledCount == 1)
  }

  @Test("Catalog enabled state follows workflow entry tasks")
  func enabledStateFollowsEntryTasks() throws {
    let first = linearMacroTask(name: "First", isEnabled: false)
    let second = linearMacroTask(name: "Second")
    let workflow = AutomationWorkflow(
      name: "Paused sequence",
      tasks: [first, second],
      dependencies: [
        AutomationDependency(fromTaskID: first.id, toTaskID: second.id, trigger: .onSuccess)
      ]
    )
    let state = AutomationRunState(workflows: [workflow])
    let catalog = AutomationCatalogProjection.make(
      state: state,
      overview: AutomationViewProjection.overview(from: state)
    )

    #expect(try #require(catalog.items.first).isEnabled == false)
    #expect(catalog.enabledCount == 0)
  }

  @Test("Entry tasks ignore disabled dependencies and preserve workflow order")
  func entryTasksUseEnabledDependencies() {
    let first = linearMacroTask(name: "First")
    let second = linearMacroTask(name: "Second")
    let third = linearMacroTask(name: "Third")
    let workflow = AutomationWorkflow(
      name: "Multiple entries",
      tasks: [third, first, second],
      dependencies: [
        AutomationDependency(fromTaskID: first.id, toTaskID: second.id, trigger: .onSuccess),
        AutomationDependency(
          fromTaskID: second.id,
          toTaskID: third.id,
          trigger: .onSuccess,
          isEnabled: false
        ),
      ]
    )

    #expect(AutomationCatalogProjection.entryTaskIDs(for: workflow) == [third.id, first.id])
  }

  private func linearMacroTask(name: String, isEnabled: Bool = true) -> AutomationTask {
    AutomationTask(
      name: name,
      kind: .macro(macroID: UUID()),
      isEnabled: isEnabled,
      targetApplicationPolicy: .launchIfNeeded,
      targetApplicationCleanupPolicy: .keepOpen,
      playbackLoops: 1,
      missedRunPolicy: .latestOnly
    )
  }
}
