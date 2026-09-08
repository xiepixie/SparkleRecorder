import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro Reconstruction CLI Tests")
struct MacroReconstructionCLITests {
    @Test func parserRejectsUnattendedExecutionAndAmbiguousOptions() throws {
        for arguments in [["accept"], ["test"], ["success"], ["import", "--macro-id", "bad", "--candidate", "file"],
                          ["inspect", "--macro", "file", "--include-video"],
                          ["export", "--macro-id", UUID().uuidString, "--macro-id", UUID().uuidString]] {
            #expect(throws: MacroReconstructionCLIError.self) { try MacroReconstructionCLI.parse(arguments) }
        }
        let request = try MacroReconstructionCLI.parse(["inspect", "--macro", "/tmp/input.json", "--json"])
        #expect(request.command == "inspect" && request.macroPath == "/tmp/input.json")
    }

    @Test func inspectListsLiteralCandidateActionIDsWithoutLibraryAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        let path = root.appendingPathComponent("candidate.json")
        let document = MacroCandidateDocument(macro: source, sourceRevision: "candidate")
        try MacroCandidateAuthoringProjection.encode(document).write(to: path)
        let result = try await MacroReconstructionCLI.execute(["inspect", "--macro", path.path], appSupportURL: root)
        let expected = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: "candidate")
        #expect(result.actions?.map(\.actionID) == expected.map(\.id))
        #expect(result.actionRevision == "candidate")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("SparkleRecorder").path))
    }

    @Test func importAcceptsReconstructionPackageDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)

        let output = root.appendingPathComponent("package")
        _ = try await MacroReconstructionCLI.execute(
            ["export", "--macro-id", source.id.uuidString, "--output", output.path], appSupportURL: root)
        let template = output.appendingPathComponent("candidate-template.json")
        let candidate = output.appendingPathComponent("candidate.json")
        try Data(contentsOf: template).write(to: candidate)

        let imported = try await MacroReconstructionCLI.execute(
            ["import", "--macro-id", source.id.uuidString, "--candidate", output.path], appSupportURL: root)
        #expect(imported.candidateID != nil)
        #expect(try await repo.loadMacro(for: source.id) == source)
    }

    @Test("Package import tolerates modifiedAt drift when executable source revision is unchanged")
    func packageImportToleratesModifiedAtDrift() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)

        let output = root.appendingPathComponent("package")
        _ = try await MacroReconstructionCLI.execute(
            ["export", "--macro-id", source.id.uuidString, "--output", output.path],
            appSupportURL: root
        )
        try Data(contentsOf: output.appendingPathComponent("candidate-template.json"))
            .write(to: output.appendingPathComponent("candidate.json"))

        var metadataOnlyUpdate = try await repo.loadMacro(for: source.id)
        let originalRevision = try MacroCandidateIdentity.revision(of: metadataOnlyUpdate)
        metadataOnlyUpdate.modifiedAt = metadataOnlyUpdate.modifiedAt.addingTimeInterval(120)
        try await repo.saveMetadata(metadataOnlyUpdate)
        let reloaded = try await repo.loadMacro(for: source.id)
        #expect(try MacroCandidateIdentity.revision(of: reloaded) == originalRevision)
        #expect(reloaded.modifiedAt != source.modifiedAt)

        let imported = try await MacroReconstructionCLI.execute(
            ["import", "--macro-id", source.id.uuidString, "--candidate", output.path],
            appSupportURL: root
        )
        #expect(imported.candidateID != nil)
    }

    @Test("Package import retains machine-readable authoring provenance")
    func packageImportRetainsProvenance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)

        let output = root.appendingPathComponent("package")
        _ = try await MacroReconstructionCLI.execute(
            ["export", "--macro-id", source.id.uuidString, "--output", output.path],
            appSupportURL: root
        )
        try Data(contentsOf: output.appendingPathComponent("candidate-template.json"))
            .write(to: output.appendingPathComponent("candidate.json"))

        let imported = try await MacroReconstructionCLI.execute(
            ["import", "--macro-id", source.id.uuidString, "--candidate", output.path],
            appSupportURL: root
        )
        let candidate = try await repo.loadCandidate(candidateID: #require(imported.candidateID), for: source.id)
        let provenance = try #require(candidate.importProvenance)
        let expectedRevision = try MacroCandidateIdentity.revision(of: source)
        #expect(provenance.source == .reconstructionPackage)
        #expect(provenance.packageSourceRevision == expectedRevision)
        #expect(provenance.contractVersion == MacroReconstructionContractVersions.manifest)
        #expect(provenance.harnessVersion == MacroReconstructionContractVersions.harness)
        #expect(provenance.authoringContractVersion == MacroReconstructionContractVersions.authoringContract)
        #expect(provenance.capabilityVersion == MacroCandidateCapabilities.current.version)
        #expect(provenance.authoringPolicyVersion == MacroReconstructionContractVersions.authoringPolicy)
        #expect(provenance.sourceContextVersion == MacroReconstructionContractVersions.sourceContext)
        #expect(provenance.actionContextVersion == MacroReconstructionContractVersions.actionContext)
        #expect(provenance.candidateActionRevision == MacroReconstructionContractVersions.candidateActionRevision)
        #expect(provenance.objective == .robust)
        #expect(provenance.visualEvidenceIncluded == false)
    }

    @Test("Legacy v3 package adapter imports a valid candidate without requiring v4 harness files")
    func legacyV3PackageStillImports() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = SavedMacro(name: "Legacy v3", events: TestFixtures.clickPair())
        try writeLegacyV3Package(source: source, to: root)

        let input = try MacroReconstructionCandidateInputResolver.decodeInput(at: root, source: source)
        #expect(input.importProvenance.source == .reconstructionPackage)
        #expect(input.importProvenance.packageVersion == "macro-reconstruction-package/v3")
        #expect(input.importProvenance.sourceContextVersion == "macro-reconstruction-source/v2")
        #expect(input.importProvenance.actionContextVersion == "macro-reconstruction-action-context/v2")
        let normalized = try MacroCandidateValidator.normalize(input.document, source: source)
        #expect(normalized.events == source.events)
    }

    @Test("Legacy v3 package with v4 candidate capability still imports")
    func legacyV3PackageWithV4CapabilityStillImports() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = SavedMacro(name: "Legacy v3/v4", events: TestFixtures.clickPair())
        try writeLegacyV3Package(source: source, to: root)
        try rewriteLegacyV3Capability(at: root, version: "macro-candidate/v4", includeRequiredEventMetadata: false)

        let input = try MacroReconstructionCandidateInputResolver.decodeInput(at: root, source: source)
        #expect(input.importProvenance.capabilityVersion == "macro-candidate/v4")
    }

    @Test("Source-aware package import rejects edits to source-context even when package revision is unchanged")
    func packageImportRejectsTamperedSourceOverview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        let sourceURL = root.appendingPathComponent("source-context.json")
        var sourceContext = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: sourceURL)) as? [String: Any]
        )
        sourceContext["name"] = "AI changed the system overview"
        try JSONSerialization.data(withJSONObject: sourceContext).write(to: sourceURL)

        #expect(throws: MacroReconstructionCandidateInputError.packageContractMismatch("source-context.json")) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: root, source: source)
        }
    }

    @Test("Source-aware package import rejects edits to the system candidate template")
    func packageImportRejectsTamperedCandidateTemplate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        let templateURL = root.appendingPathComponent("candidate-template.json")
        try Data(contentsOf: templateURL).write(to: root.appendingPathComponent("candidate.json"))
        var template = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: templateURL)) as? [String: Any]
        )
        template["summary"] = "AI changed the system template"
        try JSONSerialization.data(withJSONObject: template).write(to: templateURL)

        #expect(throws: MacroReconstructionCandidateInputError.packageContractMismatch("candidate-template.json")) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: root, source: source)
        }
    }

    @Test("Package import rejects a candidate copied from another source package")
    func packageImportRejectsSwappedCandidate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = macro()
        var second = macro()
        second.events[0].x += 40
        let firstPackage = root.appendingPathComponent("first")
        let secondPackage = root.appendingPathComponent("second")
        _ = try MacroReconstructionPackage.export(source: first, to: firstPackage)
        _ = try MacroReconstructionPackage.export(source: second, to: secondPackage)
        try Data(contentsOf: secondPackage.appendingPathComponent("candidate-template.json"))
            .write(to: firstPackage.appendingPathComponent("candidate.json"))

        #expect(throws: MacroReconstructionCandidateInputError.packageSourceRevisionMismatch) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: firstPackage)
        }
    }

    @Test("Package import rejects edits to the system-maintained harness index")
    func packageImportRejectsTamperedHarness() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        let harnessURL = root.appendingPathComponent("harness.json")
        var harness = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: harnessURL)) as? [String: Any]
        )
        harness["readingPlan"] = []
        try JSONSerialization.data(withJSONObject: harness).write(to: harnessURL)

        #expect(throws: MacroReconstructionCandidateInputError.packageContractMismatch("harness.json")) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: root)
        }
    }

    @Test("Package import rejects evidence bytes that no longer match manifest hashes")
    func packageImportRejectsTamperedArtifact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        let videoDirectory = root.appendingPathComponent("video", isDirectory: true)
        try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        try Data("changed evidence".utf8).write(to: videoDirectory.appendingPathComponent("fake.mov"))
        let manifestURL = root.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(
            MacroReconstructionPackageReport.self,
            from: Data(contentsOf: manifestURL)
        )
        manifest.visualEvidenceIncluded = true
        manifest.artifacts = [
            MacroReconstructionPackageArtifact(
                path: "video/fake.mov",
                sha256: String(repeating: "0", count: 64)
            )
        ]
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        #expect(throws: MacroReconstructionCandidateInputError.packageContractMismatch("artifact video/fake.mov")) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: root)
        }
    }

    @Test("Package import rejects a tampered action-context contract")
    func packageImportRejectsTamperedActionContextContract() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        var actionContext = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("reconstruction.json"))) as? [String: Any]
        )
        actionContext["version"] = "macro-reconstruction-action-context/v0"
        try JSONSerialization.data(withJSONObject: actionContext)
            .write(to: root.appendingPathComponent("reconstruction.json"))

        #expect(throws: MacroReconstructionCandidateInputError.unsupportedActionContextVersion("macro-reconstruction-action-context/v0")) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: root)
        }
    }

    @Test("Package import rejects source-context metadata copied from another source")
    func packageImportRejectsMismatchedSourceContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = macro()
        var second = macro()
        second.events[0].x += 55
        let firstPackage = root.appendingPathComponent("first")
        let secondPackage = root.appendingPathComponent("second")
        _ = try MacroReconstructionPackage.export(source: first, to: firstPackage)
        _ = try MacroReconstructionPackage.export(source: second, to: secondPackage)
        try Data(contentsOf: firstPackage.appendingPathComponent("candidate-template.json"))
            .write(to: firstPackage.appendingPathComponent("candidate.json"))
        try FileManager.default.removeItem(at: firstPackage.appendingPathComponent("source-context.json"))
        try FileManager.default.copyItem(
            at: secondPackage.appendingPathComponent("source-context.json"),
            to: firstPackage.appendingPathComponent("source-context.json")
        )

        #expect(throws: MacroReconstructionCandidateInputError.packageSourceRevisionMismatch) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: firstPackage)
        }
    }

    @Test("Package import rejects stale capability metadata before candidate storage")
    func packageImportRejectsStaleCapabilities() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        let url = root.appendingPathComponent("authoring-contract.json")
        var contract = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        var capabilities = try #require(contract["capabilities"] as? [String: Any])
        capabilities["version"] = "macro-candidate/v2"
        contract["capabilities"] = capabilities
        try JSONSerialization.data(withJSONObject: contract).write(to: url)

        #expect(throws: MacroReconstructionCandidateInputError.unsupportedCapabilityVersion("macro-candidate/v2")) {
            try MacroReconstructionCandidateInputResolver.decodeInput(at: root)
        }
    }

    @Test("V4 package imports the pre-required-event-fields v4 capability profile")
    func v4PackageImportsLegacyV4Capability() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        try rewriteV4Capability(at: root, version: "macro-candidate/v4", includeRequiredEventMetadata: false)

        let input = try MacroReconstructionCandidateInputResolver.decodeInput(at: root, source: source)
        #expect(input.importProvenance.capabilityVersion == "macro-candidate/v4")
    }

    @Test("V4 package imports the transitional v4 capability profile")
    func v4PackageImportsTransitionalV4Capability() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        _ = try MacroReconstructionPackage.export(source: source, to: root)
        try Data(contentsOf: root.appendingPathComponent("candidate-template.json"))
            .write(to: root.appendingPathComponent("candidate.json"))
        try rewriteV4Capability(at: root, version: "macro-candidate/v4", includeRequiredEventMetadata: true)

        let input = try MacroReconstructionCandidateInputResolver.decodeInput(at: root, source: source)
        #expect(input.importProvenance.capabilityVersion == "macro-candidate/v4")
    }

    @Test func legacyAppOwnedCandidateFieldExplainsReExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)

        let revision = try MacroCandidateIdentity.revision(of: source)
        let actions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
        let targets = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: "candidate")
        let document = MacroCandidateDocument(
            macro: source,
            sourceRevision: revision,
            coverage: zip(actions, targets).map {
                MacroCandidateCoverage(
                    sourceActionID: $0.0.id,
                    candidateActionIDs: [$0.1.id],
                    reason: "Preserved source action"
                )
            }
        )
        let strict = try MacroCandidateAuthoringProjection.encode(document)
        var rootObject = try #require(JSONSerialization.jsonObject(with: strict) as? [String: Any])
        var macroObject = try #require(rootObject["macro"] as? [String: Any])
        macroObject["followWindowOffset"] = true
        rootObject["macro"] = macroObject
        let candidateURL = root.appendingPathComponent("legacy-candidate.json")
        try JSONSerialization.data(withJSONObject: rootObject).write(to: candidateURL)

        await #expect(
            throws: MacroReconstructionCandidateInputError.outdatedCandidateFormat(field: "followWindowOffset")
        ) {
            try await MacroReconstructionCLI.execute(
                ["import", "--macro-id", source.id.uuidString, "--candidate", candidateURL.path],
                appSupportURL: root
            )
        }
    }

    @Test func importPackageWithoutCandidateExplainsMissingResult() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)

        let output = root.appendingPathComponent("package")
        _ = try await MacroReconstructionCLI.execute(
            ["export", "--macro-id", source.id.uuidString, "--output", output.path], appSupportURL: root)

        await #expect(throws: MacroReconstructionCandidateInputError.missingCandidateInPackage) {
            try await MacroReconstructionCLI.execute(
                ["import", "--macro-id", source.id.uuidString, "--candidate", output.path], appSupportURL: root)
        }
    }

    @Test func exportAndImportRetainAcceptedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let output = root.appendingPathComponent("package")
        let exported = try await MacroReconstructionCLI.execute(
            ["export", "--macro-id", source.id.uuidString, "--output", output.path], appSupportURL: root)
        #expect(exported.outputPath == output.path)
        #expect(exported.packageReport?.visualEvidenceIncluded == false)
        let candidate = output.appendingPathComponent("candidate.json")
        try Data(contentsOf: output.appendingPathComponent("candidate-template.json")).write(to: candidate)
        let imported = try await MacroReconstructionCLI.execute(
            ["import", "--macro-id", source.id.uuidString, "--candidate", candidate.path], appSupportURL: root)
        #expect(imported.candidateID != nil)
        #expect(imported.requiresAttention == false)
        #expect(try await repo.loadMacro(for: source.id) == source)
        let candidateID = try #require(imported.candidateID)
        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repo.acceptCandidate(candidateID: candidateID, for: source.id)
        }
    }

    @Test func helpIsDiscoverableWithoutAccessingTheLibrary() async throws {
        for arguments in [[], ["--help"], ["help", "--json"], ["export", "--help"]] {
            let result = try await MacroReconstructionCLI.execute(arguments)
            #expect(result.command == "help")
            #expect(result.usage?.contains("reconstruction import") == true)
            #expect(result.summary.contains("workflow macros --json"))
            #expect(result.summary.contains("Refine"))
        }
        #expect(throws: MacroReconstructionCLIError.self) {
            try MacroReconstructionCLI.parse(["accept", "--help"])
        }
    }

    @Test func summariesGuideTheNextUserDecision() {
        let exported = MacroReconstructionCLIResult(command: "export", outputPath: "/tmp/package")
        #expect(exported.summary.contains("harness.json"))
        let imported = MacroReconstructionCLIResult(command: "import", candidateID: UUID(), requiresAttention: true)
        #expect(imported.summary.contains("Refine"))
        #expect(imported.summary.contains("uncertainties"))
        #expect(imported.summary.contains("unchanged"))
    }

    private struct LegacySourceContextV2: Encodable {
        var version: String
        var sourceRevision: String
        var macroID: UUID
        var name: String
        var macroVersion: Int
        var events: [RecordedEvent]
        var surfaces: [String: MacroReconstructionSurfaceContext]
        var protectedExecution: MacroReconstructionSourceContext.ProtectedExecution
    }

    private func writeLegacyV3Package(source: SavedMacro, to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let template = try MacroReconstructionCandidateTemplate.document(source: source)
        let revision = template.sourceRevision
        let sourceActions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
        let surfaces = Dictionary(uniqueKeysWithValues: source.surfaces.map { id, surface in
            (id, MacroReconstructionSurfaceContext(id: id, surface: surface))
        })
        let sourceContext = LegacySourceContextV2(
            version: "macro-reconstruction-source/v2",
            sourceRevision: revision,
            macroID: source.id,
            name: source.name,
            macroVersion: source.version,
            events: source.events,
            surfaces: surfaces,
            protectedExecution: .init(
                loops: source.loops,
                speed: source.speed,
                followWindowOffset: source.followWindowOffset,
                hasChainedMacro: source.chainTo != nil
            )
        )
        var actionContext = MacroReconstructionActionContextProjector.document(
            actions: sourceActions,
            events: source.events,
            surfaceContexts: surfaces,
            sourceRevision: revision
        )
        actionContext.version = "macro-reconstruction-action-context/v2"
        actionContext.actions = actionContext.actions.map { row in
            var legacy = row
            legacy.pointerButton = nil
            legacy.clickCount = nil
            legacy.keyboardLabel = nil
            legacy.textInputPreview = nil
            legacy.textInputCharacterCount = nil
            legacy.scrollDeltaX = nil
            legacy.scrollDeltaY = nil
            return legacy
        }
        let contract = MacroReconstructionContractManifest(
            version: MacroReconstructionContractVersions.manifest,
            packageVersion: "macro-reconstruction-package/v3",
            candidateCapabilityVersion: MacroCandidateCapabilities.current.version,
            authoringPolicyVersion: MacroReconstructionAuthoringPolicy.currentVersion,
            sourceContextVersion: "macro-reconstruction-source/v2",
            actionContextVersion: "macro-reconstruction-action-context/v2",
            candidateActionRevision: MacroReconstructionContractVersions.candidateActionRevision
        )
        let report = MacroReconstructionPackageReport(
            packageVersion: "macro-reconstruction-package/v3",
            sourceRevision: revision,
            visualEvidenceIncluded: false,
            artifacts: [],
            warnings: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            try encoder.encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
        }
        try write(contract, "contract.json")
        try write(MacroCandidateCapabilities.current, "capabilities.json")
        try write(MacroReconstructionAuthoringPolicy(objective: .robust), "authoring-policy.json")
        try write(sourceContext, "source-context.json")
        try write(actionContext, "reconstruction.json")
        try write(report, "manifest.json")
        try MacroCandidateAuthoringProjection.encode(template)
            .write(to: root.appendingPathComponent("candidate-template.json"), options: .atomic)
        try MacroCandidateAuthoringProjection.encode(template)
            .write(to: root.appendingPathComponent("candidate.json"), options: .atomic)
    }

    private func rewriteV4Capability(
        at root: URL,
        version: String,
        includeRequiredEventMetadata: Bool
    ) throws {
        let harnessURL = root.appendingPathComponent("harness.json")
        var harness = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: harnessURL)) as? [String: Any]
        )
        var contracts = try #require(harness["contracts"] as? [String: Any])
        contracts["candidateCapabilityVersion"] = version
        harness["contracts"] = contracts
        try JSONSerialization.data(withJSONObject: harness).write(to: harnessURL)

        let authoringURL = root.appendingPathComponent("authoring-contract.json")
        var authoring = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: authoringURL)) as? [String: Any]
        )
        var capabilities = try #require(authoring["capabilities"] as? [String: Any])
        capabilities["version"] = version
        if !includeRequiredEventMetadata {
            capabilities.removeValue(forKey: "requiredEventFields")
            let rules = try #require(authoring["rules"] as? [[String: Any]])
            authoring["rules"] = rules.filter { ($0["id"] as? String) != "schema.requiredEventFields" }
        }
        authoring["capabilities"] = capabilities
        try JSONSerialization.data(withJSONObject: authoring).write(to: authoringURL)
    }

    private func rewriteLegacyV3Capability(
        at root: URL,
        version: String,
        includeRequiredEventMetadata: Bool
    ) throws {
        let contractURL = root.appendingPathComponent("contract.json")
        var contract = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: contractURL)) as? [String: Any]
        )
        contract["candidateCapabilityVersion"] = version
        try JSONSerialization.data(withJSONObject: contract).write(to: contractURL)

        let capabilitiesURL = root.appendingPathComponent("capabilities.json")
        var capabilities = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: capabilitiesURL)) as? [String: Any]
        )
        capabilities["version"] = version
        if !includeRequiredEventMetadata {
            capabilities.removeValue(forKey: "requiredEventFields")
        }
        try JSONSerialization.data(withJSONObject: capabilities).write(to: capabilitiesURL)
    }

    private func macro() -> SavedMacro {
        SavedMacro(name: "CLI source", events: [RecordedEvent(kind: .mouseMoved, time: 0, x: 10, y: 20,
            keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)])
    }
}
