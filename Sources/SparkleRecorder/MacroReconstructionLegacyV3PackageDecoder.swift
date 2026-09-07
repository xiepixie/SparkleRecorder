import Foundation
import SparkleRecorderCore

/// Explicit compatibility adapter for the prior v3 package layout. New exports
/// never recreate these files; keeping legacy policy isolated makes eventual
/// removal or migration auditable.
enum MacroReconstructionLegacyV3PackageDecoder {
    static let packageVersion = "macro-reconstruction-package/v3"
    static let sourceContextVersion = "macro-reconstruction-source/v2"
    static let actionContextVersion = "macro-reconstruction-action-context/v2"

    static func decode(
        packageDirectory: URL,
        candidate: MacroCandidateDocument,
        acceptedSource: SavedMacro?,
        fileManager: FileManager
    ) throws -> MacroReconstructionCandidateInput {
        let contractURL = packageDirectory.appendingPathComponent("contract.json")
        let capabilitiesURL = packageDirectory.appendingPathComponent("capabilities.json")
        let policyURL = packageDirectory.appendingPathComponent("authoring-policy.json")
        for required in [contractURL, capabilitiesURL, policyURL] {
            try MacroReconstructionPackageValidation.requireFile(required, fileManager: fileManager)
        }

        let decoder = JSONDecoder()
        let contract = try decoder.decode(
            MacroReconstructionContractManifest.self,
            from: Data(contentsOf: contractURL, options: .mappedIfSafe)
        )
        guard contract.version == MacroReconstructionContractVersions.manifest else {
            throw MacroReconstructionCandidateInputError.unsupportedContractVersion(contract.version)
        }
        guard contract.packageVersion == packageVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedPackageVersion(contract.packageVersion)
        }
        guard contract.candidateCapabilityVersion == MacroReconstructionContractVersions.candidateCapability else {
            throw MacroReconstructionCandidateInputError.unsupportedCapabilityVersion(contract.candidateCapabilityVersion)
        }
        guard contract.authoringPolicyVersion == MacroReconstructionContractVersions.authoringPolicy else {
            throw MacroReconstructionCandidateInputError.unsupportedAuthoringPolicyVersion(contract.authoringPolicyVersion)
        }
        guard contract.sourceContextVersion == sourceContextVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedSourceContextVersion(contract.sourceContextVersion)
        }
        guard contract.actionContextVersion == actionContextVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedActionContextVersion(contract.actionContextVersion)
        }

        let capabilities = try decoder.decode(
            MacroCandidateCapabilities.self,
            from: Data(contentsOf: capabilitiesURL, options: .mappedIfSafe)
        )
        guard capabilities == MacroCandidateCapabilities.current else {
            throw MacroReconstructionCandidateInputError.unsupportedCapabilityVersion(capabilities.version)
        }
        let policy = try decoder.decode(
            MacroReconstructionAuthoringPolicy.self,
            from: Data(contentsOf: policyURL, options: .mappedIfSafe)
        )
        guard policy.version == MacroReconstructionAuthoringPolicy.currentVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedAuthoringPolicyVersion(policy.version)
        }

        let shared = try MacroReconstructionPackageValidation.decodeSharedContext(
            packageDirectory: packageDirectory,
            candidate: candidate,
            expectedPackageVersion: packageVersion,
            allowedSourceContextVersion: sourceContextVersion,
            allowedActionContextVersion: actionContextVersion,
            legacyActionContextCompatibility: true,
            fileManager: fileManager
        )
        try MacroReconstructionPackageValidation.validateArtifactIntegrity(
            shared.manifest.artifacts,
            packageDirectory: packageDirectory,
            fileManager: fileManager
        )
        try MacroReconstructionPackageValidation.validateSystemMaintainedSourceFiles(
            acceptedSource: acceptedSource,
            sourceContext: shared.source,
            template: shared.template,
            candidate: candidate
        )

        let provenance = MacroCandidateImportProvenance(
            source: .reconstructionPackage,
            packageVersion: shared.manifest.packageVersion,
            contractVersion: contract.version,
            harnessVersion: nil,
            authoringContractVersion: nil,
            packageSourceRevision: shared.manifest.sourceRevision,
            capabilityVersion: capabilities.version,
            authoringPolicyVersion: policy.version,
            sourceContextVersion: shared.source.version,
            actionContextVersion: shared.actions.version,
            candidateActionRevision: capabilities.candidateActionRevision,
            objective: policy.objective,
            visualEvidenceIncluded: shared.manifest.visualEvidenceIncluded,
            mechanicalEvidenceIncluded: shared.manifest.mechanicalEvidenceIncluded,
            sourceEventsMatchRecording: shared.manifest.sourceEventsMatchRecording,
            artifactCount: shared.manifest.artifacts.count,
            warnings: shared.manifest.warnings
        )
        return MacroReconstructionCandidateInput(document: candidate, importProvenance: provenance)
    }
}
