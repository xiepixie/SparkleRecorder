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
    public static let runJournalFileName = "automation-runs.jsonl"

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

    public static func runJournalURL(for fileURL: URL) -> URL {
        fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(runJournalFileName)
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

private struct AutomationRunJournalEntry: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var run: AutomationTaskRun

    init(run: AutomationTaskRun) {
        self.version = Self.currentVersion
        self.run = run
    }
}

public actor AutomationJSONRepository {
    public nonisolated let fileURL: URL
    public nonisolated let runJournalURL: URL

    private let journalCompactionEntryFloor: Int
    private let journalCompactionMultiplier: Int
    private var cachedRunHistory: [AutomationTaskRun]?
    private var cachedRunIndexByID: [UUID: Int] = [:]
    private var journalEntryCount = 0

    public init(
        fileURL: URL = AutomationPersistence.defaultFileURL,
        journalCompactionEntryFloor: Int = 1_000,
        journalCompactionMultiplier: Int = 4
    ) {
        self.fileURL = fileURL
        self.runJournalURL = AutomationPersistence.runJournalURL(for: fileURL)
        self.journalCompactionEntryFloor = max(1, journalCompactionEntryFloor)
        self.journalCompactionMultiplier = max(2, journalCompactionMultiplier)
    }

    public init(
        directoryURL: URL,
        journalCompactionEntryFloor: Int = 1_000,
        journalCompactionMultiplier: Int = 4
    ) {
        self.init(
            fileURL: AutomationPersistence.fileURL(in: directoryURL),
            journalCompactionEntryFloor: journalCompactionEntryFloor,
            journalCompactionMultiplier: journalCompactionMultiplier
        )
    }

    public func loadDocument() throws -> AutomationPersistenceDocument {
        var document = try loadRawDocument()
        document.runHistory = try loadRunHistory()
        return document
    }

    public func saveDocument(_ document: AutomationPersistenceDocument) throws {
        try commitCompactedRunHistory(document.runHistory)
        var rawDocument = document
        rawDocument.runHistory = []
        try saveRawDocument(rawDocument)
    }

    public func loadWorkflows() throws -> [AutomationWorkflow] {
        try loadRawDocument().workflows
    }

    public func saveWorkflows(_ workflows: [AutomationWorkflow]) throws {
        var document = try loadRawDocument()
        document.workflows = workflows
        if FileManager.default.fileExists(atPath: runJournalURL.path) {
            document.runHistory = []
        }
        try saveRawDocument(document)
    }

    public func loadRunHistory() throws -> [AutomationTaskRun] {
        try ensureRunHistoryCache()
        return cachedRunHistory ?? []
    }

    public func appendRun(_ run: AutomationTaskRun) throws {
        try ensureRunHistoryCache()

        if !FileManager.default.fileExists(atPath: runJournalURL.path) {
            var migratedRuns = cachedRunHistory ?? []
            upsert(run, in: &migratedRuns)
            try commitCompactedRunHistory(migratedRuns)
            return
        }

        if shouldCompactJournal {
            try commitCompactedRunHistory(cachedRunHistory ?? [])
        }

        try appendJournalEntry(run)
        upsertCachedRun(run)
        journalEntryCount += 1
    }

    public func replaceRunHistory(_ runs: [AutomationTaskRun]) throws {
        try commitCompactedRunHistory(runs)
    }

    public func markRunRetentionPending(
        _ plan: AutomationRunRetentionPlan
    ) throws -> [AutomationTaskRun] {
        let runs = AutomationRunRetentionPlanner.markPending(
            runs: try loadRunHistory(),
            plan: plan
        )
        try commitCompactedRunHistory(runs)
        return runs
    }

    public func markRunRetentionApplied(
        _ plan: AutomationRunRetentionPlan,
        deletedRelativePathsByRunID: [UUID: [String]]
    ) throws -> [AutomationTaskRun] {
        let runs = AutomationRunRetentionPlanner.markApplied(
            runs: try loadRunHistory(),
            plan: plan,
            deletedRelativePathsByRunID: deletedRelativePathsByRunID
        )
        try commitCompactedRunHistory(runs)
        return runs
    }

    public func markRunScreenshotsDeleted(
        runIDs: Set<UUID>
    ) throws -> [AutomationTaskRun] {
        let runs = try AutomationRunManualDeletionPlanner.markScreenshotsDeleted(
            runs: loadRunHistory(),
            runIDs: runIDs
        )
        try commitCompactedRunHistory(runs)
        return runs
    }

    private func loadRawDocument() throws -> AutomationPersistenceDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AutomationPersistenceDocument()
        }

        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(AutomationPersistenceDocument.self, from: data)
    }

    private func saveRawDocument(_ document: AutomationPersistenceDocument) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureRunHistoryCache() throws {
        guard cachedRunHistory == nil else { return }

        let runs: [AutomationTaskRun]
        if FileManager.default.fileExists(atPath: runJournalURL.path) {
            runs = try replayJournal()
        } else {
            runs = try loadRawDocument().runHistory
            journalEntryCount = runs.count
        }
        setRunHistoryCache(runs)
    }

    private func replayJournal() throws -> [AutomationTaskRun] {
        let data = try Data(contentsOf: runJournalURL)
        guard !data.isEmpty else {
            journalEntryCount = 0
            return []
        }

        let endsWithNewline = data.last == Self.newline
        let lines = data.split(separator: Self.newline, omittingEmptySubsequences: true)
        var runs: [AutomationTaskRun] = []
        var indexByID: [UUID: Int] = [:]
        var decodedEntryCount = 0

        for (lineIndex, line) in lines.enumerated() {
            let entry: AutomationRunJournalEntry
            do {
                entry = try Self.journalDecoder.decode(
                    AutomationRunJournalEntry.self,
                    from: Data(line)
                )
            } catch {
                let isTornFinalLine = lineIndex == lines.count - 1 && !endsWithNewline
                guard isTornFinalLine else { throw error }
                continue
            }
            guard entry.version == AutomationRunJournalEntry.currentVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let index = indexByID[entry.run.id] {
                runs[index] = entry.run
            } else {
                indexByID[entry.run.id] = runs.count
                runs.append(entry.run)
            }
            decodedEntryCount += 1
        }

        journalEntryCount = decodedEntryCount
        return runs
    }

    private func appendJournalEntry(_ run: AutomationTaskRun) throws {
        try FileManager.default.createDirectory(
            at: runJournalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: runJournalURL.path) {
            _ = FileManager.default.createFile(atPath: runJournalURL.path, contents: nil)
        }

        var data = try Self.journalEncoder.encode(AutomationRunJournalEntry(run: run))
        data.append(Self.newline)
        let handle = try FileHandle(forWritingTo: runJournalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
    }

    private func commitCompactedRunHistory(_ runs: [AutomationTaskRun]) throws {
        try FileManager.default.createDirectory(
            at: runJournalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var data = Data()
        for run in runs {
            data.append(try Self.journalEncoder.encode(AutomationRunJournalEntry(run: run)))
            data.append(Self.newline)
        }
        try data.write(to: runJournalURL, options: .atomic)
        try synchronizeFile(at: runJournalURL)
        setRunHistoryCache(runs)
        journalEntryCount = runs.count
        try clearLegacyRunHistory()
    }

    private func clearLegacyRunHistory() throws {
        var document = try loadRawDocument()
        guard !document.runHistory.isEmpty else { return }
        document.runHistory = []
        try saveRawDocument(document)
    }

    private func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private func setRunHistoryCache(_ runs: [AutomationTaskRun]) {
        cachedRunHistory = runs
        cachedRunIndexByID = [:]
        for (index, run) in runs.enumerated() {
            cachedRunIndexByID[run.id] = index
        }
    }

    private func upsertCachedRun(_ run: AutomationTaskRun) {
        guard var runs = cachedRunHistory else {
            setRunHistoryCache([run])
            return
        }
        if let index = cachedRunIndexByID[run.id] {
            runs[index] = run
        } else {
            cachedRunIndexByID[run.id] = runs.count
            runs.append(run)
        }
        cachedRunHistory = runs
    }

    private func upsert(_ run: AutomationTaskRun, in runs: inout [AutomationTaskRun]) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
    }

    private var shouldCompactJournal: Bool {
        let runCount = max(1, cachedRunHistory?.count ?? 0)
        return journalEntryCount >= journalCompactionEntryFloor
            && journalEntryCount >= runCount * journalCompactionMultiplier
    }

    private static let newline: UInt8 = 0x0A

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }

    private static var journalEncoder: JSONEncoder {
        JSONEncoder()
    }

    private static var journalDecoder: JSONDecoder {
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
        if let index = runHistory.firstIndex(where: { $0.id == run.id }) {
            runHistory[index] = run
        } else {
            runHistory.append(run)
        }
    }

    public func replaceRunHistory(_ runs: [AutomationTaskRun]) {
        runHistory = runs
    }

    public func markRunRetentionPending(
        _ plan: AutomationRunRetentionPlan
    ) -> [AutomationTaskRun] {
        runHistory = AutomationRunRetentionPlanner.markPending(runs: runHistory, plan: plan)
        return runHistory
    }

    public func markRunRetentionApplied(
        _ plan: AutomationRunRetentionPlan,
        deletedRelativePathsByRunID: [UUID: [String]]
    ) -> [AutomationTaskRun] {
        runHistory = AutomationRunRetentionPlanner.markApplied(
            runs: runHistory,
            plan: plan,
            deletedRelativePathsByRunID: deletedRelativePathsByRunID
        )
        return runHistory
    }

    public func markRunScreenshotsDeleted(
        runIDs: Set<UUID>
    ) throws -> [AutomationTaskRun] {
        runHistory = try AutomationRunManualDeletionPlanner.markScreenshotsDeleted(
            runs: runHistory,
            runIDs: runIDs
        )
        return runHistory
    }
}

