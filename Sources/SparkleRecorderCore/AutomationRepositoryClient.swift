import Foundation

public struct AutomationPersistenceDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var workflows: [AutomationWorkflow]
    public var runHistory: [AutomationTaskRun]

    public init(
        version: Int = 1,
        workflows: [AutomationWorkflow] = [],
        runHistory: [AutomationTaskRun] = []
    ) {
        self.version = version
        self.workflows = workflows
        self.runHistory = runHistory
    }
}

public enum AutomationPersistence {
    public static let fileName = "automations.json"

    public static var defaultFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SparkleRecorder", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    public static func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }
}

public struct AutomationWorkflowPackageDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var workflows: [AutomationWorkflow]

    public init(
        version: Int = AutomationWorkflowPackage.currentVersion,
        exportedAt: Date = Date.now,
        workflows: [AutomationWorkflow]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.workflows = workflows
    }

    public var validationFailures: [AutomationWorkflowPackageValidationFailure] {
        workflows.compactMap { workflow in
            let issues = workflow.validationIssues()
            guard !issues.isEmpty else {
                return nil
            }
            return AutomationWorkflowPackageValidationFailure(
                workflowID: workflow.id,
                workflowName: workflow.name,
                issues: issues
            )
        }
    }
}

public struct AutomationWorkflowPackageValidationFailure: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var issues: [AutomationWorkflowValidationIssue]

    public init(
        workflowID: UUID,
        workflowName: String,
        issues: [AutomationWorkflowValidationIssue]
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.issues = issues
    }
}

public enum AutomationWorkflowPackageError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case emptyPackage
    case duplicateWorkflowIDs([UUID])
    case invalidWorkflows([AutomationWorkflowPackageValidationFailure])

    public var description: String {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported automation workflow package version \(version)."
        case .emptyPackage:
            return "Automation workflow package must include at least one workflow."
        case .duplicateWorkflowIDs(let ids):
            return "Automation workflow package contains duplicate workflow IDs: \(ids.map(\.uuidString).joined(separator: ", "))."
        case .invalidWorkflows(let failures):
            return "Automation workflow package contains \(failures.count) invalid workflow(s)."
        }
    }
}

public enum AutomationWorkflowPackage {
    public static let currentVersion = 1
    public static let fileExtension = "sparkrec_workflow"
    public static let defaultFileName = "workflows.sparkrec_workflow"

    public static func fileURL(
        in directoryURL: URL,
        fileName: String = defaultFileName
    ) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    public static func document(
        workflows: [AutomationWorkflow],
        exportedAt: Date = Date.now
    ) throws -> AutomationWorkflowPackageDocument {
        let document = AutomationWorkflowPackageDocument(
            exportedAt: exportedAt,
            workflows: workflows
        )
        try validate(document)
        return document
    }

    public static func encode(
        workflows: [AutomationWorkflow],
        exportedAt: Date = Date.now
    ) throws -> Data {
        try encode(document(workflows: workflows, exportedAt: exportedAt))
    }

    public static func encode(_ document: AutomationWorkflowPackageDocument) throws -> Data {
        try validate(document)
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> AutomationWorkflowPackageDocument {
        let document = try decoder.decode(AutomationWorkflowPackageDocument.self, from: data)
        try validate(document)
        return document
    }

    public static func validate(_ document: AutomationWorkflowPackageDocument) throws {
        guard document.version == currentVersion else {
            throw AutomationWorkflowPackageError.unsupportedVersion(document.version)
        }

        guard !document.workflows.isEmpty else {
            throw AutomationWorkflowPackageError.emptyPackage
        }

        let duplicateWorkflowIDs = duplicateValues(document.workflows.map(\.id))
        guard duplicateWorkflowIDs.isEmpty else {
            throw AutomationWorkflowPackageError.duplicateWorkflowIDs(duplicateWorkflowIDs)
        }

        let validationFailures = document.validationFailures
        guard validationFailures.isEmpty else {
            throw AutomationWorkflowPackageError.invalidWorkflows(validationFailures)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }

    private static func duplicateValues<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var duplicates: [T] = []
        for value in values {
            if !seen.insert(value).inserted && !duplicates.contains(value) {
                duplicates.append(value)
            }
        }
        return duplicates
    }
}

public actor AutomationJSONRepository {
    public nonisolated let fileURL: URL

    public init(fileURL: URL = AutomationPersistence.defaultFileURL) {
        self.fileURL = fileURL
    }

    public init(directoryURL: URL) {
        self.init(fileURL: AutomationPersistence.fileURL(in: directoryURL))
    }

    public func loadDocument() throws -> AutomationPersistenceDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AutomationPersistenceDocument()
        }

        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(AutomationPersistenceDocument.self, from: data)
    }

    public func saveDocument(_ document: AutomationPersistenceDocument) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadWorkflows() throws -> [AutomationWorkflow] {
        try loadDocument().workflows
    }

    public func saveWorkflows(_ workflows: [AutomationWorkflow]) throws {
        var document = try loadDocument()
        document.workflows = workflows
        try saveDocument(document)
    }

    public func loadRunHistory() throws -> [AutomationTaskRun] {
        try loadDocument().runHistory
    }

    public func appendRun(_ run: AutomationTaskRun) throws {
        var document = try loadDocument()
        document.runHistory.append(run)
        try saveDocument(document)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}

