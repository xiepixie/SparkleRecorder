import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Window Target Selection Tests")
struct WindowTargetSelectionTests {
    @Test("Selects the frontmost non-SparkleRecorder window under the pointer")
    func selectsFrontmostEligibleWindow() throws {
        let ownPID: Int32 = 10
        let windows = [
            PlaybackForegroundWindowObservation(
                id: 1,
                processID: ownPID,
                frame: RectValue(x: 0, y: 0, width: 500, height: 500)
            ),
            PlaybackForegroundWindowObservation(
                id: 2,
                processID: 20,
                frame: RectValue(x: 40, y: 40, width: 300, height: 300)
            ),
            PlaybackForegroundWindowObservation(
                id: 3,
                processID: 30,
                frame: RectValue(x: 40, y: 40, width: 300, height: 300)
            )
        ]

        let selected = try #require(
            WindowTargetSelection.window(
                at: CGPoint(x: 100, y: 100),
                windows: windows,
                excludingProcessID: ownPID
            )
        )

        #expect(selected.id == 2)
        #expect(selected.processID == 20)
    }

    @Test("SparkleRecorder's own window is never a selectable target")
    func excludesOwnWindow() {
        let ownPID: Int32 = 10
        let windows = [
            PlaybackForegroundWindowObservation(
                id: 1,
                processID: ownPID,
                frame: RectValue(x: 0, y: 0, width: 500, height: 500)
            )
        ]

        #expect(
            WindowTargetSelection.window(
                at: CGPoint(x: 100, y: 100),
                windows: windows,
                excludingProcessID: ownPID
            ) == nil
        )
    }

    @Test("Returns nil when the pointer is not inside an eligible app window")
    func returnsNilOutsideWindows() {
        let windows = [
            PlaybackForegroundWindowObservation(
                id: 1,
                processID: 20,
                frame: RectValue(x: 40, y: 40, width: 300, height: 300)
            )
        ]

        #expect(
            WindowTargetSelection.window(
                at: CGPoint(x: 500, y: 500),
                windows: windows
            ) == nil
        )
    }
}
