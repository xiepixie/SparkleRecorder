import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro reconstruction action round trip")
struct MacroReconstructionActionRoundTripTests {
    @Test("Every exported Reconstruction Action has an executable strict-candidate fixture")
    func everyExportedActionHasRoundTripFixture() throws {
        let fixtures: [(ActionGroupKind, [RecordedEvent])] = [
            (.click, clickPair(at: 0, x: 100)),
            (.doubleClick, repeatedClicks(count: 2, spacing: 0.10, xValues: [100, 100])),
            (.longPress, mouseHold(duration: 0.50)),
            (.drag, drag()),
            (.scroll, scroll()),
            (.keyPress, keyPress(code: 8, text: "c", duration: 0.10)),
            (.keyHold, keyPress(code: 8, text: "c", duration: 0.50)),
            (.keyRepeat, keyRepeat()),
            (.shortcut, shortcut()),
            (.modifierHold, modifierHold()),
            (.textInput, textInput()),
            (.wait, sourceWithWait()),
            (.mouseMove, [event(.mouseMoved, time: 0, x: 120, y: 220)]),
            (.waitForText, [textObservation(.waitForText, mustExist: true)]),
            (.waitForTextGone, [textObservation(.waitForText, mustExist: false)]),
            (.verifyText, [textObservation(.verifyText, mustExist: true)]),
            (.repeatedClick, repeatedClicks(count: 4, spacing: 0.08, xValues: [100, 100, 100, 100])),
            (.multiPointClick, repeatedClicks(count: 2, spacing: 0.08, xValues: [100, 220]))
        ]

        let exportedKinds = Set(
            MacroReconstructionAuthoringContract.actionKindDescriptors
                .filter(\.exportedByReconstructor)
                .map(\.name)
        )
        #expect(exportedKinds == Set(fixtures.map { $0.0.rawValue }))

        for (expectedKind, events) in fixtures {
            let source = SavedMacro(
                name: "Fixture \(expectedKind.rawValue)",
                events: events,
                surfaces: [TestFixtures.surfaceId: TestFixtures.surface(
                    recordedContentFrame: RectValue(x: 100, y: 100, width: 800, height: 600)
                )]
            )
            let revision = try MacroCandidateIdentity.revision(of: source)
            let sourceActions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: revision)
            #expect(
                sourceActions.contains(where: { $0.kind == expectedKind }),
                "Expected reconstruction fixture for \(expectedKind.rawValue), got \(sourceActions.map { $0.kind.rawValue })"
            )

