import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro candidate editor draft")
struct MacroCandidateEditorDraftTests {
    private func clickPair(x: CGFloat = 10, start: Double = 0) -> [RecordedEvent] {
        [
            RecordedEvent.make(.leftMouseDown, time: start, x: x, y: 20),
            RecordedEvent.make(.leftMouseUp, time: start + 0.05, x: x, y: 20)
        ]
    }

    private func document(events: [RecordedEvent]) throws -> MacroCandidateDocument {
        let source = SavedMacro(name: "Source", events: clickPair())
        let revision = try MacroCandidateIdentity.revision(of: source)
        let sourceAction = try #require(
            MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision).first
        )
        let candidateAction = try #require(
            MacroActionReconstructor.reconstruct(events: events, sourceRevision: "candidate").first
        )
        return MacroCandidateDocument(
            macro: SavedMacro(id: source.id, name: source.name, events: events),
            sourceRevision: revision,
            coverage: [
                MacroCandidateCoverage(
                    sourceActionID: sourceAction.id,
                    disposition: .preserved,
                    candidateActionIDs: [candidateAction.id],
                    reason: "Preserved"
                )
            ]
        )
    }

    @Test("Non-structural edits preserve reviewed coverage")
    func nonStructuralEditPreservesCoverage() throws {
        let base = try document(events: clickPair())
        var edited = base.macro
        edited.events[0].x = 240
        edited.events[1].x = 240

        let result = try MacroCandidateEditorDraftBuilder.document(from: base, editedMacro: edited)

        #expect(result.coverage == base.coverage)
        #expect(result.uncertainActionIDs.isEmpty)
        #expect(result.macro.events[0].x == 240)
    }

    @Test("Timing edits invalidate only affected coverage")
    func timingEditMarksAffectedCoverageUnresolved() throws {
        let base = try document(events: clickPair())
        var edited = base.macro
        edited.events[0].time = 0.2
        edited.events[1].time = 0.25

        let result = try MacroCandidateEditorDraftBuilder.document(from: base, editedMacro: edited)
        let coverage = try #require(result.coverage.first)

        #expect(coverage.disposition == .unresolved)
        #expect(coverage.candidateActionIDs.isEmpty)
        #expect(result.uncertainActionIDs.contains(coverage.sourceActionID))
    }

    @Test("Existing unresolved review state survives local editing")
    func unresolvedStateSurvives() throws {
        var base = try document(events: clickPair())
        base.coverage[0].disposition = .unresolved
        base.uncertainActionIDs = [base.coverage[0].sourceActionID]
        var edited = base.macro
        edited.events[0].x = 55
        edited.events[1].x = 55

        let result = try MacroCandidateEditorDraftBuilder.document(from: base, editedMacro: edited)

        #expect(result.coverage[0].disposition == .unresolved)
        #expect(result.uncertainActionIDs == [base.coverage[0].sourceActionID])
    }
}
