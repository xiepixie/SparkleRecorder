import Cocoa
import SwiftUI
import SparkleRecorderCore

struct PlayerStateListener: View {
    @EnvironmentObject var player: Player

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: player.isPlaying) { oldPlaying, playing in
                CoordinatePreviewOverlay.shared.setIgnoresMouseEvents(playing)
            }
    }
}
