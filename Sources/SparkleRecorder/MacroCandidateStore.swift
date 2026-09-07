import Foundation
import SparkleRecorderCore

public enum MacroCandidateImportSource: String, Codable, Equatable, Sendable {
    case standaloneCandidate
    case reconstructionPackage
}

public struct MacroCandidateImportProvenance: Codable, Equatable, Sendable {
    public var source: MacroCandidateImportSource
    public var packageVersion: String?
    public var contractVersion: String? = nil
    public var harnessVersion: String? = nil
    public var authoringContractVersion: String? = nil
    public var packageSourceRevision: String?
    public var capabilityVersion: String?
    public var authoringPolicyVersion: String?
    public var sourceContextVersion: String? = nil
    public var actionContextVersion: String? = nil
    public var candidateActionRevision: String? = nil
    public var objective: MacroReconstructionObjective?
    public var visualEvidenceIncluded: Bool?
    public var mechanicalEvidenceIncluded: Bool?
    public var sourceEventsMatchRecording: Bool?
    public var artifactCount: Int?
    public var warnings: [String]

    public static let standalone = MacroCandidateImportProvenance(
        source: .standaloneCandidate,
        packageVersion: nil,
        contractVersion: nil,
        harnessVersion: nil,
        authoringContractVersion: nil,
        packageSourceRevision: nil,
        capabilityVersion: nil,
        authoringPolicyVersion: nil,
        sourceContextVersion: nil,
        actionContextVersion: nil,
        candidateActionRevision: nil,
        objective: nil,
        visualEvidenceIncluded: nil,
        mechanicalEvidenceIncluded: nil,
        sourceEventsMatchRecording: nil,
        artifactCount: nil,
        warnings: []
    )
}

public enum MacroCandidateAuthoringOrigin: String, Codable, Equatable, Sendable {
    case externalAuthoring
    case localCandidateEditor

    var surfaceAuthority: MacroCandidatePlaybackSurfaceAuthority {
        switch self {
        case .externalAuthoring: .sourceRevision
        case .localCandidateEditor: .appOwnedRebinding
        }
    }
}

public struct MacroStoredCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let document: MacroCandidateDocument
    public let macro: SavedMacro
    public let normalizedDigest: String
    public let createdAt: Date
    public let authoringOrigin: MacroCandidateAuthoringOrigin
    let importProvenance: MacroCandidateImportProvenance?

    init(
        id: UUID,
        document: MacroCandidateDocument,
        macro: SavedMacro,
        normalizedDigest: String,
        createdAt: Date,
        authoringOrigin: MacroCandidateAuthoringOrigin,
        importProvenance: MacroCandidateImportProvenance? = nil
    ) {
        self.id = id
        self.document = document
        self.macro = macro
        self.normalizedDigest = normalizedDigest
        self.createdAt = createdAt
        self.authoringOrigin = authoringOrigin
        self.importProvenance = importProvenance
    }

    private enum CodingKeys: String, CodingKey {
        case id, document, macro, normalizedDigest, createdAt, authoringOrigin, importProvenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        document = try container.decode(MacroCandidateDocument.self, forKey: .document)
        macro = try container.decode(SavedMacro.self, forKey: .macro)
        normalizedDigest = try container.decode(String.self, forKey: .normalizedDigest)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        authoringOrigin = try container.decodeIfPresent(MacroCandidateAuthoringOrigin.self, forKey: .authoringOrigin)
            ?? .externalAuthoring
        importProvenance = try container.decodeIfPresent(MacroCandidateImportProvenance.self, forKey: .importProvenance)
    }
}

/// Issued only by the repository for a pinned normal-playback test. Not decodable from CLI input.
public struct MacroCandidateTestRun: Sendable {
    public let token: UUID
    public let candidateID: UUID
    public let macroID: UUID
    public let macro: SavedMacro
    public let normalizedDigest: String
    public let executionDigest: String
    public static let policyVersion = "single-iteration/v1"
    static func executionMacro(for macro: SavedMacro) -> SavedMacro {
        var result = macro
        result.loops = 1
        result.chainTo = nil
        return result
    }
    fileprivate init(candidate: MacroStoredCandidate) throws {
        token = UUID()
        candidateID = candidate.id
        macroID = candidate.macro.id
        macro = Self.executionMacro(for: candidate.macro)
        executionDigest = try MacroCandidateIdentity.revision(of: macro)
        normalizedDigest = candidate.normalizedDigest
    }
}

