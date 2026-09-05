import Foundation
import SparkleRecorderCore

struct AutomationRunRetentionCleanupPreview: Equatable, Sendable {
    var plan: AutomationRunRetentionPlan
    var estimatedByteCount: Int64

    var isEmpty: Bool { plan.items.isEmpty }
    var artifactRunCount: Int { plan.artifactRunCount }
    var metadataRunCount: Int { plan.metadataRunCount }
}

struct AutomationRunRetentionCleanupResult: Equatable, Sendable {
    var prunedArtifactRunCount: Int
    var deletedMetadataRunCount: Int
    var deletedRelativePaths: [String]
}

struct AutomationRunStorageBreakdown: Equatable, Sendable {
    var reportByteCount: Int64 = 0
    var screenshotByteCount: Int64 = 0
    var conditionEvidenceByteCount: Int64 = 0
    var otherEvidenceByteCount: Int64 = 0

    var evidenceByteCount: Int64 {
        reportByteCount + screenshotByteCount + conditionEvidenceByteCount + otherEvidenceByteCount
    }
}

struct AutomationRunStorageUsage: Equatable, Sendable {
    var breakdown: AutomationRunStorageBreakdown
    var historyByteCount: Int64
    var runCount: Int
    var executionBreakdowns: [UUID: AutomationRunStorageBreakdown]

    var totalByteCount: Int64 { breakdown.evidenceByteCount + historyByteCount }

    func breakdown(for executionID: UUID) -> AutomationRunStorageBreakdown {
        executionBreakdowns[executionID] ?? AutomationRunStorageBreakdown()
    }
}

struct AutomationRunManualDeletionPreview: Equatable, Sendable {
    var scope: AutomationRunManualDeletionScope
    var runIDs: Set<UUID>
    var plan: AutomationRunRetentionPlan?
    var breakdown: AutomationRunStorageBreakdown

    var runCount: Int { runIDs.count }
    var estimatedByteCount: Int64 {
        scope == .screenshots ? breakdown.screenshotByteCount : breakdown.evidenceByteCount
    }
}

struct AutomationRunManualDeletionResult: Equatable, Sendable {
    var scope: AutomationRunManualDeletionScope
    var affectedRunCount: Int
    var freedByteCount: Int64
}

enum AutomationRunRetentionStoreError: Error, LocalizedError, Equatable {
    case repositoryDoesNotSupportAtomicRetention
    case repositoryDoesNotSupportScreenshotMutation
    case unsafeArtifactPath(String)
    case activeRunsCannotBeDeleted
    case runsNoLongerAvailable

    var errorDescription: String? {
        switch self {
        case .repositoryDoesNotSupportAtomicRetention:
            return "The run repository does not support atomic retention updates."
        case .repositoryDoesNotSupportScreenshotMutation:
            return "The run repository does not support screenshot updates."
        case .unsafeArtifactPath(let path):
            return "Refused to delete an unsafe run artifact path: \(path)"
        case .activeRunsCannotBeDeleted:
            return "Running executions cannot be deleted. Stop the run first."
        case .runsNoLongerAvailable:
            return "The selected run history changed. Refresh and try again."
        }
    }
}

