import Foundation

public struct AutomationWorkflowDraftPreviewProjection: Codable, Equatable, Sendable {
    public var workflowName: String
    public var schema: String
    public var command: String
    public var isValid: Bool
    public var isReadyForImport: Bool
    public var taskRows: [TaskRow]
    public var dependencyRows: [DependencyRow]
    public var loopExpansionRows: [LoopExpansionRow]
    public var visualAssetRows: [VisualAssetRow]
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
        loopExpansionRows = document.workflow.tasks.compactMap(LoopExpansionRow.init(task:))
        visualAssetRows = Self.visualAssetRows(for: document)
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
        public var modeLabel: String
        public var detail: String
        public var macroResolution: MacroResolution

        public init(task: AutomationWorkflowDraftTask, macroResolution: MacroResolution) {
            key = task.key
            title = task.name?.nilIfBlankForDraftPreview ?? task.key
            typeLabel = Self.typeLabel(for: task)
            modeLabel = Self.modeLabel(for: task)
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
            case "loop":
                return NSLocalizedString("Loop", comment: "")
            default:
                return task.type
            }
        }

        private static func modeLabel(for task: AutomationWorkflowDraftTask) -> String {
            guard task.type == "loop" else {
                return typeLabel(for: task)
            }
            return task.loop?.isRepeatUntil == true
                ? NSLocalizedString("Repeat until", comment: "")
                : NSLocalizedString("Fixed count", comment: "")
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
            case "loop":
                if task.loop?.isRepeatUntil == true {
                    let bodyCount = task.loop?.tasks.count ?? 0
                    let until = conditionSummary(task.loop?.until)
                        ?? NSLocalizedString("condition missing", comment: "")
                    return String(
                        format: NSLocalizedString("Repeat until %@, %d steps", comment: ""),
                        until,
                        bodyCount
                    )
                }
                let count = task.loop?.count ?? 0
                let bodyCount = task.loop?.tasks.count ?? 0
                return String(
                    format: NSLocalizedString("Repeats %d times, %d steps", comment: ""),
                    count,
                    bodyCount
                )
            default:
                return task.type
            }
        }

        private static func conditionSummary(_ condition: AutomationWorkflowDraftCondition?) -> String? {
            LoopExpansionRow.conditionSummary(condition)
        }
    }

    public struct LoopExpansionRow: Codable, Equatable, Identifiable, Sendable {
        public var id: String { key }
        public var key: String
        public var title: String
        public var modeLabel: String
        public var repeatCount: Int
        public var bodyStepCount: Int
        public var expandedTaskCount: Int
        public var repeatMetricTitle: String
        public var expandedMetricTitle: String
        public var untilLabel: String?
        public var guardrailLabel: String?
        public var summary: String
        public var importBoundaryLabel: String
        public var capabilityLabel: String

        public init?(task: AutomationWorkflowDraftTask) {
            guard task.type == "loop" else {
                return nil
            }
            key = task.key
            title = task.name?.nilIfBlankForDraftPreview ?? task.key
            bodyStepCount = task.loop?.tasks.count ?? 0

            if task.loop?.isRepeatUntil == true {
                let loop = task.loop
                let attempts = loop?.maxAttempts ?? 0
                let approvalStepCount = loop?.onFailure?.nilIfBlankForDraftPreview ==
                    AutomationWorkflowDraftLoopFailurePolicy.requireManualApproval ? 1 : 0
                modeLabel = NSLocalizedString("Repeat until", comment: "")
                repeatCount = attempts
                expandedTaskCount = attempts > 0 ? attempts * (bodyStepCount + 1) + 1 + approvalStepCount : 0
                repeatMetricTitle = NSLocalizedString("max attempts", comment: "")
                expandedMetricTitle = NSLocalizedString("imported steps", comment: "")
                untilLabel = Self.conditionSummary(loop?.until)
                guardrailLabel = Self.guardrailSummary(for: loop)
                if attempts <= 0 {
                    summary = NSLocalizedString("Repeat-until needs max attempts before import", comment: "")
                } else if let untilLabel {
                    summary = String(
                        format: NSLocalizedString("Expands to up to %d imported steps; exits when %@ matches", comment: ""),
                        expandedTaskCount,
                        untilLabel
                    )
                } else {
                    summary = NSLocalizedString("Repeat-until needs an until condition before import", comment: "")
                }
                importBoundaryLabel = NSLocalizedString(
                    "Bounded repeat-until expands to an acyclic workflow at import",
                    comment: ""
                )
                capabilityLabel = NSLocalizedString(
                    "Runtime receives ordinary tasks; structured attempt evidence remains future work",
                    comment: ""
                )
            } else {
                modeLabel = NSLocalizedString("Fixed count", comment: "")
                repeatCount = task.loop?.count ?? 0
                expandedTaskCount = max(0, repeatCount) * bodyStepCount
                repeatMetricTitle = NSLocalizedString("repeats", comment: "")
                expandedMetricTitle = NSLocalizedString("imported steps", comment: "")
                untilLabel = nil
                guardrailLabel = nil
                if repeatCount > 0, bodyStepCount > 0 {
                    summary = String(
                        format: NSLocalizedString("Expands to %d imported steps", comment: ""),
                        expandedTaskCount
                    )
                } else {
                    summary = NSLocalizedString("Loop needs a repeat count and body tasks before import", comment: "")
                }
                importBoundaryLabel = NSLocalizedString("Draft-only loop; imported workflow stays acyclic", comment: "")
                capabilityLabel = NSLocalizedString("Repeat-until, foreach, and runtime loop evidence are not active yet", comment: "")
            }
        }

        fileprivate static func conditionSummary(_ condition: AutomationWorkflowDraftCondition?) -> String? {
            guard let condition else {
                return nil
            }
            switch condition.type {
            case "ocrText":
                if let text = condition.text?.nilIfBlankForDraftPreview {
                    return String(format: NSLocalizedString("text \"%@\"", comment: ""), text)
                }
                return NSLocalizedString("OCR text appears", comment: "")
            case "imageAppeared":
                return NSLocalizedString("image appears", comment: "")
            case "imageDisappeared":
                return NSLocalizedString("image disappears", comment: "")
            case "regionChanged":
                return NSLocalizedString("region changes", comment: "")
            case "pixelMatched":
                if let colorHex = condition.colorHex?.nilIfBlankForDraftPreview {
                    return String(format: NSLocalizedString("pixel matches %@", comment: ""), colorHex)
                }
                return NSLocalizedString("pixel matches", comment: "")
            default:
                return condition.type.nilIfBlankForDraftPreview
            }
        }

        private static func guardrailSummary(for loop: AutomationWorkflowDraftLoop?) -> String? {
            guard let loop else {
                return nil
            }
            var parts: [String] = []
            if let maxAttempts = loop.maxAttempts {
                parts.append(String(format: NSLocalizedString("max %d attempts", comment: ""), maxAttempts))
            }
            if let timeout = loop.timeoutSeconds {
                parts.append(String(format: NSLocalizedString("%.1fs timeout", comment: ""), timeout))
            }
            if let polling = loop.pollingSeconds {
                parts.append(String(format: NSLocalizedString("%.1fs polling", comment: ""), polling))
            }
            if let onFailure = loop.onFailure?.nilIfBlankForDraftPreview {
                parts.append(String(format: NSLocalizedString("on failure: %@", comment: ""), onFailure))
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
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

    public struct VisualAssetRow: Codable, Equatable, Identifiable, Sendable {
        public enum AssetKind: String, Codable, Equatable, Sendable {
            case imageTemplate
            case baseline
            case pixelSample
        }

        public var id: String
        public var taskKey: String
        public var roleLabel: String
        public var conditionType: String
        public var conditionLabel: String
        public var assetKind: AssetKind
        public var assetKindLabel: String
        public var assetKey: String?
        public var assetPath: String?
        public var sha256: String?
        public var sourceFrameID: UUID?
        public var sourceFrameShortID: String?
        public var sourceSurfaceID: String?
        public var sourceArtifactPath: String?
        public var sourceBounds: RectValue?
        public var sourceBoundsLabel: String?
        public var sourceBoundsSpace: AutomationOCRSearchRegionSpace?
        public var sourceBoundsSpaceLabel: String?
        public var regionKey: String?
        public var regionLabel: String?
        public var regionBounds: RectValue?
        public var regionBoundsLabel: String?
        public var regionSpace: AutomationOCRSearchRegionSpace?
        public var regionSpaceLabel: String?
        public var threshold: Double?
        public var thresholdLabel: String

        fileprivate init?(
            reference: VisualConditionReference,
            assets: AutomationWorkflowDraftVisualAssets?
        ) {
            let condition = reference.condition
            let kind: AssetKind
            let referencedAssetKey: String?
            let asset: AutomationWorkflowDraftVisualImageAsset?

            switch condition.type {
            case "imageAppeared", "imageDisappeared":
                kind = .imageTemplate
                referencedAssetKey = condition.imageRef?.nilIfBlankForDraftPreview
                asset = assets?.image(for: referencedAssetKey)
            case "regionChanged":
                kind = .baseline
                referencedAssetKey = condition.baselineRef?.nilIfBlankForDraftPreview
                asset = assets?.baseline(for: referencedAssetKey)
            case "pixelMatched":
                kind = .pixelSample
                referencedAssetKey = nil
                asset = nil
            default:
                return nil
            }

            let region = assets?.region(for: condition.regionRef)
            let normalizedAssetKey = asset?.key.nilIfBlankForDraftPreview ?? referencedAssetKey

            id = [
                reference.taskKey,
                reference.roleLabel,
                condition.type,
                normalizedAssetKey ?? condition.regionRef ?? "visual"
            ].joined(separator: ":")
            taskKey = reference.taskKey
            roleLabel = reference.roleLabel
            conditionType = condition.type
            conditionLabel = LoopExpansionRow.conditionSummary(condition) ?? condition.type
            assetKind = kind
            assetKindLabel = Self.assetKindLabel(for: kind)
            assetKey = normalizedAssetKey
            assetPath = asset?.path
            sha256 = asset?.sha256
            sourceFrameID = asset?.sourceFrameID
            sourceFrameShortID = asset?.sourceFrameID.map { String($0.uuidString.prefix(8)) }
            sourceSurfaceID = asset?.sourceSurfaceID
            sourceArtifactPath = asset?.sourceArtifactPath
            sourceBounds = asset?.sourceBounds
            sourceBoundsLabel = asset?.sourceBounds.map(Self.boundsLabel(for:))
            sourceBoundsSpace = asset?.sourceBoundsSpace
            sourceBoundsSpaceLabel = asset?.sourceBoundsSpace.map(Self.spaceLabel(for:))
            regionKey = region?.key ?? condition.regionRef?.nilIfBlankForDraftPreview
            regionLabel = region?.label
            regionBounds = region?.bounds
            if let bounds = region?.bounds {
                regionBoundsLabel = Self.boundsLabel(for: bounds)
            } else {
                regionBoundsLabel = nil
            }
            regionSpace = region?.space
            if let space = region?.space {
                regionSpaceLabel = Self.spaceLabel(for: space)
            } else {
                regionSpaceLabel = nil
            }
            threshold = condition.threshold
            thresholdLabel = condition.threshold.map {
                String(format: NSLocalizedString("%.2f threshold", comment: ""), $0)
            } ?? NSLocalizedString("Default threshold", comment: "")
        }

        private static func assetKindLabel(for kind: AssetKind) -> String {
            switch kind {
            case .imageTemplate:
                return NSLocalizedString("Image template", comment: "")
            case .baseline:
                return NSLocalizedString("Baseline", comment: "")
            case .pixelSample:
                return NSLocalizedString("Pixel sample", comment: "")
            }
        }

        private static func boundsLabel(for bounds: RectValue) -> String {
            String(
                format: NSLocalizedString("x %.1f, y %.1f, w %.1f, h %.1f", comment: ""),
                bounds.x,
                bounds.y,
                bounds.width,
                bounds.height
            )
        }

        private static func spaceLabel(for space: AutomationOCRSearchRegionSpace) -> String {
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

    fileprivate struct VisualConditionReference {
        var taskKey: String
        var roleLabel: String
        var condition: AutomationWorkflowDraftCondition
    }

    private static func visualAssetRows(for document: AutomationWorkflowDraftDocument) -> [VisualAssetRow] {
        visualConditionReferences(in: document.workflow.tasks).compactMap { reference in
            VisualAssetRow(reference: reference, assets: document.visualAssets)
        }
    }

    private static func visualConditionReferences(
        in tasks: [AutomationWorkflowDraftTask],
        parentKey: String? = nil
    ) -> [VisualConditionReference] {
        tasks.flatMap { task -> [VisualConditionReference] in
            let taskKey = parentKey.map { "\($0)/\(task.key)" } ?? task.key
            var references: [VisualConditionReference] = []

            if let condition = task.condition {
                references.append(VisualConditionReference(
                    taskKey: taskKey,
                    roleLabel: NSLocalizedString("Task condition", comment: ""),
                    condition: condition
                ))
            }

            if let until = task.loop?.until {
                references.append(VisualConditionReference(
                    taskKey: taskKey,
                    roleLabel: NSLocalizedString("Loop until", comment: ""),
                    condition: until
                ))
            }

            if let loop = task.loop {
                references += visualConditionReferences(in: loop.tasks, parentKey: taskKey)
            }

            return references
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