public enum MacroCandidateStoreError: Error, LocalizedError, Equatable, Sendable {
    case staleSource
    case testRequired
    case invalidTestToken
    case candidateIntegrityMismatch
    case confirmationRequired
    case noOriginalRevision
    case injectedPublicationFailure

    public var errorDescription: String? {
        switch self {
        case .staleSource:
            String(localized: "This candidate was generated from an older macro revision. Export the current reconstruction package and generate a new candidate.", table: "EditorUX")
        case .testRequired:
            String(localized: "Complete a successful playback test of this candidate before accepting it.", table: "EditorUX")
        case .invalidTestToken:
            String(localized: "This candidate test has expired or already finished. Start a new test.", table: "EditorUX")
        case .candidateIntegrityMismatch:
            String(localized: "The candidate content no longer matches its saved revision. Import and test a new candidate.", table: "EditorUX")
        case .confirmationRequired:
            String(localized: "Review and acknowledge the candidate's unresolved actions before accepting it.", table: "EditorUX")
        case .noOriginalRevision:
            String(localized: "This macro has no retained original revision to restore.", table: "EditorUX")
        case .injectedPublicationFailure:
            String(localized: "Revision publication was interrupted. Reload the macro to inspect its accepted revision.", table: "EditorUX")
        }
    }
}

enum MacroCandidatePublicationFault: Equatable, Sendable { case beforePointer, afterPointer }

/// Disk IO remains at the app edge. UUID filenames are locally generated; no model path is used.
struct MacroCandidateStore {
    let package: URL
    private var directory: URL { package.appendingPathComponent("reconstruction", isDirectory: true) }
    private var pointerURL: URL { directory.appendingPathComponent("accepted.json") }
    private struct Pointer: Codable { let revisionID: UUID }
    private struct Receipt: Codable {
        let candidateID: UUID
        let digest: String
        let sourceRevision: String
        let capabilityVersion: String?
        let testPolicyVersion: String?
        let executionDigest: String?
    }
    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
    private func retainedSourceURL(revision: String) -> URL {
        let filenameIdentity = revision.utf8.map { String(format: "%02x", $0) }.joined()
        return url("source-\(filenameIdentity).json")
    }
    private func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, at url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    func accepted() throws -> SavedMacro? {
        guard FileManager.default.fileExists(atPath: pointerURL.path) else { return nil }
        let pointer = try read(Pointer.self, at: pointerURL)
        return try read(SavedMacro.self, at: url("revision-\(pointer.revisionID.uuidString).json"))
    }
    func publish(_ macro: SavedMacro, fault: MacroCandidatePublicationFault? = nil) throws {
        let revisionID = UUID()
        try write(macro, at: url("revision-\(revisionID.uuidString).json"))
        if fault == .beforePointer { throw MacroCandidateStoreError.injectedPublicationFailure }
        // The only publication boundary. A failure before this leaves the old pointer;
        // a failure after it leaves a complete, immediately readable new revision.
        try write(Pointer(revisionID: revisionID), at: pointerURL)
        if fault == .afterPointer { throw MacroCandidateStoreError.injectedPublicationFailure }
    }
    func retainSource(_ source: SavedMacro) throws {
        // Digest is generated by Core, never a path supplied by the candidate.
        let identity = try MacroCandidateIdentity.revision(of: source)
        let sourceURL = retainedSourceURL(revision: identity)
        if !FileManager.default.fileExists(atPath: sourceURL.path) { try write(source, at: sourceURL) }
        let originalURL = url("original.json")
        if !FileManager.default.fileExists(atPath: originalURL.path) { try write(source, at: originalURL) }
    }
    func retainedSource(revision: String) throws -> SavedMacro? {
        let sourceURL = retainedSourceURL(revision: revision)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        let source = try read(SavedMacro.self, at: sourceURL)
        guard try MacroCandidateIdentity.revision(of: source) == revision else {
            throw MacroCandidateStoreError.candidateIntegrityMismatch
        }
        return source
    }

