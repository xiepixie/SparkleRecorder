import Foundation

public enum PlaybackFailureEvidenceBuilder {
    public static func makeFailureEvidence(
        macroID: UUID?,
        runID: UUID,
        startTime: Date,
        duration: TimeInterval,
        step: PlaybackStep,
        context: PlaybackContext,
        targetSurfaceId: String,
        reason: String
    ) -> PlaybackFailureEvidence? {
        guard let macroID else { return nil }
        let surface = context.surfaces[targetSurfaceId]
        return PlaybackFailureEvidence(
            macroID: macroID,
            runID: runID,
            startTime: startTime,
            duration: duration,
            failedEventIndex: step.eventIndex,
            errorMessage: reason,
            bundleIdentifier: surface?.bundleIdentifier,
            windowTitle: surface?.windowTitle
        )
    }
}
