import Cocoa
import SwiftUI
import SparkleRecorderCore

struct TimelinePlayheadView: View {
    @ObservedObject var player: Player
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject var library: MacroLibrary
    let totalDuration: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            if player.isPlaying {
                Rectangle()
                    .fill(Brand.accent(library.currentMacro?.accent))
                    .frame(width: 2, height: height)
                    .position(x: CGFloat(clock.progress) * width, y: height / 2)
                    .animation(.linear(duration: 0.1), value: clock.progress)
            }
        }
    }
}
