import Foundation

public enum AutomationViewProjection {
    private struct RunTaskInfo {
        var taskID: UUID
        var title: String
    }

    public static func overview(from state: AutomationRunState) -> AutomationOverviewProjection {
        let generatedAt = state.now ?? Date.now
        let taskInfoByRunID = taskInfoByRunID(from: state)
        let workflows = state.workflows.map { workflow in
            workflowProjection(
                for: workflow,
                runs: state.runs,
                leases: state.leases,
                taskInfoByRunID: taskInfoByRunID,
                generatedAt: generatedAt
            )
        }
        let timelineItems = state.runs.compactMap { run in
            timelineItem(
                for: run,
                state: state,
                taskInfoByRunID: taskInfoByRunID,
                generatedAt: generatedAt
            )
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

    private static let nodeSize = AutomationGraphSize(width: 204, height: 124)
    private static let horizontalSpacing = 120.0
    private static let verticalSpacing = 48.0
    private static let graphInset = 32.0

    private static func workflowProjection(
        for workflow: AutomationWorkflow,
        runs: [AutomationTaskRun],
        leases: [AutomationResourceLease],
        taskInfoByRunID: [UUID: RunTaskInfo],
        generatedAt: Date
    ) -> AutomationWorkflowProjection {
        let levels = levelsByTaskID(for: workflow)
        let positions = positionsByTaskID(for: workflow, levels: levels)
        let incomingDependencyCounts = incomingDependencyCountsByTaskID(for: workflow)
        let nodes = workflow.tasks.map { task in
            nodeProjection(
                for: task,
                workflowID: workflow.id,
                run: latestRun(for: task, workflowID: workflow.id, runs: runs),
                runs: runs.filter { $0.workflowID == workflow.id && $0.taskID == task.id },
                leases: leases,
                taskInfoByRunID: taskInfoByRunID,
                generatedAt: generatedAt,
                incomingDependencyCount: incomingDependencyCounts[task.id, default: 0],
                position: positions[task.id] ?? AutomationGraphPoint(x: graphInset, y: graphInset)
            )
        }
        let nextScheduledNode = nodes
            .compactMap { node -> (taskID: UUID, scheduledAt: Date)? in
                guard let scheduledAt = node.nextScheduledOccurrence else {
                    return nil
                }
                return (node.taskID, scheduledAt)
            }
            .min { left, right in
                left.scheduledAt < right.scheduledAt
            }
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.taskID, $0) })
        let edges = workflow.dependencies.compactMap { dependency in
            edgeProjection(for: dependency, workflowID: workflow.id, nodeByID: nodeByID, runs: runs)
        }

