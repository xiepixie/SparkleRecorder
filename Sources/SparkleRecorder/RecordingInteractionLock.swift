import Foundation

struct AppInputSessionActivity: Equatable, Sendable {
    var recordingFlowActive: Bool
    var isRecording: Bool
    var recordingFinalizationActive: Bool = false
    var manualPlaybackActive: Bool
    var playbackTargetReserved: Bool
    var isPlaying: Bool
    var reconstructionTestActive: Bool
    var auxiliaryCaptureActive: Bool = false

    /// True only while SparkleRecorder still owns foreground input, a target
    /// handoff, or an interactive capture surface. Background recording
    /// finalization no longer owns those resources.
    var ownsInputOrCaptureTarget: Bool {
        recordingFlowActive
            || isRecording
            || manualPlaybackActive
            || playbackTargetReserved
            || isPlaying
            || reconstructionTestActive
            || auxiliaryCaptureActive
    }

    /// Starting another foreground-input session must still wait for recording
    /// finalization so semantic evidence and the just-recorded Macro cannot be
    /// overlapped by a new recording/playback lifecycle.
    var blocksForegroundInputStart: Bool {
        recordingFinalizationActive || ownsInputOrCaptureTarget
    }
}

enum AppInputSessionInteractionLock {
    static func protectsMacroLibrary(_ activity: AppInputSessionActivity) -> Bool {
        // Finalization may still sanitize and persist the just-recorded Macro.
        // Keep Library mutations out of that write window without disabling the
        // entire application surface.
        activity.recordingFinalizationActive || activity.ownsInputOrCaptureTarget
    }

    static func protectsAppWindows(_ activity: AppInputSessionActivity) -> Bool {
        activity.ownsInputOrCaptureTarget
    }
}
