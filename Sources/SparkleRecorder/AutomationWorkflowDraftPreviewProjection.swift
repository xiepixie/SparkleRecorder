import Foundation

public struct AutomationWorkflowDraftPreviewProjection: Codable, Equatable, Sendable {
    public var workflowName: String
    public var schema: String
    public var command: String
    public var isValid: Bool
    public var isReadyForImport: Bool
    public var taskRows: [TaskRow]
    public var dependencyRows: [DependencyRow]
    public var simulationRows: [SimulationRow]
    public var branchRows: [BranchRow]
    public var resourceRows: [ResourceRow]
    public var importPreview: ImportPreview?
    public var issueRows: [IssueRow]
    public var nextActionRows: [NextActionRow]
    public var macroCatalogCount: Int

    public init(
        document: AutomationWorkflowDraftDocument,
        validationEnvelope: AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>,
        macroCatalogEnvelope: AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>,
        simulationEnvelope: AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>? = nil,
        importEnvelope: AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>? = nil
    ) {
        let catalog = macroCatalogEnvelope.data?.macros ?? []
        let simulation = simulationEnvelope?.data?.result
        workflowName = document.workflow.name
        schema = document.schema
        command = validationEnvelope.command
        isValid = validationEnvelope.ok
        isReadyForImport = importEnvelope?.ok ?? validationEnvelope.ok
        taskRows = document.workflow.tasks.map { task in
            TaskRow(task: task, macroResolution: Self.macroResolution(for: task, catalog: catalog))
        }
        dependencyRows = document.workflow.dependencies.map(DependencyRow.init(dependency:))
        simulationRows = simulation?.steps.map(SimulationRow.init(step:)) ?? []
        branchRows = simulation?.branchDecisions.map(BranchRow.init(decision:)) ?? []
        resourceRows = simulation?.resourceTimeline.map(ResourceRow.init(occupancy:)) ?? []
        importPreview = importEnvelope.flatMap { ImportPreview(envelope: $0) }
        issueRows = validationEnvelope.errors.map { IssueRow(message: $0, severity: .error) }
            + validationEnvelope.warnings.map { IssueRow(message: $0, severity: .warning) }
        nextActionRows = validationEnvelope.nextActions.map(NextActionRow.init(action:))
            + (simulationEnvelope?.nextActions.map(NextActionRow.init(action:)) ?? [])
            + (importEnvelope?.nextActions.map(NextActionRow.init(action:)) ?? [])
        macroCatalogCount = macroCatalogEnvelope.data?.count ?? catalog.count
    }

    public var statusLabel: String {
        if let importPreview {
            return importPreview.statusLabel
        }
        if !issueRows.contains(where: { $0.severity == .error }) {
            return issueRows.isEmpty
                ? NSLocalizedString("Ready to review", comment: "")
                : NSLocalizedString("Needs review", comment: "")
        }
        return NSLocalizedString("Blocked by validation", comment: "")
    }

    public struct ImportPreview: Codable, Equatable, Sendable {
        public var isImportable: Bool
        public var statusLabel: String
        public var workflowName: String?
        public var workflowID: UUID?
        public var taskCount: Int
        public var dependencyCount: Int
        public var macroResolutionRows: [ImportMacroResolutionRow]
        public var taskIDRows: [ImportIDRow]
        public var dependencyIDRows: [ImportIDRow]
        public var issueRows: [IssueRow]
        public var workflowIssueRows: [WorkflowIssueRow]

        public init?(envelope: AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>) {
            guard let result = envelope.data?.result else {
                return nil
            }

            isImportable = result.isImportable
            statusLabel = result.isImportable
                ? NSLocalizedString("Dry-run passed", comment: "")
                : NSLocalizedString("Import blocked", comment: "")
            workflowName = result.workflow?.name
            workflowID = result.workflow?.id
            taskCount = result.workflow?.tasks.count ?? result.taskKeyToID.count
            dependencyCount = result.workflow?.dependencies.count ?? result.dependencyKeyToID.count
            macroResolutionRows = result.macroResolutions.map(ImportMacroResolutionRow.init(resolution:))
            taskIDRows = result.taskKeyToID
                .sorted { $0.key < $1.key }
                .map { ImportIDRow(key: $0.key, id: $0.value) }
            dependencyIDRows = result.dependencyKeyToID
                .sorted { $0.key < $1.key }
                .map { ImportIDRow(key: $0.key, id: $0.value) }
            issueRows = envelope.errors.map { IssueRow(message: $0, severity: .error) }
                + envelope.warnings.map { IssueRow(message: $0, severity: .warning) }
            workflowIssueRows = result.workflowValidationIssues.map(WorkflowIssueRow.init(issue:))
        }
    }

