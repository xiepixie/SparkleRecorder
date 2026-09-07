import Foundation

/// Single source of truth for every machine-readable contract that participates in
/// reconstruction export, external authoring, import, review, and candidate testing.
/// Change a version here when its serialized semantics change; do not scatter raw
/// version strings across package builders, validators, or UI code.
public enum MacroReconstructionContractVersions {
    public static let manifest = "macro-reconstruction-contracts/v1"
    public static let package = "macro-reconstruction-package/v4"
    public static let harness = "macro-reconstruction-harness/v1"
    public static let authoringContract = "macro-reconstruction-authoring/v1"
    public static let candidateCapability = "macro-candidate/v4"
    public static let authoringPolicy = "macro-reconstruction-policy/v1"
    public static let sourceContext = "macro-reconstruction-source/v3"
    public static let actionContext = "macro-reconstruction-action-context/v3"
    public static let candidateActionRevision = "candidate"
}

/// Package-level contract ledger. Import validates this file before treating a
/// directory as an AI reconstruction package, so a package cannot silently mix
/// files produced by different authoring contracts.
public struct MacroReconstructionContractManifest: Codable, Equatable, Sendable {
    public var version: String
    public var packageVersion: String
    public var authoringContractVersion: String?
    public var candidateCapabilityVersion: String
    public var authoringPolicyVersion: String
    public var sourceContextVersion: String
    public var actionContextVersion: String
    public var candidateActionRevision: String

    public init(
        version: String,
        packageVersion: String,
        authoringContractVersion: String? = nil,
        candidateCapabilityVersion: String,
        authoringPolicyVersion: String,
        sourceContextVersion: String,
        actionContextVersion: String,
        candidateActionRevision: String
    ) {
        self.version = version
        self.packageVersion = packageVersion
        self.authoringContractVersion = authoringContractVersion
        self.candidateCapabilityVersion = candidateCapabilityVersion
        self.authoringPolicyVersion = authoringPolicyVersion
        self.sourceContextVersion = sourceContextVersion
        self.actionContextVersion = actionContextVersion
        self.candidateActionRevision = candidateActionRevision
    }

    public static let current = MacroReconstructionContractManifest(
        version: MacroReconstructionContractVersions.manifest,
        packageVersion: MacroReconstructionContractVersions.package,
        authoringContractVersion: MacroReconstructionContractVersions.authoringContract,
        candidateCapabilityVersion: MacroReconstructionContractVersions.candidateCapability,
        authoringPolicyVersion: MacroReconstructionContractVersions.authoringPolicy,
        sourceContextVersion: MacroReconstructionContractVersions.sourceContext,
        actionContextVersion: MacroReconstructionContractVersions.actionContext,
        candidateActionRevision: MacroReconstructionContractVersions.candidateActionRevision
    )
}
