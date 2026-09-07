import Testing
@testable import SparkleRecorder

@Suite("Auxiliary Capture Activity Center Tests")
struct AuxiliaryCaptureActivityCenterTests {
    @MainActor
    @Test("Overlapping screen pickers keep foreground input owned until the last token ends")
    func overlappingTokensKeepOwnership() {
        let center = AuxiliaryCaptureActivityCenter()

        let first = center.begin()
        let second = center.begin()
        #expect(center.isActive)

        center.end(first)
        #expect(center.isActive)

        center.end(second)
        #expect(!center.isActive)
    }

    @MainActor
    @Test("Ending the same picker token twice is harmless")
    func endingTokenIsIdempotent() {
        let center = AuxiliaryCaptureActivityCenter()
        let token = center.begin()

        center.end(token)
        center.end(token)

        #expect(!center.isActive)
    }
}
