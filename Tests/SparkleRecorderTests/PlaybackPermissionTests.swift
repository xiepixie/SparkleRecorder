import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Playback permission boundary")
struct PlaybackPermissionTests {
    @Test @MainActor func deniedPermissionDoesNotEnterPlayingState() {
        let player = Player(eventPoster: .none, evidenceClient: .none, canPostEvents: { false })
        var finished: Bool?
        #expect(!player.play(events: TestFixtures.clickPair(), completion: { finished = $0 }))
        #expect(finished == false)
        #expect(!player.isPlaying)
        #expect(player.playbackPermissionFailure != nil)
    }

    @Test @MainActor func automationRejectsBeforePreparingTarget() async {
        let player = Player(eventPoster: .none, evidenceClient: .none, canPostEvents: { false })
        let client = AutomationPlayerClient.live(player: player, targetApplications: .init(prepare: { _, _ in
            Issue.record("Denied playback must not launch or focus a target")
            return .success(.empty)
        }))
        let request = AutomationPlayerStartRequest(runID: UUID(), macro: SavedMacro(name: "Denied", events: TestFixtures.clickPair()))
        guard case .rejected = await client.start(request) else { Issue.record("Expected rejection"); return }
        #expect(!player.ownsAutomationRun(request.runID))
        #expect(!player.isPlaying)
    }
}