    func original() throws -> SavedMacro {
        guard FileManager.default.fileExists(atPath: url("original.json").path) else {
            throw MacroCandidateStoreError.noOriginalRevision
        }
        return try read(SavedMacro.self, at: url("original.json"))
    }
    func insert(
        document: MacroCandidateDocument,
        normalized: SavedMacro,
        authoringOrigin: MacroCandidateAuthoringOrigin,
        importProvenance: MacroCandidateImportProvenance?
    ) throws -> MacroStoredCandidate {
        let candidate = MacroStoredCandidate(
            id: UUID(),
            document: document,
            macro: normalized,
            normalizedDigest: try MacroCandidateIdentity.revision(of: normalized),
            createdAt: Date(),
            authoringOrigin: authoringOrigin,
            importProvenance: importProvenance
        )
        try write(candidate, at: url("candidate-\(candidate.id.uuidString).json"))
        return candidate
    }
    func candidate(_ id: UUID) throws -> MacroStoredCandidate {
        let value = try read(MacroStoredCandidate.self, at: url("candidate-\(id.uuidString).json"))
        guard value.id == id, try MacroCandidateIdentity.revision(of: value.macro) == value.normalizedDigest else {
            throw MacroCandidateStoreError.candidateIntegrityMismatch
        }
        return value
    }
    func candidates() throws -> [MacroStoredCandidate] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("candidate-") && $0.pathExtension == "json" }
            .map { try read(MacroStoredCandidate.self, at: $0) }.sorted { $0.createdAt > $1.createdAt }
    }
    func invalidateReceipt(_ id: UUID) throws {
        let target = url("test-\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }
    func recordSuccess(_ candidate: MacroStoredCandidate) throws {
        try write(Receipt(candidateID: candidate.id, digest: candidate.normalizedDigest,
            sourceRevision: candidate.document.sourceRevision,
            capabilityVersion: MacroCandidateCapabilities.current.version,
            testPolicyVersion: MacroCandidateTestRun.policyVersion,
            executionDigest: try MacroCandidateIdentity.revision(of: MacroCandidateTestRun.executionMacro(for: candidate.macro))), at: url("test-\(candidate.id.uuidString).json"))
    }
    func requireReceipt(_ candidate: MacroStoredCandidate) throws {
        guard let receipt = try? read(Receipt.self, at: url("test-\(candidate.id.uuidString).json")),
            receipt.candidateID == candidate.id, receipt.digest == candidate.normalizedDigest,
            receipt.sourceRevision == candidate.document.sourceRevision,
            receipt.capabilityVersion == MacroCandidateCapabilities.current.version,
            receipt.testPolicyVersion == MacroCandidateTestRun.policyVersion,
            receipt.executionDigest == (try MacroCandidateIdentity.revision(of: MacroCandidateTestRun.executionMacro(for: candidate.macro))) else {
            throw MacroCandidateStoreError.testRequired
        }
    }
}

public extension MacroRepository {
    /// Loads one complete accepted revision; consumers can retain this value for an entire run.
    func loadMacro(for id: UUID) throws -> SavedMacro {
        if let accepted = try MacroCandidateStore(package: packageURL(for: id)).accepted() { return accepted }
        var macro = try JSONDecoder().decode(SavedMacro.self,
            from: Data(contentsOf: packageURL(for: id).appendingPathComponent("macro.json")))
        macro.events = try loadEvents(for: id)
        macro.refreshCachesFromEvents()
        return macro
    }

    func importCandidate(
        _ document: MacroCandidateDocument,
        for id: UUID,
        importProvenance: MacroCandidateImportProvenance? = .standalone
    ) throws -> MacroStoredCandidate {
        try importCandidate(
            document,
            for: id,
            authoringOrigin: .externalAuthoring,
            importProvenance: importProvenance
        )
    }

    func importCandidateDraft(
        _ document: MacroCandidateDocument,
        for id: UUID,
        importProvenance: MacroCandidateImportProvenance? = nil
    ) throws -> MacroStoredCandidate {
        try importCandidate(
            document,
            for: id,
            authoringOrigin: .localCandidateEditor,
            importProvenance: importProvenance
        )
    }

    private func importCandidate(
        _ document: MacroCandidateDocument,
        for id: UUID,
        authoringOrigin: MacroCandidateAuthoringOrigin,
        importProvenance: MacroCandidateImportProvenance?
    ) throws -> MacroStoredCandidate {
        let source = try loadMacro(for: id)
        let revision = try MacroCandidateIdentity.revision(of: source)
        guard document.sourceRevision == revision else { throw MacroCandidateStoreError.staleSource }
        let normalized = try MacroCandidateValidator.normalize(
            document,
            source: source,
            surfaceAuthority: authoringOrigin.surfaceAuthority
        )
        let store = MacroCandidateStore(package: packageURL(for: id))
        try store.retainSource(source)
        return try store.insert(
            document: document,
            normalized: normalized,
            authoringOrigin: authoringOrigin,
            importProvenance: importProvenance
        )
    }

    func loadCandidate(candidateID: UUID, for id: UUID) throws -> MacroStoredCandidate {
        let candidate = try MacroCandidateStore(package: packageURL(for: id)).candidate(candidateID)
        guard candidate.macro.id == id else { throw MacroCandidateStoreError.candidateIntegrityMismatch }
        return candidate
    }

    func listCandidates(for id: UUID) throws -> [MacroStoredCandidate] {
        try MacroCandidateStore(package: packageURL(for: id)).candidates()
    }

    func loadRetainedSource(revision: String, for id: UUID) throws -> SavedMacro? {
        try MacroCandidateStore(package: packageURL(for: id)).retainedSource(revision: revision)
    }

    func prepareCandidateTest(candidateID: UUID, for id: UUID) throws -> MacroCandidateTestRun {
        let candidate = try checkedCandidate(candidateID, macroID: id)
        try MacroCandidateStore(package: packageURL(for: id)).invalidateReceipt(candidateID)
        // A new test invalidates earlier pending runs as well as earlier success.
        candidateTestRuns = candidateTestRuns.filter { $0.value.candidateID != candidateID }
        let run = try MacroCandidateTestRun(candidate: candidate)
        candidateTestRuns[run.token] = run
        return run
    }

    /// The normal Player completion path supplies the observed outcome. No CLI command calls this.
    func recordCandidateTest(_ run: MacroCandidateTestRun, succeeded: Bool) throws {
        guard let issued = candidateTestRuns.removeValue(forKey: run.token),
            issued.candidateID == run.candidateID, issued.macroID == run.macroID,
            issued.normalizedDigest == run.normalizedDigest, issued.executionDigest == run.executionDigest else { throw MacroCandidateStoreError.invalidTestToken }
        let store = MacroCandidateStore(package: packageURL(for: issued.macroID))
        try store.invalidateReceipt(issued.candidateID)
        let candidate = try checkedCandidate(issued.candidateID, macroID: issued.macroID)
        guard candidate.normalizedDigest == issued.normalizedDigest,
            try MacroCandidateIdentity.revision(of: issued.macro) == issued.executionDigest,
            try MacroCandidateIdentity.revision(of: MacroCandidateTestRun.executionMacro(for: candidate.macro)) == issued.executionDigest else {
            throw MacroCandidateStoreError.candidateIntegrityMismatch
        }
        if succeeded { try store.recordSuccess(candidate) }
    }

    func acceptCandidate(candidateID: UUID, for id: UUID, confirmUncertainties: Bool = false) throws -> SavedMacro {
        let candidate = try checkedCandidate(candidateID, macroID: id)
        if candidate.document.requiresAttention && !confirmUncertainties {
            throw MacroCandidateStoreError.confirmationRequired
        }
        let store = MacroCandidateStore(package: packageURL(for: id))
        try store.requireReceipt(candidate)
        // Re-normalizing against current metadata preserves notes, hotkeys, statistics,
        // identity and references changed since import without invalidating execution.
        let accepted = try MacroCandidateValidator.normalize(
            candidate.document,
            source: loadMacro(for: id),
            surfaceAuthority: candidate.authoringOrigin.surfaceAuthority
        )
        try store.publish(accepted, fault: candidatePublicationFault)
        return accepted
    }

    func restoreOriginal(for id: UUID) throws -> SavedMacro {
        let store = MacroCandidateStore(package: packageURL(for: id))
        let original = try store.original()
        var restored = try loadMacro(for: id)
        restored.events = original.events
        restored.surfaces = original.surfaces
        restored.loops = original.loops
        restored.speed = original.speed
        restored.followWindowOffset = original.followWindowOffset
        restored.refreshCachesFromEvents()
        try store.publish(restored, fault: candidatePublicationFault)
        return restored
    }

    private func checkedCandidate(_ candidateID: UUID, macroID: UUID) throws -> MacroStoredCandidate {
        let candidate = try loadCandidate(candidateID: candidateID, for: macroID)
        let source = try loadMacro(for: macroID)
        guard try MacroCandidateIdentity.revision(of: source) == candidate.document.sourceRevision else {
            throw MacroCandidateStoreError.staleSource
        }
        let normalized = try MacroCandidateValidator.normalize(
            candidate.document,
            source: source,
            surfaceAuthority: candidate.authoringOrigin.surfaceAuthority
        )
        guard try MacroCandidateIdentity.revision(of: normalized) == candidate.normalizedDigest else {
            throw MacroCandidateStoreError.candidateIntegrityMismatch
        }
        return candidate
    }
}

extension MacroRepository {
    func setCandidatePublicationFault(_ fault: MacroCandidatePublicationFault?) {
        candidatePublicationFault = fault
    }
}