            let candidateActions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "candidate")
            let document = MacroCandidateDocument(
                macro: source,
                sourceRevision: revision,
                summary: "Round-trip \(expectedKind.rawValue)",
                coverage: zip(sourceActions, candidateActions).map { sourceAction, candidateAction in
                    MacroCandidateCoverage(
                        sourceActionID: sourceAction.id,
                        disposition: .preserved,
                        candidateActionIDs: [candidateAction.id],
                        reason: "Preserve executable fixture"
                    )
                },
                model: "test"
            )
            let authored = try MacroCandidateAuthoringProjection.encode(document)
            let decoded = try MacroCandidateValidator.decode(authored)
            let normalized = try MacroCandidateValidator.normalize(decoded, source: source)
            #expect(normalized.events == events, "Round trip changed \(expectedKind.rawValue)")
        }
    }

    @Test("Sequence is editor grouping metadata rather than an executable source action")
    func sequenceIsExplicitlyNonExported() {
        let descriptor = MacroReconstructionAuthoringContract.actionKindDescriptors.first {
            $0.name == ActionGroupKind.sequence.rawValue
        }
        #expect(descriptor?.exportedByReconstructor == false)
        #expect(descriptor?.candidateRepresentation.contains("behaviorGroupID") == true)
    }

    @Test("Action context exposes compact keyboard pointer and scroll semantics")
    func actionContextCarriesCompactSemantics() throws {
        let optionEvents = optionTwoShortcut()
        let optionAction = try #require(
            MacroActionReconstructor.reconstruct(events: optionEvents, sourceRevision: "source")
                .first(where: { $0.kind == .shortcut })
        )
        let optionContext = MacroReconstructionActionContext(
            action: optionAction,
            events: optionEvents,
            surfaceContexts: [:]
        )
        #expect(optionContext.keyboardLabel == "⌥2")

        let rightClick = clickPair(at: 0, x: 120, button: 1, down: .rightMouseDown, up: .rightMouseUp)
        let clickAction = try #require(
            MacroActionReconstructor.reconstruct(events: rightClick, sourceRevision: "source")
                .first(where: { $0.kind == .click })
        )
        let clickContext = MacroReconstructionActionContext(
            action: clickAction,
            events: rightClick,
            surfaceContexts: [:]
        )
        #expect(clickContext.pointerButton == "right")
        #expect(clickContext.clickCount == 1)

        let scrollEvents = scroll()
        let scrollAction = try #require(
            MacroActionReconstructor.reconstruct(events: scrollEvents, sourceRevision: "source")
                .first(where: { $0.kind == .scroll })
        )
        let scrollContext = MacroReconstructionActionContext(
            action: scrollAction,
            events: scrollEvents,
            surfaceContexts: [:]
        )
        #expect(scrollContext.scrollDeltaY == -7)
    }

    private func clickPair(
        at start: Double,
        x: CGFloat,
        button: Int64 = 0,
        down: RecordedEvent.Kind = .leftMouseDown,
        up: RecordedEvent.Kind = .leftMouseUp
    ) -> [RecordedEvent] {
        [
            event(down, time: start, x: x, y: 220, button: button),
            event(up, time: start + 0.04, x: x, y: 220, button: button)
        ]
    }

    private func repeatedClicks(count: Int, spacing: Double, xValues: [CGFloat]) -> [RecordedEvent] {
        (0..<count).flatMap { index in
            clickPair(at: Double(index) * spacing, x: xValues[index])
        }
    }

    private func mouseHold(duration: Double) -> [RecordedEvent] {
        [
            event(.leftMouseDown, time: 0, x: 100, y: 220),
            event(.leftMouseUp, time: duration, x: 100, y: 220)
        ]
    }

    private func drag() -> [RecordedEvent] {
        [
            event(.leftMouseDown, time: 0, x: 100, y: 220),
            event(.leftMouseDragged, time: 0.08, x: 160, y: 260),
            event(.leftMouseUp, time: 0.16, x: 220, y: 300)
        ]
    }

    private func scroll() -> [RecordedEvent] {
        var value = event(.scrollWheel, time: 0, x: 140, y: 240)
        value.scrollDeltaY = -7
        return [value]
    }

    private func keyPress(code: UInt16, text: String, duration: Double) -> [RecordedEvent] {
        [
            event(.keyDown, time: 0, keyCode: code, unicode: text),
            event(.keyUp, time: duration, keyCode: code, unicode: text)
        ]
    }

    private func keyRepeat() -> [RecordedEvent] {
        [
            event(.keyDown, time: 0, keyCode: 8, unicode: "c"),
            event(.keyDown, time: 0.08, keyCode: 8, unicode: "c"),
            event(.keyUp, time: 0.16, keyCode: 8, unicode: "c")
        ]
    }

    private func shortcut() -> [RecordedEvent] {
        [
            event(.flagsChanged, time: 0, keyCode: 55, flags: ModFlag.command),
            event(.keyDown, time: 0.03, keyCode: 8, flags: ModFlag.command, unicode: "c"),
            event(.keyUp, time: 0.08, keyCode: 8, flags: ModFlag.command, unicode: "c"),
            event(.flagsChanged, time: 0.10, keyCode: 55, flags: 0)
        ]
    }

    private func optionTwoShortcut() -> [RecordedEvent] {
        [
            event(.flagsChanged, time: 0, keyCode: 58, flags: ModFlag.option),
            event(.keyDown, time: 0.03, keyCode: 19, flags: ModFlag.option, unicode: "™"),
            event(.keyUp, time: 0.08, keyCode: 19, flags: ModFlag.option, unicode: "™"),
            event(.flagsChanged, time: 0.10, keyCode: 58, flags: 0)
        ]
    }

    private func modifierHold() -> [RecordedEvent] {
        [
            event(.flagsChanged, time: 0, keyCode: 55, flags: ModFlag.command),
            event(.flagsChanged, time: 0.50, keyCode: 55, flags: 0)
        ]
    }

    private func textInput() -> [RecordedEvent] {
        [
            event(.keyDown, time: 0, keyCode: 0, unicode: "a"),
            event(.keyUp, time: 0.03, keyCode: 0, unicode: "a"),
            event(.keyDown, time: 0.06, keyCode: 11, unicode: "b"),
            event(.keyUp, time: 0.09, keyCode: 11, unicode: "b")
        ]
    }

    private func sourceWithWait() -> [RecordedEvent] {
        [
            event(.mouseMoved, time: 0, x: 100, y: 200),
            event(.mouseMoved, time: 2, x: 110, y: 210)
        ]
    }

    private func textObservation(_ kind: RecordedEvent.Kind, mustExist: Bool) -> RecordedEvent {
        var value = event(kind, time: 0)
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
