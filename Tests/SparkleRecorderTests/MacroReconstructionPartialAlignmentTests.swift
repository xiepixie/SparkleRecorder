import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro reconstruction partial video alignment")
struct MacroReconstructionPartialAlignmentTests {
    @Test("Coverage keeps unchanged actions exact and maps edited actions to recorded video")
    func singleGenerationAlignment() throws {
        let sourceRevision = "source-r1"
        let targetRevision = "target-r1"
        let sourceEvents = twoClicks()
        let sourceActions = try MacroActionReconstructor.reconstruct(
            events: sourceEvents,
            sourceRevision: sourceRevision
        )
        #expect(sourceActions.count == 2)
        let evidenceRows = projectedRows(for: sourceActions, segmentID: "segment-a")

        var targetEvents = sourceEvents
        let anchor = TextAnchor(
            text: "New chat",
            observedFrame: RectValue(x: 80, y: 90, width: 80, height: 24),
            coordinateFallback: PointValue(x: 100, y: 100)
        )
        targetEvents[0].coordinateBinding = .targetWindow
        targetEvents[0].coordinateStrategy = .locatorOnly
        targetEvents[0].surfaceId = "main"
        targetEvents[0].textAnchor = anchor
        targetEvents[0].textTimeout = 5
        targetEvents[1].coordinateBinding = .targetWindow
        targetEvents[1].coordinateStrategy = .locatorOnly
        targetEvents[1].surfaceId = "main"
        targetEvents[1].textAnchor = anchor
        targetEvents[1].textTimeout = 5

        let literalTargets = try MacroActionReconstructor.reconstruct(
            events: targetEvents,
            sourceRevision: "candidate"
        )
        let coverage = [
            MacroCandidateCoverage(
                sourceActionID: sourceActions[0].id,
                disposition: .replacedByLocator,
                candidateActionIDs: [literalTargets[0].id],
                reason: "Use text locator"
            ),
            MacroCandidateCoverage(
                sourceActionID: sourceActions[1].id,
                disposition: .preserved,
                candidateActionIDs: [literalTargets[1].id],
                reason: "Unchanged"
            )
        ]
        let step = MacroReconstructionCandidateLineageStep(
            sourceRevision: sourceRevision,
            sourceEvents: sourceEvents,
            targetRevision: targetRevision,
            targetEvents: targetEvents,
            coverage: coverage
        )

        let aligned = try MacroReconstructionPartialAlignmentProjector.project(
            evidenceRows: evidenceRows,
            evidenceSourceEvents: sourceEvents,
            evidenceSourceRevision: sourceRevision,
            targetEvents: targetEvents,
            targetRevision: targetRevision,
            lineage: [step]
        )

        #expect(aligned.count == 2)
        #expect(aligned[0].quality == .coverageMapped)
        #expect(aligned[0].videoSegmentID == "segment-a")
        #expect(aligned[0].videoRange == evidenceRows[0].videoRange)
        #expect(aligned[0].sourceActionIDs == [sourceActions[0].id])
        #expect(aligned[1].quality == .exactSource)
        #expect(aligned[1].videoRange == evidenceRows[1].videoRange)
    }

    @Test("Alignment composes through multiple accepted candidate generations")
    func multiGenerationAlignment() throws {
        let sourceRevision = "source-r1"
        let middleRevision = "target-r1"
        let finalRevision = "target-r2"
        let sourceEvents = twoClicks()
        let sourceActions = try MacroActionReconstructor.reconstruct(events: sourceEvents, sourceRevision: sourceRevision)
        let evidenceRows = projectedRows(for: sourceActions, segmentID: "segment-a")

        var middleEvents = sourceEvents
        middleEvents[0].x += 4
        middleEvents[1].x += 4
        let middleLiteral = try MacroActionReconstructor.reconstruct(events: middleEvents, sourceRevision: "candidate")
        let first = MacroReconstructionCandidateLineageStep(
            sourceRevision: sourceRevision,
            sourceEvents: sourceEvents,
            targetRevision: middleRevision,
            targetEvents: middleEvents,
            coverage: zip(sourceActions, middleLiteral).map { source, target in
                MacroCandidateCoverage(
                    sourceActionID: source.id,
                    disposition: source.id == sourceActions[0].id ? .replacedByLocator : .preserved,
                    candidateActionIDs: [target.id],
                    reason: "First generation"
                )
            }
        )

        let middleActions = try MacroActionReconstructor.reconstruct(events: middleEvents, sourceRevision: middleRevision)
        var finalEvents = middleEvents
        finalEvents[2].y += 6
        finalEvents[3].y += 6
        let finalLiteral = try MacroActionReconstructor.reconstruct(events: finalEvents, sourceRevision: "candidate")
        let second = MacroReconstructionCandidateLineageStep(
            sourceRevision: middleRevision,
            sourceEvents: middleEvents,
            targetRevision: finalRevision,
            targetEvents: finalEvents,
            coverage: zip(middleActions, finalLiteral).map { source, target in
                MacroCandidateCoverage(
                    sourceActionID: source.id,
                    disposition: .preserved,
                    candidateActionIDs: [target.id],
                    reason: "Second generation"
                )
            }
        )

        let aligned = try MacroReconstructionPartialAlignmentProjector.project(
            evidenceRows: evidenceRows,
            evidenceSourceEvents: sourceEvents,
            evidenceSourceRevision: sourceRevision,
            targetEvents: finalEvents,
            targetRevision: finalRevision,
            lineage: [second, first]
        )

        #expect(aligned.count == 2)
        #expect(aligned[0].videoRange == evidenceRows[0].videoRange)
        #expect(aligned[1].videoRange == evidenceRows[1].videoRange)
        #expect(aligned.allSatisfy { $0.quality == .coverageMapped })
    }