public actor AutomationInMemoryRepositoryStore {
    private var workflows: [AutomationWorkflow]
    private var runHistory: [AutomationTaskRun]

    public init(
        workflows: [AutomationWorkflow] = [],
        runHistory: [AutomationTaskRun] = []
    ) {
        self.workflows = workflows
        self.runHistory = runHistory
    }

    public func loadWorkflows() -> [AutomationWorkflow] {
        workflows
    }

    public func saveWorkflows(_ workflows: [AutomationWorkflow]) {
        self.workflows = workflows
    }

    public func loadRunHistory() -> [AutomationTaskRun] {
        runHistory
    }

    public func appendRun(_ run: AutomationTaskRun) {
        runHistory.append(run)
    }
}

public struct AutomationRepositoryClient: Sendable {
    public var loadWorkflows: @Sendable () async throws -> [AutomationWorkflow]
    public var saveWorkflows: @Sendable (_ workflows: [AutomationWorkflow]) async throws -> Void
    public var loadRunHistory: @Sendable () async throws -> [AutomationTaskRun]
    public var appendRun: @Sendable (_ run: AutomationTaskRun) async throws -> Void

    public init(
        loadWorkflows: @escaping @Sendable () async throws -> [AutomationWorkflow],
        saveWorkflows: @escaping @Sendable (_ workflows: [AutomationWorkflow]) async throws -> Void,
        loadRunHistory: @escaping @Sendable () async throws -> [AutomationTaskRun],
        appendRun: @escaping @Sendable (_ run: AutomationTaskRun) async throws -> Void
    ) {
        self.loadWorkflows = loadWorkflows
        self.saveWorkflows = saveWorkflows
        self.loadRunHistory = loadRunHistory
        self.appendRun = appendRun
    }

    public static func fileBacked(
        fileURL: URL = AutomationPersistence.defaultFileURL
    ) -> AutomationRepositoryClient {
        let repository = AutomationJSONRepository(fileURL: fileURL)
        return AutomationRepositoryClient(
            loadWorkflows: {
                try await repository.loadWorkflows()
            },
            saveWorkflows: { workflows in
                try await repository.saveWorkflows(workflows)
            },
            loadRunHistory: {
                try await repository.loadRunHistory()
            },
            appendRun: { run in
                try await repository.appendRun(run)
            }
        )
    }

    public static func fileBacked(directoryURL: URL) -> AutomationRepositoryClient {
        fileBacked(fileURL: AutomationPersistence.fileURL(in: directoryURL))
    }

    public static func inMemory(
        store: AutomationInMemoryRepositoryStore = AutomationInMemoryRepositoryStore()
    ) -> AutomationRepositoryClient {
        AutomationRepositoryClient(
            loadWorkflows: {
                await store.loadWorkflows()
            },
            saveWorkflows: { workflows in
                await store.saveWorkflows(workflows)
            },
            loadRunHistory: {
                await store.loadRunHistory()
            },
            appendRun: { run in
                await store.appendRun(run)
            }
        )
    }
}

public struct AutomationRepositorySnapshot: Codable, Equatable, Sendable {
    public var workflows: [AutomationWorkflow]
    public var runHistory: [AutomationTaskRun]
    public var refreshedAt: Date

    public init(
        workflows: [AutomationWorkflow],
        runHistory: [AutomationTaskRun],
        refreshedAt: Date
    ) {
        self.workflows = workflows
        self.runHistory = runHistory
        self.refreshedAt = refreshedAt
    }

