import Foundation

public enum AutomationCLIResultSchema {
    public static let current = "sparkle.cli.result.v1"
}

public struct AutomationCLIMessage: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var path: String?
    public var taskKey: String?
    public var dependencyKey: String?
    public var candidates: [UUID]

    public init(
        code: String,
        message: String,
        path: String? = nil,
        taskKey: String? = nil,
        dependencyKey: String? = nil,
        candidates: [UUID] = []
    ) {
        self.code = code
        self.message = message
        self.path = path
        self.taskKey = taskKey
        self.dependencyKey = dependencyKey
        self.candidates = candidates
    }

    public init(issue: AutomationWorkflowDraftIssue) {
        self.init(
            code: issue.code.rawValue,
            message: issue.message,
            path: issue.path,
            taskKey: issue.taskKey,
            dependencyKey: issue.dependencyKey,
            candidates: issue.candidates
        )
    }
}

public struct AutomationCLINextAction: Codable, Equatable, Sendable {
    public var command: String
    public var reason: String

    public init(command: String, reason: String) {
        self.command = command
        self.reason = reason
    }
}

public struct AutomationCLIResultEnvelope<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var ok: Bool
    public var schema: String
    public var command: String
    public var data: Value?
    public var warnings: [AutomationCLIMessage]
    public var errors: [AutomationCLIMessage]
    public var nextActions: [AutomationCLINextAction]

    public init(
        ok: Bool,
        schema: String = AutomationCLIResultSchema.current,
        command: String,
        data: Value?,
        warnings: [AutomationCLIMessage] = [],
        errors: [AutomationCLIMessage] = [],
        nextActions: [AutomationCLINextAction] = []
    ) {
        self.ok = ok
        self.schema = schema
        self.command = command
        self.data = data
        self.warnings = warnings
        self.errors = errors
        self.nextActions = nextActions
    }
}

public struct AutomationCLIEmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}

public extension AutomationCLIResultEnvelope {
    static func failure(
        command: String,
        code: String,
        message: String,
        path: String? = nil
    ) -> AutomationCLIResultEnvelope<Value> {
        AutomationCLIResultEnvelope<Value>(
            ok: false,
            command: command,
            data: nil,
            errors: [
                AutomationCLIMessage(
                    code: code,
                    message: message,
                    path: path
                )
            ]
        )
    }
}

public struct AutomationWorkflowMacroCatalogPayload: Codable, Equatable, Sendable {
    public var count: Int
    public var search: String?
    public var macros: [AutomationWorkflowDraftMacroCatalogEntry]