    @Test("Unresolved and cross-segment mappings remain unaligned instead of guessing")
    func unresolvedAndCrossSegmentStayUnaligned() throws {
        let sourceRevision = "source-r1"
        let targetRevision = "target-r1"
        let sourceEvents = twoClicks()
        let sourceActions = try MacroActionReconstructor.reconstruct(events: sourceEvents, sourceRevision: sourceRevision)
        let evidenceRows = [
            projectedRow(action: sourceActions[0], segmentID: "segment-a", start: 2),
            projectedRow(action: sourceActions[1], segmentID: "segment-b", start: 4)
        ]

        // Merge both source actions into one target click. The coverage is explicit,
        // but a range that crosses movie segments is not a valid seek target.
        let targetEvents = Array(sourceEvents.prefix(2))
        let targetLiteral = try MacroActionReconstructor.reconstruct(events: targetEvents, sourceRevision: "candidate")
        let step = MacroReconstructionCandidateLineageStep(
            sourceRevision: sourceRevision,
            sourceEvents: sourceEvents,
            targetRevision: targetRevision,
            targetEvents: targetEvents,
            coverage: [
                MacroCandidateCoverage(
                    sourceActionID: sourceActions[0].id,
                    disposition: .merged,
                    candidateActionIDs: [targetLiteral[0].id],
                    reason: "Merged"
                ),
                MacroCandidateCoverage(
                    sourceActionID: sourceActions[1].id,
                    disposition: .merged,
                    candidateActionIDs: [targetLiteral[0].id],
                    reason: "Merged"
                )
            ]
        )

        let aligned = try MacroReconstructionPartialAlignmentProjector.project(
            evidenceRows: evidenceRows,
            evidenceSourceEvents: sourceEvents,
            evidenceSourceRevision: sourceRevision,
            targetEvents: targetEvents,
            targetRevision: targetRevision,
            lineage: [step]
        )
        let row = try #require(aligned.first)
        #expect(row.quality == .unavailable)
        #expect(row.videoSegmentID == nil)
        #expect(row.videoRange == nil)
        #expect(row.issues.contains(.crossesVideoSegments))

        var unresolvedStep = step
        unresolvedStep.coverage[0].disposition = .unresolved
        unresolvedStep.coverage[1].disposition = .unresolved
        let unresolved = try MacroReconstructionPartialAlignmentProjector.project(
            evidenceRows: evidenceRows,
            evidenceSourceEvents: sourceEvents,
            evidenceSourceRevision: sourceRevision,
            targetEvents: targetEvents,
            targetRevision: targetRevision,
            lineage: [unresolvedStep]
        )
        #expect(unresolved.first?.quality == .unavailable)
        #expect(unresolved.first?.videoRange == nil)
    }

    private func twoClicks() -> [RecordedEvent] {
        [
            RecordedEvent.make(.leftMouseDown, time: 0, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.05, x: 100, y: 100, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseDown, time: 0.20, x: 300, y: 220, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: 0.25, x: 300, y: 220, mouseButton: 0, clickCount: 1)
        ]
    }

    private func projectedRows(
        for actions: [MacroReconstructedAction],
        segmentID: String
    ) -> [MacroReconstructionProjectedAction] {
        actions.enumerated().map { index, action in
            projectedRow(action: action, segmentID: segmentID, start: Double(index + 1) * 2)
        }
    }

    private func projectedRow(
        action: MacroReconstructedAction,
        segmentID: String,
        start: Double
    ) -> MacroReconstructionProjectedAction {
        MacroReconstructionProjectedAction(
            action: action,
            sessionRange: RecordingTimeRange(startTime: start, duration: 0.05),
            videoSegmentID: segmentID,
            videoRange: RecordingTimeRange(startTime: start, duration: 0.05),
            startFramePoint: action.startPoint,
            endFramePoint: action.endPoint,
            issues: []
        )
    }
}
