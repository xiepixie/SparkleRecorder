import Testing
@testable import SparkleRecorderCore

@Suite struct PlaybackForegroundWindowVerificationTests {
    let frame = RectValue(x: 0, y: 39, width: 2056, height: 1290)
    func window(_ id: UInt32, pid: Int32 = 7, frame: RectValue? = nil) -> PlaybackForegroundWindowObservation {
        .init(id: id, processID: pid, frame: frame ?? self.frame)
    }
    @Test func recordingCaptureUsesFrontmostMatchingWindowID() {
        let front = window(42, pid: 7)
        let behind = window(43, pid: 7)
        let unrelated = window(99, pid: 8)
        #expect(
            PlaybackForegroundWindowVerification.frontmostMatchingWindowID(
                targetProcessID: 7,
                recordedFrame: frame,
                windows: [unrelated, front, behind]
            ) == 42
        )
    }

    @Test func selectsWindowOwnerRatherThanFirstSameBundleProcess() {
        let owned = window(1, pid: 16733)
        let unrelated = window(2, pid: 43632, frame: .init(x: 20, y: 20, width: 800, height: 600))
        #expect(PlaybackForegroundWindowVerification.targetProcessID(recordedFrame: frame, windows: [unrelated, owned]) == 16733)
        #expect(PlaybackForegroundWindowVerification.targetProcessID(recordedFrame: frame, windows: [unrelated]) == nil)
        #expect(PlaybackForegroundWindowVerification.targetProcessID(recordedFrame: frame, windows: [owned, window(3, pid: 43632)]) == nil)
    }
    @Test func requiresActualFrontWindow() {
        #expect(PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, windows: [window(1)]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: false, targetProcessID: 7, recordedFrame: frame, windows: [window(1)]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, windows: [window(2, pid: 8), window(1)]))
    }
    @Test func rejectsDifferentOrAmbiguousWindow() {
        let other = window(2, frame: .init(x: 0, y: 39, width: 2049, height: 1270))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, windows: [other]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, windows: [other, window(1)]))
        #expect(PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, recordedWindowID: 2, windows: [other]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, windows: [window(1), window(2)]))
        #expect(PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, recordedFrame: frame, windows: [window(1), other]))
    }

    @Test func staleRecordedWindowIDFallsBackOnlyWhenTheOldWindowNoLongerExists() {
        let replacement = window(1, pid: 7)
        #expect(
            PlaybackForegroundWindowVerification.targetProcessID(
                recordedFrame: frame,
                recordedWindowID: 99,
                windows: [replacement]
            ) == 7
        )
        #expect(
            PlaybackForegroundWindowVerification.isReady(
                active: true,
                targetProcessID: 7,
                recordedFrame: frame,
                recordedWindowID: 99,
                windows: [replacement]
            )
        )

        let oldWindowStillExists = window(99, pid: 7)
        #expect(
            !PlaybackForegroundWindowVerification.isReady(
                active: true,
                targetProcessID: 7,
                recordedFrame: frame,
                recordedWindowID: 99,
                windows: [replacement, oldWindowStillExists]
            )
        )
    }
}
