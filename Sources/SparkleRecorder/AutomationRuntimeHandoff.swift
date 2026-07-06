import Foundation

public enum AutomationRuntimeHandoffCommandKind: Codable, Equatable, Sendable {
    case manualStart(workflowID: UUID, taskID: UUID)
    case cancelRun(runID: UUID)
}

public struct AutomationRuntimeHandoffCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: AutomationRuntimeHandoffCommandKind
    public var requestedAt: Date
    public var source: String?

    public init(
        id: UUID = UUID(),
        kind: AutomationRuntimeHandoffCommandKind,
        requestedAt: Date = Date.now,
        source: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.requestedAt = requestedAt
        self.source = source
    }

    public var action: AutomationAction {
        switch kind {
        case .manualStart(let workflowID, let taskID):
            return .manualStart(
                workflowID: workflowID,
                taskID: taskID,
                requestedAt: requestedAt
            )
        case .cancelRun(let runID):
            return .cancelRun(runID: runID, at: requestedAt)
        }
    }
}

public enum AutomationRuntimeHandoffReceiptStatus: String, Codable, Equatable, Sendable {
    case dispatched
    case failed
}

public struct AutomationRuntimeHandoffReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { commandID }
    public var commandID: UUID
    public var commandKind: AutomationRuntimeHandoffCommandKind
    public var requestedAt: Date
    public var handledAt: Date
    public var status: AutomationRuntimeHandoffReceiptStatus
    public var runIDs: [UUID]
    public var message: String?
    public var source: String?

    public init(
        commandID: UUID,
        commandKind: AutomationRuntimeHandoffCommandKind,
        requestedAt: Date,
        handledAt: Date = Date.now,
        status: AutomationRuntimeHandoffReceiptStatus,
        runIDs: [UUID] = [],
        message: String? = nil,
        source: String? = nil
    ) {
        self.commandID = commandID
        self.commandKind = commandKind
        self.requestedAt = requestedAt
        self.handledAt = handledAt
        self.status = status
        self.runIDs = runIDs.sorted { $0.uuidString < $1.uuidString }
        self.message = message
        self.source = source
    }

    public init(
        command: AutomationRuntimeHandoffCommand,
        handledAt: Date = Date.now,
        status: AutomationRuntimeHandoffReceiptStatus,
        runIDs: [UUID] = [],
        message: String? = nil,
        source: String? = nil
    ) {
        self.init(
            commandID: command.id,
            commandKind: command.kind,
            requestedAt: command.requestedAt,
            handledAt: handledAt,
            status: status,
            runIDs: runIDs,
            message: message,
            source: source ?? command.source
        )
    }
}

public struct AutomationRuntimeHandoffMailboxDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var commands: [AutomationRuntimeHandoffCommand]
    public var receipts: [AutomationRuntimeHandoffReceipt]

    public init(
        version: Int = AutomationRuntimeHandoffMailbox.currentVersion,
        commands: [AutomationRuntimeHandoffCommand] = [],
        receipts: [AutomationRuntimeHandoffReceipt] = []
    ) {
        self.version = version
        self.commands = commands
        self.receipts = receipts
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case commands
        case receipts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.commands = try container.decodeIfPresent(
            [AutomationRuntimeHandoffCommand].self,
            forKey: .commands
        ) ?? []
        self.receipts = try container.decodeIfPresent(
            [AutomationRuntimeHandoffReceipt].self,
            forKey: .receipts
        ) ?? []
    }
}

public enum AutomationRuntimeHandoffMailbox {
    public static let currentVersion = 2
    public static let fileName = "automation-runtime-handoff.json"
    public static let maxReceiptCount = 200

    public static var defaultFileURL: URL {
        AutomationPersistence.defaultFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
    }

