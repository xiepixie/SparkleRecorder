import Foundation

public enum AutomationWorkflowDraftSimulationOutcome: String, Codable, Equatable, Sendable {
    case success
    case failure
    case timeout
    case cancelled
    case conditionMatched
    case conditionNotMatched
}

public struct AutomationWorkflowDraftSimulationScenario: Codable, Equatable, Sendable {
    public var taskKey: String
    public var outcome: AutomationWorkflowDraftSimulationOutcome

    public init(taskKey: String, outcome: AutomationWorkflowDraftSimulationOutcome) {
        self.taskKey = taskKey
        self.outcome = outcome
    }

    public init?(rawValue: String) {
        let pieces = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else {
            return nil
        }
        let outcome: AutomationWorkflowDraftSimulationOutcome
        switch pieces[0].trimmingCharacters(in: .whitespacesAndNewlines) {
        case "success":
            outcome = .success
        case "failure", "failed":
            outcome = .failure
        case "timeout", "timedOut":
            outcome = .timeout
        case "cancelled", "canceled":
            outcome = .cancelled
        case "conditionMatched", "matched":
            outcome = .conditionMatched
        case "conditionNotMatched", "notMatched":
            outcome = .conditionNotMatched
        default:
            return nil
        }
        self.init(
            taskKey: pieces[1].trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: outcome
        )
    }
}

public struct AutomationWorkflowDraftSimulationOptions: Equatable, Sendable {
    public var startAt: Date
    public var scenario: AutomationWorkflowDraftSimulationScenario?

    public init(
        startAt: Date = Date(timeIntervalSince1970: 0),
        scenario: AutomationWorkflowDraftSimulationScenario? = nil
    ) {
        self.startAt = startAt
        self.scenario = scenario
    }
}

public struct AutomationWorkflowDraftSimulationResult: Codable, Equatable, Sendable {
    public var isSimulatable: Bool
    public var workflowName: String
    public var scenario: AutomationWorkflowDraftSimulationScenario?
    public var startAt: Date
    public var steps: [AutomationWorkflowDraftSimulationStep]
    public var resourceTimeline: [AutomationWorkflowDraftResourceOccupancy]
    public var branchDecisions: [AutomationWorkflowDraftBranchDecision]
    public var validationIssues: [AutomationWorkflowDraftIssue]
    public var skippedTaskKeys: [String]

    public init(
        isSimulatable: Bool,
        workflowName: String,
        scenario: AutomationWorkflowDraftSimulationScenario?,
        startAt: Date,
        steps: [AutomationWorkflowDraftSimulationStep],
        resourceTimeline: [AutomationWorkflowDraftResourceOccupancy],
        branchDecisions: [AutomationWorkflowDraftBranchDecision],
        validationIssues: [AutomationWorkflowDraftIssue],
        skippedTaskKeys: [String]
    ) {
        self.isSimulatable = isSimulatable
        self.workflowName = workflowName
        self.scenario = scenario
        self.startAt = startAt
        self.steps = steps
        self.resourceTimeline = resourceTimeline
        self.branchDecisions = branchDecisions
        self.validationIssues = validationIssues
        self.skippedTaskKeys = skippedTaskKeys
    }
}

public struct AutomationWorkflowDraftSimulationStep: Codable, Equatable, Sendable {
    public var order: Int
    public var taskKey: String
    public var taskName: String
    public var taskType: String
    public var plannedStartAt: Date
    public var plannedEndAt: Date
    public var durationSeconds: TimeInterval
    public var outcome: AutomationWorkflowDraftSimulationOutcome
    public var resource: AutomationWorkflowDraftResource
    public var upstreamTaskKeys: [String]
    public var triggeredByDependencyKeys: [String]

