import Foundation
import Testing
@testable import SparkleRecorderCore
@testable import SparkleRecorder

@Suite("Macro reconstruction package")
struct MacroReconstructionPackageTests {
    @Test("Export writes minimal source context and a strict candidate template without executing")
    func sourceAndTemplate() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let source = SavedMacro(name: "Example", events: TestFixtures.clickPair())
        let report = try MacroReconstructionPackage.export(source: source, to: output)
        #expect(report.sourceRevision == (try MacroCandidateIdentity.revision(of: source)))
        let decoded = try JSONDecoder().decode(
            MacroReconstructionSourceContext.self,
            from: Data(contentsOf: output.appendingPathComponent("source-context.json"))
        )
        #expect(decoded.sourceRevision == report.sourceRevision)
        #expect(decoded.eventCount == source.events.count)
        #expect(decoded.duration == (source.events.last?.time ?? 0))
        #expect(Set(decoded.surfaces.keys) == Set(source.surfaces.keys))
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("source-macro.json").path))
        let template = try MacroCandidateValidator.decode(Data(contentsOf: output.appendingPathComponent("candidate-template.json")))
        let harness = try JSONDecoder().decode(
            MacroReconstructionHarnessIndex.self,
            from: Data(contentsOf: output.appendingPathComponent("harness.json"))
        )
        let authoring = try JSONDecoder().decode(
            MacroReconstructionAuthoringContract.self,
            from: Data(contentsOf: output.appendingPathComponent("authoring-contract.json"))
        )
        #expect(template.sourceRevision == report.sourceRevision)
        #expect(authoring.policy.objective == .robust)
        #expect(authoring.policy.preferContentNormalizedTextGeometry)
        #expect(template.coverage.count == 1)
        #expect(report.artifacts.isEmpty)
        #expect(harness.readingPlan.contains { $0.id == "selfCheck" })
    }

    @Test("Export writes one canonical harness whose nested contracts match package context")
    func canonicalHarnessMatchesPackageFiles() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let source = SavedMacro(name: "Contracts", events: TestFixtures.clickPair())

        let report = try MacroReconstructionPackage.export(source: source, to: output)
        let decoder = JSONDecoder()
        let harness = try decoder.decode(
            MacroReconstructionHarnessIndex.self,
            from: Data(contentsOf: output.appendingPathComponent("harness.json"))
        )
        let authoring = try decoder.decode(
            MacroReconstructionAuthoringContract.self,
            from: Data(contentsOf: output.appendingPathComponent("authoring-contract.json"))
        )
        let sourceContext = try decoder.decode(
            MacroReconstructionSourceContext.self,
            from: Data(contentsOf: output.appendingPathComponent("source-context.json"))
        )
        let actionContext = try decoder.decode(
            MacroReconstructionActionContextDocument.self,
            from: Data(contentsOf: output.appendingPathComponent("reconstruction.json"))
        )

        #expect(harness.version == MacroReconstructionHarnessIndex.currentVersion)
        #expect(harness.contracts == .current)
        #expect(authoring.version == harness.contracts.authoringContractVersion)
        #expect(authoring.capabilities == .current)
        #expect(report.packageVersion == harness.contracts.packageVersion)
        #expect(sourceContext.version == harness.contracts.sourceContextVersion)
        #expect(actionContext.version == harness.contracts.actionContextVersion)
        #expect(authoring.policy.version == harness.contracts.authoringPolicyVersion)
        #expect(authoring.capabilities.candidateActionRevision == harness.contracts.candidateActionRevision)
        #expect(sourceContext.sourceRevision == actionContext.sourceRevision)
        #expect(sourceContext.sourceRevision == harness.sourceRevision)
        #expect(sourceContext.sourceRevision == report.sourceRevision)
    }

    @Test("Reconstruction action context exposes target surface and geometry directly to AI")
    func reconstructionActionContextIncludesSurfaceAndGeometry() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }

        var events = TestFixtures.clickPair(downTime: 1, upTime: 1.1, x: 260, y: 340)
        for index in events.indices {
            events[index].surfaceId = TestFixtures.surfaceId
            events[index].contentNormalizedX = 0.25
            events[index].contentNormalizedY = 0.5
        }
        let source = SavedMacro(
            name: "Surface-aware source",
            events: events,
            surfaces: [TestFixtures.surfaceId: TestFixtures.surface(
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                windowTitle: "ChatGPT",
                recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
                recordedContentFrame: RectValue(x: 100, y: 140, width: 800, height: 560)
            )]
        )

        _ = try MacroReconstructionPackage.export(source: source, to: output)
        let data = try Data(contentsOf: output.appendingPathComponent("reconstruction.json"))
        let document = try JSONDecoder().decode(MacroReconstructionActionContextDocument.self, from: data)
        #expect(document.version == MacroReconstructionContractVersions.actionContext)
        #expect(document.sourceRevision == (try MacroCandidateIdentity.revision(of: source)))
        let row = try #require(document.actions.first)

        #expect(row.surfaceID == TestFixtures.surfaceId)
        #expect(row.startPoint?.x == 260)
        #expect(row.startContentNormalized?.x == 0.25)
        let surface = try #require(row.surface)
        #expect(surface.id == TestFixtures.surfaceId)
        #expect(surface.bundleIdentifier == "com.google.Chrome")
        #expect(surface.windowTitle == "ChatGPT")
        #expect(surface.recordedContentFrame != nil)
    }

    @Test("Export writes the selected AI reconstruction objective without expanding capabilities")
    func authoringObjectiveIsMachineReadable() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let source = SavedMacro(name: "Faithful source", events: TestFixtures.clickPair())

        _ = try MacroReconstructionPackage.export(
            source: source,
            objective: .faithful,
            to: output
        )
        let authoring = try JSONDecoder().decode(
            MacroReconstructionAuthoringContract.self,
            from: Data(contentsOf: output.appendingPathComponent("authoring-contract.json"))
        )
        let policy = authoring.policy

        #expect(policy.objective == .faithful)
        #expect(!policy.preferEvidenceBackedTextLocators)
        #expect(!policy.replaceRecordedGapsWithBoundedWaits)
        #expect(!policy.preferContentNormalizedTextGeometry)
        #expect(policy.preservePathSensitiveGestures)
        #expect(policy.prohibitUnsupportedVisualLocators)
        #expect(authoring.capabilities.locatorKinds == ["text"])
    }

    @Test("Legacy authoring policy decodes normalized text geometry preference from its objective")
    func legacyAuthoringPolicyDefaultsNormalizedTextGeometryPreference() throws {
        for objective in [MacroReconstructionObjective.faithful, .robust] {
            let encoded = try JSONEncoder().encode(MacroReconstructionAuthoringPolicy(objective: objective))
            var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object.removeValue(forKey: "preferContentNormalizedTextGeometry")
            let legacy = try JSONSerialization.data(withJSONObject: object)

            let decoded = try JSONDecoder().decode(MacroReconstructionAuthoringPolicy.self, from: legacy)

            #expect(decoded.preferContentNormalizedTextGeometry == (objective == .robust))
        }
    }

    @Test("Library metadata never leaks into the strict candidate authoring template")
    func libraryMetadataIsProjectedOutOfCandidateTemplate() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        var source = SavedMacro(
            name: "Library macro",
            events: TestFixtures.clickPair(),
            libraryOrder: 0,
            hotkey: HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048),
            notes: "private library note",
            chainTo: UUID(),
            playCount: 17,
            lastPlayedAt: Date(timeIntervalSince1970: 123),
            totalRunTime: 456
        )
        source.cachedDuration = 999
        source.cachedEventCount = 999
        source.cachedWaveformBars = [WaveformBar(id: 0, kind: .leftMouseDown, positionFraction: 0.5, isImpact: true)]

        _ = try MacroReconstructionPackage.export(source: source, to: output)
        let templateData = try Data(contentsOf: output.appendingPathComponent("candidate-template.json"))
        let template = try MacroCandidateValidator.decode(templateData)
        let root = try #require(JSONSerialization.jsonObject(with: templateData) as? [String: Any])
        let macro = try #require(root["macro"] as? [String: Any])

        #expect(template.macro.events == source.events)
        #expect(template.macro.surfaces.isEmpty)
        #expect(macro["surfaces"] == nil)
        #expect(macro["libraryOrder"] == nil)
        #expect(macro["playCount"] == nil)
        #expect(macro["lastPlayedAt"] == nil)
        #expect(macro["totalRunTime"] == nil)
        #expect(macro["cachedDuration"] == nil)
        #expect(macro["cachedEventCount"] == nil)
        #expect(macro["cachedWaveformBars"] == nil)
        #expect(macro["hotkey"] == nil)
        #expect(macro["chainTo"] == nil)
        #expect(macro["semanticRecording"] == nil)
        #expect(macro["playableSanitization"] == nil)

        let normalized = try MacroCandidateValidator.normalize(template, source: source)
        #expect(normalized.libraryOrder == source.libraryOrder)
        #expect(normalized.playCount == source.playCount)
        #expect(normalized.hotkey == source.hotkey)
        #expect(normalized.chainTo == source.chainTo)
        #expect(normalized.events == source.events)
        #expect(normalized.surfaces == source.surfaces)
    }

    @Test("Aligned mechanical evidence is exported with playable provenance and stale evidence is withheld")
    func mechanicalEvidenceRequiresCurrentSourceIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceEvent = RecordedEvent.make(.scrollWheel, time: 1, x: 20, y: 30)
        let source = SavedMacro(name: "Mechanical evidence", events: [sourceEvent])
        let sample = RecordingEvidenceSample(index: 0, event: sourceEvent)
        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 100,
            sessionEndTime: 2,
            sourceEvents: [.init(sourceEventIndex: 0, sourcePlaybackTime: 1, sessionTime: 1)],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: source.events),
            playableEvidenceLinks: [.init(playableEventIndex: 0, evidenceSampleRange: 0...0)]
        )
        let bundle = SemanticRecordingBundle(
            inputEvidenceSamples: [sample],
            reconstructionProvenance: provenance
        )

        let aligned = root.appendingPathComponent("aligned")
        let report = try MacroReconstructionPackage.export(source: source, bundle: bundle, to: aligned)
        #expect(report.mechanicalEvidenceIncluded)
        #expect(FileManager.default.fileExists(atPath: aligned.appendingPathComponent("input-evidence.json").path))
        let exported = try JSONDecoder().decode(
            [RecordingEvidenceSample].self,
            from: Data(contentsOf: aligned.appendingPathComponent("input-evidence.json"))
        )
        #expect(exported == [sample])

        var edited = source
        edited.events[0].x += 10
        let stale = root.appendingPathComponent("stale")
        let staleReport = try MacroReconstructionPackage.export(source: edited, bundle: bundle, to: stale)
        #expect(!staleReport.mechanicalEvidenceIncluded)
        #expect(!FileManager.default.fileExists(atPath: stale.appendingPathComponent("input-evidence.json").path))
    }

    @Test("Edited and legacy sources cannot export old alignment as current", arguments: 0...2)
    func sourceContentBinding(variant: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = TestFixtures.clickPair()
        var source = SavedMacro(name: "Edited source", events: original)
        if variant == 1 { source.events[0].x += 50 }
        var provenance = RecordingReconstructionProvenance(sessionOriginHostTime: 100, sessionEndTime: 2,
            sourceEvents: [.init(sourceEventIndex: 0, sourcePlaybackTime: original[0].time, sessionTime: 0)],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: original))
        if variant == 2 { provenance.sourceEventDigest = nil }
        let report = try MacroReconstructionPackage.export(source: source,
            bundle: SemanticRecordingBundle(reconstructionProvenance: provenance), to: root)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("alignment.json").path) == (variant == 0))
        #expect(report.sourceEventsMatchRecording == (variant == 0))
        if variant != 0 { #expect(report.warnings.contains { $0.contains("source event content") }) }
    }

    @Test("Export refuses existing output rather than mixing evidence packages")
    func refusesExistingDirectory() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        #expect(throws: (any Error).self) {
            try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []), to: output)
        }
    }

    @Test("Visual evidence needs explicit inclusion and missing files stay reported")
    func visualOptIn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = SemanticRecordingBundle(videoSegments: [RecordingVideoSegment(
            artifactRef: try RecordingArtifactRef("video/missing.mov"), startTime: 0, duration: 1
        )])
        let report = try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
            bundle: bundle, bundleDirectory: root, includeVisualEvidence: false, to: root.appendingPathComponent("export"))
        #expect(report.artifacts.isEmpty)
        #expect(!report.visualEvidenceIncluded)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("export/visual-inspection.json").path))
    }

    @Test("Aligned visual export gives AI seek crop and zoom navigation without inventing locators")
    func alignedVisualInspectionGuide() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleRoot = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundleRoot.appendingPathComponent("video"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundleRoot.appendingPathComponent("frames"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var events = TestFixtures.clickPair(downTime: 0, upTime: 0.1, x: 600, y: 450)
        events.indices.forEach { events[$0].surfaceId = "surface-1" }
        let source = SavedMacro(name: "Visual target", events: events)
        let segmentID = UUID()
        let frameID = UUID()
        let videoRef = try RecordingArtifactRef("video/source.mov")
        let frameRef = try RecordingArtifactRef("frames/source.png")
        try Data("video".utf8).write(to: bundleRoot.appendingPathComponent(videoRef.path))
        try Data("frame".utf8).write(to: bundleRoot.appendingPathComponent(frameRef.path))
        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 100,
            sessionEndTime: 4,
            sourceEvents: [
                .init(sourceEventIndex: 0, sourcePlaybackTime: 0, sessionTime: 2),
                .init(sourceEventIndex: 1, sourcePlaybackTime: 0.1, sessionTime: 2.1)
            ],
            clockSegments: [
                .init(
                    id: segmentID.uuidString,
                    anchors: [.init(recordingTime: 1, videoTime: 0), .init(recordingTime: 4, videoTime: 3)],
                    maximumError: 0
                )
            ],
            geometrySnapshots: [
                .init(
                    surfaceID: "surface-1",
                    recordingTime: 1,
                    validUntil: 4,
                    captureBounds: RectValue(x: 100, y: 200, width: 1_000, height: 500),
                    frameSize: RecordingImageSize(width: 2_000, height: 1_000)
                )
            ],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: events)
        )
        let bundle = SemanticRecordingBundle(
            videoSegments: [
                RecordingVideoSegment(
                    id: segmentID,
                    artifactRef: videoRef,
                    startTime: 0,
                    duration: 3,
                    frameSize: RecordingImageSize(width: 2_000, height: 1_000)
                )
            ],
            frames: [
                RecordingFrameReference(
                    id: frameID,
                    recordingTime: 2.05,
                    videoSegmentID: segmentID,
                    videoTime: 1.05,
                    imageRef: frameRef,
                    imageSize: RecordingImageSize(width: 2_000, height: 1_000),
                    source: .mouseUp,
                    surfaceID: "surface-1"
                )
            ],
            reconstructionProvenance: provenance
        )
        let output = root.appendingPathComponent("export")
        let report = try MacroReconstructionPackage.export(
            source: source,
            bundle: bundle,
            bundleDirectory: bundleRoot,
            includeVisualEvidence: true,
            to: output
        )

        #expect(report.visualEvidenceIncluded)
        let guideURL = output.appendingPathComponent("visual-inspection.json")
        #expect(FileManager.default.fileExists(atPath: guideURL.path))
        let guide = try JSONDecoder().decode(MacroVisualInspectionGuide.self, from: Data(contentsOf: guideURL))
        let action = try #require(guide.actions.first)
        #expect(action.video?.artifactPath == "video/\(segmentID.uuidString).mov")
        #expect(action.frames.map(\.artifactPath) == ["frames/\(frameID.uuidString).png"])
        #expect(action.focuses.first?.primaryRegion.normalizedFrame.coordinateSpace == .normalizedFrame)
        #expect(action.focuses.first?.contextRegion.framePixels.coordinateSpace == .framePixels)
        let harness = try JSONDecoder().decode(
            MacroReconstructionHarnessIndex.self,
            from: Data(contentsOf: output.appendingPathComponent("harness.json"))
        )
        let authoring = try JSONDecoder().decode(
            MacroReconstructionAuthoringContract.self,
            from: Data(contentsOf: output.appendingPathComponent("authoring-contract.json"))
        )
        #expect(harness.readingPlan.contains { $0.id == "inspectOnDemand" })
        #expect(harness.readingPlan.contains { $0.id == "draft" })
        #expect(authoring.rules.contains { $0.id == "text.explicitSurface" })
        #expect(authoring.rules.contains { $0.id == "text.normalizedGeometry" })
        #expect(authoring.rules.contains { $0.id == "evidence.supportedLocatorsOnly" })
    }

    @Test("Suppressed movie export requires an exact complete clock and current redaction receipt", arguments: 0...7)
    func suppressedMovieEvidence(variant: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try RecordingArtifactRef("original.mov")
        let redacted = try RecordingArtifactRef("redacted.mov")
        try Data("private".utf8).write(to: root.appendingPathComponent(original.path))
        try Data("masked".utf8).write(to: root.appendingPathComponent(redacted.path))
        let segment = RecordingVideoSegment(artifactRef: original, startTime: 0, duration: 10)
        let suppression = RecordingSuppressionRecord(reason: .privateRegion,
            timeRange: RecordingTimeRange(startTime: 4, duration: 1))
        let anchors = variant == 2
            ? [RecordingVideoClockAnchor(recordingTime: 2, videoTime: 0), .init(recordingTime: 12, videoTime: 10)]
            : [RecordingVideoClockAnchor(recordingTime: 0, videoTime: 0), .init(recordingTime: 10, videoTime: 10)]
        let clock = RecordingVideoClockSegment(id: segment.id.uuidString, anchors: anchors,
            maximumError: variant == 3 ? 0.01 : 0)
        let receipt = SemanticRecordingRenderedVideoRedaction(videoSegmentID: segment.id,
            sourceVideoRef: variant == 4 ? redacted : original,
            redactedVideoRef: variant == 7 ? original : redacted,
            renderedRangeCount: variant == 6 ? 0 : 1,
            sourceSuppressionIDs: variant == 5 ? [] : [suppression.id])
        let bundle = SemanticRecordingBundle(videoSegments: [segment], suppressions: [suppression],
            redactedVideos: [receipt], reconstructionProvenance: .init(sessionOriginHostTime: 100,
                sessionEndTime: 10, clockSegments: variant == 1 ? [] : [clock]))
        let report = try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
            bundle: bundle, bundleDirectory: root, includeVisualEvidence: true, to: root.appendingPathComponent("export"))
        #expect(report.visualEvidenceIncluded == (variant == 0))
        #expect(report.artifacts.count == (variant == 0 ? 1 : 0))
    }

    @Test("Suppressed frames require matching source, full mask coverage and distinct bytes", arguments: 0...5)
    func suppressedFrameEvidence(variant: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try RecordingArtifactRef("original.png")
        let redacted = try RecordingArtifactRef("redacted.png")
        try Data("private".utf8).write(to: root.appendingPathComponent(original.path))
        if variant == 5 {
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(redacted.path),
                withDestinationURL: root.appendingPathComponent(original.path))
        } else {
            try Data("masked".utf8).write(to: root.appendingPathComponent(redacted.path))
        }
        let frame = RecordingFrameReference(recordingTime: 1, imageRef: original,
            imageSize: .init(width: 10, height: 10), source: .manual)
        let suppression = RecordingSuppressionRecord(reason: .privateRegion, frameID: frame.id)
        let receipt = SemanticRecordingRenderedFrameRedaction(frameID: frame.id,
            sourceImageRef: variant == 1 ? redacted : original,
            redactedImageRef: variant == 4 ? original : redacted,
            renderedMaskCount: variant == 3 ? 0 : 1,
            sourceSuppressionIDs: variant == 2 ? [] : [suppression.id])
        let bundle = SemanticRecordingBundle(frames: [frame], suppressions: [suppression], redactedFrames: [receipt])
        let report = try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
            bundle: bundle, bundleDirectory: root, includeVisualEvidence: true, to: root.appendingPathComponent("export"))
        #expect(report.visualEvidenceIncluded == (variant == 0))
        #expect(report.artifacts.count == (variant == 0 ? 1 : 0))
    }

    @Test("Visual export rejects an artifact symlink outside the bundle")
    func externalArtifactSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleRoot = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let privateFile = root.appendingPathComponent("private.png")
        try Data("private".utf8).write(to: privateFile)
        try FileManager.default.createSymbolicLink(at: bundleRoot.appendingPathComponent("frame.png"), withDestinationURL: privateFile)
        let frame = RecordingFrameReference(recordingTime: 0, imageRef: try RecordingArtifactRef("frame.png"), source: .manual)
        #expect(throws: (any Error).self) {
            try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
                bundle: SemanticRecordingBundle(frames: [frame]), bundleDirectory: bundleRoot,
                includeVisualEvidence: true, to: root.appendingPathComponent("export"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("export").path))
    }

}
