import Cocoa
import SwiftUI
import SparkleRecorderCore

struct MiniWaveform: View {
    let events: [RecordedEvent]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = events.last?.time ?? 0
            let dur = total > 0 ? total : 1
            let bars = sampleEvents(maxBars: 60, width: w, dur: dur)

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
                        x: min(max(0, bar.x), max(0, size.width - barWidth)),
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

    struct Bar { let x: CGFloat; let kind: RecordedEvent.Kind; let isImpact: Bool }

    func sampleEvents(maxBars: Int, width: CGFloat, dur: TimeInterval) -> [Bar] {
        guard !events.isEmpty else { return [] }
        let n = min(events.count, maxBars)
        let stride = max(1, events.count / n)
        var result: [Bar] = []
        var i = 0
        while i < events.count {
            let ev = events[i]
            let x = CGFloat(ev.time / dur) * width
            result.append(Bar(x: x, kind: ev.kind, isImpact: Brand.isImpact(ev.kind)))
            i += stride
        }
        return result
    }

    func color(for kind: RecordedEvent.Kind) -> Color {
        Brand.eventColor(kind)
    }
}