    public init(
        order: Int,
        taskKey: String,
        taskName: String,
        taskType: String,
        plannedStartAt: Date,
        plannedEndAt: Date,
        durationSeconds: TimeInterval,
        outcome: AutomationWorkflowDraftSimulationOutcome,
        resource: AutomationWorkflowDraftResource,
        upstreamTaskKeys: [String],
        triggeredByDependencyKeys: [String]
    ) {
        self.order = order
        self.taskKey = taskKey
        self.taskName = taskName
        self.taskType = taskType
        self.plannedStartAt = plannedStartAt
        self.plannedEndAt = plannedEndAt
        self.durationSeconds = max(0, durationSeconds)
        self.outcome = outcome
        self.resource = resource
        self.upstreamTaskKeys = upstreamTaskKeys
        self.triggeredByDependencyKeys = triggeredByDependencyKeys
    }
}

public struct AutomationWorkflowDraftResourceOccupancy: Codable, Equatable, Sendable {
    public var resource: AutomationWorkflowDraftResource
    public var taskKey: String
    public var startAt: Date
    public var endAt: Date
    public var durationSeconds: TimeInterval

    public init(
        resource: AutomationWorkflowDraftResource,
        taskKey: String,
        startAt: Date,
        endAt: Date,
        durationSeconds: TimeInterval
    ) {
        self.resource = resource
        self.taskKey = taskKey
        self.startAt = startAt
        self.endAt = endAt
        self.durationSeconds = max(0, durationSeconds)
    }
}

public struct AutomationWorkflowDraftBranchDecision: Codable, Equatable, Sendable {
    public var dependencyKey: String
    public var from: String
    public var to: String
    public var trigger: String
    public var sourceOutcome: AutomationWorkflowDraftSimulationOutcome
    public var fired: Bool
    public var reason: String

    public init(
        dependencyKey: String,
        from: String,
        to: String,
        trigger: String,
        sourceOutcome: AutomationWorkflowDraftSimulationOutcome,
        fired: Bool,
        reason: String
    ) {
        self.dependencyKey = dependencyKey
        self.from = from
        self.to = to
        self.trigger = trigger
        self.sourceOutcome = sourceOutcome
        self.fired = fired
        self.reason = reason
    }
}

public enum AutomationWorkflowDraftSimulator {
    public static func simulate(
        _ document: AutomationWorkflowDraftDocument,
        context: AutomationWorkflowDraftValidationContext = AutomationWorkflowDraftValidationContext(),
        options: AutomationWorkflowDraftSimulationOptions = AutomationWorkflowDraftSimulationOptions()
    ) -> AutomationWorkflowDraftSimulationResult {
        let validation = AutomationWorkflowDraftValidator.validate(document, context: context)
        guard validation.isValid else {
            return AutomationWorkflowDraftSimulationResult(
                isSimulatable: false,
                workflowName: document.workflow.name,
                scenario: options.scenario,
                startAt: options.startAt,
                steps: [],
                resourceTimeline: [],
                branchDecisions: [],
                validationIssues: validation.issues,
                skippedTaskKeys: document.workflow.tasks.map { $0.key }
            )
        }

        let expandedDocument = AutomationWorkflowDraftLoopExpander.expandedDocument(document)
        var engine = DraftSimulationEngine(
            document: expandedDocument,
            context: context,
            options: options,
            validationIssues: validation.issues
        )
        return engine.run()
    }
}

private struct DraftSimulationEngine {
    struct Completion {
        var step: AutomationWorkflowDraftSimulationStep
        var completedAt: Date
    }

    struct PendingStart {
        var startAt: Date
        var upstreamTaskKeys: [String]
        var dependencyKeys: [String]
    }

    var document: AutomationWorkflowDraftDocument
    var context: AutomationWorkflowDraftValidationContext
    var options: AutomationWorkflowDraftSimulationOptions
    var validationIssues: [AutomationWorkflowDraftIssue]

    private var tasksByKey: [String: AutomationWorkflowDraftTask] {
        Dictionary(uniqueKeysWithValues: document.workflow.tasks.map { ($0.key.trimmedForDraftSimulation, $0) })
    }

