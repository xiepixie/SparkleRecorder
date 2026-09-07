import Foundation
import SparkleRecorderCore

/// Decoder for the current layered reconstruction Harness. It owns only v4
/// contract policy; reusable source/evidence integrity checks live separately.
enum MacroReconstructionV4PackageDecoder {
    static func decode(
        packageDirectory: URL,
        candidate: MacroCandidateDocument,
        acceptedSource: SavedMacro?,
        fileManager: FileManager
    ) throws -> MacroReconstructionCandidateInput {
        let harnessURL = packageDirectory.appendingPathComponent("harness.json")
        let authoringContractURL = packageDirectory.appendingPathComponent("authoring-contract.json")
        try MacroReconstructionPackageValidation.requireFile(harnessURL, fileManager: fileManager)
        try MacroReconstructionPackageValidation.requireFile(authoringContractURL, fileManager: fileManager)

        let decoder = JSONDecoder()
        let harness = try decoder.decode(
            MacroReconstructionHarnessIndex.self,
            from: Data(contentsOf: harnessURL, options: .mappedIfSafe)
        )
        guard harness.version == MacroReconstructionHarnessIndex.currentVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedContractVersion(harness.version)
        }
        guard harness == MacroReconstructionHarnessIndex(
            sourceRevision: harness.sourceRevision,
            macroID: harness.macroID,
            objective: harness.objective
        ) else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("harness.json")
        }

        let authoring = try decoder.decode(
            MacroReconstructionAuthoringContract.self,
            from: Data(contentsOf: authoringContractURL, options: .mappedIfSafe)
        )
        guard authoring.version == MacroReconstructionAuthoringContract.currentVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedContractVersion(authoring.version)
        }

        let contract = harness.contracts
        guard contract.version == MacroReconstructionContractVersions.manifest else {
            throw MacroReconstructionCandidateInputError.unsupportedContractVersion(contract.version)
        }
        guard contract.packageVersion == MacroReconstructionContractVersions.package else {
            throw MacroReconstructionCandidateInputError.unsupportedPackageVersion(contract.packageVersion)
        }
        guard contract.authoringContractVersion == MacroReconstructionContractVersions.authoringContract else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("authoringContractVersion")
        }
        guard contract.candidateCapabilityVersion == MacroReconstructionContractVersions.candidateCapability,
              authoring.capabilities == MacroCandidateCapabilities.current else {
            throw MacroReconstructionCandidateInputError.unsupportedCapabilityVersion(authoring.capabilities.version)
        }
        guard contract.authoringPolicyVersion == MacroReconstructionContractVersions.authoringPolicy,
              authoring.policy.version == MacroReconstructionAuthoringPolicy.currentVersion,
              authoring.policy.objective == harness.objective else {
            throw MacroReconstructionCandidateInputError.unsupportedAuthoringPolicyVersion(authoring.policy.version)
        }
        guard contract.sourceContextVersion == MacroReconstructionContractVersions.sourceContext else {
            throw MacroReconstructionCandidateInputError.unsupportedSourceContextVersion(contract.sourceContextVersion)
        }
        guard contract.actionContextVersion == MacroReconstructionContractVersions.actionContext else {
            throw MacroReconstructionCandidateInputError.unsupportedActionContextVersion(contract.actionContextVersion)
        }
        guard contract.candidateActionRevision == MacroReconstructionContractVersions.candidateActionRevision,
              authoring.capabilities.candidateActionRevision == contract.candidateActionRevision else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("candidateActionRevision")
        }
        guard authoring == MacroReconstructionAuthoringContract(objective: harness.objective) else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("authoring-contract.json")
        }

        let shared = try MacroReconstructionPackageValidation.decodeSharedContext(
            packageDirectory: packageDirectory,
            candidate: candidate,
            expectedPackageVersion: MacroReconstructionContractVersions.package,
            allowedSourceContextVersion: MacroReconstructionContractVersions.sourceContext,
            allowedActionContextVersion: MacroReconstructionContractVersions.actionContext,
            legacyActionContextCompatibility: false,
            fileManager: fileManager
        )
        guard harness.sourceRevision == candidate.sourceRevision,
              harness.macroID == candidate.macro.id else {
            throw MacroReconstructionCandidateInputError.packageSourceRevisionMismatch
        }
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
            harnessVersion: harness.version,
            authoringContractVersion: authoring.version,
            packageSourceRevision: shared.manifest.sourceRevision,
            capabilityVersion: authoring.capabilities.version,
            authoringPolicyVersion: authoring.policy.version,
            sourceContextVersion: shared.source.version,
            actionContextVersion: shared.actions.version,
            candidateActionRevision: authoring.capabilities.candidateActionRevision,
            objective: authoring.policy.objective,
            visualEvidenceIncluded: shared.manifest.visualEvidenceIncluded,
            mechanicalEvidenceIncluded: shared.manifest.mechanicalEvidenceIncluded,
            sourceEventsMatchRecording: shared.manifest.sourceEventsMatchRecording,
            artifactCount: shared.manifest.artifacts.count,
            warnings: shared.manifest.warnings
        )
        return MacroReconstructionCandidateInput(document: candidate, importProvenance: provenance)
    }
}
