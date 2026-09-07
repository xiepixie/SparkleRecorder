import Testing
@testable import SparkleRecorder

@Suite("Manual Playback Visibility Session Tests")
struct ManualPlaybackVisibilitySessionTests {
    @Test @MainActor
    func oneSnapshotSpansAPlaybackChainAndRestoresOnce() {
        var captureCount = 0
        var restoreCount = 0
        let session = ManualPlaybackVisibilitySession(captureRestore: {
            captureCount += 1
            return { restoreCount += 1 }
        })

        session.beginIfNeeded()
        session.beginIfNeeded()

        #expect(session.isActive)
        #expect(captureCount == 1)
        #expect(restoreCount == 0)

        session.restore()
        session.restore()

        #expect(!session.isActive)
        #expect(captureCount == 1)
        #expect(restoreCount == 1)

        session.beginIfNeeded()
        #expect(captureCount == 2)
        session.restore()
        #expect(restoreCount == 2)
    }
}
