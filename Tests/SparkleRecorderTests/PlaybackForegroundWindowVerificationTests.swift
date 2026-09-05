import Testing
@testable import SparkleRecorderCore

@Suite struct PlaybackForegroundWindowVerificationTests {
    let frame = RectValue(x: 0, y: 39, width: 2056, height: 1290)
    func window(_ id: UInt32, pid: Int32 = 7, frame: RectValue? = nil) -> PlaybackForegroundWindowObservation {
        .init(id: id, processID: pid, frame: frame ?? self.frame)
    }
    @Test func requiresActualFrontWindow() {
        #expect(PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, expectedFrame: frame, windows: [window(1)]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: false, targetProcessID: 7, expectedFrame: frame, windows: [window(1)]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, expectedFrame: frame, windows: [window(2, pid: 8), window(1)]))
    }
    @Test func rejectsDifferentOrAmbiguousWindow() {
        let other = window(2, frame: .init(x: 0, y: 39, width: 2049, height: 1270))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, expectedFrame: frame, windows: [other, window(1)]))
        #expect(!PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, expectedFrame: frame, windows: [window(1), window(2)]))
        #expect(PlaybackForegroundWindowVerification.isReady(active: true, targetProcessID: 7, expectedFrame: frame, windows: [window(1), other]))
    }
}