public struct AutomationRepositoryClient: Sendable {
    public var loadWorkflows: @Sendable () async throws -> [AutomationWorkflow]
    public var saveWorkflows: @Sendable (_ workflows: [AutomationWorkflow]) async throws -> Void
    public var loadRunHistory: @Sendable () async throws -> [AutomationTaskRun]
    public var appendRun: @Sendable (_ run: AutomationTaskRun) async throws -> Void
    public var replaceRunHistory: @Sendable (_ runs: [AutomationTaskRun]) async throws -> Void
    public var markRunRetentionPending: (@Sendable (_ plan: AutomationRunRetentionPlan) async throws -> [AutomationTaskRun])?
    public var markRunRetentionApplied: (@Sendable (
        _ plan: AutomationRunRetentionPlan,
        _ deletedRelativePathsByRunID: [UUID: [String]]
    ) async throws -> [AutomationTaskRun])?
    public var markRunScreenshotsDeleted: (@Sendable (
        _ runIDs: Set<UUID>
    ) async throws -> [AutomationTaskRun])?

    public init(
        loadWorkflows: @escaping @Sendable () async throws -> [AutomationWorkflow],
        saveWorkflows: @escaping @Sendable (_ workflows: [AutomationWorkflow]) async throws -> Void,
        loadRunHistory: @escaping @Sendable () async throws -> [AutomationTaskRun],
        appendRun: @escaping @Sendable (_ run: AutomationTaskRun) async throws -> Void,
        replaceRunHistory: @escaping @Sendable (_ runs: [AutomationTaskRun]) async throws -> Void = { _ in },
        markRunRetentionPending: (@Sendable (_ plan: AutomationRunRetentionPlan) async throws -> [AutomationTaskRun])? = nil,
        markRunRetentionApplied: (@Sendable (
            _ plan: AutomationRunRetentionPlan,
            _ deletedRelativePathsByRunID: [UUID: [String]]
        ) async throws -> [AutomationTaskRun])? = nil,
        markRunScreenshotsDeleted: (@Sendable (
            _ runIDs: Set<UUID>
        ) async throws -> [AutomationTaskRun])? = nil
    ) {
        self.loadWorkflows = loadWorkflows
        self.saveWorkflows = saveWorkflows
        self.loadRunHistory = loadRunHistory
        self.appendRun = appendRun
        self.replaceRunHistory = replaceRunHistory
        self.markRunRetentionPending = markRunRetentionPending
        self.markRunRetentionApplied = markRunRetentionApplied
        self.markRunScreenshotsDeleted = markRunScreenshotsDeleted
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
            },
            replaceRunHistory: { runs in
                try await repository.replaceRunHistory(runs)
            },
            markRunRetentionPending: { plan in
                try await repository.markRunRetentionPending(plan)
            },
            markRunRetentionApplied: { plan, deletedPaths in
                try await repository.markRunRetentionApplied(
                    plan,
                    deletedRelativePathsByRunID: deletedPaths
                )
            },
            markRunScreenshotsDeleted: { runIDs in
                try await repository.markRunScreenshotsDeleted(runIDs: runIDs)
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
            },
            replaceRunHistory: { runs in
                await store.replaceRunHistory(runs)
            },
            markRunRetentionPending: { plan in
                await store.markRunRetentionPending(plan)
            },
            markRunRetentionApplied: { plan, deletedPaths in
                await store.markRunRetentionApplied(
                    plan,
                    deletedRelativePathsByRunID: deletedPaths
                )
            },
            markRunScreenshotsDeleted: { runIDs in
                try await store.markRunScreenshotsDeleted(runIDs: runIDs)
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
