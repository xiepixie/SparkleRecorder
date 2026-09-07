import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Macro reconstruction harness contract")
struct MacroReconstructionHarnessContractTests {
    @Test("Harness vocabulary covers every executable event and every project action kind")
    func vocabularyIsExhaustive() {
        let authoring = MacroReconstructionAuthoringContract(objective: .robust)

        #expect(Set(authoring.executableEventKinds.map(\.code)) == Set(RecordedEvent.Kind.allCases.map(\.rawValue)))
        #expect(Set(authoring.capabilities.eventKinds) == Set(RecordedEvent.Kind.allCases.map(\.rawValue)))
        #expect(Set(authoring.reconstructionActionKinds.map(\.name)) == Set(ActionGroupKind.allCases.map(\.rawValue)))
        #expect(authoring.reconstructionActionKinds.first(where: { $0.name == ActionGroupKind.sequence.rawValue })?.exportedByReconstructor == false)
        #expect(authoring.reconstructionActionKinds.first(where: { $0.name == ActionGroupKind.waitForTextGone.rawValue })?.candidateRepresentation.contains("kind=100") == true)
        #expect(authoring.reconstructionActionKinds.first(where: { $0.name == ActionGroupKind.verifyText.rawValue })?.candidateRepresentation.contains("kind=101") == true)
    }

    @Test("Harness expands every string enum accepted by candidate JSON")
    func enumCatalogIsExhaustive() {
        let values = MacroReconstructionAuthoringContract(objective: .robust).enumValues

        #expect(values.coordinateBinding == CoordinateBinding.allCases.map(\.rawValue))
        #expect(values.coordinateStrategy == CoordinateStrategy.allCases.map(\.rawValue))
        #expect(values.locatorFallbackPolicy == LocatorFallbackPolicy.allCases.map(\.rawValue))
        #expect(values.textMatchMode == TextMatchMode.allCases.map(\.rawValue))
        #expect(values.coverageDisposition == MacroCandidateDisposition.allCases.map(\.rawValue))
        #expect(values.reconstructionObjective == MacroReconstructionObjective.allCases.map(\.rawValue))
    }

    @Test("Authoring contract exposes the major strict-validator rule families")
    func authoringRulesCoverValidatorFamilies() {
        let ids = Set(MacroReconstructionAuthoringContract.authoringRules.map(\.id))
        let expected: Set<String> = [
            "schema.knownFieldsOnly", "schema.supportedMacroVersion",
            "timeline.nonDecreasing", "coordinates.finiteBounds", "coordinates.completePairs",
            "pointer.fieldBounds", "input.balancedPointer", "input.balancedKeyboard",
            "surface.referenceExists", "surface.explicitTargetWindow", "surface.validDefinition", "surface.sourceOwned",
            "text.explicitSurface", "text.locatorMouseContract", "text.stableGestureIdentity",
            "text.boundedObservation", "text.anchorBounds", "text.fallbackRequiresPoint", "text.normalizedGeometry",
            "scroll.payloadBounds", "coverage.complete", "coverage.targets", "uncertainty.knownActions",
            "execution.sourceOwned", "privacy.noReadableRestoration", "disabled.stillValidated"
        ]
        #expect(expected.isSubset(of: ids))
    }

    @Test("Every executable event kind survives strict external authoring round trip")
    func everyExecutableEventKindRoundTrips() throws {
        for kind in RecordedEvent.Kind.allCases {
            let events = validSequence(containing: kind)
            #expect(events.contains(where: { $0.kind == kind }), "Fixture must contain \(kind)")
            let source = SavedMacro(
                name: "Round trip \(kind.rawValue)",
                events: events,
                surfaces: [TestFixtures.surfaceId: TestFixtures.surface(
                    recordedContentFrame: RectValue(x: 100, y: 100, width: 800, height: 600)
                )]
            )
            let sourceRevision = try MacroCandidateIdentity.revision(of: source)
            let sourceActions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: sourceRevision)
            let candidateActions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "candidate")
            let document = MacroCandidateDocument(
                macro: source,
                sourceRevision: sourceRevision,
                summary: "round trip",
                coverage: zip(sourceActions, candidateActions).map { sourceAction, candidateAction in
                    MacroCandidateCoverage(
                        sourceActionID: sourceAction.id,
                        disposition: .preserved,
                        candidateActionIDs: [candidateAction.id],
                        reason: "round trip"
                    )
                },
                model: "test"
            )