    public static func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    public static func normalizedCommands(
        _ commands: [AutomationRuntimeHandoffCommand]
    ) -> [AutomationRuntimeHandoffCommand] {
        var latestByID: [UUID: AutomationRuntimeHandoffCommand] = [:]
        for command in commands {
            latestByID[command.id] = command
        }
        return latestByID.values.sorted {
            if $0.requestedAt != $1.requestedAt {
                return $0.requestedAt < $1.requestedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public static func normalizedReceipts(
        _ receipts: [AutomationRuntimeHandoffReceipt],
        limit: Int = maxReceiptCount
    ) -> [AutomationRuntimeHandoffReceipt] {
        var latestByCommandID: [UUID: AutomationRuntimeHandoffReceipt] = [:]
        for receipt in receipts {
            let existing = latestByCommandID[receipt.commandID]
            if existing == nil ||
                receipt.handledAt > existing!.handledAt ||
                (
                    receipt.handledAt == existing!.handledAt &&
                        receipt.commandID.uuidString < existing!.commandID.uuidString
                ) {
                latestByCommandID[receipt.commandID] = receipt
            }
        }
        return latestByCommandID.values
            .sorted {
                if $0.handledAt != $1.handledAt {
                    return $0.handledAt > $1.handledAt
                }
                return $0.commandID.uuidString < $1.commandID.uuidString
            }
            .prefix(max(0, limit))
            .map { $0 }
    }
}

public actor AutomationRuntimeHandoffStore {
    public nonisolated let fileURL: URL

    public init(fileURL: URL = AutomationRuntimeHandoffMailbox.defaultFileURL) {
        self.fileURL = fileURL
    }

    public init(directoryURL: URL) {
        self.init(fileURL: AutomationRuntimeHandoffMailbox.fileURL(in: directoryURL))
    }

    public func loadDocument() throws -> AutomationRuntimeHandoffMailboxDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AutomationRuntimeHandoffMailboxDocument()
        }

        let data = try Data(contentsOf: fileURL)
        let document = try Self.decoder.decode(
            AutomationRuntimeHandoffMailboxDocument.self,
            from: data
        )
        guard document.version >= 1, document.version <= AutomationRuntimeHandoffMailbox.currentVersion else {
            return AutomationRuntimeHandoffMailboxDocument()
        }
        return AutomationRuntimeHandoffMailboxDocument(
            version: AutomationRuntimeHandoffMailbox.currentVersion,
            commands: AutomationRuntimeHandoffMailbox.normalizedCommands(document.commands),
            receipts: AutomationRuntimeHandoffMailbox.normalizedReceipts(document.receipts)
        )
    }

    public func saveDocument(_ document: AutomationRuntimeHandoffMailboxDocument) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let normalized = AutomationRuntimeHandoffMailboxDocument(
            version: AutomationRuntimeHandoffMailbox.currentVersion,
            commands: AutomationRuntimeHandoffMailbox.normalizedCommands(document.commands),
            receipts: AutomationRuntimeHandoffMailbox.normalizedReceipts(document.receipts)
        )
        let data = try Self.encoder.encode(normalized)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadCommands() throws -> [AutomationRuntimeHandoffCommand] {
        try loadDocument().commands
    }

    public func loadReceipts() throws -> [AutomationRuntimeHandoffReceipt] {
        try loadDocument().receipts
    }

    public func receipt(commandID: UUID) throws -> AutomationRuntimeHandoffReceipt? {
        try loadReceipts().first { $0.commandID == commandID }
    }

    @discardableResult
    public func enqueue(_ command: AutomationRuntimeHandoffCommand) throws -> AutomationRuntimeHandoffCommand {
        var document = try loadDocument()
        document.commands.removeAll { $0.id == command.id }
        document.commands.append(command)
        document.receipts.removeAll { $0.commandID == command.id }
        try saveDocument(document)
        return command
    }

    public func removeCommands(ids: Set<UUID>) throws {
        guard !ids.isEmpty else {
            return
        }
        var document = try loadDocument()
        document.commands.removeAll { ids.contains($0.id) }
        try saveDocument(document)
    }

    public func recordReceipt(_ receipt: AutomationRuntimeHandoffReceipt) throws {
        var document = try loadDocument()
        document.receipts.removeAll { $0.commandID == receipt.commandID }
        document.receipts.append(receipt)
        try saveDocument(document)
    }

    public func completeCommand(receipt: AutomationRuntimeHandoffReceipt) throws {
        var document = try loadDocument()
        document.commands.removeAll { $0.id == receipt.commandID }
        document.receipts.removeAll { $0.commandID == receipt.commandID }
        document.receipts.append(receipt)
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

public actor AutomationInMemoryRuntimeHandoffStore {
    private var commands: [AutomationRuntimeHandoffCommand]
    private var receipts: [AutomationRuntimeHandoffReceipt]

    public init(
        commands: [AutomationRuntimeHandoffCommand] = [],
        receipts: [AutomationRuntimeHandoffReceipt] = []
    ) {
        self.commands = AutomationRuntimeHandoffMailbox.normalizedCommands(commands)
        self.receipts = AutomationRuntimeHandoffMailbox.normalizedReceipts(receipts)
    }

    public func loadCommands() -> [AutomationRuntimeHandoffCommand] {
        AutomationRuntimeHandoffMailbox.normalizedCommands(commands)
    }

    public func loadReceipts() -> [AutomationRuntimeHandoffReceipt] {
        AutomationRuntimeHandoffMailbox.normalizedReceipts(receipts)
    }

    public func receipt(commandID: UUID) -> AutomationRuntimeHandoffReceipt? {
        loadReceipts().first { $0.commandID == commandID }
    }

    @discardableResult
    public func enqueue(_ command: AutomationRuntimeHandoffCommand) -> AutomationRuntimeHandoffCommand {
        commands.removeAll { $0.id == command.id }
        commands.append(command)
        commands = AutomationRuntimeHandoffMailbox.normalizedCommands(commands)
        receipts.removeAll { $0.commandID == command.id }
        return command
    }

    public func removeCommands(ids: Set<UUID>) {
        commands.removeAll { ids.contains($0.id) }
    }

    public func recordReceipt(_ receipt: AutomationRuntimeHandoffReceipt) {
        receipts.removeAll { $0.commandID == receipt.commandID }
        receipts.append(receipt)
        receipts = AutomationRuntimeHandoffMailbox.normalizedReceipts(receipts)
    }

    public func completeCommand(receipt: AutomationRuntimeHandoffReceipt) {
        commands.removeAll { $0.id == receipt.commandID }
        recordReceipt(receipt)
    }
}

public struct AutomationRuntimeHandoffClient: Sendable {
    public var enqueue: @Sendable (
        _ command: AutomationRuntimeHandoffCommand
    ) async throws -> AutomationRuntimeHandoffCommand
    public var loadCommands: @Sendable () async throws -> [AutomationRuntimeHandoffCommand]
    public var loadReceipts: @Sendable () async throws -> [AutomationRuntimeHandoffReceipt]
    public var receipt: @Sendable (_ commandID: UUID) async throws -> AutomationRuntimeHandoffReceipt?
    public var removeCommands: @Sendable (_ ids: Set<UUID>) async throws -> Void
    public var recordReceipt: @Sendable (_ receipt: AutomationRuntimeHandoffReceipt) async throws -> Void
    public var completeCommand: @Sendable (_ receipt: AutomationRuntimeHandoffReceipt) async throws -> Void

    public init(
        enqueue: @escaping @Sendable (
            _ command: AutomationRuntimeHandoffCommand
        ) async throws -> AutomationRuntimeHandoffCommand,
        loadCommands: @escaping @Sendable () async throws -> [AutomationRuntimeHandoffCommand],
        loadReceipts: @escaping @Sendable () async throws -> [AutomationRuntimeHandoffReceipt],
        receipt: @escaping @Sendable (_ commandID: UUID) async throws -> AutomationRuntimeHandoffReceipt?,
        removeCommands: @escaping @Sendable (_ ids: Set<UUID>) async throws -> Void,
        recordReceipt: @escaping @Sendable (_ receipt: AutomationRuntimeHandoffReceipt) async throws -> Void,
        completeCommand: @escaping @Sendable (_ receipt: AutomationRuntimeHandoffReceipt) async throws -> Void
    ) {
        self.enqueue = enqueue
        self.loadCommands = loadCommands
        self.loadReceipts = loadReceipts
        self.receipt = receipt
        self.removeCommands = removeCommands
        self.recordReceipt = recordReceipt
        self.completeCommand = completeCommand
    }

    public static func fileBacked(
        fileURL: URL = AutomationRuntimeHandoffMailbox.defaultFileURL
    ) -> AutomationRuntimeHandoffClient {
        let store = AutomationRuntimeHandoffStore(fileURL: fileURL)
        return AutomationRuntimeHandoffClient(
            enqueue: { command in try await store.enqueue(command) },
            loadCommands: { try await store.loadCommands() },
            loadReceipts: { try await store.loadReceipts() },
            receipt: { commandID in try await store.receipt(commandID: commandID) },
            removeCommands: { ids in try await store.removeCommands(ids: ids) },
            recordReceipt: { receipt in try await store.recordReceipt(receipt) },
            completeCommand: { receipt in try await store.completeCommand(receipt: receipt) }
        )
    }

    public static func fileBacked(directoryURL: URL) -> AutomationRuntimeHandoffClient {
        fileBacked(fileURL: AutomationRuntimeHandoffMailbox.fileURL(in: directoryURL))
    }

    public static func inMemory(
        store: AutomationInMemoryRuntimeHandoffStore = AutomationInMemoryRuntimeHandoffStore()
    ) -> AutomationRuntimeHandoffClient {
        AutomationRuntimeHandoffClient(
            enqueue: { command in await store.enqueue(command) },
            loadCommands: { await store.loadCommands() },
            loadReceipts: { await store.loadReceipts() },
            receipt: { commandID in await store.receipt(commandID: commandID) },
            removeCommands: { ids in await store.removeCommands(ids: ids) },
            recordReceipt: { receipt in await store.recordReceipt(receipt) },
            completeCommand: { receipt in await store.completeCommand(receipt: receipt) }
        )
    }
}
