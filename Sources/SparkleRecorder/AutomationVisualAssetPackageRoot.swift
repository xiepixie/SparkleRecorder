import Foundation

public enum AutomationVisualAssetPackageRootSource: String, Codable, Equatable, Sendable {
    case aiDraftImport
    case workflowPackageImport
    case manual
}

public struct AutomationVisualAssetPackageRoot: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var packageDirectoryPath: String
    public var source: AutomationVisualAssetPackageRootSource
    public var associatedAt: Date

    public init(
        workflowID: UUID,
        packageDirectoryPath: String,
        source: AutomationVisualAssetPackageRootSource = .manual,
        associatedAt: Date = Date.now
    ) {
        self.workflowID = workflowID
        self.packageDirectoryPath = packageDirectoryPath
        self.source = source
        self.associatedAt = associatedAt
    }

    public var packageDirectoryURL: URL {
        URL(fileURLWithPath: packageDirectoryPath, isDirectory: true)
    }

    public static func roots(
        for workflows: [AutomationWorkflow],
        packageDirectoryURL: URL,
        source: AutomationVisualAssetPackageRootSource,
        associatedAt: Date = Date.now
    ) -> [AutomationVisualAssetPackageRoot] {
        guard let packageDirectoryPath = AutomationVisualAssetPackageRoots.normalizedPackageDirectoryPath(
            packageDirectoryURL
        ) else {
            return []
        }

        return workflows.compactMap { workflow in
            guard workflow.visualAssets?.hasPackageFileAssets == true else {
                return nil
            }
            return AutomationVisualAssetPackageRoot(
                workflowID: workflow.id,
                packageDirectoryPath: packageDirectoryPath,
                source: source,
                associatedAt: associatedAt
            )
        }
    }
}

public struct AutomationVisualAssetPackageRootDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var roots: [AutomationVisualAssetPackageRoot]

    public init(
        version: Int = AutomationVisualAssetPackageRoots.currentVersion,
        roots: [AutomationVisualAssetPackageRoot] = []
    ) {
        self.version = version
        self.roots = roots
    }
}

public enum AutomationVisualAssetPackageRoots {
    public static let currentVersion = 1
    public static let fileName = "automation-visual-asset-roots.json"

    public static var defaultFileURL: URL {
        AutomationPersistence.defaultFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
    }

    public static func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    public static func normalizedPackageDirectoryPath(_ url: URL) -> String? {
        guard url.isFileURL else {
            return nil
        }
        return url.standardizedFileURL.path
    }

    public static func normalizedRoots(
        _ roots: [AutomationVisualAssetPackageRoot]
    ) -> [AutomationVisualAssetPackageRoot] {
        var latestByWorkflowID: [UUID: AutomationVisualAssetPackageRoot] = [:]
        for root in roots {
            guard !root.packageDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            latestByWorkflowID[root.workflowID] = root
        }
        return latestByWorkflowID.values.sorted {
            $0.workflowID.uuidString < $1.workflowID.uuidString
        }
    }
}

public extension AutomationWorkflowDraftVisualAssets {
    var hasPackageFileAssets: Bool {
        !images.isEmpty || !baselines.isEmpty
    }
}

