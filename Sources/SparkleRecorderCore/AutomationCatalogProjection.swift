import Foundation

public enum AutomationAuthoringTier: String, Codable, Equatable, Hashable, Sendable {
  case singleMacro
  case linearSequence
  case advancedWorkflow
}

public struct AutomationCatalogItemProjection: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID { workflowID }

  public var workflowID: UUID
  public var name: String
  public var tier: AutomationAuthoringTier
  public var macroCount: Int
  public var stepCount: Int
  public var isEnabled: Bool
  public var hasSchedule: Bool
  public var nextScheduledOccurrence: Date?
  public var status: AutomationDisplayStatus
  public var statusDetail: String
  public var latestActivityAt: Date?
  public var hasEvidence: Bool

  public init(
    workflowID: UUID,
    name: String,
    tier: AutomationAuthoringTier,
    macroCount: Int,
    stepCount: Int,
    isEnabled: Bool,
    hasSchedule: Bool,
    nextScheduledOccurrence: Date?,
    status: AutomationDisplayStatus,
    statusDetail: String,
    latestActivityAt: Date?,
    hasEvidence: Bool
  ) {
    self.workflowID = workflowID
    self.name = name
    self.tier = tier
    self.macroCount = macroCount
    self.stepCount = stepCount
    self.isEnabled = isEnabled
    self.hasSchedule = hasSchedule
    self.nextScheduledOccurrence = nextScheduledOccurrence
    self.status = status
    self.statusDetail = statusDetail
    self.latestActivityAt = latestActivityAt
    self.hasEvidence = hasEvidence
  }
}

public struct AutomationCatalogProjection: Codable, Equatable, Sendable {
  public var items: [AutomationCatalogItemProjection]
  public var enabledCount: Int
  public var scheduledCount: Int
  public var needsAttentionCount: Int

  public init(
    items: [AutomationCatalogItemProjection],
    enabledCount: Int,
    scheduledCount: Int,
    needsAttentionCount: Int
  ) {
    self.items = items
    self.enabledCount = enabledCount
    self.scheduledCount = scheduledCount
    self.needsAttentionCount = needsAttentionCount
  }

  public static func make(
    state: AutomationRunState,
    overview: AutomationOverviewProjection
  ) -> AutomationCatalogProjection {
    let workflowProjectionByID = Dictionary(
      uniqueKeysWithValues: overview.workflows.map { ($0.id, $0) }
    )
    let runsByWorkflowID = Dictionary(grouping: state.runs, by: \.workflowID)

    let items = state.workflows.compactMap { workflow -> AutomationCatalogItemProjection? in
      guard let projection = workflowProjectionByID[workflow.id] else { return nil }
      let runs = runsByWorkflowID[workflow.id] ?? []
      let latestRun = runs.max { activityDate(for: $0) < activityDate(for: $1) }
      let entryTaskIDs = Set(entryTaskIDs(for: workflow))
      let startTasks = workflow.tasks.filter { entryTaskIDs.contains($0.id) }
      let isEnabled = startTasks.contains { $0.isEnabled }
      let hasSchedule = workflow.tasks.contains { task in
        guard let schedule = task.schedule else { return false }
        return schedule != .manual
      }

      return AutomationCatalogItemProjection(
        workflowID: workflow.id,
        name: workflow.name,
        tier: tier(for: workflow),
        macroCount: workflow.tasks.count { $0.kind.macroID != nil },
        stepCount: workflow.tasks.count,
        isEnabled: isEnabled,
        hasSchedule: hasSchedule,
        nextScheduledOccurrence: projection.nextScheduledOccurrence,
        status: projection.status,
        statusDetail: projection.statusDetail,
        latestActivityAt: latestRun.map(activityDate),
        hasEvidence: runs.contains { $0.evidenceID != nil }
      )
    }
    .sorted { left, right in
      switch (left.nextScheduledOccurrence, right.nextScheduledOccurrence) {
      case (let leftDate?, let rightDate?) where leftDate != rightDate:
        return leftDate < rightDate
      case (.some, nil):
        return true
      case (nil, .some):
        return false
      default:
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
      }
    }

    let enabledCount = items.filter(\.isEnabled).count
    let scheduledCount = items.filter(\.hasSchedule).count
    let needsAttentionCount = items.filter {
      $0.status == .failed || $0.status == .blocked || $0.status == .timedOut
    }.count

    return AutomationCatalogProjection(
      items: items,
      enabledCount: enabledCount,
      scheduledCount: scheduledCount,
      needsAttentionCount: needsAttentionCount
    )
  }

