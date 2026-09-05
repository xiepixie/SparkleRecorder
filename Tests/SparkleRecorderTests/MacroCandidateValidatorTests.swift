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
        let data = try JSONEncoder().encode(candidate)
        #expect(try MacroCandidateValidator.decode(data) == candidate)
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var macro = try #require(root["macro"] as? [String: Any])
        var events = try #require(macro["events"] as? [[String: Any]])
        events[0]["imageLocator"] = ["file": "hidden.png"]
        macro["events"] = events; root["macro"] = macro
        let invalid = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: MacroCandidateValidationError.self) { try MacroCandidateValidator.decode(invalid) }
    }
    @Test func fullTextRewriteAndExplicitNoiseRemovalAreAllowed() throws {
        let source = SavedMacro(name: "Original", events: [event(.leftMouseDown), event(.leftMouseUp, 0.1)])
        var wait = event(.waitForText)
        wait.textAnchor = TextAnchor(text: "Ready", observedFrame: RectValue(x: 0, y: 0, width: 30, height: 10))
        wait.textTimeout = 15
        var verify = wait; verify.kind = .verifyText; verify.time = 0.2
        let candidate = try document(source: source, events: [wait, verify])
        #expect(try MacroCandidateValidator.normalize(candidate, source: source).events.count == 2)
        let empty = try document(source: source, events: [])
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
    @Test func nestedUnsupportedTextAnchorFieldIsRejected() throws {
        let source = SavedMacro(name: "Original", events: [event()])
        var input = event()
        input.textAnchor = TextAnchor(text: "Ready", observedFrame: RectValue(x: 0, y: 0, width: 10, height: 10))
        let data = try JSONEncoder().encode(document(source: source, events: [input]))
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
        #expect(MacroCandidateCapabilities.current.eventKinds.contains(100))
        #expect(MacroCandidateCapabilities.current.eventKinds.contains(101))
        #expect(MacroCandidateCapabilities.current.locatorKinds == ["text"])
    }
}