    public var state: AutomationRunState {
        AutomationRunState(
            workflows: workflows,
            runs: runHistory,
            now: refreshedAt
        )
    }
}

public struct AutomationRepositoryRefreshFailure: Equatable, Sendable {
    public var message: String
    public var failedAt: Date

    public init(message: String, failedAt: Date) {
        self.message = message
        self.failedAt = failedAt
    }
}

public enum AutomationRepositoryRefreshResult: Equatable, Sendable {
    case loaded(AutomationRepositorySnapshot)
    case failed(AutomationRepositoryRefreshFailure)

    public var snapshot: AutomationRepositorySnapshot? {
        if case .loaded(let snapshot) = self {
            return snapshot
        }
        return nil
    }

    public var failure: AutomationRepositoryRefreshFailure? {
        if case .failed(let failure) = self {
            return failure
        }
        return nil
    }
}

public enum AutomationRepositoryRefreshState: Equatable, Sendable {
    case idle
    case loading(startedAt: Date, previousSnapshot: AutomationRepositorySnapshot?)
    case loaded(AutomationRepositorySnapshot)
    case failed(AutomationRepositoryRefreshFailure, previousSnapshot: AutomationRepositorySnapshot?)

    public var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    public var snapshot: AutomationRepositorySnapshot? {
        switch self {
        case .idle:
            return nil
        case .loading(_, let previousSnapshot):
            return previousSnapshot
        case .loaded(let snapshot):
            return snapshot
        case .failed(_, let previousSnapshot):
            return previousSnapshot
        }
    }

    public var failure: AutomationRepositoryRefreshFailure? {
        if case .failed(let failure, _) = self {
            return failure
        }
        return nil
    }
}

public struct AutomationRepositorySnapshotClient: Sendable {
    public var refresh: @Sendable () async -> AutomationRepositoryRefreshResult

    public init(refresh: @escaping @Sendable () async -> AutomationRepositoryRefreshResult) {
        self.refresh = refresh
    }

    public static func repositoryBacked(
        _ repository: AutomationRepositoryClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationRepositorySnapshotClient {
        AutomationRepositorySnapshotClient {
            let refreshedAt = now()
            do {
                let workflows = try await repository.loadWorkflows()
                let runHistory = try await repository.loadRunHistory()
                return .loaded(AutomationRepositorySnapshot(
                    workflows: workflows,
                    runHistory: runHistory,
                    refreshedAt: refreshedAt
                ))
            } catch {
                return .failed(AutomationRepositoryRefreshFailure(
                    message: String(describing: error),
                    failedAt: refreshedAt
                ))
            }
        }
    }
}

public actor AutomationRepositoryRefreshStateStore {
    private var state: AutomationRepositoryRefreshState

    public init(state: AutomationRepositoryRefreshState = .idle) {
        self.state = state
    }

    public func currentState() -> AutomationRepositoryRefreshState {
        state
    }

    public func setState(_ state: AutomationRepositoryRefreshState) {
        self.state = state
    }
}

public struct AutomationRepositoryRefreshClient: Sendable {
    public var currentState: @Sendable () async -> AutomationRepositoryRefreshState
    public var refresh: @Sendable () async -> AutomationRepositoryRefreshState

    public init(
        currentState: @escaping @Sendable () async -> AutomationRepositoryRefreshState,
        refresh: @escaping @Sendable () async -> AutomationRepositoryRefreshState
    ) {
        self.currentState = currentState
        self.refresh = refresh
    }

    public static func stateful(
        snapshotClient: AutomationRepositorySnapshotClient,
        stateStore: AutomationRepositoryRefreshStateStore = AutomationRepositoryRefreshStateStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationRepositoryRefreshClient {
        AutomationRepositoryRefreshClient(
            currentState: {
                await stateStore.currentState()
            },
            refresh: {
                let previousSnapshot = await stateStore.currentState().snapshot
                await stateStore.setState(.loading(
                    startedAt: now(),
                    previousSnapshot: previousSnapshot
                ))

                let result = await snapshotClient.refresh()
                let state: AutomationRepositoryRefreshState
                switch result {
                case .loaded(let snapshot):
                    state = .loaded(snapshot)
                case .failed(let failure):
                    state = .failed(failure, previousSnapshot: previousSnapshot)
                }

                await stateStore.setState(state)
                return state
            }
        )
    }
}
