import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Target Application Client Tests")
struct AutomationTargetApplicationClientTests {
    @Test("Cleanup only selects applications recorded as launched by the run")
    func cleanupOnlySelectsRunLaunchedApplications() {
        let session = AutomationTargetApplicationSession(
            launchedBundleIdentifiers: ["com.example.B", "com.example.A"]
        )

        #expect(session.bundleIdentifiersToQuit(under: .keepOpen).isEmpty)
        #expect(session.bundleIdentifiersToQuit(under: .quitIfLaunched) == [
            "com.example.A",
            "com.example.B",
        ])
        #expect(AutomationTargetApplicationSession.empty
            .bundleIdentifiersToQuit(under: .quitIfLaunched)
            .isEmpty)
    }

    @Test("Player rejects a run when target application preparation fails")
    @MainActor
    func playerRejectsFailedTargetPreparation() async throws {
        let macro = SavedMacro(
            name: "Bound task",
            events: TestFixtures.clickPair(),
            surfaces: [
                TestFixtures.surfaceId: TestFixtures.surface(
                    appName: "Target App",
                    bundleIdentifier: "com.example.TargetApp",
                    windowTitle: "Target"
                )
            ]
        )
        let recorder = TargetApplicationPreparationRecorder()
        let targetApplications = AutomationTargetApplicationClient { surfaces, policy in
            await recorder.record(surfaces: surfaces, policy: policy)
            return .failure(.init(message: "Target window unavailable"))
        }
        let player = AutomationPlayerClient.live(
            player: Player(),
            targetApplications: targetApplications
        )

        let result = await player.start(AutomationPlayerStartRequest(
            runID: UUID(),
            macro: macro,
            targetApplicationPolicy: .launchIfNeeded
        ))

        #expect(result == .rejected(.rejected(reason: "Target window unavailable")))
        #expect(await recorder.policies == [.launchIfNeeded])
        #expect(await recorder.surfaceCounts == [1])
    }
}

private actor TargetApplicationPreparationRecorder {
    private var recordedPolicies: [AutomationTargetApplicationPolicy] = []
    private var recordedSurfaceCounts: [Int] = []

    var policies: [AutomationTargetApplicationPolicy] { recordedPolicies }
    var surfaceCounts: [Int] { recordedSurfaceCounts }

    func record(
        surfaces: [String: PlaybackSurface],
        policy: AutomationTargetApplicationPolicy
    ) {
        recordedPolicies.append(policy)
        recordedSurfaceCounts.append(surfaces.count)
    }
}
