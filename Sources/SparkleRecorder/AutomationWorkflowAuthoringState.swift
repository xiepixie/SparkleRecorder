import Foundation
import SparkleRecorderCore

struct AutomationWorkflowAuthoringRepairSignature: Equatable {
  struct Workflow: Equatable {
    struct Task: Equatable {
      enum TriggerVocabulary: Equatable {
        case standard
        case condition
      }

      var id: UUID
      var triggerVocabulary: TriggerVocabulary
    }

    var id: UUID
    var tasks: [Task]
    var dependencyIDs: [UUID]
  }

  var workflows: [Workflow]

  init(workflows: [AutomationWorkflow]) {
    self.workflows = workflows.map { workflow in
      Workflow(
        id: workflow.id,
        tasks: workflow.tasks.map { task in
          let vocabulary: Workflow.Task.TriggerVocabulary
          switch task.kind {
          case .condition:
            vocabulary = .condition
          case .macro, .delay, .notification:
            vocabulary = .standard
          }
          return Workflow.Task(id: task.id, triggerVocabulary: vocabulary)
        },
        dependencyIDs: workflow.dependencies.map(\.id)
      )
    }
  }
}

struct AutomationWorkflowAuthoringState {
  enum DependencyCompletion {
    case invalid
    case existing(UUID)
    case create(AutomationDependency)
  }

  var selectedWorkflowID: UUID?
  var selection: AutomationAuthoringSelection
  var pendingDependencySourceID: UUID?
  var pendingDependencyTrigger: AutomationDependencyTriggerDraft
  var selectedInspectorRunID: UUID?

  init(
    selectedWorkflowID: UUID? = nil,
    selection: AutomationAuthoringSelection = .workflow,
    pendingDependencySourceID: UUID? = nil,
    pendingDependencyTrigger: AutomationDependencyTriggerDraft = .onSuccess,
    selectedInspectorRunID: UUID? = nil
  ) {
    self.selectedWorkflowID = selectedWorkflowID
    self.selection = selection
    self.pendingDependencySourceID = pendingDependencySourceID
    self.pendingDependencyTrigger = pendingDependencyTrigger
    self.selectedInspectorRunID = selectedInspectorRunID
  }

  var selectedTaskID: UUID? {
    guard case .task(let taskID) = selection else { return nil }
    return taskID
  }

  var selectedDependencyID: UUID? {
    guard case .dependency(let dependencyID) = selection else { return nil }
    return dependencyID
  }

  var isLinkingDependency: Bool {
    pendingDependencySourceID != nil
  }

  func dependencyTriggerOptions(in workflow: AutomationWorkflow?) -> [AutomationDependencyTriggerDraft] {
    let sourceTask = pendingDependencySourceID.flatMap { workflow?.task(id: $0) }
    return AutomationDependencyTriggerDraft.options(for: sourceTask)
  }

  mutating func selectWorkflow(_ workflowID: UUID?) {
    selectedWorkflowID = workflowID
    selection = .workflow
    selectedInspectorRunID = nil
    cancelDependency()
  }

  mutating func selectTask(_ taskID: UUID, workflowID: UUID? = nil) {
    if let workflowID {
      selectedWorkflowID = workflowID
    }
    selection = .task(taskID)
    selectedInspectorRunID = nil
  }

  mutating func selectCreatedTask(_ taskID: UUID, workflowID: UUID) {
    selectedWorkflowID = workflowID
    selection = .task(taskID)
    selectedInspectorRunID = nil
    cancelDependency()
  }

  mutating func selectDependency(_ dependencyID: UUID, workflowID: UUID? = nil) {
    if let workflowID {
      selectedWorkflowID = workflowID
    }
    selection = .dependency(dependencyID)
    selectedInspectorRunID = nil
    cancelDependency()
  }

  mutating func selectTimelineItem(_ item: AutomationResourceTimelineItem) {
    selectedWorkflowID = item.workflowID
    selection = .task(item.taskID)
    selectedInspectorRunID = item.runID
    cancelDependency()
  }

  mutating func applyNavigation(_ resolution: AutomationWorkspaceNavigationResolution) {
    selectedWorkflowID = resolution.workflowID
    selection = resolution.selection
    selectedInspectorRunID = nil
    cancelDependency()
  }

