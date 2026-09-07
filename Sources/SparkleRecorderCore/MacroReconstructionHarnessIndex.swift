import Foundation

public struct MacroReconstructionHarnessReadStage: Codable, Equatable, Sendable {
    public var id: String
    public var files: [String]
    public var purpose: String

    public init(id: String, files: [String], purpose: String) {
        self.id = id
        self.files = files
        self.purpose = purpose
    }
}

public struct MacroReconstructionPackageFileRole: Codable, Equatable, Sendable {
    public var path: String
    public var role: String
    public var requiredForAuthoring: Bool
    public var requiredForImport: Bool
    public var systemMaintained: Bool

    public init(path: String, role: String, requiredForAuthoring: Bool, requiredForImport: Bool, systemMaintained: Bool) {
        self.path = path
        self.role = role
        self.requiredForAuthoring = requiredForAuthoring
        self.requiredForImport = requiredForImport
        self.systemMaintained = systemMaintained
    }
}

/// Small entry point for an external reconstruction run. Keep this file compact:
/// it tells the author what to read and when; detailed rules live in
/// authoring-contract.json and source evidence stays in its own files.
public struct MacroReconstructionHarnessIndex: Codable, Equatable, Sendable {
    public static let currentVersion = MacroReconstructionContractVersions.harness

    public var version: String
    public var sourceRevision: String
    public var macroID: UUID
    public var objective: MacroReconstructionObjective
    public var contracts: MacroReconstructionContractManifest
    public var readingPlan: [MacroReconstructionHarnessReadStage]
    public var files: [MacroReconstructionPackageFileRole]
    public var outputFile: String

    public init(sourceRevision: String, macroID: UUID, objective: MacroReconstructionObjective) {
        version = Self.currentVersion
        self.sourceRevision = sourceRevision
        self.macroID = macroID
        self.objective = objective
        contracts = .current
        readingPlan = Self.defaultReadingPlan
        files = Self.defaultFileRoles
        outputFile = "candidate.json"
    }

    public static let defaultReadingPlan: [MacroReconstructionHarnessReadStage] = [
        .init(
            id: "orient",
            files: ["harness.json"],
            purpose: "Confirm package versions, objective, file roles and the staged reading plan."
        ),
        .init(
            id: "understand",
            files: ["source-context.json", "reconstruction.json", "manifest.json"],
            purpose: "Understand the Macro, Playback Surfaces, action inventory, evidence availability and warnings without loading raw events or media."
        ),
        .init(
            id: "inspectOnDemand",
            files: ["visual-inspection.json", "alignment.json", "input-evidence.json", "video/*", "frames/*"],
            purpose: "Open only evidence needed for fragile or ambiguous actions. Optional files may be absent."
        ),
        .init(
            id: "draft",
            files: ["authoring-contract.json", "candidate-template.json"],
            purpose: "Load the complete authoring vocabulary/rules and the full source-shaped event template only when ready to write candidate.json."
        ),
        .init(
            id: "selfCheck",
            files: ["authoring-contract.json", "reconstruction.json"],
            purpose: "Validate enum names, event-state balance, text-operation invariants, Surface references and complete source-action coverage before returning candidate.json."
        )
    ]

    public static let defaultFileRoles: [MacroReconstructionPackageFileRole] = [
        .init(path: "harness.json", role: "Small package index and staged reading plan.", requiredForAuthoring: true, requiredForImport: true, systemMaintained: true),
        .init(path: "authoring-contract.json", role: "Canonical executable vocabulary, enums, validation rules and authoring policy.", requiredForAuthoring: true, requiredForImport: true, systemMaintained: true),
        .init(path: "source-context.json", role: "Lightweight Source Revision summary, Playback Surfaces and protected execution facts; excludes raw events.", requiredForAuthoring: true, requiredForImport: true, systemMaintained: true),
        .init(path: "reconstruction.json", role: "Primary action-level inventory and targeting context derived from the source events.", requiredForAuthoring: true, requiredForImport: true, systemMaintained: true),
        .init(path: "candidate-template.json", role: "Complete source-shaped candidate and the single exported copy of raw executable events; read at draft time.", requiredForAuthoring: true, requiredForImport: true, systemMaintained: true),
        .init(path: "manifest.json", role: "Evidence availability, warnings, package revision and exported artifact hashes.", requiredForAuthoring: true, requiredForImport: true, systemMaintained: true),
        .init(path: "candidate.json", role: "The only file authored by the external AI and imported as the proposed Candidate.", requiredForAuthoring: false, requiredForImport: true, systemMaintained: false),
        .init(path: "alignment.json", role: "Optional verified recording/source timing provenance.", requiredForAuthoring: false, requiredForImport: false, systemMaintained: true),
        .init(path: "input-evidence.json", role: "Optional high-resolution mechanical evidence behind compact playable events.", requiredForAuthoring: false, requiredForImport: false, systemMaintained: true),
        .init(path: "visual-inspection.json", role: "Optional action-linked video/frame/observation navigation data for aligned visual evidence.", requiredForAuthoring: false, requiredForImport: false, systemMaintained: true),
        .init(path: "video/*", role: "Optional permitted recording video bytes.", requiredForAuthoring: false, requiredForImport: false, systemMaintained: true),
        .init(path: "frames/*", role: "Optional permitted key-frame image bytes.", requiredForAuthoring: false, requiredForImport: false, systemMaintained: true)
    ]
}