actor AutomationRunRetentionStore {
    private let repository: AutomationRepositoryClient
    private let supportDirectory: URL
    private let fileManager: FileManager

    init(
        repository: AutomationRepositoryClient = .fileBacked(),
        supportDirectory: URL = AutomationPersistence.defaultFileURL.deletingLastPathComponent(),
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.supportDirectory = supportDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func preview(
        settings: AutomationRunRetentionSettings,
        evaluatedAt: Date = Date()
    ) async throws -> AutomationRunRetentionCleanupPreview {
        let runs = try await repository.loadRunHistory()
        let plan = AutomationRunRetentionPlanner.plan(
            runs: runs,
            settings: settings,
            evaluatedAt: evaluatedAt
        )
        let urls = try plan.items.flatMap(artifactURLs(for:))
        return AutomationRunRetentionCleanupPreview(
            plan: plan,
            estimatedByteCount: urls.reduce(0) { $0 + allocatedSize(of: $1) }
        )
    }

    func storageUsage() async throws -> AutomationRunStorageUsage {
        let runs = try await repository.loadRunHistory()
        var executions: [UUID: AutomationRunStorageBreakdown] = [:]
        var countedURLsByExecution: [UUID: Set<URL>] = [:]

        for run in runs {
            let inventory = try artifactInventory(for: run)
            var execution = executions[run.executionID] ?? AutomationRunStorageBreakdown()
            for item in inventory {
                let url = item.url.standardizedFileURL
                guard countedURLsByExecution[run.executionID, default: []].insert(url).inserted else {
                    continue
                }
                let size = allocatedSize(of: item.url)
                apply(size: size, category: item.category, to: &execution)
            }
            executions[run.executionID] = execution
        }

        var total = AutomationRunStorageBreakdown()
        for item in wholeStoreInventory() {
            apply(size: allocatedSize(of: item.url), category: item.category, to: &total)
        }

        return AutomationRunStorageUsage(
            breakdown: total,
            historyByteCount: allocatedSize(of: AutomationPersistence.runJournalURL(
                for: supportDirectory.appendingPathComponent("automations.json")
            )),
            runCount: runs.count,
            executionBreakdowns: executions
        )
    }

    func manualDeletionPreview(
        runIDs: Set<UUID>,
        scope: AutomationRunManualDeletionScope,
        evaluatedAt: Date = Date()
    ) async throws -> AutomationRunManualDeletionPreview {
        let runs = try await repository.loadRunHistory()
        let selected: [AutomationTaskRun]
        do {
            selected = try AutomationRunManualDeletionPlanner.validatedRuns(
                runs: runs,
                runIDs: runIDs
            )
        } catch AutomationRunManualDeletionValidationError.activeRuns {
            throw AutomationRunRetentionStoreError.activeRunsCannotBeDeleted
        } catch {
            throw AutomationRunRetentionStoreError.runsNoLongerAvailable
        }

        var breakdown = AutomationRunStorageBreakdown()
        var countedURLs = Set<URL>()
        for run in selected {
            for item in try artifactInventory(for: run) {
                guard countedURLs.insert(item.url.standardizedFileURL).inserted else { continue }
                apply(size: allocatedSize(of: item.url), category: item.category, to: &breakdown)
            }
        }
        let plan = scope == .screenshots ? nil : try AutomationRunManualDeletionPlanner.plan(
            runs: runs,
            runIDs: runIDs,
            scope: scope,
            evaluatedAt: evaluatedAt
        )
        return AutomationRunManualDeletionPreview(
            scope: scope,
            runIDs: runIDs,
            plan: plan,
            breakdown: breakdown
        )
    }

    func applyManualDeletion(
        _ preview: AutomationRunManualDeletionPreview
    ) async throws -> AutomationRunManualDeletionResult {
        switch preview.scope {
        case .screenshots:
            guard let markDeleted = repository.markRunScreenshotsDeleted else {
                throw AutomationRunRetentionStoreError.repositoryDoesNotSupportScreenshotMutation
            }
            let runs = try await repository.loadRunHistory()
            let selected: [AutomationTaskRun]
            do {
                selected = try AutomationRunManualDeletionPlanner.validatedRuns(
                    runs: runs,
                    runIDs: preview.runIDs
                )
            } catch AutomationRunManualDeletionValidationError.activeRuns {
                throw AutomationRunRetentionStoreError.activeRunsCannotBeDeleted
            } catch {
                throw AutomationRunRetentionStoreError.runsNoLongerAvailable
            }
            for run in selected {
                for item in try artifactInventory(for: run) where item.category == .screenshot {
                    _ = try safeRelativePath(for: item.url, permitsFile: true)
                    if fileManager.fileExists(atPath: item.url.path) {
                        try fileManager.removeItem(at: item.url)
                    }
                }
            }
            _ = try await markDeleted(preview.runIDs)
            return AutomationRunManualDeletionResult(
                scope: .screenshots,
                affectedRunCount: preview.runCount,
                freedByteCount: preview.estimatedByteCount
            )

        case .evidence, .history:
            guard let originalPlan = preview.plan else {
                throw AutomationRunRetentionStoreError.runsNoLongerAvailable
            }
            let runs = try await repository.loadRunHistory()
            let plan: AutomationRunRetentionPlan
            do {
                plan = try AutomationRunManualDeletionPlanner.plan(
                    runs: runs,
                    runIDs: preview.runIDs,
                    scope: preview.scope,
                    evaluatedAt: originalPlan.evaluatedAt
                )
            } catch AutomationRunManualDeletionValidationError.activeRuns {
                throw AutomationRunRetentionStoreError.activeRunsCannotBeDeleted
            } catch {
                throw AutomationRunRetentionStoreError.runsNoLongerAvailable
            }
            _ = try await apply(AutomationRunRetentionCleanupPreview(
                plan: plan,
                estimatedByteCount: preview.estimatedByteCount
            ))
            return AutomationRunManualDeletionResult(
                scope: preview.scope,
                affectedRunCount: preview.runCount,
                freedByteCount: preview.estimatedByteCount
            )
        }
    }

    func apply(
        _ preview: AutomationRunRetentionCleanupPreview
    ) async throws -> AutomationRunRetentionCleanupResult {
        guard let markPending = repository.markRunRetentionPending,
              let markApplied = repository.markRunRetentionApplied else {
            throw AutomationRunRetentionStoreError.repositoryDoesNotSupportAtomicRetention
        }

        _ = try await markPending(preview.plan)

        var deletedPathsByRunID: [UUID: [String]] = [:]
        for item in preview.plan.items where !item.artifactKinds.isEmpty {
            for url in try artifactURLs(for: item) {
                let relativePath = try safeRelativePath(for: url)
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                deletedPathsByRunID[item.runID, default: []].append(relativePath)
            }
        }

        _ = try await markApplied(preview.plan, deletedPathsByRunID)
        return AutomationRunRetentionCleanupResult(
            prunedArtifactRunCount: preview.plan.artifactRunCount,
            deletedMetadataRunCount: preview.plan.metadataRunCount,
            deletedRelativePaths: deletedPathsByRunID.values.flatMap { $0 }.sorted()
        )
    }

    private enum StorageCategory {
        case report
        case screenshot
        case conditionEvidence
        case otherEvidence
    }

    private struct StorageItem {
        var url: URL
        var category: StorageCategory
    }

    private func artifactInventory(for run: AutomationTaskRun) throws -> [StorageItem] {
        var items: [StorageItem] = []
        if let macroID = run.macroID,
           let evidenceID = run.evidenceID ?? run.artifactRetention?.originalEvidenceID {
            let directory = supportDirectory
                .appendingPathComponent("Macros", isDirectory: true)
                .appendingPathComponent("\(macroID.uuidString).sparkrec", isDirectory: true)
                .appendingPathComponent("runs", isDirectory: true)
                .appendingPathComponent(evidenceID.uuidString, isDirectory: true)
            _ = try safeRelativePath(for: directory)
            if let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                items += children.map { url in
                    let category: StorageCategory
                    switch url.lastPathComponent {
                    case "report.json": category = .report
                    case "failure.png": category = .screenshot
                    default: category = .otherEvidence
                    }
                    return StorageItem(url: url, category: category)
                }
            }
        }
        let conditionDirectory = supportDirectory
            .appendingPathComponent("AutomationEvidence", isDirectory: true)
            .appendingPathComponent(run.id.uuidString, isDirectory: true)
        _ = try safeRelativePath(for: conditionDirectory)
        if fileManager.fileExists(atPath: conditionDirectory.path) {
            items.append(StorageItem(url: conditionDirectory, category: .conditionEvidence))
        }
        return items
    }

    private func wholeStoreInventory() -> [StorageItem] {
        let macroRoot = supportDirectory.appendingPathComponent("Macros", isDirectory: true)
        let conditionRoot = supportDirectory.appendingPathComponent("AutomationEvidence", isDirectory: true)
        var items: [StorageItem] = []

        if let enumerator = fileManager.enumerator(
            at: macroRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                let relative = url.standardizedFileURL.path
                    .dropFirst(macroRoot.standardizedFileURL.path.count)
                let components = relative.split(separator: "/")
                guard components.count == 4,
                      components[0].hasSuffix(".sparkrec"),
                      components[1] == "runs",
                      UUID(uuidString: String(components[2])) != nil else { continue }
                let category: StorageCategory
                switch components[3] {
                case "report.json": category = .report
                case "failure.png": category = .screenshot
                default: category = .otherEvidence
                }
                items.append(StorageItem(url: url, category: category))
            }
        }

        if let enumerator = fileManager.enumerator(
            at: conditionRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                items.append(StorageItem(url: url, category: .conditionEvidence))
            }
        }
        return items
    }

    private func apply(
        size: Int64,
        category: StorageCategory,
        to breakdown: inout AutomationRunStorageBreakdown
    ) {
        switch category {
        case .report: breakdown.reportByteCount += size
        case .screenshot: breakdown.screenshotByteCount += size
        case .conditionEvidence: breakdown.conditionEvidenceByteCount += size
        case .otherEvidence: breakdown.otherEvidenceByteCount += size
        }
    }

    private func artifactURLs(for item: AutomationRunRetentionPlanItem) throws -> [URL] {
        var urls: [URL] = []
        if item.artifactKinds.contains(.macroRunEvidence),
           let macroID = item.macroID,
           let evidenceID = item.evidenceID {
            urls.append(
                supportDirectory
                    .appendingPathComponent("Macros", isDirectory: true)
                    .appendingPathComponent("\(macroID.uuidString).sparkrec", isDirectory: true)
                    .appendingPathComponent("runs", isDirectory: true)
                    .appendingPathComponent(evidenceID.uuidString, isDirectory: true)
            )
        }
        if item.artifactKinds.contains(.conditionEvidence) {
            urls.append(
                supportDirectory
                    .appendingPathComponent("AutomationEvidence", isDirectory: true)
                    .appendingPathComponent(item.runID.uuidString, isDirectory: true)
            )
        }
        for url in urls {
            _ = try safeRelativePath(for: url)
        }
        return urls
    }

    private func safeRelativePath(for url: URL, permitsFile: Bool = false) throws -> String {
        let rootPath = supportDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw AutomationRunRetentionStoreError.unsafeArtifactPath(candidatePath)
        }

        let relativePath = String(candidatePath.dropFirst(rootPath.count + 1))
        let components = relativePath.split(separator: "/").map(String.init)
        let isMacroEvidence = components.count == 4
            && components[0] == "Macros"
            && components[1].hasSuffix(".sparkrec")
            && components[2] == "runs"
            && UUID(uuidString: components[3]) != nil
        let isConditionEvidence = components.count == 2
            && components[0] == "AutomationEvidence"
            && UUID(uuidString: components[1]) != nil
        let isMacroEvidenceFile = permitsFile
            && components.count == 5
            && components[0] == "Macros"
            && components[1].hasSuffix(".sparkrec")
            && components[2] == "runs"
            && UUID(uuidString: components[3]) != nil
            && ["report.json", "manifest.json", "failure.png"].contains(components[4])
        guard isMacroEvidence || isConditionEvidence || isMacroEvidenceFile else {
            throw AutomationRunRetentionStoreError.unsafeArtifactPath(relativePath)
        }
        return relativePath
    }

    private func allocatedSize(of url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            guard let values = try? childURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
