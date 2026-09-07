import Testing
@testable import SparkleRecorder

@Suite("App Stop Menu Mode Tests")
struct AppStopMenuModeTests {
    @Test("Stop menu describes destructive recording semantics instead of generic Stop")
    func recordingModesAreExplicit() {
        #expect(AppStopMenuMode.project(activity(recordingFlowActive: true)) == .cancelRecordingPreparation)
        #expect(AppStopMenuMode.project(activity(isRecording: true)) == .discardRecording)
        #expect(AppStopMenuMode.project(activity(recordingFinalizationActive: true)) == .finishingRecording)
        #expect(!AppStopMenuMode.finishingRecording.isEnabled)
    }

    @Test("Screen picking owns Stop until the picker is cancelled")
    func pickingModeIsExplicit() {
        let mode = AppStopMenuMode.project(activity(auxiliaryCaptureActive: true))
        #expect(mode == .cancelPicking)
        #expect(mode.isEnabled)
    }

    @Test("Playback preparation and execution share Stop Playback semantics")
    func playbackModesAreExplicit() {
        #expect(AppStopMenuMode.project(activity(manualPlaybackActive: true)) == .stopPlayback)
        #expect(AppStopMenuMode.project(activity(playbackTargetReserved: true)) == .stopPlayback)
        #expect(AppStopMenuMode.project(activity(isPlaying: true)) == .stopPlayback)
        #expect(AppStopMenuMode.stopPlayback.isEnabled)
    }

    @Test("Idle Stop menu is disabled")
    func idleIsDisabled() {
        let mode = AppStopMenuMode.project(activity())
        #expect(mode == .idle)
        #expect(!mode.isEnabled)
    }

    private func activity(
        recordingFlowActive: Bool = false,
        isRecording: Bool = false,
        recordingFinalizationActive: Bool = false,
        manualPlaybackActive: Bool = false,
        playbackTargetReserved: Bool = false,
        isPlaying: Bool = false,
        reconstructionTestActive: Bool = false,
        auxiliaryCaptureActive: Bool = false
    ) -> AppInputSessionActivity {
        AppInputSessionActivity(
            recordingFlowActive: recordingFlowActive,
            isRecording: isRecording,
            recordingFinalizationActive: recordingFinalizationActive,
            manualPlaybackActive: manualPlaybackActive,
            playbackTargetReserved: playbackTargetReserved,
            isPlaying: isPlaying,
            reconstructionTestActive: reconstructionTestActive,
            auxiliaryCaptureActive: auxiliaryCaptureActive
        )
    }
}
