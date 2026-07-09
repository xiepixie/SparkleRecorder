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
            delayLabel: delayLabel(for: dependency, sourceRun: sourceRun),
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
            resourceKeys: resourceKeys(for: task.resourceRequirement),
            kindLabel: kindLabel(for: task.kind),
            statusDetail: statusDetail(for: task, run: run),
            scheduledAt: run.scheduledStartTime,
            earliestStartAt: run.earliestStartTime,
            startedAt: run.actualStartTime,
            completedAt: run.completedAt,
            createdAt: run.createdAt,
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
            format: String(localized: "Attempt %d of %d", table: "Common"),
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
                kindLabel: String(localized: "Screen text", table: "Recording"),
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
                kindLabel: String(localized: "Previous outcome", table: "Common"),
                targetLabel: label,
                detail: String(format: String(localized: "Checks previous runs for %@", table: "Common"), label),
                pollingInterval: spec.pollingInterval,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )

        case .externalSignal(let signalName):
            return AutomationConditionProgressProjection(
                kind: .externalSignal,
                kindLabel: String(localized: "External signal", table: "Common"),
                targetLabel: signalName,
                detail: String(format: String(localized: "Waits for signal %@", table: "Common"), signalName),
                pollingInterval: spec.pollingInterval,
                isActivelyPolling: isActivelyPolling,
                timeoutCountdown: countdown
            )

        case .manualApproval:
            return AutomationConditionProgressProjection(
                kind: .manualApproval,
                kindLabel: String(localized: "Manual approval", table: "Common"),
                targetLabel: spec.name,
                detail: String(localized: "Waits for user approval", table: "Common"),
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
            pixelSampleRadius: condition.pixelSampleRadius,
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
            return String(localized: "Region changed", table: "EditorUX")
        case .imageAppeared:
            return String(localized: "Image appeared", table: "Common")
        case .imageDisappeared:
            return String(localized: "Image disappeared", table: "Common")
        case .pixelMatched:
            return String(localized: "Pixel matched", table: "Common")
        }
    }

    private static func visualConditionTargetLabel(
        for condition: AutomationVisualCondition
    ) -> String {
        switch condition.type {
        case .regionChanged:
            return condition.regionRef ?? String(localized: "Watched region", table: "Common")
        case .imageAppeared, .imageDisappeared:
            return condition.imageRef ?? String(localized: "Image reference", table: "Common")
        case .pixelMatched:
            return condition.targetColorHex ?? condition.regionRef ?? String(localized: "Target color", table: "Common")
        }
    }

    private static func visualConditionDetail(
        for condition: AutomationVisualCondition
    ) -> String {
        var parts: [String] = []
        if let regionRef = condition.regionRef {
            parts.append(String(format: String(localized: "Region %@", table: "Common"), regionRef))
        }
        if let imageRef = condition.imageRef {
            parts.append(String(format: String(localized: "Image %@", table: "Common"), imageRef))
        }
        if let baselineRef = condition.baselineRef {
            parts.append(String(format: String(localized: "Baseline %@", table: "Common"), baselineRef))
        }
        if let colorHex = condition.targetColorHex {
            parts.append(String(format: String(localized: "Color %@", table: "Common"), colorHex))
        }
        if let pixelSampleRadius = condition.pixelSampleRadius {
            parts.append(String(format: String(localized: "Sample radius %d", table: "Common"), pixelSampleRadius))
        }
        if let threshold = condition.threshold {
            parts.append(String(format: String(localized: "Threshold %.2f", table: "Common"), threshold))
        }
        if let pixel = condition.pixel {
            parts.append(String(
                format: String(localized: "Pixel %.0f, %.0f", table: "Common"),
                pixel.x,
                pixel.y
            ))
        }
        return parts.isEmpty ? visualConditionKindLabel(for: condition.type) : parts.joined(separator: " | ")
    }

    private static func ocrConditionDetail(for condition: AutomationOCRCondition) -> String {
        let matchLabel = condition.matchMode == .exact
            ? String(localized: "Exact match", table: "Common")
            : String(localized: "Contains text", table: "Common")
        guard condition.searchRegion != nil else {
            return matchLabel
        }
        return String(
            format: String(localized: "%@ in %@", table: "Common"),
            matchLabel,
            searchRegionSpaceLabel(for: condition.searchRegionSpace)
        )
    }

    private static func searchRegionSpaceLabel(for space: AutomationOCRSearchRegionSpace) -> String {
        switch space {
        case .automatic:
            return String(localized: "Automatic", table: "Common")
        case .displayAbsolute:
            return String(localized: "Display absolute", table: "Common")
        case .displayNormalized:
            return String(localized: "Display normalized", table: "Common")
        case .windowLocal:
            return String(localized: "Window local", table: "Common")
        case .windowNormalized:
            return String(localized: "Window normalized", table: "Common")
        case .contentLocal:
            return String(localized: "Content local", table: "Common")
        case .contentNormalized:
            return String(localized: "Content normalized", table: "Common")
        }
    }

    private static func joinPolicyLabel(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return String(localized: "All incoming branches", table: "Common")
        case .any:
            return String(localized: "Any incoming branch", table: "Common")
        case .firstMatched:
            return String(localized: "First matching branch", table: "Common")
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
            return String(localized: "No tasks in workflow", table: "Automation")
        }

        let runningCount = nodes.count { $0.status == .running }
        let queuedCount = nodes.count { $0.status == .queued }
        let waitingCount = nodes.count { $0.status == .waiting }
        let attentionCount = nodes.count { [.blocked, .failed, .timedOut].contains($0.status) }
        let completedCount = nodes.count { $0.status == .completed }
        let cancelledCount = nodes.count { $0.status == .cancelled }

        if runningCount > 0 {
            return String(
                format: String(localized: "%d running, %d waiting", table: "Automation"),
                runningCount,
                waitingCount + queuedCount
            )
        }
        if queuedCount > 0 {
            return String(format: String(localized: "%d queued to run", table: "Automation"), queuedCount)
        }
        if waitingCount > 0 {
            return String(format: String(localized: "%d waiting for upstream tasks or resources", table: "Automation"), waitingCount)
        }
        if attentionCount > 0 {
            return String(format: String(localized: "%d tasks need attention", table: "Automation"), attentionCount)
        }
        if completedCount == nodes.count {
            return String(localized: "All tasks completed", table: "Automation")
        }
        if cancelledCount > 0 {
            return String(format: String(localized: "%d tasks cancelled", table: "Automation"), cancelledCount)
        }
        return String(format: String(localized: "%d tasks waiting for first run", table: "Automation"), nodes.count)
    }

    private static func statusDetail(
        for task: AutomationTask,
        run: AutomationTaskRun?
    ) -> String {
        guard let run else {
            return String(localized: "No run has started yet", table: "Automation")
        }

        if let outcome = run.outcome {
            return outcomeDetail(for: outcome)
        }

        switch run.status {
        case .planned:
            return String(localized: "Waiting for its scheduled start", table: "EditorUX")
        case .waitingForDependencies:
            return String(localized: "Waiting for an upstream task", table: "Automation")
        case .waitingForResource:
            return resourceWaitingDetail(for: task.resourceRequirement)
        case .queued:
            return String(localized: "Queued to run", table: "Automation")
        case .running:
            return String(localized: "Running now", table: "Automation")
        case .completed:
            return String(localized: "Completed", table: "Common")
        }
    }

    private static func outcomeDetail(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return String(localized: "Completed successfully", table: "Common")
        case .failed(let report):
            return report?.errorMessage ?? String(localized: "Run failed", table: "Automation")
        case .cancelled(let reason):
            return reason ?? String(localized: "Cancelled", table: "Common")
        case .timedOut:
            return String(localized: "Timed out before completion", table: "Common")
        case .resourceConflict(let resource):
            return resource.map {
                String(format: String(localized: "Resource conflict: %@", table: "Common"), resourceLabel(for: $0))
            } ?? String(localized: "Resource conflict", table: "Common")
        case .permissionDenied(let permission, let message):
            return String(format: String(localized: "%@: %@", table: "Common"), permissionLabel(for: permission), message)
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition did not match", table: "Automation")
        case .missingMacro:
            return String(localized: "Macro is missing", table: "EditorUX")
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
                outcomeLabel: String(localized: "Disabled", table: "Common"),
                detail: String(localized: "Branch disabled", table: "Common")
            )
        }

        guard let outcome = sourceRun.outcome else {
            return AutomationBranchDecisionProjection(
                sourceRunID: sourceRun.id,
                targetRunID: targetRun?.id,
                executionID: sourceRun.executionID,
                status: .waiting,
                outcomeLabel: String(localized: "Waiting for outcome", table: "Common"),
                detail: String(localized: "Waiting for upstream outcome", table: "Common")
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
                detail: String(format: String(localized: "Triggered after %@", table: "Common"), label)
            )
        }

        return AutomationBranchDecisionProjection(
            sourceRunID: sourceRun.id,
            targetRunID: targetRun?.id,
            executionID: sourceRun.executionID,
            decidedAt: decidedAt,
            status: .skipped,
            outcomeLabel: label,
            detail: String(format: String(localized: "Skipped after %@", table: "Common"), label)
        )
    }

    private static func outcomeLabel(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return String(localized: "Success", table: "Common")
        case .failed:
            return String(localized: "Failure", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .timedOut:
            return String(localized: "Timeout", table: "Common")
        case .resourceConflict:
            return String(localized: "Resource conflict", table: "Common")
        case .permissionDenied:
            return String(localized: "Permission denied", table: "Settings")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .missingMacro:
            return String(localized: "Missing macro", table: "EditorUX")
        case .rejected:
            return String(localized: "Rejected", table: "Common")
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
            width: max(2000, maxX + nodeSize.width + graphInset * 8),
            height: max(2000, maxY + nodeSize.height + graphInset * 8)
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
            String(localized: "Macro", table: "EditorUX")
        case .condition:
            String(localized: "Condition", table: "Automation")
        case .delay:
            String(localized: "Delay", table: "EditorUX")
        case .notification:
            String(localized: "Notification", table: "Common")
        }
    }

    private static func scheduleLabel(for schedule: AutomationSchedule?) -> String {
        guard let schedule else {
            return String(localized: "Manual", table: "Common")
        }

        switch schedule {
        case .manual:
            return String(localized: "Manual", table: "Common")
        case .once:
            return String(localized: "Scheduled once", table: "Common")
        case .repeating:
            return String(localized: "Repeating", table: "Common")
        }
    }

    private static func triggerLabel(for trigger: AutomationDependencyTrigger) -> String {
        switch trigger {
        case .onSuccess:
            String(localized: "On success", table: "Common")
        case .onFailure:
            String(localized: "On failure", table: "Common")
        case .onTimeout:
            String(localized: "On timeout", table: "Common")
        case .onCancelled:
            String(localized: "On cancel", table: "Common")
        case .onConditionMatched:
            String(localized: "Condition matched", table: "Automation")
        case .onConditionNotMatched:
            String(localized: "Condition not matched", table: "Automation")
        case .onOutcome(let predicate):
            predicateLabel(for: predicate)
        case .always:
            String(localized: "Always", table: "Common")
        }
    }

    private static func predicateLabel(for predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .success:
            String(localized: "Success", table: "Common")
        case .failure:
            String(localized: "Failure", table: "Common")
        case .timeout:
            String(localized: "Timeout", table: "Common")
        case .cancelled:
            String(localized: "Cancelled", table: "Common")
        case .conditionMatched:
            String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            String(localized: "Condition not matched", table: "Automation")
        case .anyTerminal:
            String(localized: "Any terminal outcome", table: "Common")
        }
    }

    private static func delayLabel(for dependency: AutomationDependency, sourceRun: AutomationTaskRun?) -> String {
        guard dependency.dynamicDelay != nil else {
            return delayLabel(for: dependency.delay)
        }
        guard let sourceRun else {
            return String(localized: "Observed time", table: "Common")
        }

        let resolution = dependency.delayResolution(after: sourceRun)
        switch resolution.source {
        case .fixed:
            return delayLabel(for: resolution.delay)
        case .recognizedDuration:
            return String(
                format: String(localized: "Observed %@", table: "Common"),
                compactDelayLabel(for: resolution.delay)
            )
        case .fallback:
            return String(
                format: String(localized: "Fallback %@", table: "Common"),
                compactDelayLabel(for: resolution.delay)
            )
        }
    }

    private static func delayLabel(for delay: TimeInterval) -> String {
        guard delay > 0 else {
            return String(localized: "No delay", table: "EditorUX")
        }
        return String(format: String(localized: "%ds delay", table: "EditorUX"), Int(delay.rounded()))
    }

    private static func compactDelayLabel(for delay: TimeInterval) -> String {
        let totalSeconds = Int(max(0, delay).rounded())
        guard totalSeconds > 0 else {
            return String(localized: "no delay", table: "EditorUX")
        }
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0, parts.count < 2 {
            parts.append("\(minutes)m")
        }
        if seconds > 0, parts.isEmpty {
            parts.append("\(seconds)s")
        }
        return parts.prefix(2).joined(separator: " ")
    }

    private static func resourceLabel(for requirement: AutomationResourceRequirement) -> String {
        guard !requirement.resources.isEmpty else {
            return String(localized: "Background", table: "Common")
        }

        return sortedResources(in: requirement)
            .map(resourceLabel(for:))
            .joined(separator: ", ")
    }

    private static func resourceKeys(for requirement: AutomationResourceRequirement) -> [String] {
        sortedResources(in: requirement).map(\.rawValue)
    }

    private static func resourceWaitingDetail(
        for requirement: AutomationResourceRequirement,
        blocker: AutomationResourceBlockerProjection? = nil
    ) -> String {
        if let blocker, let taskTitle = blocker.taskTitle {
            return String(
                format: String(localized: "Waiting for %@ held by %@", table: "Common"),
                resourceWaitLabel(for: blocker.resource),
                taskTitle
            )
        }
        if let blocker {
            return String(
                format: String(localized: "Waiting for %@", table: "Common"),
                resourceWaitLabel(for: blocker.resource)
            )
        }
        if requirement.resources.contains(.foregroundInput) {
            return String(localized: "Waiting for mouse and keyboard", table: "Common")
        }
        guard !requirement.resources.isEmpty else {
            return String(localized: "Waiting for a required resource", table: "EditorUX")
        }
        return String(
            format: String(localized: "Waiting for %@", table: "Common"),
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
            String(localized: "Needs mouse and keyboard", table: "Common")
        case .screenCapture:
            String(localized: "Screen capture", table: "Recording")
        case .accessibility:
            String(localized: "Accessibility", table: "Settings")
        case .network:
            String(localized: "Network", table: "Common")
        }
    }

    private static func resourceWaitLabel(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            String(localized: "mouse and keyboard", table: "Common")
        case .screenCapture:
            String(localized: "screen capture", table: "Common")
        case .accessibility:
            String(localized: "Accessibility", table: "Settings")
        case .network:
            String(localized: "network", table: "Common")
        }
    }

    private static func resourcePriorityLabel(for priority: AutomationResourcePriority) -> String {
        switch priority {
        case .low:
            String(localized: "Low priority", table: "Common")
        case .normal:
            String(localized: "Normal priority", table: "Common")
        case .high:
            String(localized: "High priority", table: "Common")
        }
    }

    private static func permissionLabel(for permission: AutomationPermission) -> String {
        switch permission {
        case .accessibility:
            String(localized: "Accessibility", table: "Settings")
        case .inputMonitoring:
            String(localized: "Input Monitoring", table: "Common")
        case .screenRecording:
            String(localized: "Screen Recording", table: "Recording")
        case .automation:
            String(localized: "Automation", table: "Automation")
        case .postEvents:
            String(localized: "Post Events", table: "EditorUX")
        }
    }
}
