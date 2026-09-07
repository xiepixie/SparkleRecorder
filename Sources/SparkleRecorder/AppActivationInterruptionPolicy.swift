import Foundation

enum AppActivationInterruption: Equatable, Sendable {
    case none
    case cancelRecordingPreparation
    case saveInterruptedRecording
    case stopPlayback
}

enum AppActivationInterruptionPolicy {
    /// Resolves what must happen when macOS makes SparkleRecorder frontmost.
    /// `recordingTargetHandoffArmed` becomes true only after SparkleRecorder has
    /// hidden itself and handed focus to the user's intended recording target;
    /// earlier preflight UI is allowed to remain active.
    static func resolve(
        activity: AppInputSessionActivity,
        recordingTargetHandoffArmed: Bool
    ) -> AppActivationInterruption {
        if activity.isRecording {
            return .saveInterruptedRecording
        }
        if activity.recordingFlowActive && recordingTargetHandoffArmed {
            return .cancelRecordingPreparation
        }
        if activity.manualPlaybackActive
            || activity.playbackTargetReserved
            || activity.isPlaying
            || activity.reconstructionTestActive {
            return .stopPlayback
        }
        return .none
    }
}