        return AutomationWorkflowProjection(
            id: workflow.id,
            name: workflow.name,
            status: workflowStatus(for: nodes),
            statusDetail: workflowStatusDetail(for: nodes),
            nextScheduledOccurrence: nextScheduledNode?.scheduledAt,
            nextScheduledTaskID: nextScheduledNode?.taskID,
            nodes: nodes,
            edges: edges,
            graphSize: graphSize(for: positions),
            nodeSize: nodeSize
        )
    }

    private static func taskInfoByRunID(from state: AutomationRunState) -> [UUID: RunTaskInfo] {
        var taskByWorkflowAndTaskID: [String: AutomationTask] = [:]
        for workflow in state.workflows {
            for task in workflow.tasks {
                taskByWorkflowAndTaskID[taskLookupKey(workflowID: workflow.id, taskID: task.id)] = task
            }
        }

        return Dictionary(uniqueKeysWithValues: state.runs.compactMap { run in
            guard let task = taskByWorkflowAndTaskID[taskLookupKey(
                workflowID: run.workflowID,
                taskID: run.taskID
            )] else {
                return nil
            }
            return (run.id, RunTaskInfo(taskID: task.id, title: task.name))
        })
    }

    private static func taskLookupKey(workflowID: UUID, taskID: UUID) -> String {
        "\(workflowID.uuidString):\(taskID.uuidString)"
    }

    private static func nodeProjection(
        for task: AutomationTask,
        workflowID: UUID,
        run: AutomationTaskRun?,
        runs: [AutomationTaskRun],
        leases: [AutomationResourceLease],
        taskInfoByRunID: [UUID: RunTaskInfo],
        generatedAt: Date,
        incomingDependencyCount: Int,
        position: AutomationGraphPoint
    ) -> AutomationTaskNodeProjection {
        AutomationTaskNodeProjection(
            workflowID: workflowID,
            taskID: task.id,
            runID: run?.id,
            title: task.name,
            kindLabel: kindLabel(for: task.kind),
            scheduleLabel: scheduleLabel(for: task.schedule),
            nextScheduledOccurrence: nextScheduledOccurrence(
                for: task,
                runs: runs,
                generatedAt: generatedAt
            ),
            resourceLabel: resourceLabel(for: task.resourceRequirement),
            incomingDependencyCount: incomingDependencyCount,
            joinPolicy: task.joinPolicy,
            joinPolicyLabel: joinPolicyLabel(for: task.joinPolicy),
            status: displayStatus(for: task, run: run),
            statusDetail: statusDetail(for: task, run: run),
            resourceWaiting: resourceWaitingProjection(
                for: task,
                run: run,
                leases: leases,
                taskInfoByRunID: taskInfoByRunID,
                generatedAt: generatedAt
            ),
            timeoutCountdown: timeoutCountdown(for: task, run: run, generatedAt: generatedAt),
            retryAttemptSummary: retryAttemptSummary(for: task, run: run, generatedAt: generatedAt),
            conditionProgress: conditionProgress(for: task, run: run, generatedAt: generatedAt),
            hasEvidence: hasEvidence(run),
            position: position
        )
    }

    private static func nextScheduledOccurrence(
        for task: AutomationTask,
        runs: [AutomationTaskRun],
        generatedAt: Date
    ) -> Date? {
        guard let schedule = task.schedule, task.isEnabled else {
            return nil
        }
        let existingScheduledStarts = Set(runs.compactMap(\.scheduledStartTime))
        return schedule
            .nextOccurrence(
                onOrAfter: generatedAt,
                excludingScheduledStartTimes: existingScheduledStarts
            )?
            .scheduledAt
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
        let targetRun = sourceRun.flatMap { sourceRun in
            downstreamRun(
                for: dependency,
                sourceRun: sourceRun,
                workflowID: workflowID,
                runs: runs
            )
        }
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
            branchDecision: branchDecision(
                for: dependency,
                sourceRun: sourceRun,
                targetRun: targetRun
            ),
            start: start,
            end: end
        )
    }

    private static func downstreamRun(
        for dependency: AutomationDependency,
        sourceRun: AutomationTaskRun,
        workflowID: UUID,
        runs: [AutomationTaskRun]
    ) -> AutomationTaskRun? {
        runs
            .filter { run in
                run.workflowID == workflowID &&
                    run.taskID == dependency.toTaskID &&
                    run.executionID == sourceRun.executionID &&
                    run.upstreamRunIDs.contains(sourceRun.id)
            }
            .max { timelineSortDate($0) < timelineSortDate($1) }
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
        state: AutomationRunState,
        taskInfoByRunID: [UUID: RunTaskInfo],
        generatedAt: Date
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
            resourceWaiting: resourceWaitingProjection(
                for: task,
                run: run,
                leases: state.leases,
                taskInfoByRunID: taskInfoByRunID,
                generatedAt: generatedAt
            ),
            timeoutCountdown: timeoutCountdown(for: task, run: run, generatedAt: generatedAt),
            retryAttemptSummary: retryAttemptSummary(for: task, run: run, generatedAt: generatedAt),
            conditionProgress: conditionProgress(for: task, run: run, generatedAt: generatedAt),
            hasEvidence: hasEvidence(run)
        )
    }

    private static func hasEvidence(_ run: AutomationTaskRun?) -> Bool {
        guard let run else {
            return false
        }
        return run.evidenceID != nil ||
            run.conditionEvidence != nil ||
            !(run.branchEvidence ?? []).isEmpty
    }

    private static func timeoutCountdown(
        for task: AutomationTask,
        run: AutomationTaskRun?,
        generatedAt: Date
    ) -> AutomationTimeoutCountdownProjection? {
        guard
            let run,
            run.outcome == nil,
            run.status == .queued || run.status == .running,
            let startedAt = run.actualStartTime,
            let timeout = task.timeout,
            timeout > 0
        else {
            return nil
        }

        let deadline = startedAt.addingTimeInterval(timeout)
        let remaining = max(0, deadline.timeIntervalSince(generatedAt))
        let elapsed = max(0, generatedAt.timeIntervalSince(startedAt))
        let elapsedFraction = min(1, elapsed / timeout)
        return AutomationTimeoutCountdownProjection(
            startedAt: startedAt,
            deadline: deadline,
            timeout: timeout,
            remaining: remaining,
            elapsedFraction: elapsedFraction
        )
    }

    private static func retryAttemptSummary(
        for task: AutomationTask,
        run: AutomationTaskRun?,
        generatedAt: Date
    ) -> AutomationRetryAttemptSummary? {
        guard let run else {
            return nil
        }

        let maxAttempts = max(task.retryPolicy.maxAttempts, run.attempt)
        guard maxAttempts > 1 || run.attempt > 1 else {
            return nil
        }

        let currentAttempt = max(1, run.attempt)
        let remainingAttempts = max(0, maxAttempts - currentAttempt)
        let nextRetryAt: Date? = {
            guard
                run.outcome == nil,
                run.status == .planned,
                currentAttempt > 1,
                let dueAt = run.earliestStartTime ?? run.scheduledStartTime,
                dueAt > generatedAt
            else {
                return nil
            }
            return dueAt
        }()
        return AutomationRetryAttemptSummary(
            currentAttempt: currentAttempt,
            maxAttempts: maxAttempts,
            remainingAttempts: remainingAttempts,
            nextRetryAt: nextRetryAt,
            label: retryAttemptLabel(currentAttempt: currentAttempt, maxAttempts: maxAttempts)
        )
    }

    private static func retryAttemptLabel(
        currentAttempt: Int,
        maxAttempts: Int
    ) -> String {
        String(
            format: NSLocalizedString("Attempt %d of %d", comment: ""),
            currentAttempt,
            maxAttempts
        )
    }

    private static func resourceWaitingProjection(
        for task: AutomationTask,
        run: AutomationTaskRun?,
        leases: [AutomationResourceLease],
        taskInfoByRunID: [UUID: RunTaskInfo],
        generatedAt: Date
    ) -> AutomationResourceWaitingProjection? {
        guard
            let run,
            run.outcome == nil,
            run.status == .waitingForResource
        else {
            return nil
        }

        let resources = sortedResources(in: task.resourceRequirement)
        let waitingSince = resourceWaitingStart(for: run)
        let waitedDuration = max(0, generatedAt.timeIntervalSince(waitingSince))
        let maxWaitDuration = task.resourceRequirement.maxWaitDuration
        let deadline = maxWaitDuration.map {
            waitingSince.addingTimeInterval($0)
        }
        let remainingDuration = deadline.map {
            max(0, $0.timeIntervalSince(generatedAt))
        }
        let elapsedFraction = maxWaitDuration.map { duration -> Double in
            guard duration > 0 else {
                return 1
            }
            return min(max(waitedDuration / duration, 0), 1)
        }
        let blockers = resourceBlockers(
            for: task.resourceRequirement,
            waitingRunID: run.id,
            leases: leases,
            taskInfoByRunID: taskInfoByRunID
        )
        let detail = resourceWaitingDetail(
            for: task.resourceRequirement,
            blocker: blockers.first
        )

        return AutomationResourceWaitingProjection(
            detail: detail,
            resources: resources,
            resourceLabels: resources.map(resourceLabel(for:)),
            priority: task.resourceRequirement.priority,
            priorityLabel: resourcePriorityLabel(for: task.resourceRequirement.priority),
            waitingSince: waitingSince,
            waitedDuration: waitedDuration,
            maxWaitDuration: maxWaitDuration,
            deadline: deadline,
            remainingDuration: remainingDuration,
            elapsedFraction: elapsedFraction,
            blockers: blockers
        )
    }

    private static func resourceWaitingStart(for run: AutomationTaskRun) -> Date {
        run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    private static func resourceBlockers(
        for requirement: AutomationResourceRequirement,
        waitingRunID: UUID,
        leases: [AutomationResourceLease],
        taskInfoByRunID: [UUID: RunTaskInfo]
    ) -> [AutomationResourceBlockerProjection] {
        let requiredResources = Set(requirement.resources)
        guard !requiredResources.isEmpty else {
            return []
        }

        return leases
            .filter { lease in
                requiredResources.contains(lease.resource) && lease.runID != waitingRunID
            }
            .sorted { left, right in
                if resourceSortIndex(left.resource) != resourceSortIndex(right.resource) {
                    return resourceSortIndex(left.resource) < resourceSortIndex(right.resource)
                }
                if left.acquiredAt != right.acquiredAt {
                    return left.acquiredAt < right.acquiredAt
                }
                return left.id.uuidString < right.id.uuidString
            }
            .map { lease in
                let info = taskInfoByRunID[lease.runID]
                return AutomationResourceBlockerProjection(
                    resource: lease.resource,
                    resourceLabel: resourceLabel(for: lease.resource),
                    runID: lease.runID,
                    taskID: info?.taskID,
                    taskTitle: info?.title,
                    leaseExpiresAt: lease.expiresAt
                )
            }
    }

    private static func conditionProgress(
        for task: AutomationTask,
        run: AutomationTaskRun?,
        generatedAt: Date
    ) -> AutomationConditionProgressProjection? {
        guard case .condition(let spec) = task.kind else {
            return nil
        }

        let isActivelyPolling = run.map { run in
            run.outcome == nil && (run.status == .queued || run.status == .running)
        } ?? false
        let countdown = conditionTimeoutCountdown(for: spec, run: run, generatedAt: generatedAt)

        switch spec.kind {
        case .ocrText(let condition):
            return AutomationConditionProgressProjection(
                kind: .ocrText,
                kindLabel: NSLocalizedString("Screen text", comment: ""),
                targetLabel: condition.text,
                detail: ocrConditionDetail(for: condition),
                pollingInterval: spec.pollingInterval,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )

        case .visual(let condition):
            return visualConditionProgress(
                condition,
                spec: spec,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )

        case .previousOutcome(let predicate):
            let label = predicateLabel(for: predicate)
            return AutomationConditionProgressProjection(
                kind: .previousOutcome,
                kindLabel: NSLocalizedString("Previous outcome", comment: ""),
                targetLabel: label,
                detail: String(format: NSLocalizedString("Checks previous runs for %@", comment: ""), label),
                pollingInterval: spec.pollingInterval,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )

        case .externalSignal(let signalName):
            return AutomationConditionProgressProjection(
                kind: .externalSignal,
                kindLabel: NSLocalizedString("External signal", comment: ""),
                targetLabel: signalName,
                detail: String(format: NSLocalizedString("Waits for signal %@", comment: ""), signalName),
                pollingInterval: spec.pollingInterval,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )

        case .manualApproval:
            return AutomationConditionProgressProjection(
                kind: .manualApproval,
                kindLabel: NSLocalizedString("Manual approval", comment: ""),
                targetLabel: spec.name,
                detail: NSLocalizedString("Waits for user approval", comment: ""),
                pollingInterval: spec.pollingInterval,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )
        }
    }

    private static func conditionTimeoutCountdown(
        for spec: AutomationConditionSpec,
        run: AutomationTaskRun?,
        generatedAt: Date
    ) -> AutomationTimeoutCountdownProjection? {
        guard
            let run,
            run.outcome == nil,
            run.status == .queued || run.status == .running,
            let startedAt = run.actualStartTime,
            let timeout = spec.timeout,
            timeout > 0
        else {
            return nil
        }

        let deadline = startedAt.addingTimeInterval(timeout)
        let remaining = max(0, deadline.timeIntervalSince(generatedAt))
        let elapsed = max(0, generatedAt.timeIntervalSince(startedAt))
        return AutomationTimeoutCountdownProjection(
            startedAt: startedAt,
            deadline: deadline,
            timeout: timeout,
            remaining: remaining,
            elapsedFraction: min(1, elapsed / timeout)
        )
    }

    private static func visualConditionProgress(
        _ condition: AutomationVisualCondition,
        spec: AutomationConditionSpec,
        isActivelyPolling: Bool,
        timeoutCountdown: AutomationTimeoutCountdownProjection?
    ) -> AutomationConditionProgressProjection {
        AutomationConditionProgressProjection(
            kind: conditionProgressKind(for: condition.type),
            kindLabel: visualConditionKindLabel(for: condition.type),
            targetLabel: visualConditionTargetLabel(for: condition),
            detail: visualConditionDetail(for: condition),
            pollingInterval: spec.pollingInterval,
            isActivelyPolling: isActivelyPolling,
            timeoutCountdown: timeoutCountdown,
            regionRef: condition.regionRef,
            imageRef: condition.imageRef,
            baselineRef: condition.baselineRef,
            pixel: condition.pixel,
            colorHex: condition.targetColorHex,
            threshold: condition.threshold
        )
    }

    private static func conditionProgressKind(
        for type: AutomationVisualConditionType
    ) -> AutomationConditionProgressKind {
        switch type {
        case .regionChanged:
            return .regionChanged
        case .imageAppeared:
            return .imageAppeared
        case .imageDisappeared:
            return .imageDisappeared
        case .pixelMatched:
            return .pixelMatched
        }
    }

    private static func visualConditionKindLabel(
        for type: AutomationVisualConditionType
    ) -> String {
        switch type {
        case .regionChanged:
            return NSLocalizedString("Region changed", comment: "")
        case .imageAppeared:
            return NSLocalizedString("Image appeared", comment: "")
        case .imageDisappeared:
            return NSLocalizedString("Image disappeared", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Pixel matched", comment: "")
        }
    }

    private static func visualConditionTargetLabel(
        for condition: AutomationVisualCondition
    ) -> String {
        switch condition.type {
        case .regionChanged:
            return condition.regionRef ?? NSLocalizedString("Watched region", comment: "")
        case .imageAppeared, .imageDisappeared:
            return condition.imageRef ?? NSLocalizedString("Image reference", comment: "")
        case .pixelMatched:
            return condition.targetColorHex ?? condition.regionRef ?? NSLocalizedString("Target color", comment: "")
        }
    }

    private static func visualConditionDetail(
        for condition: AutomationVisualCondition
    ) -> String {
        var parts: [String] = []
        if let regionRef = condition.regionRef {
            parts.append(String(format: NSLocalizedString("Region %@", comment: ""), regionRef))
        }
        if let imageRef = condition.imageRef {
            parts.append(String(format: NSLocalizedString("Image %@", comment: ""), imageRef))
        }
        if let baselineRef = condition.baselineRef {
            parts.append(String(format: NSLocalizedString("Baseline %@", comment: ""), baselineRef))
        }
        if let colorHex = condition.targetColorHex {
            parts.append(String(format: NSLocalizedString("Color %@", comment: ""), colorHex))
        }
        if let threshold = condition.threshold {
            parts.append(String(format: NSLocalizedString("Threshold %.2f", comment: ""), threshold))
        }
        if let pixel = condition.pixel {
            parts.append(String(
                format: NSLocalizedString("Pixel %.0f, %.0f", comment: ""),
                pixel.x,
                pixel.y
            ))
        }
        return parts.isEmpty ? visualConditionKindLabel(for: condition.type) : parts.joined(separator: " | ")
    }

    private static func ocrConditionDetail(for condition: AutomationOCRCondition) -> String {
        let matchLabel = condition.matchMode == .exact
            ? NSLocalizedString("Exact match", comment: "")
            : NSLocalizedString("Contains text", comment: "")
        guard condition.searchRegion != nil else {
            return matchLabel
        }
        return String(
            format: NSLocalizedString("%@ in %@", comment: ""),
            matchLabel,
            searchRegionSpaceLabel(for: condition.searchRegionSpace)
        )
    }

    private static func searchRegionSpaceLabel(for space: AutomationOCRSearchRegionSpace) -> String {
        switch space {
        case .automatic:
            return NSLocalizedString("Automatic", comment: "")
        case .displayAbsolute:
            return NSLocalizedString("Display absolute", comment: "")
        case .displayNormalized:
            return NSLocalizedString("Display normalized", comment: "")
        case .windowLocal:
            return NSLocalizedString("Window local", comment: "")
        case .windowNormalized:
            return NSLocalizedString("Window normalized", comment: "")
        case .contentLocal:
            return NSLocalizedString("Content local", comment: "")
        case .contentNormalized:
            return NSLocalizedString("Content normalized", comment: "")
        }
    }

    private static func joinPolicyLabel(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return NSLocalizedString("All incoming branches", comment: "")
        case .any:
            return NSLocalizedString("Any incoming branch", comment: "")
        case .firstMatched:
            return NSLocalizedString("First matching branch", comment: "")
        }
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
            return .waiting
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

    private static func workflowStatus(for nodes: [AutomationTaskNodeProjection]) -> AutomationDisplayStatus {
        guard !nodes.isEmpty else {
            return .scheduled
        }

        let statuses = Set(nodes.map(\.status))
        if statuses.contains(.running) {
            return .running
        }
        if statuses.contains(.queued) {
            return .queued
        }
        if statuses.contains(.waiting) {
            return .waiting
        }
        if statuses.contains(.blocked) || statuses.contains(.failed) || statuses.contains(.timedOut) {
            return .blocked
        }
        if nodes.allSatisfy({ $0.status == .completed }) {
            return .completed
        }
        if statuses.contains(.cancelled) {
            return .cancelled
        }
        return .scheduled
    }

    private static func workflowStatusDetail(for nodes: [AutomationTaskNodeProjection]) -> String {
        guard !nodes.isEmpty else {
            return NSLocalizedString("No tasks in workflow", comment: "")
        }

        let runningCount = nodes.count { $0.status == .running }
        let queuedCount = nodes.count { $0.status == .queued }
        let waitingCount = nodes.count { $0.status == .waiting }
        let attentionCount = nodes.count { [.blocked, .failed, .timedOut].contains($0.status) }
        let completedCount = nodes.count { $0.status == .completed }
        let cancelledCount = nodes.count { $0.status == .cancelled }

        if runningCount > 0 {
            return String(
                format: NSLocalizedString("%d running, %d waiting", comment: ""),
                runningCount,
                waitingCount + queuedCount
            )
        }
        if queuedCount > 0 {
            return String(format: NSLocalizedString("%d queued to run", comment: ""), queuedCount)
        }
        if waitingCount > 0 {
            return String(format: NSLocalizedString("%d waiting for upstream tasks or resources", comment: ""), waitingCount)
        }
        if attentionCount > 0 {
            return String(format: NSLocalizedString("%d tasks need attention", comment: ""), attentionCount)
        }
        if completedCount == nodes.count {
            return NSLocalizedString("All tasks completed", comment: "")
        }
        if cancelledCount > 0 {
            return String(format: NSLocalizedString("%d tasks cancelled", comment: ""), cancelledCount)
        }
        return String(format: NSLocalizedString("%d tasks waiting for first run", comment: ""), nodes.count)
    }

    private static func statusDetail(
        for task: AutomationTask,
        run: AutomationTaskRun?
    ) -> String {
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
            return resourceWaitingDetail(for: task.resourceRequirement)
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

    private static func branchDecision(
        for dependency: AutomationDependency,
        sourceRun: AutomationTaskRun?,
        targetRun: AutomationTaskRun?
    ) -> AutomationBranchDecisionProjection? {
        guard let sourceRun else {
            return nil
        }

        if let evidence = sourceRun.branchEvidence?.first(where: { $0.dependencyID == dependency.id }) {
            return AutomationBranchDecisionProjection(
                sourceRunID: evidence.sourceRunID,
                targetRunID: evidence.targetRunID ?? targetRun?.id,
                executionID: evidence.executionID,
                decidedAt: evidence.decidedAt,
                status: evidence.status,
                outcomeLabel: outcomeLabel(for: evidence.sourceOutcome),
                detail: evidence.reason
            )
        }

        guard dependency.isEnabled else {
            return AutomationBranchDecisionProjection(
                sourceRunID: sourceRun.id,
                targetRunID: targetRun?.id,
                executionID: sourceRun.executionID,
                decidedAt: sourceRun.completedAt,
                status: .disabled,
                outcomeLabel: NSLocalizedString("Disabled", comment: ""),
                detail: NSLocalizedString("Branch disabled", comment: "")
            )
        }

        guard let outcome = sourceRun.outcome else {
            return AutomationBranchDecisionProjection(
                sourceRunID: sourceRun.id,
                targetRunID: targetRun?.id,
                executionID: sourceRun.executionID,
                status: .waiting,
                outcomeLabel: NSLocalizedString("Waiting for outcome", comment: ""),
                detail: NSLocalizedString("Waiting for upstream outcome", comment: "")
            )
        }

        let label = outcomeLabel(for: outcome)
        let decidedAt = sourceRun.completedAt ?? sourceRun.actualStartTime ?? sourceRun.createdAt
        if dependency.fires(for: outcome) {
            return AutomationBranchDecisionProjection(
                sourceRunID: sourceRun.id,
                targetRunID: targetRun?.id,
                executionID: sourceRun.executionID,
                decidedAt: decidedAt,
                status: .triggered,
                outcomeLabel: label,
                detail: String(format: NSLocalizedString("Triggered after %@", comment: ""), label)
            )
        }

        return AutomationBranchDecisionProjection(
            sourceRunID: sourceRun.id,
            targetRunID: targetRun?.id,
            executionID: sourceRun.executionID,
            decidedAt: decidedAt,
            status: .skipped,
            outcomeLabel: label,
            detail: String(format: NSLocalizedString("Skipped after %@", comment: ""), label)
        )
    }

    private static func outcomeLabel(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return NSLocalizedString("Success", comment: "")
        case .failed:
            return NSLocalizedString("Failure", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .timedOut:
            return NSLocalizedString("Timeout", comment: "")
        case .resourceConflict:
            return NSLocalizedString("Resource conflict", comment: "")
        case .permissionDenied:
            return NSLocalizedString("Permission denied", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .missingMacro:
            return NSLocalizedString("Missing macro", comment: "")
        case .rejected:
            return NSLocalizedString("Rejected", comment: "")
        }
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

    private static func incomingDependencyCountsByTaskID(
        for workflow: AutomationWorkflow
    ) -> [UUID: Int] {
        workflow.dependencies
            .filter(\.isEnabled)
            .reduce(into: [UUID: Int]()) { counts, dependency in
                counts[dependency.toTaskID, default: 0] += 1
            }
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

        return sortedResources(in: requirement)
            .map(resourceLabel(for:))
            .joined(separator: ", ")
    }

    private static func resourceWaitingDetail(
        for requirement: AutomationResourceRequirement,
        blocker: AutomationResourceBlockerProjection? = nil
    ) -> String {
        if let blocker, let taskTitle = blocker.taskTitle {
            return String(
                format: NSLocalizedString("Waiting for %@ held by %@", comment: ""),
                resourceWaitLabel(for: blocker.resource),
                taskTitle
            )
        }
        if let blocker {
            return String(
                format: NSLocalizedString("Waiting for %@", comment: ""),
                resourceWaitLabel(for: blocker.resource)
            )
        }
        if requirement.resources.contains(.foregroundInput) {
            return NSLocalizedString("Waiting for mouse and keyboard", comment: "")
        }
        guard !requirement.resources.isEmpty else {
            return NSLocalizedString("Waiting for a required resource", comment: "")
        }
        return String(
            format: NSLocalizedString("Waiting for %@", comment: ""),
            resourceLabel(for: requirement)
        )
    }

    private static func sortedResources(in requirement: AutomationResourceRequirement) -> [AutomationResource] {
        requirement.resources.sorted { left, right in
            resourceSortIndex(left) < resourceSortIndex(right)
        }
    }

    private static func resourceSortIndex(_ resource: AutomationResource) -> Int {
        switch resource {
        case .foregroundInput:
            return 0
        case .screenCapture:
            return 1
        case .accessibility:
            return 2
        case .network:
            return 3
        }
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

    private static func resourceWaitLabel(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            NSLocalizedString("mouse and keyboard", comment: "")
        case .screenCapture:
            NSLocalizedString("screen capture", comment: "")
        case .accessibility:
            NSLocalizedString("Accessibility", comment: "")
        case .network:
            NSLocalizedString("network", comment: "")
        }
    }

    private static func resourcePriorityLabel(for priority: AutomationResourcePriority) -> String {
        switch priority {
        case .low:
            NSLocalizedString("Low priority", comment: "")
        case .normal:
            NSLocalizedString("Normal priority", comment: "")
        case .high:
            NSLocalizedString("High priority", comment: "")
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
