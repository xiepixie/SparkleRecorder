import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Workflow Authoring State Tests")
struct AutomationWorkflowAuthoringStateTests {
  @Test("Repair signature tracks authoring topology without reacting to unrelated task edits")
  func repairSignatureTracksOnlyRelevantTopology() {
    let task = AutomationTask(name: "Task", kind: .delay(1))
    let workflow = AutomationWorkflow(name: "Flow", tasks: [task])
    let baseline = AutomationWorkflowAuthoringRepairSignature(workflows: [workflow])

    var renamed = workflow
    renamed.tasks[0].name = "Renamed"
    #expect(AutomationWorkflowAuthoringRepairSignature(workflows: [renamed]) == baseline)

    var changedKind = workflow
    changedKind.tasks[0].kind = .condition(
      AutomationConditionSpec(name: "Gate", kind: .manualApproval)
    )
    #expect(AutomationWorkflowAuthoringRepairSignature(workflows: [changedKind]) != baseline)

    var removedTask = workflow
    removedTask.tasks.removeAll()
    #expect(AutomationWorkflowAuthoringRepairSignature(workflows: [removedTask]) != baseline)
  }

  @Test("Repair replaces a missing workflow selection and clears transient link state")
  func repairMissingWorkflow() {
    let existingTask = AutomationTask(name: "Existing", kind: .delay(1))
    let existingWorkflow = AutomationWorkflow(name: "Existing", tasks: [existingTask])
    var state = AutomationWorkflowAuthoringState(
      selectedWorkflowID: UUID(),
      selection: .task(UUID()),
      pendingDependencySourceID: UUID(),
      pendingDependencyTrigger: .onFailure,
      selectedInspectorRunID: UUID()
    )

    state.repair(workflows: [existingWorkflow])

    #expect(state.selectedWorkflowID == existingWorkflow.id)
    #expect(state.selection == .workflow)
    #expect(state.pendingDependencySourceID == nil)
    #expect(state.pendingDependencyTrigger == .onSuccess)
    #expect(state.selectedInspectorRunID == nil)
  }

  @Test("Repair drops missing task and dependency selections")
  func repairMissingNestedSelections() {
    let task = AutomationTask(name: "Task", kind: .delay(1))
    let workflow = AutomationWorkflow(name: "Flow", tasks: [task])

    var taskState = AutomationWorkflowAuthoringState(
      selectedWorkflowID: workflow.id,
      selection: .task(UUID()),
      selectedInspectorRunID: UUID()
    )
    taskState.repair(workflows: [workflow])
    #expect(taskState.selection == .workflow)
    #expect(taskState.selectedInspectorRunID == nil)

    var dependencyState = AutomationWorkflowAuthoringState(
      selectedWorkflowID: workflow.id,
      selection: .dependency(UUID()),
      selectedInspectorRunID: UUID()
    )
    dependencyState.repair(workflows: [workflow])
    #expect(dependencyState.selection == .workflow)
    #expect(dependencyState.selectedInspectorRunID == nil)
  }

  @Test("Repair cancels a link whose source task disappeared")
  func repairMissingLinkSource() {
    let workflow = AutomationWorkflow(name: "Flow")
    var state = AutomationWorkflowAuthoringState(
      selectedWorkflowID: workflow.id,
      pendingDependencySourceID: UUID(),
      pendingDependencyTrigger: .onFailure
    )

    state.repair(workflows: [workflow])

    #expect(state.pendingDependencySourceID == nil)
    #expect(state.pendingDependencyTrigger == .onSuccess)
  }

  @Test("Repair normalizes the pending trigger when the source task kind changes")
  func repairTriggerAfterSourceKindChange() {
    let source = AutomationTask(
      name: "Gate",
      kind: .condition(
        AutomationConditionSpec(
          name: "Gate",
          kind: .manualApproval
        )
      )
    )
    let workflow = AutomationWorkflow(name: "Flow", tasks: [source])
    var state = AutomationWorkflowAuthoringState(
      selectedWorkflowID: workflow.id,
      selection: .task(source.id),
      pendingDependencySourceID: source.id,
      pendingDependencyTrigger: .onSuccess
    )

    state.repair(workflows: [workflow])

    #expect(state.pendingDependencyTrigger == AutomationDependencyTriggerDraft.onConditionMatched)
  }

