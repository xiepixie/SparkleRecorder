import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Failure Evidence Builder Tests")
struct PlaybackFailureEvidenceBuilderTests {
    @Test("Builds failure evidence from playback step and target surface context")
    func buildsFailureEvidenceFromStepContext() throws {
        let macroID = UUID()
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let surface = TestFixtures.surface(
            bundleIdentifier: "com.example.Target",
            windowTitle: "Checkout"
        )
        let context = TestFixtures.playbackContext(surface: surface)
        let step = playbackStep(eventIndex: 4)

        let evidence = try #require(PlaybackFailureEvidenceBuilder.makeFailureEvidence(
            macroID: macroID,
            runID: runID,
            startTime: startedAt,
            duration: 2.75,
            step: step,
            context: context,
            targetSurfaceId: TestFixtures.surfaceId,
            reason: "verifyText failed"
        ))

        #expect(evidence.macroID == macroID)
        #expect(evidence.runID == runID)
        #expect(evidence.startTime == startedAt)
        #expect(evidence.duration == 2.75)
        #expect(evidence.failedEventIndex == 4)
        #expect(evidence.errorMessage == "verifyText failed")
        #expect(evidence.bundleIdentifier == "com.example.Target")
        #expect(evidence.windowTitle == "Checkout")
    }

    @Test("Returns nil when no macro id is available")
    func returnsNilWithoutMacroID() {
        let evidence = PlaybackFailureEvidenceBuilder.makeFailureEvidence(
            macroID: nil,
            runID: UUID(),
            startTime: Date(timeIntervalSince1970: 2_000),
            duration: 1,
            step: playbackStep(),
            context: TestFixtures.playbackContext(),
            targetSurfaceId: TestFixtures.surfaceId,
            reason: "point resolution failed"
        )

        #expect(evidence == nil)
    }

    @Test("Missing surface metadata still produces clamped failure evidence")
    func missingSurfaceMetadataBuildsEvidence() throws {
        let macroID = UUID()
        let step = playbackStep(eventIndex: 9)

        let evidence = try #require(PlaybackFailureEvidenceBuilder.makeFailureEvidence(
            macroID: macroID,
            runID: UUID(),
            startTime: Date(timeIntervalSince1970: 2_000),
            duration: -1,
            step: step,
            context: PlaybackContext(),
            targetSurfaceId: "missing",
            reason: "locator resolution failed"
        ))

        #expect(evidence.macroID == macroID)
        #expect(evidence.duration == 0)
        #expect(evidence.failedEventIndex == 9)
        #expect(evidence.errorMessage == "locator resolution failed")
        #expect(evidence.bundleIdentifier == nil)
        #expect(evidence.windowTitle == nil)
    }

    private func playbackStep(eventIndex: Int = 1) -> PlaybackStep {
        PlaybackStep(
            eventIndex: eventIndex,
            event: TestFixtures.clickEvent(surfaceId: TestFixtures.surfaceId),
            deltaFromPrevious: 0,
            scheduledOffset: 0,
            progress: 0
        )
    }
}
