import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro Candidate Validator Tests")
struct MacroCandidateValidatorTests {
    func event(_ kind: RecordedEvent.Kind = .mouseMoved, _ time: Double = 0) -> RecordedEvent {
        RecordedEvent(kind: kind, time: time, x: 10, y: 20, keyCode: 0, flags: 0,
                      mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
    }
    func document(source: SavedMacro, events: [RecordedEvent]) throws -> MacroCandidateDocument {
        let revision = try MacroCandidateIdentity.revision(of: source)
        let targets = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "candidate").map(\.id)
        return MacroCandidateDocument(macro: SavedMacro(name: "AI name", events: events), sourceRevision: revision,
            coverage: try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision).map {
                MacroCandidateCoverage(sourceActionID: $0.id, disposition: targets.isEmpty ? .removedAsNoise : .merged,
                                       candidateActionIDs: targets, reason: "Reconstructed from evidence")
            })
    }
    @Test func broadRewritePreservesSourceMetadataAndRefreshesCaches() throws {
        var source = SavedMacro(name: "Original", events: [event()], loops: 3, speed: 2, notes: "Private note", playCount: 9)
        source.favorite = true
        var candidate = try document(source: source, events: [event(.keyDown), event(.keyUp, 0.1)])
        candidate.macro.cachedEventCount = 1000
        let result = try MacroCandidateValidator.normalize(candidate, source: source)
        #expect(result.id == source.id && result.name == source.name && result.notes == source.notes)
        #expect(result.favorite && result.playCount == 9 && result.loops == 3 && result.speed == 2)
        #expect(result.events == candidate.macro.events && result.cachedEventCount == 2 && result.duration == 0.1)
    }
    @Test func executableIdentityIgnoresDisplayAndInvalidStatistics() throws {
        var source = SavedMacro(name: "Original", events: [event()])
        let revision = try MacroCandidateIdentity.revision(of: source)
        source.name = "Renamed"; source.totalRunTime = .nan; source.cachedDuration = .infinity
        source.events[0].behaviorGroupName = "Annotation"
        #expect(try MacroCandidateIdentity.revision(of: source) == revision)
        source.speed = 2
        #expect(try MacroCandidateIdentity.revision(of: source) != revision)
    }
    @Test func staleSourceAndMissingCoverageFail() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var candidate = try document(source: source, events: [event()])
        candidate.sourceRevision = "old"
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        candidate = try document(source: source, events: [event()]); candidate.coverage = []
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }
    @Test func rejectsDanglingCoverageButRetainsUncertaintyForReview() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var candidate = try document(source: source, events: [event()])
        candidate.coverage[0].candidateActionIDs = ["invented"]
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        candidate.coverage[0].candidateActionIDs = []; candidate.coverage[0].disposition = .unresolved
        candidate.uncertainActionIDs = [candidate.coverage[0].sourceActionID]
        _ = try MacroCandidateValidator.normalize(candidate, source: source)
        #expect(candidate.requiresAttention)
    }
    @Test func rejectsUnsafeInputAndNumericData() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        for events in [[event(.leftMouseDown)], [event(.keyUp)], [event(.leftMouseDragged)], [event(.mouseMoved, -1)]] {
            var candidate = try document(source: source, events: [event()])
            candidate.macro.events = events
            #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        }
        var candidate = try document(source: source, events: [event()])
        candidate.macro.events[0].x = .infinity
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }
    @Test func rejectsMissingSurfaceAndUnboundedWait() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var candidate = try document(source: source, events: [event()])
        candidate.macro.events[0].surfaceId = "missing"
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        candidate.macro.events[0].surfaceId = nil; candidate.macro.events[0].kind = .waitForText
        candidate.macro.events[0].textAnchor = TextAnchor(text: "Ready", observedFrame: RectValue(x: 0, y: 0, width: 30, height: 10))
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }
    @Test func strictDecodeRejectsUnsupportedPlaybackFields() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        let candidate = try document(source: source, events: [event()])
        let data = try MacroCandidateAuthoringProjection.encode(candidate)
        #expect(try MacroCandidateValidator.decode(data) == candidate)
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var macro = try #require(root["macro"] as? [String: Any])
        var events = try #require(macro["events"] as? [[String: Any]])
        events[0]["imageLocator"] = ["file": "hidden.png"]
        macro["events"] = events; root["macro"] = macro
        let invalid = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.decode(invalid) }
    }
    @Test func strictDecodeRejectsLibraryAndExecutionOwnedMacroFields() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        let candidate = try document(source: source, events: [event()])
        let data = try MacroCandidateAuthoringProjection.encode(candidate)
        let baseRoot = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let protectedFields = [
            "libraryOrder", "loops", "speed", "followWindowOffset", "hotkey", "notes",
            "chainTo", "semanticRecording", "playableSanitization", "playCount", "lastPlayedAt",
            "totalRunTime", "cachedDuration", "cachedEventCount", "cachedWaveformBars"
        ]

        for field in protectedFields {
            var root = baseRoot
            var macro = try #require(root["macro"] as? [String: Any])
            macro[field] = 0
            root["macro"] = macro
            let invalid = try JSONSerialization.data(withJSONObject: root)
            #expect(throws: MacroCandidateValidationError.self) {
                try MacroCandidateValidator.decode(invalid)
            }
        }
    }

    @Test func fullTextRewriteAndExplicitNoiseRemovalAreAllowed() throws {
        let surface = TestFixtures.surface()
        var sourceEvents = [event(.leftMouseDown), event(.leftMouseUp, 0.1)]
        sourceEvents.indices.forEach { sourceEvents[$0].surfaceId = TestFixtures.surfaceId }
        let source = SavedMacro(
            name: "Original",
            events: sourceEvents,
            surfaces: [TestFixtures.surfaceId: surface]
        )
        var wait = event(.waitForText)
        wait.surfaceId = TestFixtures.surfaceId
        wait.textAnchor = TextAnchor(text: "Ready", observedFrame: RectValue(x: 0, y: 0, width: 30, height: 10))
        wait.textTimeout = 15
        var verify = wait; verify.kind = .verifyText; verify.time = 0.2
        var candidate = try document(source: source, events: [wait, verify])
        candidate.macro.surfaces = source.surfaces
        #expect(try MacroCandidateValidator.normalize(candidate, source: source).events.count == 2)
        var empty = try document(source: source, events: [])
        empty.macro.surfaces = source.surfaces
        #expect(try MacroCandidateValidator.normalize(empty, source: source).events.isEmpty)
    }
    @Test func disabledInputCannotBalanceEnabledPressAndModifiersMustRelease() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var up = event(.leftMouseUp, 0.1); up.isDisabled = true
        var candidate = try document(source: source, events: [event(.leftMouseDown), up])
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        var modifier = event(.flagsChanged); modifier.flags = 0x20000
        candidate = try document(source: source, events: [modifier])
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }
    @Test func sourceSuppressionBlocksNewReadableValues() throws {
        var source = SavedMacro(name: "Original", events: [event()])
        source.playableSanitization = MacroPlayableSanitizationSummary(sanitizedEventCount: 1,
            withheldReadableFieldCount: 1, reviewRequiredEventCount: 0, reviewRequiredFieldCount: 0)
        var input = event(.keyDown); input.unicodeString = "restored secret"
        let candidate = try document(source: source, events: [input, event(.keyUp, 0.1)])
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }
    @Test func sourceSuppressionAlsoProtectsBehaviorLabelsAndReviewRequiredFields() throws {
        var source = SavedMacro(name: "Original", events: [event()])
        source.playableSanitization = MacroPlayableSanitizationSummary(sanitizedEventCount: 1,
            withheldReadableFieldCount: 1, reviewRequiredEventCount: 0, reviewRequiredFieldCount: 0)
        var labeled = event(); labeled.behaviorGroupName = "private password"
        var candidate = try document(source: source, events: [labeled])
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        source.playableSanitization = MacroPlayableSanitizationSummary(sanitizedEventCount: 0,
            withheldReadableFieldCount: 0, reviewRequiredEventCount: 1, reviewRequiredFieldCount: 1)
        labeled.behaviorGroupName = nil; labeled.unicodeString = "review-required secret"
        candidate = try document(source: source, events: [labeled])
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }
    @Test func normalizedGeometryAndTimeoutBoundsAreEnforced() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var candidate = try document(source: source, events: [event()])
        candidate.macro.events[0].contentNormalizedX = 1.1
        candidate.macro.events[0].contentNormalizedY = 0.5
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
        candidate.macro.events[0].contentNormalizedX = nil; candidate.macro.events[0].contentNormalizedY = nil
        candidate.macro.events[0].textTimeout = 3601
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.normalize(candidate, source: source) }
    }

    @Test func inconsistentAbsoluteAndContentNormalizedTextGeometryIsRejected() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        let frame = RectValue(x: 0, y: 39, width: 2056, height: 1290)
        var wait = event(.waitForText)
        wait.surfaceId = "surface-1"
        wait.textTimeout = 10
        wait.textAnchor = TextAnchor(
            text: "New chat",
            observedFrame: RectValue(x: 17.77, y: 193.43, width: 89.98, height: 19.61),
            searchRegion: RectValue(x: 0, y: 113.38, width: 227.72, height: 179.4),
            coordinateFallback: PointValue(x: 62.76, y: 203.08),
            observedContentNormalizedFrame: RectValue(x: 0.008643, y: 0.145546, width: 0.043765, height: 0.014755),
            searchContentNormalizedRegion: RectValue(x: 0, y: 0.085312, width: 0.110759, height: 0.134989),
            coordinateFallbackContentNormalized: PointValue(x: 0.030525, y: 0.152807)
        )
        var candidate = try document(source: source, events: [wait])
        candidate.macro.surfaces["surface-1"] = PlaybackSurface(
            bundleIdentifier: "com.google.Chrome",
            recordedFrame: frame,
            recordedContentFrame: frame,
            contentElementRole: "AXGroup"
        )

        #expect(throws: MacroCandidateValidationError.self) {
            try MacroCandidateValidator.normalize(candidate, source: source)
        }
    }

    @Test func everyCandidateTextOperationRequiresExplicitSurface() throws {
        let source = SavedMacro(
            name: "Original",
            events: [event()],
            surfaces: [TestFixtures.surfaceId: TestFixtures.surface()]
        )
        for kind in [RecordedEvent.Kind.waitForText, .verifyText] {
            var textEvent = event(kind)
            textEvent.textAnchor = TextAnchor(
                text: "Ready",
                observedFrame: RectValue(x: 10, y: 20, width: 30, height: 10)
            )
            textEvent.textTimeout = 10
            var candidate = try document(source: source, events: [textEvent])
            candidate.macro.surfaces = source.surfaces
            #expect(throws: MacroCandidateValidationError.self) {
                try MacroCandidateValidator.normalize(candidate, source: source)
            }
        }
    }

    @Test func externalCandidateMayOmitSourceOwnedPlaybackSurfaces() throws {
        let surface = TestFixtures.surface(
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "ChatGPT"
        )
        var sourceEvents = [event()]
        sourceEvents[0].surfaceId = TestFixtures.surfaceId
        let source = SavedMacro(
            name: "Original",
            events: sourceEvents,
            surfaces: [TestFixtures.surfaceId: surface]
        )
        var candidate = try document(source: source, events: sourceEvents)
        candidate.macro.surfaces = [:]

        let normalized = try MacroCandidateValidator.normalize(candidate, source: source)

        #expect(normalized.surfaces == source.surfaces)
        #expect(normalized.events[0].surfaceId == TestFixtures.surfaceId)
    }

    @Test func externalCandidateCannotRewritePlaybackSurfaceIdentity() throws {
        let sourceSurface = TestFixtures.surface(
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Source window",
            recordedFrame: RectValue(x: 0, y: 39, width: 1200, height: 800),
            recordedContentFrame: RectValue(x: 0, y: 39, width: 1200, height: 800)
        )
        var sourceEvents = [event()]
        sourceEvents[0].surfaceId = TestFixtures.surfaceId
        let source = SavedMacro(
            name: "Original",
            events: sourceEvents,
            surfaces: [TestFixtures.surfaceId: sourceSurface]
        )
        var candidate = try document(source: source, events: sourceEvents)
        candidate.macro.surfaces = source.surfaces
        candidate.macro.surfaces[TestFixtures.surfaceId]?.windowTitle = "AI invented window"

        #expect(throws: MacroCandidateValidationError.self) {
            try MacroCandidateValidator.normalize(candidate, source: source)
        }
    }

    @Test func externalCandidateIgnoresNonExecutableSurfaceCaptureTimestamp() throws {
        let sourceSurface = TestFixtures.surface(
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "ChatGPT",
            recordedFrame: RectValue(x: 0, y: 39, width: 1200, height: 800),
            recordedContentFrame: RectValue(x: 0, y: 39, width: 1200, height: 800)
        )
        var sourceEvents = [event()]
        sourceEvents[0].surfaceId = TestFixtures.surfaceId
        let source = SavedMacro(
            name: "Original",
            events: sourceEvents,
            surfaces: [TestFixtures.surfaceId: sourceSurface]
        )
        var candidate = try document(source: source, events: sourceEvents)
        candidate.macro.surfaces = source.surfaces
        candidate.macro.surfaces[TestFixtures.surfaceId]?.capturedAt = sourceSurface.capturedAt.addingTimeInterval(10)

        let normalized = try MacroCandidateValidator.normalize(candidate, source: source)
        #expect(normalized.surfaces == source.surfaces)
    }

    @Test func locatorDrivenClickRequiresOneSurfaceAndOneAnchorForTheWholeGesture() throws {
        let surface = TestFixtures.surface()
        let sourceEvents = TestFixtures.clickPair()
        let source = SavedMacro(
            name: "Original",
            events: sourceEvents,
            surfaces: [TestFixtures.surfaceId: surface]
        )
        let anchor = TextAnchor(
            text: "New chat",
            observedFrame: RectValue(x: 20, y: 30, width: 80, height: 20),
            coordinateFallback: PointValue(x: 60, y: 40)
        )
        var click = TextClickEventFactory.makeEvents(
            startTime: 0,
            textAnchor: anchor,
            timeout: 10,
            fallbackPolicy: .allowCoordinateFallback,
            surfaceId: TestFixtures.surfaceId
        )
        var candidate = try document(source: source, events: click)
        candidate.macro.surfaces = source.surfaces
        _ = try MacroCandidateValidator.normalize(candidate, source: source)

        click[1].textAnchor?.text = "Different target"
        candidate = try document(source: source, events: click)
        candidate.macro.surfaces = source.surfaces
        #expect(throws: MacroCandidateValidationError.self) {
            try MacroCandidateValidator.normalize(candidate, source: source)
        }
    }

    @Test func contentNormalizedTextGeometryRequiresExplicitSurface() throws {
        let source = SavedMacro(
            name: "Original",
            events: [event()],
            surfaces: [TestFixtures.surfaceId: TestFixtures.surface()]
        )
        var wait = event(.waitForText)
        wait.textAnchor = TextAnchor(
            text: "Ready",
            observedFrame: RectValue(x: 0, y: 0, width: 30, height: 10),
            searchContentNormalizedRegion: RectValue(x: 0.1, y: 0.2, width: 0.4, height: 0.2)
        )
        wait.textTimeout = 10
        var candidate = try document(source: source, events: [wait])
        candidate.macro.surfaces = source.surfaces

        #expect(throws: MacroCandidateValidationError.self) {
            try MacroCandidateValidator.normalize(candidate, source: source)
        }

        candidate.macro.events[0].surfaceId = TestFixtures.surfaceId
        #expect(try MacroCandidateValidator.normalize(candidate, source: source).events[0].surfaceId == TestFixtures.surfaceId)
    }
    @Test func nestedUnsupportedTextAnchorFieldIsRejected() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var input = event()
        input.textAnchor = TextAnchor(text: "Ready", observedFrame: RectValue(x: 0, y: 0, width: 10, height: 10))
        let data = try MacroCandidateAuthoringProjection.encode(
            document(source: source, events: [input])
        )
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var macro = try #require(root["macro"] as? [String: Any])
        var events = try #require(macro["events"] as? [[String: Any]])
        var anchor = try #require(events[0]["textAnchor"] as? [String: Any])
        anchor["stabilityWindow"] = 3; events[0]["textAnchor"] = anchor
        macro["events"] = events; root["macro"] = macro
        let invalid = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.decode(invalid) }
    }
    @Test func capabilityManifestDeclaresActualTextOnlyVocabulary() {
        #expect(MacroCandidateCapabilities.current.version == "macro-candidate/v4")
        #expect(MacroCandidateCapabilities.current.authoringMacroFields == [
            "createdAt", "events", "id", "modifiedAt", "name", "version"
        ])
        #expect(MacroCandidateCapabilities.current.eventKinds.contains(100))
        #expect(MacroCandidateCapabilities.current.eventKinds.contains(101))
        #expect(MacroCandidateCapabilities.current.locatorKinds == ["text"])
        #expect(MacroCandidateCapabilities.current.surfaceAuthoringPolicy.sourceSurfacesAreReadOnly)
        #expect(MacroCandidateCapabilities.current.surfaceAuthoringPolicy.sourceSurfacesAreOmittedFromCandidate)
        #expect(MacroCandidateCapabilities.current.surfaceAuthoringPolicy.eventSurfaceReferencesMayChange)
        #expect(MacroCandidateCapabilities.current.surfaceAuthoringPolicy.textOperationsRequireExplicitSurface)
        #expect(MacroCandidateCapabilities.current.surfaceAuthoringPolicy.liveSurfaceRebindingIsAppOwned)
        #expect(MacroCandidateCapabilities.current.textOperationPolicy.locatorMouseEventsRequireTargetWindowBinding)
        #expect(MacroCandidateCapabilities.current.textOperationPolicy.locatorMouseEventsRequireLocatorOnlyStrategy)
        #expect(MacroCandidateCapabilities.current.textOperationPolicy.pointerGestureRequiresStableLocatorIdentity)
        #expect(MacroCandidateCapabilities.current.textOperationPolicy.waitAndVerifyRequireBoundedTimeout)
        #expect(MacroCandidateCapabilities.current.textOperationPolicy.verificationIsSingleObservation)
    }
}