  @Test("Completing a link rejects missing source or target tasks")
  func completeRejectsDanglingEndpoints() {
    let source = AutomationTask(name: "Source", kind: .delay(1))
    let target = AutomationTask(name: "Target", kind: .delay(1))
    let workflow = AutomationWorkflow(name: "Flow", tasks: [source, target])

    var missingSource = AutomationWorkflowAuthoringState(
      selectedWorkflowID: workflow.id,
      pendingDependencySourceID: UUID(),
      pendingDependencyTrigger: .onSuccess
    )
    if case .invalid = missingSource.completeDependency(to: target.id, in: workflow) {
      #expect(missingSource.pendingDependencySourceID == nil)
    } else {
      Issue.record("Expected a missing source to invalidate the link")
    }

    var missingTarget = AutomationWorkflowAuthoringState(selectedWorkflowID: workflow.id)
    let didBeginMissingTargetLink = missingTarget.beginDependency(from: source.id, in: workflow)
    #expect(didBeginMissingTargetLink)
    if case .invalid = missingTarget.completeDependency(to: UUID(), in: workflow) {
      #expect(missingTarget.pendingDependencySourceID == nil)
    } else {
      Issue.record("Expected a missing target to invalidate the link")
    }
  }

  @Test("Completing an existing link selects the existing dependency")
  func completeSelectsExistingDependency() {
    let source = AutomationTask(name: "Source", kind: .delay(1))
    let target = AutomationTask(name: "Target", kind: .delay(1))
    let dependency = AutomationDependency(
      fromTaskID: source.id,
      toTaskID: target.id,
      trigger: .onSuccess
    )
    let workflow = AutomationWorkflow(
      name: "Flow",
      tasks: [source, target],
      dependencies: [dependency]
    )
    var state = AutomationWorkflowAuthoringState(selectedWorkflowID: workflow.id)
    let didBeginExistingLink = state.beginDependency(from: source.id, in: workflow)
    #expect(didBeginExistingLink)

    let completion = state.completeDependency(to: target.id, in: workflow)

    if case .existing(let dependencyID) = completion {
      #expect(dependencyID == dependency.id)
    } else {
      Issue.record("Expected the existing dependency to be selected")
    }
    #expect(state.selection == .dependency(dependency.id))
    #expect(state.pendingDependencySourceID == nil)
  }

  @Test("Completing a new link uses the source task trigger vocabulary")
  func completeCreatesNormalizedDependency() {
    let source = AutomationTask(
      name: "Gate",
      kind: .condition(
        AutomationConditionSpec(
          name: "Gate",
          kind: .manualApproval
        )
      )
    )
    let target = AutomationTask(name: "Target", kind: .delay(1))
    let workflow = AutomationWorkflow(name: "Flow", tasks: [source, target])
    var state = AutomationWorkflowAuthoringState(
      selectedWorkflowID: workflow.id,
      pendingDependencySourceID: source.id,
      pendingDependencyTrigger: .onSuccess
    )

    let completion = state.completeDependency(to: target.id, in: workflow)

    if case .create(let dependency) = completion {
      #expect(dependency.fromTaskID == source.id)
      #expect(dependency.toTaskID == target.id)
      #expect(dependency.trigger == AutomationDependencyTrigger.onConditionMatched)
      #expect(state.selection == AutomationAuthoringSelection.dependency(dependency.id))
    } else {
      Issue.record("Expected a new dependency")
    }
  }

  @Test("Task selection preserves an active link while workflow and dependency selection cancel it")
  func selectionTransitionsOwnLinkCleanup() {
    let source = AutomationTask(name: "Source", kind: .delay(1))
    let target = AutomationTask(name: "Target", kind: .delay(1))
    let dependency = AutomationDependency(
      fromTaskID: source.id,
      toTaskID: target.id,
      trigger: .onSuccess
    )
    let workflow = AutomationWorkflow(
      name: "Flow",
      tasks: [source, target],
      dependencies: [dependency]
    )
    var state = AutomationWorkflowAuthoringState(selectedWorkflowID: workflow.id)
    let didBeginFirstLink = state.beginDependency(from: source.id, in: workflow)
    #expect(didBeginFirstLink)

    state.selectTask(target.id)
    #expect(state.pendingDependencySourceID == source.id)

    state.selectDependency(dependency.id)
    #expect(state.pendingDependencySourceID == nil)

    let didBeginSecondLink = state.beginDependency(from: source.id, in: workflow)
    #expect(didBeginSecondLink)
    state.selectWorkflow(workflow.id)
    #expect(state.pendingDependencySourceID == nil)
  }
}