public actor AutomationVisualAssetPackageRootStore {
    public nonisolated let fileURL: URL

    public init(fileURL: URL = AutomationVisualAssetPackageRoots.defaultFileURL) {
        self.fileURL = fileURL
    }

    public init(directoryURL: URL) {
        self.init(fileURL: AutomationVisualAssetPackageRoots.fileURL(in: directoryURL))
    }

    public func loadDocument() throws -> AutomationVisualAssetPackageRootDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AutomationVisualAssetPackageRootDocument()
        }

        let data = try Data(contentsOf: fileURL)
        let document = try Self.decoder.decode(
            AutomationVisualAssetPackageRootDocument.self,
            from: data
        )
        guard document.version == AutomationVisualAssetPackageRoots.currentVersion else {
            return AutomationVisualAssetPackageRootDocument()
        }
        return AutomationVisualAssetPackageRootDocument(
            version: document.version,
            roots: AutomationVisualAssetPackageRoots.normalizedRoots(document.roots)
        )
    }

    public func saveDocument(_ document: AutomationVisualAssetPackageRootDocument) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let normalized = AutomationVisualAssetPackageRootDocument(
            version: AutomationVisualAssetPackageRoots.currentVersion,
            roots: AutomationVisualAssetPackageRoots.normalizedRoots(document.roots)
        )
        let data = try Self.encoder.encode(normalized)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadRoots() throws -> [AutomationVisualAssetPackageRoot] {
        try loadDocument().roots
    }

    public func saveRoots(_ roots: [AutomationVisualAssetPackageRoot]) throws {
        try saveDocument(AutomationVisualAssetPackageRootDocument(roots: roots))
    }

    public func upsertRoots(_ roots: [AutomationVisualAssetPackageRoot]) throws {
        guard !roots.isEmpty else {
            return
        }
        var existing = try loadRoots()
        let replacementIDs = Set(roots.map(\.workflowID))
        existing.removeAll { replacementIDs.contains($0.workflowID) }
        existing.append(contentsOf: roots)
        try saveRoots(existing)
    }

    public func removeRoots(workflowIDs: Set<UUID>) throws {
        guard !workflowIDs.isEmpty else {
            return
        }
        let remaining = try loadRoots().filter { !workflowIDs.contains($0.workflowID) }
        try saveRoots(remaining)
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

public actor AutomationInMemoryVisualAssetPackageRootStore {
    private var roots: [AutomationVisualAssetPackageRoot]

    public init(roots: [AutomationVisualAssetPackageRoot] = []) {
        self.roots = AutomationVisualAssetPackageRoots.normalizedRoots(roots)
    }

    public func loadRoots() -> [AutomationVisualAssetPackageRoot] {
        roots
    }

    public func saveRoots(_ roots: [AutomationVisualAssetPackageRoot]) {
        self.roots = AutomationVisualAssetPackageRoots.normalizedRoots(roots)
    }

    public func upsertRoots(_ roots: [AutomationVisualAssetPackageRoot]) {
        let replacementIDs = Set(roots.map(\.workflowID))
        self.roots.removeAll { replacementIDs.contains($0.workflowID) }
        self.roots.append(contentsOf: roots)
        self.roots = AutomationVisualAssetPackageRoots.normalizedRoots(self.roots)
    }

    public func removeRoots(workflowIDs: Set<UUID>) {
        roots.removeAll { workflowIDs.contains($0.workflowID) }
    }
}

public struct AutomationVisualAssetPackageRootClient: Sendable {
    public var loadRoots: @Sendable () async throws -> [AutomationVisualAssetPackageRoot]
    public var saveRoots: @Sendable (_ roots: [AutomationVisualAssetPackageRoot]) async throws -> Void
    public var upsertRoots: @Sendable (_ roots: [AutomationVisualAssetPackageRoot]) async throws -> Void
    public var removeRoots: @Sendable (_ workflowIDs: Set<UUID>) async throws -> Void

    public init(
        loadRoots: @escaping @Sendable () async throws -> [AutomationVisualAssetPackageRoot],
        saveRoots: @escaping @Sendable (_ roots: [AutomationVisualAssetPackageRoot]) async throws -> Void,
        upsertRoots: @escaping @Sendable (_ roots: [AutomationVisualAssetPackageRoot]) async throws -> Void,
        removeRoots: @escaping @Sendable (_ workflowIDs: Set<UUID>) async throws -> Void
    ) {
        self.loadRoots = loadRoots
        self.saveRoots = saveRoots
        self.upsertRoots = upsertRoots
        self.removeRoots = removeRoots
    }

    public static func fileBacked(
        fileURL: URL = AutomationVisualAssetPackageRoots.defaultFileURL
    ) -> AutomationVisualAssetPackageRootClient {
        let store = AutomationVisualAssetPackageRootStore(fileURL: fileURL)
        return AutomationVisualAssetPackageRootClient(
            loadRoots: {
                try await store.loadRoots()
            },
            saveRoots: { roots in
                try await store.saveRoots(roots)
            },
            upsertRoots: { roots in
                try await store.upsertRoots(roots)
            },
            removeRoots: { workflowIDs in
                try await store.removeRoots(workflowIDs: workflowIDs)
            }
        )
    }

    public static func fileBacked(directoryURL: URL) -> AutomationVisualAssetPackageRootClient {
        fileBacked(fileURL: AutomationVisualAssetPackageRoots.fileURL(in: directoryURL))
    }

    public static func inMemory(
        store: AutomationInMemoryVisualAssetPackageRootStore = AutomationInMemoryVisualAssetPackageRootStore()
    ) -> AutomationVisualAssetPackageRootClient {
        AutomationVisualAssetPackageRootClient(
            loadRoots: {
                await store.loadRoots()
            },
            saveRoots: { roots in
                await store.saveRoots(roots)
            },
            upsertRoots: { roots in
                await store.upsertRoots(roots)
            },
            removeRoots: { workflowIDs in
                await store.removeRoots(workflowIDs: workflowIDs)
            }
        )
    }
}