    public struct ImportMacroResolutionRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { taskKey }
        public var taskKey: String
        public var macroName: String
        public var macroID: UUID?
        public var sourceLabel: String
        public var isResolved: Bool

        public init(resolution: AutomationWorkflowDraftMacroResolution) {
            taskKey = resolution.taskKey
            macroName = resolution.macroName?.nilIfBlankForDraftPreview
                ?? NSLocalizedString("Unnamed macro", comment: "")
            macroID = resolution.macroID
            sourceLabel = Self.sourceLabel(for: resolution.source)
            isResolved = resolution.macroID != nil && resolution.source != .unresolved
        }

        private static func sourceLabel(for source: AutomationWorkflowDraftMacroResolutionSource) -> String {
            switch source {
            case .id:
                return NSLocalizedString("Matched by ID", comment: "")
            case .catalogName:
                return NSLocalizedString("Matched by catalog name", comment: "")
            case .unresolved:
                return NSLocalizedString("Unresolved", comment: "")
            }
        }
    }

    public struct ImportIDRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { key }
        public var key: String
        public var uuid: UUID
        public var shortID: String

        public init(key: String, id: UUID) {
            self.key = key
            uuid = id
            shortID = String(id.uuidString.prefix(8))
        }
    }

    public struct WorkflowIssueRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { message }
        public var code: String
        public var message: String

        public init(issue: AutomationWorkflowValidationIssue) {
            switch issue {
            case .duplicateTaskID(let id):
                code = "duplicateTaskID"
                message = String(format: NSLocalizedString("Duplicate task ID %@", comment: ""), id.uuidString)
            case .duplicateDependencyID(let id):
                code = "duplicateDependencyID"
                message = String(format: NSLocalizedString("Duplicate dependency ID %@", comment: ""), id.uuidString)
            case .missingDependencySource(let dependencyID, let taskID):
                code = "missingDependencySource"
                message = String(
                    format: NSLocalizedString("Dependency %@ references missing source task %@", comment: ""),
                    dependencyID.uuidString,
                    taskID.uuidString
                )
            case .missingDependencyTarget(let dependencyID, let taskID):
                code = "missingDependencyTarget"
                message = String(
                    format: NSLocalizedString("Dependency %@ references missing target task %@", comment: ""),
                    dependencyID.uuidString,
                    taskID.uuidString
                )
            case .selfDependency(let dependencyID, let taskID):
                code = "selfDependency"
                message = String(
                    format: NSLocalizedString("Dependency %@ loops back to task %@", comment: ""),
                    dependencyID.uuidString,
                    taskID.uuidString
                )
            case .cycleDetected(let taskID):
                code = "cycleDetected"
                message = String(format: NSLocalizedString("Cycle detected at task %@", comment: ""), taskID.uuidString)
            }
        }
    }

    public var simulationLabel: String {
        if simulationRows.isEmpty {
            return NSLocalizedString("No simulated steps", comment: "")
        }
        return String(
            format: NSLocalizedString("%d simulated steps", comment: ""),
            simulationRows.count
        )
    }

    public struct TaskRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { key }
        public var key: String
        public var title: String
        public var typeLabel: String
        public var detail: String
        public var macroResolution: MacroResolution

        public init(task: AutomationWorkflowDraftTask, macroResolution: MacroResolution) {
            key = task.key
            title = task.name?.nilIfBlankForDraftPreview ?? task.key
            typeLabel = Self.typeLabel(for: task)
            detail = Self.detail(for: task)
            self.macroResolution = macroResolution
        }

        private static func typeLabel(for task: AutomationWorkflowDraftTask) -> String {
            switch task.type {
            case "macro":
                return NSLocalizedString("Macro", comment: "")
            case "condition":
                return NSLocalizedString("Condition", comment: "")
            case "delay":
                return NSLocalizedString("Delay", comment: "")
            case "notification":
                return NSLocalizedString("Notification", comment: "")
            case "manualApproval":
                return NSLocalizedString("Manual approval", comment: "")
            default:
                return task.type
            }
        }

        private static func detail(for task: AutomationWorkflowDraftTask) -> String {
            switch task.type {
            case "macro":
                return task.macroRef?.name?.nilIfBlankForDraftPreview
                    ?? task.macroRef?.id?.uuidString
                    ?? NSLocalizedString("No macro selected", comment: "")
            case "condition":
                return task.condition?.text?.nilIfBlankForDraftPreview
                    ?? task.condition?.type
                    ?? NSLocalizedString("Condition details missing", comment: "")
            case "delay":
                return task.delaySeconds.map {
                    String(format: NSLocalizedString("%.1fs delay", comment: ""), $0)
                } ?? NSLocalizedString("Delay missing", comment: "")
            case "notification":
                return task.notification?.title.nilIfBlankForDraftPreview
                    ?? NSLocalizedString("Notification title missing", comment: "")
            case "manualApproval":
                return NSLocalizedString("Manual approval required", comment: "")
            default:
                return task.type
            }
        }
    }

    public struct DependencyRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var from: String
        public var to: String
        public var triggerLabel: String
        public var delayLabel: String?

        public init(dependency: AutomationWorkflowDraftDependency) {
            from = dependency.from
            to = dependency.to
            triggerLabel = Self.triggerLabel(for: dependency.trigger)
            delayLabel = dependency.delaySeconds.map {
                String(format: NSLocalizedString("%.1fs delay", comment: ""), $0)
            }
            id = dependency.key ?? "\(dependency.from)->\(dependency.to):\(dependency.trigger)"
        }

        private static func triggerLabel(for trigger: String) -> String {
            switch trigger {
            case "success":
                return NSLocalizedString("Success", comment: "")
            case "failure":
                return NSLocalizedString("Failure", comment: "")
            case "timeout":
                return NSLocalizedString("Timeout", comment: "")
            case "cancelled":
                return NSLocalizedString("Cancelled", comment: "")
            case "conditionMatched":
                return NSLocalizedString("Condition matched", comment: "")
            case "conditionNotMatched":
                return NSLocalizedString("Condition not matched", comment: "")
            case "always":
                return NSLocalizedString("Always", comment: "")
            default:
                return trigger
            }
        }
    }

    public struct IssueRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var severity: Severity
        public var code: String
        public var message: String
        public var path: String?
        public var subject: String?
        public var candidateCount: Int

        public init(message: AutomationCLIMessage, severity: Severity) {
            self.severity = severity
            code = message.code
            self.message = message.message
            path = message.path
            subject = message.taskKey ?? message.dependencyKey
            candidateCount = message.candidates.count
            id = [
                severity.rawValue,
                message.code,
                message.path ?? "",
                message.taskKey ?? "",
                message.dependencyKey ?? ""
            ].joined(separator: ":")
        }
    }

    public struct SimulationRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { taskKey }
        public var order: Int
        public var taskKey: String
        public var taskName: String
        public var taskType: String
        public var plannedStartAt: Date
        public var plannedEndAt: Date
        public var durationSeconds: TimeInterval
        public var outcomeLabel: String
        public var resourceLabel: String

        public init(step: AutomationWorkflowDraftSimulationStep) {
            order = step.order
            taskKey = step.taskKey
            taskName = step.taskName
            taskType = step.taskType
            plannedStartAt = step.plannedStartAt
            plannedEndAt = step.plannedEndAt
            durationSeconds = step.durationSeconds
            outcomeLabel = Self.outcomeLabel(for: step.outcome)
            resourceLabel = Self.resourceLabel(for: step.resource)
        }
    }

    public struct BranchRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { dependencyKey }
        public var dependencyKey: String
        public var from: String
        public var to: String
        public var trigger: String
        public var sourceOutcome: String
        public var fired: Bool
        public var reason: String

        public init(decision: AutomationWorkflowDraftBranchDecision) {
            dependencyKey = decision.dependencyKey
            from = decision.from
            to = decision.to
            trigger = decision.trigger
            sourceOutcome = Self.outcomeLabel(for: decision.sourceOutcome)
            fired = decision.fired
            reason = decision.reason
        }
    }

    public struct ResourceRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { "\(resourceLabel):\(taskKey):\(startAt.timeIntervalSince1970)" }
        public var resourceLabel: String
        public var taskKey: String
        public var startAt: Date
        public var endAt: Date
        public var durationSeconds: TimeInterval

        public init(occupancy: AutomationWorkflowDraftResourceOccupancy) {
            resourceLabel = SimulationRow.resourceLabel(for: occupancy.resource)
            taskKey = occupancy.taskKey
            startAt = occupancy.startAt
            endAt = occupancy.endAt
            durationSeconds = occupancy.durationSeconds
        }
    }

    public enum Severity: String, Codable, Equatable, Sendable {
        case error
        case warning
    }

    public struct NextActionRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { command }
        public var command: String
        public var reason: String

        public init(action: AutomationCLINextAction) {
            command = action.command
            reason = action.reason
        }
    }

    public enum MacroResolution: Codable, Equatable, Sendable {
        case notRequired
        case resolved(name: String, id: UUID?)
        case missing(reference: String)
        case ambiguous(reference: String, candidateCount: Int)

        public var label: String {
            switch self {
            case .notRequired:
                return NSLocalizedString("No macro needed", comment: "")
            case .resolved:
                return NSLocalizedString("Macro resolved", comment: "")
            case .missing:
                return NSLocalizedString("Missing macro", comment: "")
            case .ambiguous:
                return NSLocalizedString("Choose macro", comment: "")
            }
        }
    }

    private static func macroResolution(
        for task: AutomationWorkflowDraftTask,
        catalog: [AutomationWorkflowDraftMacroCatalogEntry]
    ) -> MacroResolution {
        guard task.type == "macro" else {
            return .notRequired
        }
        guard let macroRef = task.macroRef, !macroRef.isEmpty else {
            return .missing(reference: NSLocalizedString("No macro selected", comment: ""))
        }

        if let id = macroRef.id {
            if let match = catalog.first(where: { $0.id == id }) {
                return .resolved(name: match.name, id: id)
            }
            return .missing(reference: id.uuidString)
        }

        guard let name = macroRef.name?.nilIfBlankForDraftPreview else {
            return .missing(reference: NSLocalizedString("No macro selected", comment: ""))
        }

        let matches = catalog.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        switch matches.count {
        case 0:
            return catalog.isEmpty ? .resolved(name: name, id: nil) : .missing(reference: name)
        case 1:
            return .resolved(name: matches[0].name, id: matches[0].id)
        default:
            return .ambiguous(reference: name, candidateCount: matches.count)
        }
    }
}

