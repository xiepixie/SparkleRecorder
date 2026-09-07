import Testing
@testable import SparkleRecorder

@Suite("App Activation Interruption Policy Tests")
struct AppActivationInterruptionPolicyTests {
    @Test("Preflight UI may stay active before target handoff")
    func preflightActivationDoesNotCancel() {
        let activity = AppInputSessionActivity(
            recordingFlowActive: true,
            isRecording: false,
            recordingFinalizationActive: false,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false
        )

        #expect(AppActivationInterruptionPolicy.resolve(
            activity: activity,
            recordingTargetHandoffArmed: false
        ) == .none)
    }

    @Test("Returning to SparkleRecorder after target handoff cancels countdown preparation")
    func targetHandoffActivationCancelsPreparation() {
        let activity = AppInputSessionActivity(
            recordingFlowActive: true,
            isRecording: false,
            recordingFinalizationActive: false,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false
        )

        #expect(AppActivationInterruptionPolicy.resolve(
            activity: activity,
            recordingTargetHandoffArmed: true
        ) == .cancelRecordingPreparation)
    }

    @Test("Live recording saves while playback stops")
    func activeInputSessionsHaveExplicitInterruptionSemantics() {
        #expect(AppActivationInterruptionPolicy.resolve(
            activity: activity(isRecording: true),
            recordingTargetHandoffArmed: true
        ) == .saveInterruptedRecording)
        #expect(AppActivationInterruptionPolicy.resolve(
            activity: activity(playbackTargetReserved: true),
            recordingTargetHandoffArmed: false
        ) == .stopPlayback)
        #expect(AppActivationInterruptionPolicy.resolve(
            activity: activity(isPlaying: true),
            recordingTargetHandoffArmed: false
        ) == .stopPlayback)
    }

    private func activity(
        isRecording: Bool = false,
        playbackTargetReserved: Bool = false,
        isPlaying: Bool = false
    ) -> AppInputSessionActivity {
        AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: isRecording,
            recordingFinalizationActive: false,
            manualPlaybackActive: false,
            playbackTargetReserved: playbackTargetReserved,
            isPlaying: isPlaying,
            reconstructionTestActive: false
        )
    }
}
