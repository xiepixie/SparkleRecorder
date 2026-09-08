import CryptoKit
import Foundation
import SparkleRecorderCore

struct MacroReconstructionPackageSharedContext {
    var manifest: MacroReconstructionPackageReport
    var source: MacroReconstructionSourceContext
    var actions: MacroReconstructionActionContextDocument
    var template: MacroCandidateDocument
}

/// Cross-version integrity checks shared by the current Harness decoder and
/// explicit legacy adapters. This Module never decides which package version is
/// acceptable; version-specific decoders own that policy.
enum MacroReconstructionPackageValidation {
    static func requireFile(_ url: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw MacroReconstructionCandidateInputError.missingPackageMetadata(url.lastPathComponent)
        }
    }

    static func decodeSharedContext(
        packageDirectory: URL,
        candidate: MacroCandidateDocument,
        expectedPackageVersion: String,
        allowedSourceContextVersion: String,
        allowedActionContextVersion: String,
        legacyActionContextCompatibility: Bool,
        fileManager: FileManager
    ) throws -> MacroReconstructionPackageSharedContext {
        let manifestURL = packageDirectory.appendingPathComponent("manifest.json")
        let sourceContextURL = packageDirectory.appendingPathComponent("source-context.json")
        let actionContextURL = packageDirectory.appendingPathComponent("reconstruction.json")
        let candidateTemplateURL = packageDirectory.appendingPathComponent("candidate-template.json")
        for required in [manifestURL, sourceContextURL, actionContextURL, candidateTemplateURL] {
            try requireFile(required, fileManager: fileManager)
        }

        let decoder = JSONDecoder()
        let manifest = try decoder.decode(
            MacroReconstructionPackageReport.self,
            from: Data(contentsOf: manifestURL, options: .mappedIfSafe)
        )
        guard manifest.packageVersion == expectedPackageVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedPackageVersion(manifest.packageVersion)
        }

        let sourceContext = try decoder.decode(
            MacroReconstructionSourceContext.self,
            from: Data(contentsOf: sourceContextURL, options: .mappedIfSafe)
        )
        guard sourceContext.version == allowedSourceContextVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedSourceContextVersion(sourceContext.version)
        }

        let actionContext = try decoder.decode(
            MacroReconstructionActionContextDocument.self,
            from: Data(contentsOf: actionContextURL, options: .mappedIfSafe)
        )
        guard actionContext.version == allowedActionContextVersion else {
            throw MacroReconstructionCandidateInputError.unsupportedActionContextVersion(actionContext.version)
        }

        let template = try MacroReconstructionCandidateInputResolver.decodeCandidate(
            Data(contentsOf: candidateTemplateURL, options: .mappedIfSafe)
        )
        guard manifest.sourceRevision == candidate.sourceRevision,
              sourceContext.sourceRevision == candidate.sourceRevision,
              actionContext.sourceRevision == candidate.sourceRevision,
              template.sourceRevision == candidate.sourceRevision,
              sourceContext.macroID == candidate.macro.id,
              template.macro.id == candidate.macro.id else {
            throw MacroReconstructionCandidateInputError.packageSourceRevisionMismatch
        }
        guard sourceContext.eventCount == template.macro.events.count,
              abs(sourceContext.duration - (template.macro.events.last?.time ?? 0)) < 0.000_001 else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("source-context.json")
        }

        let expectedActions = try MacroActionReconstructor.reconstruct(
            events: template.macro.events,
            sourceRevision: sourceContext.sourceRevision
        )
        let expectedActionContext = MacroReconstructionActionContextProjector.document(
            actions: expectedActions,
            events: template.macro.events,
            surfaceContexts: sourceContext.surfaces,
            sourceRevision: sourceContext.sourceRevision
        )
        guard actionContextMatches(
            actual: actionContext,
            expectedCurrent: expectedActionContext,
            serializedVersion: allowedActionContextVersion,
            legacyCompatibility: legacyActionContextCompatibility
        ) else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("reconstruction.json")
        }

        return MacroReconstructionPackageSharedContext(
            manifest: manifest,
            source: sourceContext,
            actions: actionContext,
            template: template
        )
    }

    static func validateSystemMaintainedSourceFiles(
        acceptedSource: SavedMacro?,
        sourceContext: MacroReconstructionSourceContext,
        template: MacroCandidateDocument,
        candidate: MacroCandidateDocument
    ) throws {
        guard let acceptedSource else { return }
        let revision = try MacroCandidateIdentity.revision(of: acceptedSource)
        guard revision == candidate.sourceRevision else {
            throw MacroReconstructionCandidateInputError.packageSourceRevisionMismatch
        }

        var expectedContext = MacroReconstructionSourceContext(
            source: acceptedSource,
            sourceRevision: revision
        )
        // Legacy v3 serializes v2 with embedded events; decoding collapses that
        // representation to the same semantic overview plus its v2 version label.
        expectedContext.version = sourceContext.version
        guard sourceContext == expectedContext else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("source-context.json")
        }

        var expectedTemplate = try MacroReconstructionCandidateTemplate.strictDocument(source: acceptedSource)
        // modifiedAt is library metadata, not part of MacroCandidateIdentity.revision.
        // It may legitimately advance after package export while the executable source
        // remains identical, so it cannot participate in stale/tamper detection here.
        // All other system-maintained template fields remain strictly compared.
        expectedTemplate.macro.modifiedAt = template.macro.modifiedAt
        guard template == expectedTemplate else {
            throw MacroReconstructionCandidateInputError.packageContractMismatch("candidate-template.json")
        }
    }

    static func validateArtifactIntegrity(
        _ artifacts: [MacroReconstructionPackageArtifact],
        packageDirectory: URL,
        fileManager: FileManager
    ) throws {
        guard !artifacts.isEmpty else { return }
        let root = packageDirectory.resolvingSymlinksInPath().standardizedFileURL
        for artifact in artifacts {
            guard !artifact.path.isEmpty,
                  !artifact.path.hasPrefix("/"),
                  !artifact.path.split(separator: "/").contains("..") else {
                throw MacroReconstructionCandidateInputError.packageContractMismatch("artifact path \(artifact.path)")
            }
            let url = root.appendingPathComponent(artifact.path)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard url.path.hasPrefix(root.path + "/"),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw MacroReconstructionCandidateInputError.packageContractMismatch("artifact \(artifact.path)")
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == artifact.sha256 else {
                throw MacroReconstructionCandidateInputError.packageContractMismatch("artifact \(artifact.path)")
            }
        }
    }

    private static func actionContextMatches(
        actual: MacroReconstructionActionContextDocument,
        expectedCurrent: MacroReconstructionActionContextDocument,
        serializedVersion: String,
        legacyCompatibility: Bool
    ) -> Bool {
        guard legacyCompatibility else { return actual == expectedCurrent }
        var legacyExpected = expectedCurrent
        legacyExpected.version = serializedVersion
        legacyExpected.actions = legacyExpected.actions.map { row in
            var copy = row
            copy.pointerButton = nil
            copy.clickCount = nil
            copy.keyboardLabel = nil
            copy.textInputPreview = nil
            copy.textInputCharacterCount = nil
            copy.scrollDeltaX = nil
            copy.scrollDeltaY = nil
            return copy
        }
        return actual == legacyExpected
    }
}
