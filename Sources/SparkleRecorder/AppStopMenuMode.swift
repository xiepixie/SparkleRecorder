import Foundation

enum AppStopMenuMode: Equatable, Sendable {
    case idle
    case cancelRecordingPreparation
    case discardRecording
    case finishingRecording
    case cancelPicking
    case stopPlayback

    static func project(_ activity: AppInputSessionActivity) -> AppStopMenuMode {
        if activity.recordingFinalizationActive {
            return .finishingRecording
        }
        if activity.isRecording {
            return .discardRecording
        }
        if activity.recordingFlowActive {
            return .cancelRecordingPreparation
        }
        if activity.auxiliaryCaptureActive {
            return .cancelPicking
        }
        if activity.manualPlaybackActive
            || activity.playbackTargetReserved
            || activity.isPlaying
            || activity.reconstructionTestActive {
            return .stopPlayback
        }
        return .idle
    }

    var isEnabled: Bool {
        switch self {
        case .idle, .finishingRecording:
            return false
        case .cancelRecordingPreparation, .discardRecording, .cancelPicking, .stopPlayback:
            return true
        }
    }

    var title: String {
        switch self {
        case .idle:
            return String(localized: "Stop", table: "Common")
        case .cancelRecordingPreparation:
            return String(localized: "Cancel Recording", table: "Recording")
        case .discardRecording:
            return String(localized: "Discard Recording", table: "Recording")
        case .finishingRecording:
            return String(localized: "Finishing Recording…", table: "Recording")
        case .cancelPicking:
            return String(localized: "Cancel Picking", table: "EditorUX")
        case .stopPlayback:
            return String(localized: "Stop Playback", table: "Recording")
        }
    }
}