    mutating func run() -> AutomationWorkflowDraftSimulationResult {
        let tasks = document.workflow.tasks.filter { $0.enabled ?? true }
        let enabledKeys = Set(tasks.map { $0.key.trimmedForDraftSimulation })
        let dependencies = document.workflow.dependencies
            .filter { ($0.enabled ?? true) && enabledKeys.contains($0.from.trimmedForDraftSimulation) && enabledKeys.contains($0.to.trimmedForDraftSimulation) }
        let incoming = Dictionary(grouping: dependencies, by: { $0.to.trimmedForDraftSimulation })
        let outgoing = Dictionary(grouping: dependencies, by: { $0.from.trimmedForDraftSimulation })
        var pending: [String: PendingStart] = [:]
        var completions: [String: Completion] = [:]
        var steps: [AutomationWorkflowDraftSimulationStep] = []
        var decisions: [AutomationWorkflowDraftBranchDecision] = []

        for task in tasks where incoming[task.key.trimmedForDraftSimulation, default: []].isEmpty {
            pending[task.key.trimmedForDraftSimulation] = PendingStart(startAt: options.startAt, upstreamTaskKeys: [], dependencyKeys: [])
        }

        while let nextKey = nextPendingKey(pending, tasks: tasks) {
            guard let task = tasksByKey[nextKey], let start = pending.removeValue(forKey: nextKey) else {
                break
            }
            let outcome = outcome(for: task)
            let duration = duration(for: task, outcome: outcome)
            let plannedStart = start.startAt
            let plannedEnd = plannedStart.addingTimeInterval(duration)
            let step = AutomationWorkflowDraftSimulationStep(
                order: steps.count,
                taskKey: nextKey,
                taskName: task.name?.trimmedForDraftSimulation.nilIfEmptyForDraftSimulation ?? nextKey,
                taskType: task.type.trimmedForDraftSimulation,
                plannedStartAt: plannedStart,
                plannedEndAt: plannedEnd,
                durationSeconds: duration,
                outcome: outcome,
                resource: resource(for: task),
                upstreamTaskKeys: start.upstreamTaskKeys,
                triggeredByDependencyKeys: start.dependencyKeys
            )
            steps.append(step)
            completions[nextKey] = Completion(step: step, completedAt: plannedEnd)

            for dependency in outgoing[nextKey, default: []] {
                let dependencyKey = key(for: dependency)
                let fired = trigger(dependency.trigger, matches: outcome)
                decisions.append(AutomationWorkflowDraftBranchDecision(
                    dependencyKey: dependencyKey,
                    from: dependency.from.trimmedForDraftSimulation,
                    to: dependency.to.trimmedForDraftSimulation,
                    trigger: dependency.trigger.trimmedForDraftSimulation,
                    sourceOutcome: outcome,
                    fired: fired,
                    reason: fired ? "Trigger matched \(outcome.rawValue)." : "Trigger did not match \(outcome.rawValue)."
                ))
            }

            for target in targetKeysReadyAfterCompletion(
                dependencies: dependencies,
                incoming: incoming,
                completions: completions
            ) where completions[target] == nil {
                let resolution = dependencyResolution(for: target, incoming: incoming[target, default: []], completions: completions)
                if let resolution {
                    if let existing = pending[target] {
                        pending[target] = mergedPendingStart(existing, resolution, for: target)
                    } else {
                        pending[target] = resolution
                    }
                }
            }
        }

        let resourceTimeline = steps
            .filter { $0.resource != .none && $0.durationSeconds > 0 }
            .map {
                AutomationWorkflowDraftResourceOccupancy(
                    resource: $0.resource,
                    taskKey: $0.taskKey,
                    startAt: $0.plannedStartAt,
                    endAt: $0.plannedEndAt,
                    durationSeconds: $0.durationSeconds
                )
            }
        let completedKeys = Set(completions.keys)
        let skipped = tasks
            .map { $0.key.trimmedForDraftSimulation }
            .filter { !completedKeys.contains($0) }

        return AutomationWorkflowDraftSimulationResult(
            isSimulatable: true,
            workflowName: document.workflow.name,
            scenario: options.scenario,
            startAt: options.startAt,
            steps: steps,
            resourceTimeline: resourceTimeline,
            branchDecisions: decisions,
            validationIssues: validationIssues,
            skippedTaskKeys: skipped
        )
    }