  public static func tier(for workflow: AutomationWorkflow) -> AutomationAuthoringTier {
    guard !workflow.tasks.isEmpty else { return .advancedWorkflow }
    if workflow.tasks.count == 1,
      workflow.dependencies.isEmpty,
      workflow.tasks[0].kind.macroID != nil
    {
      return .singleMacro
    }
    return isLinearSequence(workflow) ? .linearSequence : .advancedWorkflow
  }

  public static func entryTaskIDs(for workflow: AutomationWorkflow) -> [UUID] {
    let incomingTaskIDs = Set(
      workflow.dependencies.filter(\.isEnabled).map(\.toTaskID)
    )
    return workflow.tasks.lazy
      .filter { !incomingTaskIDs.contains($0.id) }
      .map(\.id)
  }

  private static func isLinearSequence(_ workflow: AutomationWorkflow) -> Bool {
    guard workflow.tasks.count(where: { $0.kind.macroID != nil }) >= 2 else { return false }
    guard workflow.tasks.allSatisfy(isLinearTask) else { return false }
    guard workflow.dependencies.allSatisfy(isLinearDependency) else { return false }

    let enabledDependencies = workflow.dependencies.filter(\.isEnabled)
    guard enabledDependencies.count == workflow.tasks.count - 1 else { return false }

    let taskIDs = Set(workflow.tasks.map(\.id))
    var incoming: [UUID: Int] = [:]
    var outgoing: [UUID: Int] = [:]
    var adjacency: [UUID: [UUID]] = [:]
    for dependency in enabledDependencies {
      guard taskIDs.contains(dependency.fromTaskID), taskIDs.contains(dependency.toTaskID) else {
        return false
      }
      incoming[dependency.toTaskID, default: 0] += 1
      outgoing[dependency.fromTaskID, default: 0] += 1
      adjacency[dependency.fromTaskID, default: []].append(dependency.toTaskID)
      adjacency[dependency.toTaskID, default: []].append(dependency.fromTaskID)
    }
    guard incoming.values.allSatisfy({ $0 <= 1 }),
      outgoing.values.allSatisfy({ $0 <= 1 }),
      taskIDs.count(where: { incoming[$0, default: 0] == 0 }) == 1,
      taskIDs.count(where: { outgoing[$0, default: 0] == 0 }) == 1
    else {
      return false
    }

    var visited: Set<UUID> = []
    var pending = [workflow.tasks[0].id]
    while let taskID = pending.popLast() {
      guard visited.insert(taskID).inserted else { continue }
      pending.append(contentsOf: adjacency[taskID, default: []])
    }
    return visited == taskIDs
  }

  private static func isLinearTask(_ task: AutomationTask) -> Bool {
    switch task.kind {
    case .macro:
      return task.retryPolicy == .none
        && task.joinPolicy == .all
        && task.targetApplicationPolicy == .launchIfNeeded
        && task.targetApplicationCleanupPolicy == .keepOpen
        && task.playbackLoops == 1
        && task.missedRunPolicy == .latestOnly
    case .condition(let condition):
      guard case .ocrText = condition.kind else { return false }
      return task.retryPolicy == .none && task.joinPolicy == .all
    case .delay:
      return task.retryPolicy == .none && task.joinPolicy == .all
    case .notification:
      return false
    }
  }

  private static func isLinearDependency(_ dependency: AutomationDependency) -> Bool {
    guard dependency.isEnabled, dependency.dynamicDelay == nil else { return false }
    switch dependency.trigger {
    case .onSuccess, .onConditionMatched:
      return true
    case .onFailure, .onTimeout, .onCancelled, .onConditionNotMatched, .onOutcome, .always:
      return false
    }
  }

  private static func activityDate(for run: AutomationTaskRun) -> Date {
    run.completedAt ?? run.actualStartTime ?? run.earliestStartTime ?? run.createdAt
  }
}
