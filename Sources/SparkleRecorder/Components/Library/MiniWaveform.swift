import Cocoa
import SwiftUI
import SparkleRecorderCore

struct MiniWaveform: View {
    let events: [RecordedEvent]

    var body: some View {
        GeometryReader { geo in
            let total = events.last?.time ?? 0
            let dur = total > 0 ? total : 1
            let bars = WaveformProjection.timedBars(from: events, maxBars: 60, duration: dur)

            Canvas { context, size in
                let trackHeight = size.height * 0.5
                let trackRect = CGRect(
                    x: 0,
                    y: (size.height - trackHeight) / 2,
                    width: size.width,
                    height: trackHeight
                )
                context.fill(
                    Capsule(style: .continuous).path(in: trackRect),
                    with: .color(Color.primary.opacity(0.045))
                )
                
                for bar in bars {
                    let barWidth: CGFloat = bar.isImpact ? 2 : 1.2
                    let barHeight = bar.isImpact ? size.height * 0.82 : size.height * 0.42
                    let rect = CGRect(
                        x: min(max(0, CGFloat(bar.positionFraction) * size.width), max(0, size.width - barWidth)),
                        y: (size.height - barHeight) / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(
                        RoundedRectangle(cornerRadius: 1, style: .continuous).path(in: rect),
                        with: .color(color(for: bar.kind).opacity(bar.isImpact ? 0.74 : 0.42))
                    )
                }
            }
        }
    }

    func color(for kind: RecordedEvent.Kind) -> Color {
        Brand.eventColor(kind)
    }
}