    private func nextPendingKey(_ pending: [String: PendingStart], tasks: [AutomationWorkflowDraftTask]) -> String? {
        pending.keys.min { left, right in
            let leftStart = pending[left]?.startAt ?? .distantFuture
            let rightStart = pending[right]?.startAt ?? .distantFuture
            if leftStart != rightStart {
                return leftStart < rightStart
            }
            return taskOrder(left, tasks: tasks) < taskOrder(right, tasks: tasks)
        }
    }

    private func taskOrder(_ key: String, tasks: [AutomationWorkflowDraftTask]) -> Int {
        tasks.firstIndex { $0.key.trimmedForDraftSimulation == key } ?? Int.max
    }

    private func targetKeysReadyAfterCompletion(
        dependencies: [AutomationWorkflowDraftDependency],
        incoming: [String: [AutomationWorkflowDraftDependency]],
        completions: [String: Completion]
    ) -> [String] {
        Array(Set(dependencies.map { $0.to.trimmedForDraftSimulation }))
            .filter { dependencyResolution(for: $0, incoming: incoming[$0, default: []], completions: completions) != nil }
            .sorted()
    }

    private func dependencyResolution(
        for target: String,
        incoming: [AutomationWorkflowDraftDependency],
        completions: [String: Completion]
    ) -> PendingStart? {
        guard !incoming.isEmpty else {
            return PendingStart(startAt: options.startAt, upstreamTaskKeys: [], dependencyKeys: [])
        }

        switch joinPolicy(for: target) {
        case .all:
            return allDependencyResolution(incoming: incoming, completions: completions)
        case .any, .firstMatched:
            return singleDependencyResolution(incoming: incoming, completions: completions)
        }
    }

    private func allDependencyResolution(
        incoming: [AutomationWorkflowDraftDependency],
        completions: [String: Completion]
    ) -> PendingStart? {
        var startAt: Date?
        var upstream: [String] = []
        var dependencyKeys: [String] = []

        for dependency in incoming {
            let from = dependency.from.trimmedForDraftSimulation
            guard let completion = completions[from] else {
                return nil
            }
            guard trigger(dependency.trigger, matches: completion.step.outcome) else {
                return nil
            }
            let candidate = completion.completedAt.addingTimeInterval(max(0, dependency.delaySeconds ?? 0))
            startAt = max(startAt ?? candidate, candidate)
            upstream.append(from)
            dependencyKeys.append(key(for: dependency))
        }

        return PendingStart(
            startAt: startAt ?? options.startAt,
            upstreamTaskKeys: upstream,
            dependencyKeys: dependencyKeys
        )
    }

    private func singleDependencyResolution(
        incoming: [AutomationWorkflowDraftDependency],
        completions: [String: Completion]
    ) -> PendingStart? {
        let matches = incoming.compactMap { dependency -> PendingStart? in
            let from = dependency.from.trimmedForDraftSimulation
            guard let completion = completions[from],
                  trigger(dependency.trigger, matches: completion.step.outcome) else {
                return nil
            }
            return PendingStart(
                startAt: completion.completedAt.addingTimeInterval(max(0, dependency.delaySeconds ?? 0)),
                upstreamTaskKeys: [from],
                dependencyKeys: [key(for: dependency)]
            )
        }

        return matches.min { left, right in
            if left.startAt != right.startAt {
                return left.startAt < right.startAt
            }
            return (left.dependencyKeys.first ?? "") < (right.dependencyKeys.first ?? "")
        }
    }