private extension AutomationWorkflowDraftPreviewProjection.SimulationRow {
    static func outcomeLabel(for outcome: AutomationWorkflowDraftSimulationOutcome) -> String {
        switch outcome {
        case .success:
            return NSLocalizedString("Success", comment: "")
        case .failure:
            return NSLocalizedString("Failure", comment: "")
        case .timeout:
            return NSLocalizedString("Timeout", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        }
    }

    static func resourceLabel(for resource: AutomationWorkflowDraftResource) -> String {
        switch resource {
        case .foregroundInput:
            return NSLocalizedString("Needs mouse and keyboard", comment: "")
        case .screenCapture:
            return NSLocalizedString("Screen capture", comment: "")
        case .accessibility:
            return NSLocalizedString("Accessibility", comment: "")
        case .network:
            return NSLocalizedString("Network", comment: "")
        case .none:
            return NSLocalizedString("None", comment: "")
        }
    }
}

private extension AutomationWorkflowDraftPreviewProjection.BranchRow {
    static func outcomeLabel(for outcome: AutomationWorkflowDraftSimulationOutcome) -> String {
        AutomationWorkflowDraftPreviewProjection.SimulationRow.outcomeLabel(for: outcome)
    }
}

private extension String {
    var nilIfBlankForDraftPreview: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
