import Foundation

public enum AutomationViewProjection {
    public static func overview(from state: AutomationRunState) -> AutomationOverviewProjection {
        let generatedAt = state.now ?? Date.now
        let workflows = state.workflows.map { workflow in
            workflowProjection(for: workflow, runs: state.runs)
        }
        let timelineItems = state.runs.compactMap { run in
            timelineItem(for: run, state: state)
        }.sorted { left, right in
            timelineSortDate(left) < timelineSortDate(right)
        }
        let statusCounts = makeStatusCounts(workflows: workflows)

        return AutomationOverviewProjection(
            generatedAt: generatedAt,
            workflows: workflows,
            timelineItems: timelineItems,
            statusCounts: statusCounts
        )
    }

    private static let nodeSize = AutomationGraphSize(width: 196, height: 88)
    private static let horizontalSpacing = 120.0
    private static let verticalSpacing = 48.0
    private static let graphInset = 32.0

    private static func workflowProjection(
        for workflow: AutomationWorkflow,
        runs: [AutomationTaskRun]
    ) -> AutomationWorkflowProjection {
        let levels = levelsByTaskID(for: workflow)
        let positions = positionsByTaskID(for: workflow, levels: levels)
        let nodes = workflow.tasks.map { task in
            nodeProjection(
                for: task,
                workflowID: workflow.id,
                run: latestRun(for: task, workflowID: workflow.id, runs: runs),
                position: positions[task.id] ?? AutomationGraphPoint(x: graphInset, y: graphInset)
            )
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.taskID, $0) })
        let edges = workflow.dependencies.compactMap { dependency in
            edgeProjection(for: dependency, workflowID: workflow.id, nodeByID: nodeByID, runs: runs)
        }

        return AutomationWorkflowProjection(
            id: workflow.id,
            name: workflow.name,
            nodes: nodes,
            edges: edges,
            graphSize: graphSize(for: positions),
            nodeSize: nodeSize
        )
    }

    private static func nodeProjection(
        for task: AutomationTask,
        workflowID: UUID,
        run: AutomationTaskRun?,
        position: AutomationGraphPoint
    ) -> AutomationTaskNodeProjection {
        AutomationTaskNodeProjection(
            workflowID: workflowID,
            taskID: task.id,
            runID: run?.id,
            title: task.name,
            kindLabel: kindLabel(for: task.kind),
            scheduleLabel: scheduleLabel(for: task.schedule),
            resourceLabel: resourceLabel(for: task.resourceRequirement),
            status: displayStatus(for: task, run: run),
            statusDetail: statusDetail(for: run),
            hasEvidence: run?.evidenceID != nil,
            position: position
        )
    }

    private static func edgeProjection(
        for dependency: AutomationDependency,
        workflowID: UUID,
        nodeByID: [UUID: AutomationTaskNodeProjection],
        runs: [AutomationTaskRun]
    ) -> AutomationDependencyEdgeProjection? {
        guard let source = nodeByID[dependency.fromTaskID],
              let target = nodeByID[dependency.toTaskID] else {
            return nil
        }

        let sourceRun = latestRun(
            forTaskID: dependency.fromTaskID,
            workflowID: workflowID,
            runs: runs
        )
        let start = AutomationGraphPoint(
            x: source.position.x + nodeSize.width,
            y: source.position.y + nodeSize.height / 2
        )
        let end = AutomationGraphPoint(
            x: target.position.x,
            y: target.position.y + nodeSize.height / 2
        )

        return AutomationDependencyEdgeProjection(
            id: dependency.id,
            fromTaskID: dependency.fromTaskID,
            toTaskID: dependency.toTaskID,
            triggerLabel: triggerLabel(for: dependency.trigger),
            delayLabel: delayLabel(for: dependency.delay),
            status: edgeStatus(for: dependency, sourceRun: sourceRun),
            start: start,
            end: end
        )
    }

    private static func latestRun(
        for task: AutomationTask,
        workflowID: UUID,
        runs: [AutomationTaskRun]
    ) -> AutomationTaskRun? {
        latestRun(forTaskID: task.id, workflowID: workflowID, runs: runs)
    }

    private static func latestRun(
        forTaskID taskID: UUID,
        workflowID: UUID,
        runs: [AutomationTaskRun]
    ) -> AutomationTaskRun? {
        runs
            .filter { $0.workflowID == workflowID && $0.taskID == taskID }
            .max { timelineSortDate($0) < timelineSortDate($1) }
    }

    private static func timelineItem(
        for run: AutomationTaskRun,
        state: AutomationRunState
    ) -> AutomationResourceTimelineItem? {
        guard let workflow = state.workflow(id: run.workflowID),
              let task = workflow.task(id: run.taskID) else {
            return nil
        }

        return AutomationResourceTimelineItem(
            id: run.id,
            workflowID: run.workflowID,
            taskID: run.taskID,
            runID: run.id,
            title: task.name,
            lane: timelineLane(for: task, run: run),
            status: displayStatus(for: task, run: run),
            resourceLabel: resourceLabel(for: task.resourceRequirement),
            startedAt: run.actualStartTime,
            completedAt: run.completedAt,
            hasEvidence: run.evidenceID != nil
        )
    }

    private static func displayStatus(
        for task: AutomationTask,
        run: AutomationTaskRun?
    ) -> AutomationDisplayStatus {
        guard let run else {
            return .scheduled
        }

        if let outcome = run.outcome {
            return displayStatus(for: outcome)
        }

        switch run.status {
        case .planned:
            return .scheduled
        case .waitingForDependencies:
            return .waiting
        case .waitingForResource:
            return task.resourceRequirement.requiresForegroundInput ? .queued : .waiting
        case .queued:
            return .queued
        case .running:
            return .running
        case .completed:
            return .completed
        }
    }

    private static func displayStatus(for outcome: AutomationOutcome) -> AutomationDisplayStatus {
        switch outcome {
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .resourceConflict, .permissionDenied, .missingMacro, .rejected:
            return .blocked
        }
    }

    private static func statusDetail(for run: AutomationTaskRun?) -> String {
        guard let run else {
            return NSLocalizedString("No run has started yet", comment: "")
        }

        if let outcome = run.outcome {
            return outcomeDetail(for: outcome)
        }

        switch run.status {
        case .planned:
            return NSLocalizedString("Waiting for its scheduled start", comment: "")
        case .waitingForDependencies:
            return NSLocalizedString("Waiting for an upstream task", comment: "")
        case .waitingForResource:
            return NSLocalizedString("Waiting for a required resource", comment: "")
        case .queued:
            return NSLocalizedString("Queued to run", comment: "")
        case .running:
            return NSLocalizedString("Running now", comment: "")
        case .completed:
            return NSLocalizedString("Completed", comment: "")
        }
    }

    private static func outcomeDetail(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return NSLocalizedString("Completed successfully", comment: "")
        case .failed(let report):
            return report?.errorMessage ?? NSLocalizedString("Run failed", comment: "")
        case .cancelled(let reason):
            return reason ?? NSLocalizedString("Cancelled", comment: "")
        case .timedOut:
            return NSLocalizedString("Timed out before completion", comment: "")
        case .resourceConflict(let resource):
            return resource.map {
                String(format: NSLocalizedString("Resource conflict: %@", comment: ""), resourceLabel(for: $0))
            } ?? NSLocalizedString("Resource conflict", comment: "")
        case .permissionDenied(let permission, let message):
            return String(format: NSLocalizedString("%@: %@", comment: ""), permissionLabel(for: permission), message)
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition did not match", comment: "")
        case .missingMacro:
            return NSLocalizedString("Macro is missing", comment: "")
        case .rejected(let reason):
            return reason
        }
    }

    private static func edgeStatus(
        for dependency: AutomationDependency,
        sourceRun: AutomationTaskRun?
    ) -> AutomationDependencyDisplayStatus {
        guard dependency.isEnabled else {
            return .disabled
        }
        guard let sourceRun else {
            return .pending
        }
        guard let outcome = sourceRun.outcome else {
            return sourceRun.status == .running ? .waiting : .pending
        }
        return dependency.fires(for: outcome) ? .satisfied : .blocked
    }

    private static func timelineLane(
        for task: AutomationTask,
        run: AutomationTaskRun
    ) -> AutomationResourceTimelineLane {
        if run.outcome != nil {
            return .completed
        }
        switch run.status {
        case .planned, .waitingForDependencies, .queued:
            return .waiting
        case .waitingForResource:
            return task.resourceRequirement.requiresForegroundInput ? .foregroundInput : .waiting
        case .running:
            if task.resourceRequirement.resources.contains(.foregroundInput) {
                return .foregroundInput
            }
            if task.resourceRequirement.resources.contains(.screenCapture) {
                return .screenCapture
            }
            return .waiting
        case .completed:
            return .completed
        }
    }

    private static func levelsByTaskID(for workflow: AutomationWorkflow) -> [UUID: Int] {
        let taskIDs = Set(workflow.tasks.map(\.id))
        var levels = Dictionary(uniqueKeysWithValues: workflow.tasks.map { ($0.id, 0) })
        guard !workflow.tasks.isEmpty else {
            return levels
        }

        for _ in workflow.tasks.indices {
            for dependency in workflow.dependencies where dependency.isEnabled {
                guard taskIDs.contains(dependency.fromTaskID),
                      taskIDs.contains(dependency.toTaskID) else {
                    continue
                }
                let nextLevel = min(workflow.tasks.count - 1, (levels[dependency.fromTaskID] ?? 0) + 1)
                levels[dependency.toTaskID] = max(levels[dependency.toTaskID] ?? 0, nextLevel)
            }
        }

        return levels
    }

    private static func positionsByTaskID(
        for workflow: AutomationWorkflow,
        levels: [UUID: Int]
    ) -> [UUID: AutomationGraphPoint] {
        var rowByLevel: [Int: Int] = [:]
        var positions: [UUID: AutomationGraphPoint] = [:]

        for task in workflow.tasks {
            let level = levels[task.id] ?? 0
            let row = rowByLevel[level, default: 0]
            rowByLevel[level] = row + 1
            positions[task.id] = AutomationGraphPoint(
                x: task.graphPosition?.x ?? graphInset + Double(level) * (nodeSize.width + horizontalSpacing),
                y: task.graphPosition?.y ?? graphInset + Double(row) * (nodeSize.height + verticalSpacing)
            )
        }

        return positions
    }

    private static func graphSize(for positions: [UUID: AutomationGraphPoint]) -> AutomationGraphSize {
        let maxX = positions.values.map(\.x).max() ?? graphInset
        let maxY = positions.values.map(\.y).max() ?? graphInset
        return AutomationGraphSize(
            width: max(640, maxX + nodeSize.width + graphInset),
            height: max(320, maxY + nodeSize.height + graphInset)
        )
    }

    private static func makeStatusCounts(workflows: [AutomationWorkflowProjection]) -> [AutomationStatusCount] {
        let statuses = workflows.flatMap { $0.nodes.map(\.status) }
        return AutomationDisplayStatus.allCases.compactMap { status in
            let count = statuses.count { $0 == status }
            return count > 0 ? AutomationStatusCount(status: status, count: count) : nil
        }
    }

    private static func timelineSortDate(_ item: AutomationResourceTimelineItem) -> Date {
        item.startedAt ?? item.completedAt ?? .distantPast
    }

    private static func timelineSortDate(_ run: AutomationTaskRun) -> Date {
        run.completedAt ?? run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    private static func kindLabel(for kind: AutomationTaskKind) -> String {
        switch kind {
        case .macro:
            NSLocalizedString("Macro", comment: "")
        case .condition:
            NSLocalizedString("Condition", comment: "")
        case .delay:
            NSLocalizedString("Delay", comment: "")
        case .notification:
            NSLocalizedString("Notification", comment: "")
        }
    }

    private static func scheduleLabel(for schedule: AutomationSchedule?) -> String {
        guard let schedule else {
            return NSLocalizedString("Manual", comment: "")
        }

        switch schedule {
        case .manual:
            return NSLocalizedString("Manual", comment: "")
        case .once:
            return NSLocalizedString("Scheduled once", comment: "")
        case .repeating:
            return NSLocalizedString("Repeating", comment: "")
        }
    }

    private static func triggerLabel(for trigger: AutomationDependencyTrigger) -> String {
        switch trigger {
        case .onSuccess:
            NSLocalizedString("On success", comment: "")
        case .onFailure:
            NSLocalizedString("On failure", comment: "")
        case .onTimeout:
            NSLocalizedString("On timeout", comment: "")
        case .onCancelled:
            NSLocalizedString("On cancel", comment: "")
        case .onConditionMatched:
            NSLocalizedString("Condition matched", comment: "")
        case .onConditionNotMatched:
            NSLocalizedString("Condition not matched", comment: "")
        case .onOutcome(let predicate):
            predicateLabel(for: predicate)
        case .always:
            NSLocalizedString("Always", comment: "")
        }
    }

    private static func predicateLabel(for predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .success:
            NSLocalizedString("Success", comment: "")
        case .failure:
            NSLocalizedString("Failure", comment: "")
        case .timeout:
            NSLocalizedString("Timeout", comment: "")
        case .cancelled:
            NSLocalizedString("Cancelled", comment: "")
        case .conditionMatched:
            NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            NSLocalizedString("Condition not matched", comment: "")
        case .anyTerminal:
            NSLocalizedString("Any terminal outcome", comment: "")
        }
    }

    private static func delayLabel(for delay: TimeInterval) -> String {
        guard delay > 0 else {
            return NSLocalizedString("No delay", comment: "")
        }
        return String(format: NSLocalizedString("%ds delay", comment: ""), Int(delay.rounded()))
    }

    private static func resourceLabel(for requirement: AutomationResourceRequirement) -> String {
        guard !requirement.resources.isEmpty else {
            return NSLocalizedString("Background", comment: "")
        }

        let knownResources: [AutomationResource] = [.foregroundInput, .screenCapture, .accessibility, .network]
        return knownResources
            .filter { requirement.resources.contains($0) }
            .map(resourceLabel(for:))
            .joined(separator: ", ")
    }

    private static func resourceLabel(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            NSLocalizedString("Needs mouse and keyboard", comment: "")
        case .screenCapture:
            NSLocalizedString("Screen capture", comment: "")
        case .accessibility:
            NSLocalizedString("Accessibility", comment: "")
        case .network:
            NSLocalizedString("Network", comment: "")
        }
    }

    private static func permissionLabel(for permission: AutomationPermission) -> String {
        switch permission {
        case .accessibility:
            NSLocalizedString("Accessibility", comment: "")
        case .inputMonitoring:
            NSLocalizedString("Input Monitoring", comment: "")
        case .screenRecording:
            NSLocalizedString("Screen Recording", comment: "")
        case .automation:
            NSLocalizedString("Automation", comment: "")
        case .postEvents:
            NSLocalizedString("Post Events", comment: "")
        }
    }
}