    private func mergedPendingStart(
        _ existing: PendingStart,
        _ incoming: PendingStart,
        for target: String
    ) -> PendingStart {
        switch joinPolicy(for: target) {
        case .all:
            return PendingStart(
                startAt: max(existing.startAt, incoming.startAt),
                upstreamTaskKeys: incoming.upstreamTaskKeys,
                dependencyKeys: incoming.dependencyKeys
            )
        case .any, .firstMatched:
            return existing.startAt <= incoming.startAt ? existing : incoming
        }
    }

    private func joinPolicy(for taskKey: String) -> AutomationJoinPolicy {
        guard let task = tasksByKey[taskKey],
              let rawValue = task.joinPolicy?.trimmedForDraftSimulation,
              !rawValue.isEmpty else {
            return .all
        }
        return AutomationJoinPolicy(rawValue: rawValue) ?? .all
    }

    private func outcome(for task: AutomationWorkflowDraftTask) -> AutomationWorkflowDraftSimulationOutcome {
        let key = task.key.trimmedForDraftSimulation
        if options.scenario?.taskKey.trimmedForDraftSimulation == key,
           let scenarioOutcome = options.scenario?.outcome {
            return scenarioOutcome
        }

        switch task.type.trimmedForDraftSimulation {
        case "condition", "manualApproval":
            return .conditionMatched
        default:
            return .success
        }
    }

    private func duration(
        for task: AutomationWorkflowDraftTask,
        outcome: AutomationWorkflowDraftSimulationOutcome
    ) -> TimeInterval {
        if outcome == .timeout {
            return max(0, task.timeoutSeconds ?? estimatedDuration(for: task))
        }
        return estimatedDuration(for: task)
    }

    private func estimatedDuration(for task: AutomationWorkflowDraftTask) -> TimeInterval {
        switch task.type.trimmedForDraftSimulation {
        case "macro":
            return macroDuration(for: task)
        case "delay":
            return max(0, task.delaySeconds ?? 0)
        default:
            return 0
        }
    }

    private func macroDuration(for task: AutomationWorkflowDraftTask) -> TimeInterval {
        guard let macroRef = task.macroRef else {
            return 0
        }
        if let id = macroRef.id,
           let entry = context.macroCatalog.first(where: { $0.id == id }) {
            return entry.durationSeconds
        }
        if let name = macroRef.name?.trimmedForDraftSimulation, !name.isEmpty,
           let entry = context.macroCatalog.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return entry.durationSeconds
        }
        return 0
    }

    private func resource(for task: AutomationWorkflowDraftTask) -> AutomationWorkflowDraftResource {
        if let resource = task.resource {
            return resource
        }
        if task.type.trimmedForDraftSimulation != "macro" {
            return .none
        }
        if let id = task.macroRef?.id,
           let entry = context.macroCatalog.first(where: { $0.id == id }) {
            return entry.resourceRequirement
        }
        if let name = task.macroRef?.name?.trimmedForDraftSimulation,
           let entry = context.macroCatalog.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return entry.resourceRequirement
        }
        return .foregroundInput
    }

    private func trigger(
        _ trigger: String,
        matches outcome: AutomationWorkflowDraftSimulationOutcome
    ) -> Bool {
        switch trigger.trimmedForDraftSimulation {
        case "success":
            return outcome == .success
        case "failure":
            return outcome == .failure
        case "timeout":
            return outcome == .timeout
        case "cancelled":
            return outcome == .cancelled
        case "conditionMatched":
            return outcome == .conditionMatched
        case "conditionNotMatched":
            return outcome == .conditionNotMatched
        case "always":
            return true
        default:
            return false
        }
    }

    private func key(for dependency: AutomationWorkflowDraftDependency) -> String {
        dependency.key?.trimmedForDraftSimulation.nilIfEmptyForDraftSimulation ??
            "\(dependency.from.trimmedForDraftSimulation)->\(dependency.to.trimmedForDraftSimulation):\(dependency.trigger.trimmedForDraftSimulation)"
    }
}

private extension String {
    var trimmedForDraftSimulation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftSimulation: String? {
        isEmpty ? nil : self
    }
}