    public init(
        macros: [AutomationWorkflowDraftMacroCatalogEntry],
        search: String? = nil
    ) {
        self.macros = macros
        self.count = macros.count
        self.search = search
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowMacroCatalogPayload {
    static func workflowMacroCatalog(
        command: String,
        macros: [AutomationWorkflowDraftMacroCatalogEntry],
        search: String? = nil
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload> {
        AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowMacroCatalogPayload(
                macros: macros,
                search: search
            )
        )
    }
}

public struct AutomationWorkflowDraftValidationPayload: Codable, Equatable, Sendable {
    public var isValid: Bool
    public var issueCount: Int
    public var issues: [AutomationWorkflowDraftIssue]

    public init(result: AutomationWorkflowDraftValidationResult) {
        self.isValid = result.isValid
        self.issueCount = result.issues.count
        self.issues = result.issues
    }
}

public struct AutomationWorkflowDraftSimulationPayload: Codable, Equatable, Sendable {
    public var isSimulatable: Bool
    public var result: AutomationWorkflowDraftSimulationResult

    public init(result: AutomationWorkflowDraftSimulationResult) {
        self.isSimulatable = result.isSimulatable
        self.result = result
    }
}

public struct AutomationWorkflowDraftImportPayload: Codable, Equatable, Sendable {
    public var mode: AutomationWorkflowDraftImportMode
    public var isImportable: Bool
    public var result: AutomationWorkflowDraftImportResult

    public init(result: AutomationWorkflowDraftImportResult) {
        self.mode = result.mode
        self.isImportable = result.isImportable
        self.result = result
    }
}

public struct AutomationWorkflowDraftEditPayload: Codable, Equatable, Sendable {
    public var operation: String
    public var isValid: Bool
    public var document: AutomationWorkflowDraftDocument
    public var validation: AutomationWorkflowDraftValidationResult
    public var changedTaskKeys: [String]
    public var changedDependencyKeys: [String]
    public var wrotePath: String?

    public init(result: AutomationWorkflowDraftEditResult) {
        self.operation = result.operation
        self.isValid = result.isValid
        self.document = result.document
        self.validation = result.validation
        self.changedTaskKeys = result.changedTaskKeys
        self.changedDependencyKeys = result.changedDependencyKeys
        self.wrotePath = result.wrotePath
    }
}

public struct AutomationWorkflowSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var version: Int
    public var taskCount: Int
    public var dependencyCount: Int
    public var enabledTaskCount: Int
    public var runCount: Int
    public var latestRunID: UUID?
    public var latestRunStatus: AutomationTaskRunStatus?
    public var latestRunOutcome: AutomationOutcome?
    public var createdAt: Date
    public var modifiedAt: Date
    public var validationIssueCount: Int

    public init(
        workflow: AutomationWorkflow,
        runs: [AutomationTaskRun] = []
    ) {
        let latestRun = runs.sorted { left, right in
            Self.sortDate(for: left) > Self.sortDate(for: right)
        }.first

        self.id = workflow.id
        self.name = workflow.name
        self.version = workflow.version
        self.taskCount = workflow.tasks.count
        self.dependencyCount = workflow.dependencies.count
        self.enabledTaskCount = workflow.tasks.filter(\.isEnabled).count
        self.runCount = runs.count
        self.latestRunID = latestRun?.id
        self.latestRunStatus = latestRun?.status
        self.latestRunOutcome = latestRun?.outcome
        self.createdAt = workflow.createdAt
        self.modifiedAt = workflow.modifiedAt
        self.validationIssueCount = workflow.validationIssues().count
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowListPayload: Codable, Equatable, Sendable {
    public var count: Int
    public var workflows: [AutomationWorkflowSummary]

    public init(workflows: [AutomationWorkflowSummary]) {
        self.count = workflows.count
        self.workflows = workflows
    }
}

public struct AutomationWorkflowShowPayload: Codable, Equatable, Sendable {
    public var summary: AutomationWorkflowSummary
    public var workflow: AutomationWorkflow
    public var runHistory: [AutomationTaskRun]

    public init(
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) {
        let workflowRuns = runHistory.filter { $0.workflowID == workflow.id }
        self.summary = AutomationWorkflowSummary(workflow: workflow, runs: workflowRuns)
        self.workflow = workflow
        self.runHistory = workflowRuns
    }
}

public struct AutomationWorkflowDraftExportPayload: Codable, Equatable, Sendable {
    public var result: AutomationWorkflowDraftExportResult
    public var wrotePath: String?

    public init(
        result: AutomationWorkflowDraftExportResult,
        wrotePath: String? = nil
    ) {
        self.result = result
        self.wrotePath = wrotePath
    }
}

public enum AutomationWorkflowStatusKind: String, Codable, Equatable, Sendable {
    case idle
    case planned
    case waitingForDependencies
    case waitingForResource
    case queued
    case running
    case completed
    case needsAttention
}

public struct AutomationTaskStatusSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { taskID }

    public var taskID: UUID
    public var taskName: String
    public var isEnabled: Bool
    public var requiresForegroundInput: Bool
    public var status: AutomationWorkflowStatusKind
    public var statusLabel: String
    public var statusDetail: String
    public var latestRunID: UUID?
    public var latestExecutionID: UUID?
    public var latestRunStatus: AutomationTaskRunStatus?
    public var latestOutcome: AutomationOutcome?
    public var scheduledStartTime: Date?
    public var earliestStartTime: Date?
    public var actualStartTime: Date?
    public var completedAt: Date?
    public var attempt: Int?

    public init(task: AutomationTask, runs: [AutomationTaskRun]) {
        let latestRun = runs.sorted { left, right in
            Self.sortDate(for: left) > Self.sortDate(for: right)
        }.first
        let status = Self.status(for: latestRun)

        self.taskID = task.id
        self.taskName = task.name
        self.isEnabled = task.isEnabled
        self.requiresForegroundInput = task.resourceRequirement.requiresForegroundInput
        self.status = status
        self.statusLabel = Self.label(for: status)
        self.statusDetail = Self.detail(for: status, run: latestRun)
        self.latestRunID = latestRun?.id
        self.latestExecutionID = latestRun?.executionID
        self.latestRunStatus = latestRun?.status
        self.latestOutcome = latestRun?.outcome
        self.scheduledStartTime = latestRun?.scheduledStartTime
        self.earliestStartTime = latestRun?.earliestStartTime
        self.actualStartTime = latestRun?.actualStartTime
        self.completedAt = latestRun?.completedAt
        self.attempt = latestRun?.attempt
    }

    private static func status(for run: AutomationTaskRun?) -> AutomationWorkflowStatusKind {
        guard let run else {
            return .idle
        }

        switch run.status {
        case .planned:
            return .planned
        case .waitingForDependencies:
            return .waitingForDependencies
        case .waitingForResource:
            return .waitingForResource
        case .queued:
            return .queued
        case .running:
            return .running
        case .completed:
            guard let outcome = run.outcome else {
                return .completed
            }
            return outcome.needsWorkflowAttention ? .needsAttention : .completed
        }
    }

    private static func label(for status: AutomationWorkflowStatusKind) -> String {
        switch status {
        case .idle:
            return "未运行"
        case .planned:
            return "已计划"
        case .waitingForDependencies:
            return "等待上一步"
        case .waitingForResource:
            return "等待资源"
        case .queued:
            return "准备执行"
        case .running:
            return "正在执行"
        case .completed:
            return "已完成"
        case .needsAttention:
            return "需要处理"
        }
    }

    private static func detail(for status: AutomationWorkflowStatusKind, run: AutomationTaskRun?) -> String {
        switch status {
        case .idle:
            return "这个任务还没有运行记录。"
        case .planned:
            return "已计划，等待触发。"
        case .waitingForDependencies:
            return "正在等待上一步完成。"
        case .waitingForResource:
            return "正在等待鼠标键盘空闲。"
        case .queued:
            return "已进入执行队列。"
        case .running:
            return "正在执行当前任务。"
        case .completed:
            return "最近一次运行已完成。"
        case .needsAttention:
            return run?.outcome?.workflowAttentionDetail ?? "最近一次运行需要处理。"
        }
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowStatus: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { summary.id }

    public var summary: AutomationWorkflowSummary
    public var overallStatus: AutomationWorkflowStatusKind
    public var statusLabel: String
    public var statusDetail: String
    public var activeRunCount: Int
    public var waitingRunCount: Int
    public var completedRunCount: Int
    public var attentionRunCount: Int
    public var latestRun: AutomationTaskRun?
    public var tasks: [AutomationTaskStatusSummary]

    public init(workflow: AutomationWorkflow, runHistory: [AutomationTaskRun]) {
        let workflowRuns = runHistory.filter { $0.workflowID == workflow.id }
        let runsByTask = Dictionary(grouping: workflowRuns, by: \.taskID)
        let tasks = workflow.tasks.map { task in
            AutomationTaskStatusSummary(task: task, runs: runsByTask[task.id] ?? [])
        }
        let latestRun = workflowRuns.sorted { left, right in
            Self.sortDate(for: left) > Self.sortDate(for: right)
        }.first
        let overallStatus = Self.overallStatus(
            taskSummaries: tasks,
            validationIssueCount: workflow.validationIssues().count
        )

        self.summary = AutomationWorkflowSummary(workflow: workflow, runs: workflowRuns)
        self.overallStatus = overallStatus
        self.statusLabel = Self.label(for: overallStatus)
        self.statusDetail = Self.detail(
            for: overallStatus,
            activeRunCount: tasks.filter { $0.status == .running }.count,
            waitingRunCount: tasks.filter { $0.status == .waitingForDependencies || $0.status == .waitingForResource }.count,
            attentionRunCount: tasks.filter { $0.status == .needsAttention }.count,
            validationIssueCount: workflow.validationIssues().count
        )
        self.activeRunCount = tasks.filter { $0.status == .running }.count
        self.waitingRunCount = tasks.filter { $0.status == .waitingForDependencies || $0.status == .waitingForResource }.count
        self.completedRunCount = tasks.filter { $0.status == .completed }.count
        self.attentionRunCount = tasks.filter { $0.status == .needsAttention }.count
        self.latestRun = latestRun
        self.tasks = tasks
    }

    private static func overallStatus(
        taskSummaries: [AutomationTaskStatusSummary],
        validationIssueCount: Int
    ) -> AutomationWorkflowStatusKind {
        if validationIssueCount > 0 {
            return .needsAttention
        }
        if taskSummaries.contains(where: { $0.status == .running }) {
            return .running
        }
        if taskSummaries.contains(where: { $0.status == .waitingForResource }) {
            return .waitingForResource
        }
        if taskSummaries.contains(where: { $0.status == .queued }) {
            return .queued
        }
        if taskSummaries.contains(where: { $0.status == .waitingForDependencies }) {
            return .waitingForDependencies
        }
        if taskSummaries.contains(where: { $0.status == .needsAttention }) {
            return .needsAttention
        }
        if taskSummaries.contains(where: { $0.status == .planned }) {
            return .planned
        }
        if !taskSummaries.isEmpty, taskSummaries.allSatisfy({ $0.status == .completed }) {
            return .completed
        }
        return .idle
    }

    private static func label(for status: AutomationWorkflowStatusKind) -> String {
        switch status {
        case .idle:
            return "未运行"
        case .planned:
            return "已计划"
        case .waitingForDependencies:
            return "等待上一步"
        case .waitingForResource:
            return "等待鼠标键盘空闲"
        case .queued:
            return "准备执行"
        case .running:
            return "正在执行"
        case .completed:
            return "已完成"
        case .needsAttention:
            return "需要处理"
        }
    }

    private static func detail(
        for status: AutomationWorkflowStatusKind,
        activeRunCount: Int,
        waitingRunCount: Int,
        attentionRunCount: Int,
        validationIssueCount: Int
    ) -> String {
        if validationIssueCount > 0 {
            return "\(validationIssueCount) 个工作流结构问题需要处理。"
        }

        switch status {
        case .idle:
            return "这个工作流还没有运行记录。"
        case .planned:
            return "任务已计划，等待触发。"
        case .waitingForDependencies:
            return "有任务正在等待上一步完成。"
        case .waitingForResource:
            return "有任务正在等待鼠标键盘空闲。"
        case .queued:
            return "有任务已进入执行队列。"
        case .running:
            return "\(max(activeRunCount, 1)) 个任务正在执行。"
        case .completed:
            return "最近一次运行已完成。"
        case .needsAttention:
            return "\(max(attentionRunCount, 1)) 个任务需要处理。"
        }
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowStatusPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var count: Int
    public var workflows: [AutomationWorkflowStatus]

    public init(
        workflows: [AutomationWorkflowStatus],
        generatedAt: Date = Date.now
    ) {
        self.generatedAt = generatedAt
        self.count = workflows.count
        self.workflows = workflows
    }
}

public struct AutomationWorkflowRunPayload: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var requestedTaskID: UUID
    public var requestedAt: Date
    public var executionID: UUID?
    public var startedRunID: UUID?
    public var isComplete: Bool
    public var timedOut: Bool
    public var workflowStatus: AutomationWorkflowStatus
    public var executionRuns: [AutomationTaskRun]

    public init(
        workflow: AutomationWorkflow,
        requestedTaskID: UUID,
        requestedAt: Date,
        beforeRuns: [AutomationTaskRun],
        afterState: AutomationRunState,
        timedOut: Bool = false
    ) {
        let beforeRunIDs = Set(beforeRuns.map(\.id))
        let newRuns = afterState.runs.filter { run in
            run.workflowID == workflow.id && !beforeRunIDs.contains(run.id)
        }
        let startedRun = newRuns.first { $0.taskID == requestedTaskID } ?? newRuns.first
        let executionID = startedRun?.executionID
        let executionRuns = afterState.runs
            .filter { run in
                run.workflowID == workflow.id &&
                    (executionID.map { run.executionID == $0 } ?? newRuns.contains(where: { $0.id == run.id }))
            }
            .sorted { left, right in
                Self.sortDate(for: left) < Self.sortDate(for: right)
            }

        self.workflowID = workflow.id
        self.workflowName = workflow.name
        self.requestedTaskID = requestedTaskID
        self.requestedAt = requestedAt
        self.executionID = executionID
        self.startedRunID = startedRun?.id
        self.isComplete = !executionRuns.isEmpty && executionRuns.allSatisfy(\.isTerminal)
        self.timedOut = timedOut
        self.workflowStatus = AutomationWorkflowStatus(workflow: workflow, runHistory: afterState.runs)
        self.executionRuns = executionRuns
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowCancelPayload: Codable, Equatable, Sendable {
    public var runID: UUID
    public var requestedAt: Date
    public var cancelled: Bool
    public var run: AutomationTaskRun?
    public var workflowStatus: AutomationWorkflowStatus?

    public init(
        runID: UUID,
        requestedAt: Date,
        beforeRun: AutomationTaskRun?,
        afterState: AutomationRunState
    ) {
        let afterRun = afterState.run(id: runID)
        let workflow = afterRun.flatMap { run in afterState.workflow(id: run.workflowID) }

        self.runID = runID
        self.requestedAt = requestedAt
        self.cancelled = beforeRun?.isTerminal == false &&
            afterRun?.outcome == .cancelled(reason: "User cancelled")
        self.run = afterRun
        self.workflowStatus = workflow.map { AutomationWorkflowStatus(workflow: $0, runHistory: afterState.runs) }
    }
}

public enum AutomationRuntimeHandoffTarget: String, Codable, Equatable, Sendable {
    case appHost
}

public struct AutomationRuntimeHandoffPayload: Codable, Equatable, Sendable {
    public var target: AutomationRuntimeHandoffTarget
    public var command: AutomationRuntimeHandoffCommand
    public var enqueuedAt: Date
    public var pendingCommandCount: Int

    public init(
        target: AutomationRuntimeHandoffTarget = .appHost,
        command: AutomationRuntimeHandoffCommand,
        enqueuedAt: Date,
        pendingCommandCount: Int
    ) {
        self.target = target
        self.command = command
        self.enqueuedAt = enqueuedAt
        self.pendingCommandCount = pendingCommandCount
    }
}

public enum AutomationRuntimeHandoffDeliveryState: String, Codable, Equatable, Sendable {
    case pending
    case dispatched
    case failed
    case missing
}

public struct AutomationRuntimeHandoffStatusPayload: Codable, Equatable, Sendable {
    public var target: AutomationRuntimeHandoffTarget
    public var commandID: UUID
    public var state: AutomationRuntimeHandoffDeliveryState
    public var command: AutomationRuntimeHandoffCommand?
    public var receipt: AutomationRuntimeHandoffReceipt?
    public var workflowStatus: AutomationWorkflowStatus?
    public var runs: [AutomationTaskRun]
    public var pendingCommandCount: Int
    public var receiptCount: Int
    public var checkedAt: Date

    public init(
        target: AutomationRuntimeHandoffTarget = .appHost,
        commandID: UUID,
        command: AutomationRuntimeHandoffCommand?,
        receipt: AutomationRuntimeHandoffReceipt?,
        workflowStatus: AutomationWorkflowStatus? = nil,
        runs: [AutomationTaskRun] = [],
        pendingCommandCount: Int,
        receiptCount: Int,
        checkedAt: Date
    ) {
        self.target = target
        self.commandID = commandID
        self.command = command
        self.receipt = receipt
        self.workflowStatus = workflowStatus
        self.runs = Self.orderedRuns(runs, receipt: receipt)
        self.pendingCommandCount = pendingCommandCount
        self.receiptCount = receiptCount
        self.checkedAt = checkedAt

        if let receipt {
            switch receipt.status {
            case .dispatched:
                self.state = .dispatched
            case .failed:
                self.state = .failed
            }
        } else if command != nil {
            self.state = .pending
        } else {
            self.state = .missing
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case commandID
        case state
        case command
        case receipt
        case workflowStatus
        case runs
        case pendingCommandCount
        case receiptCount
        case checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.target = try container.decodeIfPresent(
            AutomationRuntimeHandoffTarget.self,
            forKey: .target
        ) ?? .appHost
        self.commandID = try container.decode(UUID.self, forKey: .commandID)
        self.state = try container.decodeIfPresent(
            AutomationRuntimeHandoffDeliveryState.self,
            forKey: .state
        ) ?? .missing
        self.command = try container.decodeIfPresent(
            AutomationRuntimeHandoffCommand.self,
            forKey: .command
        )
        self.receipt = try container.decodeIfPresent(
            AutomationRuntimeHandoffReceipt.self,
            forKey: .receipt
        )
        self.workflowStatus = try container.decodeIfPresent(
            AutomationWorkflowStatus.self,
            forKey: .workflowStatus
        )
        self.runs = Self.orderedRuns(
            try container.decodeIfPresent([AutomationTaskRun].self, forKey: .runs) ?? [],
            receipt: receipt
        )
        self.pendingCommandCount = try container.decodeIfPresent(Int.self, forKey: .pendingCommandCount) ?? 0
        self.receiptCount = try container.decodeIfPresent(Int.self, forKey: .receiptCount) ?? 0
        self.checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt) ?? Date(timeIntervalSince1970: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(commandID, forKey: .commandID)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(receipt, forKey: .receipt)
        try container.encodeIfPresent(workflowStatus, forKey: .workflowStatus)
        try container.encode(runs, forKey: .runs)
        try container.encode(pendingCommandCount, forKey: .pendingCommandCount)
        try container.encode(receiptCount, forKey: .receiptCount)
        try container.encode(checkedAt, forKey: .checkedAt)
    }

    private static func orderedRuns(
        _ runs: [AutomationTaskRun],
        receipt: AutomationRuntimeHandoffReceipt?
    ) -> [AutomationTaskRun] {
        guard let receipt, !receipt.runIDs.isEmpty else {
            return runs.sorted { sortDate(for: $0) > sortDate(for: $1) }
        }

        var runsByID = Dictionary(grouping: runs, by: \.id)
            .mapValues { groupedRuns in
                groupedRuns.sorted { sortDate(for: $0) > sortDate(for: $1) }.first!
            }
        var ordered = receipt.runIDs.compactMap { runID in
            runsByID.removeValue(forKey: runID)
        }
        ordered.append(contentsOf: runsByID.values.sorted { sortDate(for: $0) > sortDate(for: $1) })
        return ordered
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowRunsPayload: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var count: Int
    public var runs: [AutomationTaskRun]
    public var status: AutomationWorkflowStatus

    public init(
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) {
        let workflowRuns = runHistory
            .filter { $0.workflowID == workflow.id }
            .sorted { left, right in
                Self.sortDate(for: left) > Self.sortDate(for: right)
            }

        self.workflowID = workflow.id
        self.workflowName = workflow.name
        self.count = workflowRuns.count
        self.runs = workflowRuns
        self.status = AutomationWorkflowStatus(workflow: workflow, runHistory: runHistory)
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationRuntimeHandoffPayload {
    static func workflowHandoff(
        command: String,
        payload: AutomationRuntimeHandoffPayload
    ) -> AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload> {
        let nextActions: [AutomationCLINextAction]
        switch payload.command.kind {
        case .manualStart(let workflowID, _):
            nextActions = [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow handoff status \(payload.command.id.uuidString) --json",
                    reason: "Check whether the running App host has dispatched or rejected the handoff command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(workflowID.uuidString) --json",
                    reason: "Read workflow status after the App host consumes the handoff command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow runs \(workflowID.uuidString) --json",
                    reason: "Inspect run history after the App host starts or finishes the workflow."
                )
            ]
        case .cancelRun:
            nextActions = [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow handoff status \(payload.command.id.uuidString) --json",
                    reason: "Check whether the running App host has dispatched or rejected the cancellation command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status --json",
                    reason: "Read workflow status after the App host consumes the cancellation command."
                )
            ]
        }

        return AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload>(
            ok: true,
            command: command,
            data: payload,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationRuntimeHandoffStatusPayload {
    static func workflowHandoffStatus(
        command: String,
        payload: AutomationRuntimeHandoffStatusPayload
    ) -> AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload> {
        var nextActions: [AutomationCLINextAction] = []
        switch payload.state {
        case .pending:
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow handoff status \(payload.commandID.uuidString) --json",
                reason: "Poll until the running App host records a dispatched or failed receipt."
            ))
        case .dispatched:
            if let workflowID = payload.workflowID {
                nextActions.append(AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(workflowID.uuidString) --json",
                    reason: "Read workflow status after the App host dispatched the command."
                ))
                nextActions.append(AutomationCLINextAction(
                    command: "SparkleRecorder workflow runs \(workflowID.uuidString) --json",
                    reason: "Inspect run history for the dispatched command."
                ))
            }
        case .failed:
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow handoff status \(payload.commandID.uuidString) --json",
                reason: "Review the failed handoff receipt before retrying the command."
            ))
        case .missing:
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow run <workflow-id> --task <task> --confirm --handoff app --json",
                reason: "Create a new App-host handoff command if this command ID is not known."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload>(
            ok: payload.state != .missing,
            command: command,
            data: payload,
            nextActions: nextActions
        )
    }
}

private extension AutomationRuntimeHandoffStatusPayload {
    var workflowID: UUID? {
        if let workflowStatus {
            return workflowStatus.summary.id
        }
        if let workflowID = runs.first?.workflowID {
            return workflowID
        }
        if let command {
            switch command.kind {
            case .manualStart(let workflowID, _):
                return workflowID
            case .cancelRun:
                return nil
            }
        }
        if let receipt {
            switch receipt.commandKind {
            case .manualStart(let workflowID, _):
                return workflowID
            case .cancelRun:
                return nil
            }
        }
        return nil
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowListPayload {
    static func workflowList(
        command: String,
        workflows: [AutomationWorkflow],
        runHistory: [AutomationTaskRun]
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowListPayload> {
        let runsByWorkflow = Dictionary(grouping: runHistory, by: \.workflowID)
        let summaries = workflows
            .map { workflow in
                AutomationWorkflowSummary(
                    workflow: workflow,
                    runs: runsByWorkflow[workflow.id] ?? []
                )
            }
            .sorted { left, right in
                if left.modifiedAt != right.modifiedAt {
                    return left.modifiedAt > right.modifiedAt
                }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }

        return AutomationCLIResultEnvelope<AutomationWorkflowListPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowListPayload(workflows: summaries),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow show <workflow-id> --json",
                    reason: "Inspect a workflow before exporting or running it."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowRunPayload {
    static func workflowRun(
        command: String,
        payload: AutomationWorkflowRunPayload
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowRunPayload> {
        var warnings: [AutomationCLIMessage] = []
        if payload.timedOut {
            warnings.append(AutomationCLIMessage(
                code: "runWaitTimedOut",
                message: "Workflow run did not reach a terminal state before the wait timeout."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowRunPayload>(
            ok: payload.startedRunID != nil && !payload.timedOut,
            command: command,
            data: payload,
            warnings: warnings,
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(payload.workflowID.uuidString) --json",
                    reason: "Read the latest workflow status after this runtime command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow runs \(payload.workflowID.uuidString) --json",
                    reason: "Inspect run history and outcomes for this workflow."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowCancelPayload {
    static func workflowCancel(
        command: String,
        payload: AutomationWorkflowCancelPayload
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowCancelPayload> {
        AutomationCLIResultEnvelope<AutomationWorkflowCancelPayload>(
            ok: payload.cancelled || payload.run?.isTerminal == true,
            command: command,
            data: payload,
            warnings: payload.cancelled ? [] : [
                AutomationCLIMessage(
                    code: "runAlreadyTerminal",
                    message: "The requested run was already terminal or could not be cancelled from this runtime session."
                )
            ],
            nextActions: payload.workflowStatus.map { status in
                [
                    AutomationCLINextAction(
                        command: "SparkleRecorder workflow status \(status.summary.id.uuidString) --json",
                        reason: "Read the workflow status after cancellation."
                    )
                ]
            } ?? []
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowRunsPayload {
    static func workflowRuns(
        command: String,
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowRunsPayload> {
        let payload = AutomationWorkflowRunsPayload(workflow: workflow, runHistory: runHistory)
        return AutomationCLIResultEnvelope<AutomationWorkflowRunsPayload>(
            ok: true,
            command: command,
            data: payload,
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(workflow.id.uuidString) --json",
                    reason: "Read the summarized workflow status for these runs."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowStatusPayload {
    static func workflowStatus(
        command: String,
        workflows: [AutomationWorkflow],
        runHistory: [AutomationTaskRun],
        generatedAt: Date = Date.now
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowStatusPayload> {
        let statuses = workflows
            .map { workflow in
                AutomationWorkflowStatus(workflow: workflow, runHistory: runHistory)
            }
            .sorted { left, right in
                if left.summary.modifiedAt != right.summary.modifiedAt {
                    return left.summary.modifiedAt > right.summary.modifiedAt
                }
                return left.summary.name.localizedCaseInsensitiveCompare(right.summary.name) == .orderedAscending
            }

        var nextActions: [AutomationCLINextAction] = []
        if statuses.isEmpty {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow import <draft.json> --confirm --json",
                reason: "Import a validated workflow draft before checking runtime status."
            ))
        } else {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow show <workflow-id> --json",
                reason: "Inspect the workflow graph and run history for a status item."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowStatusPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowStatusPayload(
                workflows: statuses,
                generatedAt: generatedAt
            ),
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowShowPayload {
    static func workflowShow(
        command: String,
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowShowPayload> {
        AutomationCLIResultEnvelope<AutomationWorkflowShowPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowShowPayload(
                workflow: workflow,
                runHistory: runHistory
            ),
            warnings: workflow.validationIssues().map { issue in
                AutomationCLIMessage(
                    code: "workflowValidationIssue",
                    message: "Workflow validation issue: \(issue)."
                )
            },
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow export \(workflow.id.uuidString) --format draft-json --json",
                    reason: "Export this workflow to an AI-editable draft before asking an agent to modify it."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftExportPayload {
    static func workflowDraftExport(
        command: String,
        result: AutomationWorkflowDraftExportResult,
        wrotePath: String? = nil
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload> {
        let warnings = result.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if result.isExportable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <exported-draft.json> --json",
                reason: "Validate the exported draft before editing or re-importing it."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload>(
            ok: result.isExportable,
            command: command,
            data: AutomationWorkflowDraftExportPayload(result: result, wrotePath: wrotePath),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftEditPayload {
    static func workflowDraftEdit(
        command: String,
        result: AutomationWorkflowDraftEditResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftEditPayload> {
        let warnings = result.validation.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.validation.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if !result.isValid {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <draft.json> --json",
                reason: "Fix draft errors before simulating or importing this workflow."
            ))
        } else if result.document.workflow.tasks.isEmpty {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft task add <draft.json> --key <task-key> --type macro --json",
                reason: "Add at least one task to make the workflow useful."
            ))
        } else {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft simulate <draft.json> --json",
                reason: "Preview task order, branches, and resource usage before import."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftEditPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowDraftEditPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

private extension AutomationOutcome {
    var needsWorkflowAttention: Bool {
        switch self {
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return false
        case .failed, .cancelled, .timedOut, .resourceConflict, .permissionDenied, .missingMacro, .rejected:
            return true
        }
    }

    var workflowAttentionDetail: String {
        switch self {
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return "最近一次运行已完成。"
        case .failed:
            return "最近一次运行失败。"
        case .cancelled(let reason):
            return reason.map { "最近一次运行已取消：\($0)" } ?? "最近一次运行已取消。"
        case .timedOut:
            return "最近一次运行超时。"
        case .resourceConflict(let resource):
            return resource.map { "资源冲突：\($0.rawValue)。" } ?? "最近一次运行发生资源冲突。"
        case .permissionDenied(let permission, let message):
            return "缺少权限 \(permission.rawValue)：\(message)"
        case .missingMacro(let macroID):
            return "缺少宏 \(macroID.uuidString)。"
        case .rejected(let reason):
            return "运行被拒绝：\(reason)"
        }
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftImportPayload {
    static func workflowDraftImport(
        command: String,
        result: AutomationWorkflowDraftImportResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload> {
        let warnings = result.validationIssues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.validationIssues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if !result.isImportable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <draft.json> --macro-catalog <catalog.json> --json",
                reason: "Fix import-blocking draft issues before confirming this workflow."
            ))
        } else if result.mode == .dryRun {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow import <draft.json> --confirm --json",
                reason: "Dry-run passed; confirm import once UI preview and user review are complete."
            ))
        } else if let workflowID = result.workflow?.id {
            nextActions.append(AutomationCLINextAction(
                command: "Open SparkleRecorder Workflow page",
                reason: "Workflow \(workflowID.uuidString) was imported; review it in the app before running mouse or keyboard automation."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>(
            ok: result.isImportable,
            command: command,
            data: AutomationWorkflowDraftImportPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftSimulationPayload {
    static func workflowDraftSimulation(
        command: String,
        result: AutomationWorkflowDraftSimulationResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload> {
        let warnings = result.validationIssues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.validationIssues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if !result.isSimulatable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <draft.json> --json",
                reason: "Fix validation errors before simulating this workflow draft."
            ))
        }
        if result.steps.isEmpty && result.isSimulatable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft task add <draft.json> --key <task-key> --type macro --json",
                reason: "Add at least one enabled root task so the simulation has a starting point."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>(
            ok: result.isSimulatable,
            command: command,
            data: AutomationWorkflowDraftSimulationPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftValidationPayload {
    static func workflowDraftValidation(
        command: String,
        result: AutomationWorkflowDraftValidationResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload> {
        let warnings = result.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>(
            ok: result.isValid,
            command: command,
            data: AutomationWorkflowDraftValidationPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions(for: result)
        )
    }

    static func workflowDraftValidationFailure(
        command: String,
        code: String,
        message: String,
        path: String? = nil
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload> {
        failure(command: command, code: code, message: message, path: path)
    }

    private static func nextActions(
        for result: AutomationWorkflowDraftValidationResult
    ) -> [AutomationCLINextAction] {
        var actions: [AutomationCLINextAction] = []
        if result.issues.contains(where: { $0.code == .ambiguousMacroRef || $0.code == .missingMacroRef }) {
            actions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow macros --json",
                reason: "Choose an exact macro ID from the local macro catalog."
            ))
        }
        if result.issues.contains(where: { $0.code == .missingTimeoutBranch }) {
            actions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft dependency add <draft.json> --from <task-key> --to <fallback-task-key> --trigger timeout --json",
                reason: "Add an explicit timeout branch so long waits have a visible fallback."
            ))
        }
        return actions
    }
}
