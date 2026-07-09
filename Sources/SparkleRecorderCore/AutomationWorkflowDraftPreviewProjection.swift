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
                ? String(localized: "Ready to review", table: "Common")
                : String(localized: "Needs review", table: "Common")
        }
        return String(localized: "Blocked by validation", table: "Common")
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
                ? String(localized: "Dry-run passed", table: "Automation")
                : String(localized: "Import blocked", table: "Common")
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
                ?? String(localized: "Unnamed macro", table: "EditorUX")
            macroID = resolution.macroID
            sourceLabel = Self.sourceLabel(for: resolution.source)
            isResolved = resolution.macroID != nil && resolution.source != .unresolved
        }

        private static func sourceLabel(for source: AutomationWorkflowDraftMacroResolutionSource) -> String {
            switch source {
            case .id:
                return String(localized: "Matched by ID", table: "Common")
            case .catalogName:
                return String(localized: "Matched by catalog name", table: "Common")
            case .unresolved:
                return String(localized: "Unresolved", table: "Common")
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
                message = String(format: String(localized: "Duplicate task ID %@", table: "Automation"), id.uuidString)
            case .duplicateDependencyID(let id):
                code = "duplicateDependencyID"
                message = String(format: String(localized: "Duplicate dependency ID %@", table: "Automation"), id.uuidString)
            case .missingDependencySource(let dependencyID, let taskID):
                code = "missingDependencySource"
                message = String(
                    format: String(localized: "Dependency %@ references missing source task %@", table: "Automation"),
                    dependencyID.uuidString,
                    taskID.uuidString
                )
            case .missingDependencyTarget(let dependencyID, let taskID):
                code = "missingDependencyTarget"
                message = String(
                    format: String(localized: "Dependency %@ references missing target task %@", table: "Automation"),
                    dependencyID.uuidString,
                    taskID.uuidString
                )
            case .selfDependency(let dependencyID, let taskID):
                code = "selfDependency"
                message = String(
                    format: String(localized: "Dependency %@ loops back to task %@", table: "Automation"),
                    dependencyID.uuidString,
                    taskID.uuidString
                )
            case .cycleDetected(let taskID):
                code = "cycleDetected"
                message = String(format: String(localized: "Cycle detected at task %@", table: "Automation"), taskID.uuidString)
            }
        }
    }

    public var simulationLabel: String {
        if simulationRows.isEmpty {
            return String(localized: "No simulated steps", table: "Common")
        }
        return String(
            format: String(localized: "%d simulated steps", table: "Common"),
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
                return String(localized: "Macro", table: "EditorUX")
            case "condition":
                return String(localized: "Condition", table: "Automation")
            case "delay":
                return String(localized: "Delay", table: "EditorUX")
            case "notification":
                return String(localized: "Notification", table: "Common")
            case "manualApproval":
                return String(localized: "Manual approval", table: "Common")
            case "loop":
                return String(localized: "Loop", table: "Common")
            default:
                return task.type
            }
        }

        private static func modeLabel(for task: AutomationWorkflowDraftTask) -> String {
            guard task.type == "loop" else {
                return typeLabel(for: task)
            }
            return task.loop?.isRepeatUntil == true
                ? String(localized: "Repeat until", table: "Common")
                : String(localized: "Fixed count", table: "Common")
        }

        private static func detail(for task: AutomationWorkflowDraftTask) -> String {
            switch task.type {
            case "macro":
                return task.macroRef?.name?.nilIfBlankForDraftPreview
                    ?? task.macroRef?.id?.uuidString
                    ?? String(localized: "No macro selected", table: "EditorUX")
            case "condition":
                return task.condition?.text?.nilIfBlankForDraftPreview
                    ?? task.condition?.type
                    ?? String(localized: "Condition details missing", table: "Automation")
            case "delay":
                return task.delaySeconds.map {
                    String(format: String(localized: "%.1fs delay", table: "EditorUX"), $0)
                } ?? String(localized: "Delay missing", table: "EditorUX")
            case "notification":
                return task.notification?.title.nilIfBlankForDraftPreview
                    ?? String(localized: "Notification title missing", table: "Common")
            case "manualApproval":
                return String(localized: "Manual approval required", table: "Common")
            case "loop":
                if task.loop?.isRepeatUntil == true {
                    let bodyCount = task.loop?.tasks.count ?? 0
                    let until = conditionSummary(task.loop?.until)
                        ?? String(localized: "condition missing", table: "Common")
                    return String(
                        format: String(localized: "Repeat until %@, %d steps", table: "Common"),
                        until,
                        bodyCount
                    )
                }
                let count = task.loop?.count ?? 0
                let bodyCount = task.loop?.tasks.count ?? 0
                return String(
                    format: String(localized: "Repeats %d times, %d steps", table: "Common"),
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
                modeLabel = String(localized: "Repeat until", table: "Common")
                repeatCount = attempts
                expandedTaskCount = attempts > 0 ? attempts * (bodyStepCount + 1) + 1 + approvalStepCount : 0
                repeatMetricTitle = String(localized: "max attempts", table: "Common")
                expandedMetricTitle = String(localized: "imported steps", table: "Common")
                untilLabel = Self.conditionSummary(loop?.until)
                guardrailLabel = Self.guardrailSummary(for: loop)
                if attempts <= 0 {
                    summary = String(localized: "Repeat-until needs max attempts before import", table: "EditorUX")
                } else if let untilLabel {
                    summary = String(
                        format: String(localized: "Expands to up to %d imported steps; exits when %@ matches", table: "EditorUX"),
                        expandedTaskCount,
                        untilLabel
                    )
                } else {
                    summary = String(localized: "Repeat-until needs an until condition before import", table: "Automation")
                }
                importBoundaryLabel = String(localized: "Bounded repeat-until expands to an acyclic workflow at import", table: "Common")
                capabilityLabel = String(localized: "Runtime receives ordinary tasks; structured attempt evidence remains future work", table: "Common")
            } else {
                modeLabel = String(localized: "Fixed count", table: "Common")
                repeatCount = task.loop?.count ?? 0
                expandedTaskCount = max(0, repeatCount) * bodyStepCount
                repeatMetricTitle = String(localized: "repeats", table: "Common")
                expandedMetricTitle = String(localized: "imported steps", table: "Common")
                untilLabel = nil
                guardrailLabel = nil
                if repeatCount > 0, bodyStepCount > 0 {
                    summary = String(
                        format: String(localized: "Expands to %d imported steps", table: "Common"),
                        expandedTaskCount
                    )
                } else {
                    summary = String(localized: "Loop needs a repeat count and body tasks before import", table: "Automation")
                }
                importBoundaryLabel = String(localized: "Draft-only loop; imported workflow stays acyclic", table: "Automation")
                capabilityLabel = String(localized: "Repeat-until, foreach, and runtime loop evidence are not active yet", table: "Automation")
            }
        }

        fileprivate static func conditionSummary(_ condition: AutomationWorkflowDraftCondition?) -> String? {
            guard let condition else {
                return nil
            }
            switch condition.type {
            case "ocrText":
                if let text = condition.text?.nilIfBlankForDraftPreview {
                    return String(format: String(localized: "text \"%@\"", table: "Common"), text)
                }
                return String(localized: "OCR text appears", table: "Common")
            case "imageAppeared":
                return String(localized: "image appears", table: "Common")
            case "imageDisappeared":
                return String(localized: "image disappears", table: "Common")
            case "regionChanged":
                return String(localized: "region changes", table: "Common")
            case "pixelMatched":
                if let colorHex = condition.colorHex?.nilIfBlankForDraftPreview {
                    return String(format: String(localized: "pixel matches %@", table: "Common"), colorHex)
                }
                return String(localized: "pixel matches", table: "Common")
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
                parts.append(String(format: String(localized: "max %d attempts", table: "Common"), maxAttempts))
            }
            if let timeout = loop.timeoutSeconds {
                parts.append(String(format: String(localized: "%.1fs timeout", table: "Common"), timeout))
            }
            if let polling = loop.pollingSeconds {
                parts.append(String(format: String(localized: "%.1fs polling", table: "Common"), polling))
            }
            if let onFailure = loop.onFailure?.nilIfBlankForDraftPreview {
                parts.append(String(format: String(localized: "on failure: %@", table: "Common"), onFailure))
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
                String(format: String(localized: "%.1fs delay", table: "EditorUX"), $0)
            }
            id = dependency.key ?? "\(dependency.from)->\(dependency.to):\(dependency.trigger)"
        }

        private static func triggerLabel(for trigger: String) -> String {
            switch trigger {
            case "success":
                return String(localized: "Success", table: "Common")
            case "failure":
                return String(localized: "Failure", table: "Common")
            case "timeout":
                return String(localized: "Timeout", table: "Common")
            case "cancelled":
                return String(localized: "Cancelled", table: "Common")
            case "conditionMatched":
                return String(localized: "Condition matched", table: "Automation")
            case "conditionNotMatched":
                return String(localized: "Condition not matched", table: "Automation")
            case "always":
                return String(localized: "Always", table: "Common")
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
                String(format: String(localized: "%.2f threshold", table: "Common"), $0)
            } ?? String(localized: "Default threshold", table: "Common")
        }

        private static func assetKindLabel(for kind: AssetKind) -> String {
            switch kind {
            case .imageTemplate:
                return String(localized: "Image template", table: "Common")
            case .baseline:
                return String(localized: "Baseline", table: "Common")
            case .pixelSample:
                return String(localized: "Pixel sample", table: "Common")
            }
        }

        private static func boundsLabel(for bounds: RectValue) -> String {
            String(
                format: String(localized: "x %.1f, y %.1f, w %.1f, h %.1f", table: "Common"),
                bounds.x,
                bounds.y,
                bounds.width,
                bounds.height
            )
        }

        private static func spaceLabel(for space: AutomationOCRSearchRegionSpace) -> String {
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
                return String(localized: "No macro needed", table: "EditorUX")
            case .resolved:
                return String(localized: "Macro resolved", table: "EditorUX")
            case .missing:
                return String(localized: "Missing macro", table: "EditorUX")
            case .ambiguous:
                return String(localized: "Choose macro", table: "EditorUX")
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
            return .missing(reference: String(localized: "No macro selected", table: "EditorUX"))
        }

        if let id = macroRef.id {
            if let match = catalog.first(where: { $0.id == id }) {
                return .resolved(name: match.name, id: id)
            }
            return .missing(reference: id.uuidString)
        }

        guard let name = macroRef.name?.nilIfBlankForDraftPreview else {
            return .missing(reference: String(localized: "No macro selected", table: "EditorUX"))
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
                    roleLabel: String(localized: "Task condition", table: "Common"),
                    condition: condition
                ))
            }

            if let until = task.loop?.until {
                references.append(VisualConditionReference(
                    taskKey: taskKey,
                    roleLabel: String(localized: "Loop until", table: "Common"),
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
            return String(localized: "Success", table: "Common")
        case .failure:
            return String(localized: "Failure", table: "Common")
        case .timeout:
            return String(localized: "Timeout", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        }
    }

    static func resourceLabel(for resource: AutomationWorkflowDraftResource) -> String {
        switch resource {
        case .foregroundInput:
            return String(localized: "Needs mouse and keyboard", table: "Common")
        case .screenCapture:
            return String(localized: "Screen capture", table: "Recording")
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .network:
            return String(localized: "Network", table: "Common")
        case .none:
            return String(localized: "None", table: "Common")
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
