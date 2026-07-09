import Cocoa
import SwiftUI
import SparkleRecorderCore

struct EditorTimeline: View {
    @EnvironmentObject var library: MacroLibrary
    @EnvironmentObject var player: Player
    let samples: [TimelineSampledEvent]
    let totalDuration: TimeInterval
    let groups: [ActionGroup]
    @Binding var selection: Set<UUID>

    @State private var hoverFraction: Double?
    @State private var dragRange: (start: Double, end: Double)?
    @GestureState private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIMELINE", tableName: "EditorUX")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                LegendChip(label: String(localized: "Keys", table: "Common"),    tint: Brand.sigBlue)
                LegendChip(label: String(localized: "Clicks", table: "EditorUX"),  tint: Brand.sigGreen)
                LegendChip(label: String(localized: "Scrolls", table: "Common"), tint: Brand.sigTeal)
                LegendChip(label: String(localized: "Drags", table: "EditorUX"),   tint: Brand.sigViolet)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .leading) {
	                    RoundedRectangle(cornerRadius: 8, style: .continuous)
	                        .fill(Color.primary.opacity(0.035))
	                        .overlay(
	                            RoundedRectangle(cornerRadius: 8, style: .continuous)
	                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                        )

                    // Event bars
                    Canvas { context, size in
                        guard totalDuration > 0 else { return }
                        let h = size.height
                        let w = size.width
                        for sampled in samples {
                            let ev = sampled.event
                            let x = CGFloat(ev.time / totalDuration) * w
                            let isImpact = Brand.isImpact(ev.kind)
                            let rectHeight = isImpact ? h * 0.75 : h * 0.45
                            let rect = CGRect(x: x - 1, y: (h - rectHeight) / 2, width: 2, height: rectHeight)
                            let color = Brand.eventColor(ev.kind).opacity(isImpact ? 1.0 : 0.7)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                        }
                    }

                    // Selection range
                    if let r = selectionRange(in: w) {
                        let barHalfWidth: CGFloat = 1.0
                        let startX = r.start - barHalfWidth
                        let boxWidth = (r.end - r.start) + (barHalfWidth * 2)
                        
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                            .overlay(
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 1.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            )
                            .frame(width: max(2, boxWidth), height: h)
                            .offset(x: startX)
                    }

                    // Drag preview
                    if let dr = dragRange {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: max(2, CGFloat(abs(dr.end - dr.start)) * w), height: h)
                            .offset(x: CGFloat(min(dr.start, dr.end)) * w)
                    }

                    // Playhead
                    TimelinePlayheadView(player: player, clock: player.clock, totalDuration: totalDuration)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, s, _ in s = true }
                        .onChanged { val in
                            let s = Double(max(0, min(1, val.startLocation.x / w)))
                            let e = Double(max(0, min(1, val.location.x / w)))
                            dragRange = (s, e)
                        }
                        .onEnded { _ in
                            if let dr = dragRange {
                                let newSel = TimelineProjection.selection(
                                    dragStartFraction: dr.start,
                                    dragEndFraction: dr.end,
                                    totalDuration: totalDuration,
                                    groups: groups
                                )
                                if !newSel.isEmpty {
                                    selection = newSel
                                }
                            }
                            dragRange = nil
                        }
                )
            }
            .frame(height: 50)

            HStack {
                Text(formatTime(0))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(totalDuration / 2))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(totalDuration))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let id = selection.first, selection.count == 1,
                   let grp = groups.first(where: { $0.id == id }) {
                    let themeColor = actionKindColor(grp.kind)
                    HStack(spacing: 4) {
                        Circle().fill(themeColor).frame(width: 6, height: 6)
                        Text(formatTime(grp.startTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(themeColor.opacity(0.12)))
                }
	                Text("Drag on timeline to select a range; a tiny range selects the nearest action.", tableName: "EditorUX")
	                    .font(.system(size: 10))
	                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    func selectionRange(in width: CGFloat) -> (start: CGFloat, end: CGFloat)? {
        guard !selection.isEmpty, totalDuration > 0 else { return nil }
        guard let range = TimelineProjection.selectedTimeRange(selection: selection, groups: groups) else { return nil }
        let s = CGFloat(range.start / totalDuration) * width
        let e = CGFloat(range.end / totalDuration) * width
        return (s, e)
    }

    func formatTime(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        let cs = Int((d - floor(d)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    func eventColor(for kind: RecordedEvent.Kind) -> Color {
        Brand.eventColor(kind)
    }
}