            let authored = try MacroCandidateAuthoringProjection.encode(document)
            let decoded = try MacroCandidateValidator.decode(authored)
            let normalized = try MacroCandidateValidator.normalize(decoded, source: source)
            #expect(normalized.events == events, "Strict candidate round trip changed \(kind)")
        }
    }

    @Test("AI-authored text-locator rewrite from an exported package imports and normalizes")
    func aiAuthoredRewriteImportsFromPackage() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        var events = TestFixtures.clickPair(downTime: 0.5, upTime: 0.6, x: 240, y: 180)
        events.indices.forEach { events[$0].surfaceId = TestFixtures.surfaceId }
        let source = SavedMacro(
            name: "AI rewrite",
            events: events,
            surfaces: [TestFixtures.surfaceId: TestFixtures.surface(
                recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
                recordedContentFrame: RectValue(x: 100, y: 100, width: 800, height: 600)
            )]
        )
        _ = try MacroReconstructionPackage.export(source: source, to: output)

        var candidate = try MacroCandidateValidator.decode(
            Data(contentsOf: output.appendingPathComponent("candidate-template.json"))
        )
        let anchor = TextAnchor(
            text: "New chat",
            matchMode: .contains,
            observedFrame: RectValue(x: 205, y: 168, width: 90, height: 24),
            searchRegion: RectValue(x: 180, y: 140, width: 180, height: 80),
            coordinateFallback: PointValue(x: 240, y: 180)
        )
        for index in candidate.macro.events.indices {
            candidate.macro.events[index].surfaceId = TestFixtures.surfaceId
            candidate.macro.events[index].coordinateBinding = .targetWindow
            candidate.macro.events[index].coordinateStrategy = .locatorOnly
            candidate.macro.events[index].locatorFallbackPolicy = .allowCoordinateFallback
            candidate.macro.events[index].textAnchor = anchor
            candidate.macro.events[index].textTimeout = 5
        }
        let sourceActions = try MacroActionReconstructor.reconstruct(
            events: source.events,
            sourceRevision: candidate.sourceRevision
        )
        let rewrittenActions = try MacroActionReconstructor.reconstruct(
            events: candidate.macro.events,
            sourceRevision: "candidate"
        )
        #expect(sourceActions.count == 1)
        #expect(rewrittenActions.count == 1)
        candidate.summary = "Replace fragile coordinate click with an evidence-backed text target."
        candidate.coverage = [
            MacroCandidateCoverage(
                sourceActionID: try #require(sourceActions.first).id,
                disposition: .replacedByLocator,
                candidateActionIDs: [try #require(rewrittenActions.first).id],
                reason: "The visible New chat label is a more stable target than the recorded pixel."
            )
        ]
        try MacroCandidateAuthoringProjection.encode(candidate)
            .write(to: output.appendingPathComponent("candidate.json"), options: .atomic)

        let input = try MacroReconstructionCandidateInputResolver.decodeInput(at: output, source: source)
        let normalized = try MacroCandidateValidator.normalize(input.document, source: source)
        #expect(normalized.events.count == 2)
        #expect(normalized.events.allSatisfy { $0.textAnchor?.text == "New chat" })
        #expect(normalized.events.allSatisfy { $0.coordinateStrategy == .locatorOnly })
        #expect(normalized.events.allSatisfy { $0.surfaceId == TestFixtures.surfaceId })
        #expect(input.importProvenance.packageVersion == MacroReconstructionContractVersions.package)
    }

    @Test("Layered package keeps overview files compact and raw events single-copy")
    func packageLayeringAvoidsContextDuplication() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let events = (0..<240).map { index in
            RecordedEvent(
                kind: .mouseMoved,
                time: Double(index) * 0.01,
                x: CGFloat(100 + index),
                y: 200,
                keyCode: 0,
                flags: 0,
                mouseButton: 0,
                clickCount: 0,
                scrollDeltaY: 0,
                scrollDeltaX: 0
            )
        }
        let source = SavedMacro(name: "Long source", events: events)

        _ = try MacroReconstructionPackage.export(source: source, to: output)

        let harnessData = try Data(contentsOf: output.appendingPathComponent("harness.json"))
        let authoringData = try Data(contentsOf: output.appendingPathComponent("authoring-contract.json"))
        let sourceData = try Data(contentsOf: output.appendingPathComponent("source-context.json"))
        let reconstructionData = try Data(contentsOf: output.appendingPathComponent("reconstruction.json"))
        let templateData = try Data(contentsOf: output.appendingPathComponent("candidate-template.json"))
        let sourceObject = try #require(JSONSerialization.jsonObject(with: sourceData) as? [String: Any])

        #expect(harnessData.count < 16_384)
        #expect(sourceData.count < 16_384)
        #expect(authoringData.count < 65_536)
        #expect(sourceObject["events"] == nil)
        #expect(reconstructionData.count < templateData.count)
        #expect(templateData.count > sourceData.count * 4)
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("observations.json").path))
    }

    @Test("New package has one canonical harness and no overlapping contract files")
    func packageUsesCanonicalHarnessEntryPoint() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let source = SavedMacro(name: "Harness", events: TestFixtures.clickPair())

        _ = try MacroReconstructionPackage.export(source: source, to: output)

        let required = ["harness.json", "authoring-contract.json", "source-context.json", "reconstruction.json", "candidate-template.json", "manifest.json"]
        for name in required {
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path), "Missing \(name)")
        }
        for redundant in ["contract.json", "capabilities.json", "authoring-policy.json", "instructions.md"] {
            #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent(redundant).path), "Redundant \(redundant) should not be exported")
        }

        let harness = try JSONDecoder().decode(
            MacroReconstructionHarnessIndex.self,
            from: Data(contentsOf: output.appendingPathComponent("harness.json"))
        )
        let authoring = try JSONDecoder().decode(
            MacroReconstructionAuthoringContract.self,
            from: Data(contentsOf: output.appendingPathComponent("authoring-contract.json"))
        )
        #expect(harness.contracts.packageVersion == MacroReconstructionContractVersions.package)
        #expect(harness.sourceRevision == (try MacroCandidateIdentity.revision(of: source)))
        #expect(harness.files.first(where: { $0.path == "candidate.json" })?.systemMaintained == false)
        #expect(harness.files.filter(\.requiredForImport).map(\.path).contains("harness.json"))
        #expect(authoring.version == MacroReconstructionContractVersions.authoringContract)
    }

    private func validSequence(containing kind: RecordedEvent.Kind) -> [RecordedEvent] {
        switch kind {
        case .leftMouseDown, .leftMouseUp:
            return mousePair(down: .leftMouseDown, up: .leftMouseUp, button: 0)
        case .rightMouseDown, .rightMouseUp:
            return mousePair(down: .rightMouseDown, up: .rightMouseUp, button: 1)
        case .mouseMoved:
            return [event(.mouseMoved, time: 0)]
        case .leftMouseDragged:
            return mouseDrag(down: .leftMouseDown, drag: .leftMouseDragged, up: .leftMouseUp, button: 0)
        case .rightMouseDragged:
            return mouseDrag(down: .rightMouseDown, drag: .rightMouseDragged, up: .rightMouseUp, button: 1)
        case .keyDown, .keyUp:
            return [event(.keyDown, time: 0, keyCode: 8, unicode: "c"), event(.keyUp, time: 0.1, keyCode: 8, unicode: "c")]
        case .flagsChanged:
            return [event(.flagsChanged, time: 0, keyCode: 55, flags: ModFlag.command), event(.flagsChanged, time: 0.1, keyCode: 55, flags: 0)]
        case .scrollWheel:
            var scroll = event(.scrollWheel, time: 0)
            scroll.scrollDeltaY = -3
            return [scroll]
        case .otherMouseDown, .otherMouseUp:
            return mousePair(down: .otherMouseDown, up: .otherMouseUp, button: 2)
        case .otherMouseDragged:
            return mouseDrag(down: .otherMouseDown, drag: .otherMouseDragged, up: .otherMouseUp, button: 2)
        case .waitForText:
            return [textObservation(.waitForText, time: 0, mustExist: true)]
        case .verifyText:
            return [textObservation(.verifyText, time: 0, mustExist: true)]
        }
    }

    private func mousePair(down: RecordedEvent.Kind, up: RecordedEvent.Kind, button: Int64) -> [RecordedEvent] {
        [event(down, time: 0, button: button), event(up, time: 0.1, button: button)]
    }

    private func mouseDrag(down: RecordedEvent.Kind, drag: RecordedEvent.Kind, up: RecordedEvent.Kind, button: Int64) -> [RecordedEvent] {
        [
            event(down, time: 0, x: 120, y: 220, button: button),
            event(drag, time: 0.1, x: 180, y: 260, button: button),
            event(up, time: 0.2, x: 220, y: 300, button: button)
        ]
    }

    private func textObservation(_ kind: RecordedEvent.Kind, time: Double, mustExist: Bool) -> RecordedEvent {
        var value = event(kind, time: time)
        value.surfaceId = TestFixtures.surfaceId
        value.textAnchor = TextAnchor(
            text: "Ready",
            matchMode: .contains,
            observedFrame: RectValue(x: 200, y: 200, width: 80, height: 24),
            searchRegion: RectValue(x: 180, y: 180, width: 160, height: 80)
        )
        value.textTimeout = 5
        value.verifyMustExist = mustExist
        return value
    }

    private func event(
        _ kind: RecordedEvent.Kind,
        time: Double,
        x: CGFloat = 120,
        y: CGFloat = 220,
        keyCode: UInt16 = 0,
        flags: UInt64 = 0,
        button: Int64 = 0,
        unicode: String? = nil
    ) -> RecordedEvent {
        RecordedEvent(
            kind: kind,
            time: time,
            x: x,
            y: y,
            keyCode: keyCode,
            flags: flags,
            mouseButton: button,
            clickCount: kind.isMouse ? 1 : 0,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            unicodeString: unicode
        )
    }
}
