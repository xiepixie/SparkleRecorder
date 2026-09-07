import AVFoundation
import Foundation
import Testing
@testable import SparkleRecorder

@Suite("Macro reconstruction video surface") @MainActor
struct MacroReconstructionVideoSurfaceTests {
    @Test("Review video uses AVPlayerLayer and releases the player on teardown")
    func playerLayerBackendOwnsNoReviewPlayerAfterTeardown() throws {
        let player = AVPlayer()
        let view = MacroReconstructionPlayerLayerView(player: player)
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        view.layoutSubtreeIfNeeded()

        let playerLayer = try #require(
            view.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
        )
        #expect(playerLayer.player === player)

        view.setPlayer(nil)
        #expect(playerLayer.player == nil)
    }

    @Test("Review sheet does not reintroduce SwiftUI VideoPlayer")
    func reviewSheetAvoidsDistributionCrashBackend() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheetURL = repositoryRoot
            .appendingPathComponent("Sources/SparkleRecorder/Components/Library/MacroReconstructionSheet.swift")
        let source = try String(contentsOf: sheetURL, encoding: .utf8)

        #expect(source.contains("MacroReconstructionVideoSurface(player: player)"))
        #expect(!source.contains("VideoPlayer(player:"))
        #expect(!source.contains("import AVKit"))
    }
}
