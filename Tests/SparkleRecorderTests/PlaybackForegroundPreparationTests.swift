import Foundation

import Testing
import SparkleRecorderCore

@Suite("Verified foreground handoff")
struct PlaybackForegroundPreparationTests {
    @Test func acceptedRequestWithoutForegroundNeverSucceeds() async {
        let client = PlaybackForegroundPreparation(request: {}, isReady: { false }, sleep: {})
        #expect(await client.prepare(attempts: 3) == false)
    }

    @Test func waitsForObservedReadiness() async {
        let probe = ForegroundProbe()
        let client = PlaybackForegroundPreparation(request: { await probe.request() },
            isReady: { await probe.ready }, sleep: {})
        #expect(await client.prepare(attempts: 4))
        #expect(await probe.count == 3)
    }

    @Test func cancelledWaitDoesNotPermitPlayback() async {
        let client = PlaybackForegroundPreparation(request: {}, isReady: { false }, sleep: { throw CancellationError() })
        #expect(await client.prepare() == false)
    }
}
private actor ForegroundProbe {
    var count = 0
    var ready: Bool { count >= 3 }
    func request() { count += 1 }
}