  @discardableResult
  mutating func beginDependency(from taskID: UUID, in workflow: AutomationWorkflow) -> Bool {
    guard let sourceTask = workflow.task(id: taskID) else {
      cancelDependency()
      return false
    }

    selectedWorkflowID = workflow.id
    selection = .task(taskID)
    selectedInspectorRunID = nil
    pendingDependencySourceID = taskID
    pendingDependencyTrigger =
      AutomationDependencyTriggerDraft.options(for: sourceTask).first ?? .onSuccess
    return true
  }

  mutating func setPendingDependencyTrigger(
    _ trigger: AutomationDependencyTriggerDraft,
    in workflow: AutomationWorkflow?
  ) {
    guard let sourceID = pendingDependencySourceID,
      let sourceTask = workflow?.task(id: sourceID)
    else {
      cancelDependency()
      return
    }

    let options = AutomationDependencyTriggerDraft.options(for: sourceTask)
    pendingDependencyTrigger = options.contains(trigger) ? trigger : options.first ?? .onSuccess
  }

  mutating func completeDependency(
    to taskID: UUID,
    in workflow: AutomationWorkflow
  ) -> DependencyCompletion {
    guard let sourceID = pendingDependencySourceID,
      sourceID != taskID,
      let sourceTask = workflow.task(id: sourceID),
      workflow.task(id: taskID) != nil
    else {
      cancelDependency()
      return .invalid
    }

    selectedWorkflowID = workflow.id
    selectedInspectorRunID = nil

    if let existing = workflow.dependencies.first(where: {
      $0.fromTaskID == sourceID && $0.toTaskID == taskID
    }) {
      selection = .dependency(existing.id)
      cancelDependency()
      return .existing(existing.id)
    }

    let options = AutomationDependencyTriggerDraft.options(for: sourceTask)
    let trigger = options.contains(pendingDependencyTrigger)
      ? pendingDependencyTrigger
      : options.first ?? .onSuccess
    let dependency = AutomationDependency(
      fromTaskID: sourceID,
      toTaskID: taskID,
      trigger: trigger.trigger
    )
    selection = .dependency(dependency.id)
    cancelDependency()
    return .create(dependency)
  }

  mutating func cancelDependency() {
    pendingDependencySourceID = nil
    pendingDependencyTrigger = .onSuccess
  }

  mutating func didDeleteDependency(_ dependencyID: UUID) {
    cancelDependency()
    if selectedDependencyID == dependencyID {
      selection = .workflow
      selectedInspectorRunID = nil
    }
  }

  mutating func didDeleteWorkflow(
    _ workflowID: UUID,
    remainingWorkflows: [AutomationWorkflow]
  ) {
    if selectedWorkflowID == workflowID {
      selectWorkflow(remainingWorkflows.first?.id)
    } else {
      selectedInspectorRunID = nil
      cancelDependency()
    }
  }

  mutating func repair(workflows: [AutomationWorkflow]) {
    let workflowsByID = Dictionary(uniqueKeysWithValues: workflows.map { ($0.id, $0) })
    let repairedWorkflowID = selectedWorkflowID.flatMap { workflowsByID[$0] != nil ? $0 : nil }
      ?? workflows.first?.id

    if repairedWorkflowID != selectedWorkflowID {
      selectedWorkflowID = repairedWorkflowID
      selection = .workflow
      selectedInspectorRunID = nil
      cancelDependency()
    }

    guard let workflowID = repairedWorkflowID,
      let workflow = workflowsByID[workflowID]
    else {
      selectedWorkflowID = nil
      selection = .workflow
      selectedInspectorRunID = nil
      cancelDependency()
      return
    }

    switch selection {
    case .workflow:
      selectedInspectorRunID = nil
    case .task(let taskID):
      if workflow.task(id: taskID) == nil {
        selection = .workflow
        selectedInspectorRunID = nil
      }
    case .dependency(let dependencyID):
      if !workflow.dependencies.contains(where: { $0.id == dependencyID }) {
        selection = .workflow
        selectedInspectorRunID = nil
      }
    }

    guard let sourceID = pendingDependencySourceID,
      let sourceTask = workflow.task(id: sourceID)
    else {
      if pendingDependencySourceID != nil {
        cancelDependency()
      }
      return
    }

    let options = AutomationDependencyTriggerDraft.options(for: sourceTask)
    if !options.contains(pendingDependencyTrigger) {
      pendingDependencyTrigger = options.first ?? .onSuccess
    }
  }
}
