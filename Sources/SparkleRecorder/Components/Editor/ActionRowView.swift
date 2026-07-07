import Cocoa
import SwiftUI
import SparkleRecorderCore

struct ActionRowView: View {
    @EnvironmentObject var library: MacroLibrary
    let row: ActionRow
    let order: Int
    let selected: Bool
    let isMoving: Bool
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onDragStarted: () -> Void
    @Binding var draggedID: UUID?
    @State private var hovered = false

    private var g: ActionGroup { row.group }
    private var isDraggable: Bool { g.kind.isReorderableAction }

    var body: some View {
        if isDraggable {
            rowContent
                .onDrag {
                    onDragStarted()
                    draggedID = row.id
                    return NSItemProvider(object: row.id.uuidString as NSString)
                }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .center) {
                HStack {
                    Image(systemName: "line.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(isDraggable && (hovered || isMoving) ? 1.0 : 0.0)
                        .help(isDraggable ? NSLocalizedString("Drag to reorder", comment: "") : "")
                    Spacer()
                }
                .padding(.leading, 6)

                Text(String(format: "%02d", order))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .opacity((hovered || isMoving) ? 0.62 : 1.0)
            }
            .frame(width: EventCol.num, alignment: .center)
            .contentShape(Rectangle())

            Text(String(format: "%.3fs", g.startTime))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: EventCol.time, alignment: .center)

	            HStack(spacing: 8) {
	                ZStack {
	                    RoundedRectangle(cornerRadius: 5, style: .continuous)
	                        .fill(actionKindColor(g.kind).opacity(selected ? 0.20 : 0.14))
	                    Image(systemName: actionKindIcon(g.kind))
	                        .font(.system(size: 9, weight: .semibold))
	                        .foregroundStyle(actionKindColor(g.kind))
	                }
	                .frame(width: 20, height: 20)
	                Text(g.summary)
	                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
	                    .foregroundStyle(.primary)
	                    .lineLimit(1)
	                    .truncationMode(.tail)
	                    .help(g.summary)
                
                if let countLabel = actionRowCountLabel(for: g) {
                    let countTint = g.kind.previewsPointSequence
                        ? actionKindColor(g.kind)
                        : (g.kind == .scroll ? actionKindColor(g.kind) : (g.kind == .sequence ? Brand.sigAmber : Brand.accent(library.currentMacro?.accent)))
                    Text(countLabel)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(countTint)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 0.5)
                        .background(
                            Capsule()
                                .fill(countTint.opacity(0.12))
                        )
                }
            }
	            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let statusLabel = actionRowTextTargetStatusLabel(g.textTargetReadiness) {
                    Text(statusLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Brand.sigAmber)
                } else if let ocrText = g.textAnchor?.text {
                    if ActionGroupProjection.textAnchorIsReady(g.textAnchor) {
                        Text("\"\(ocrText)\"")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Brand.sigAmber)
                    } else {
                        Text(NSLocalizedString("No target text", comment: ""))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Brand.sigAmber)
                    }
                } else if g.kind.previewsPointSequence {
                    Text(String(format: NSLocalizedString("%d points", comment: ""), max(g.path.count, g.clickCount)))
                } else if let sp = g.startPoint {
                    if let ep = g.endPoint, g.kind.editsPathTarget {
                        Text("(\(Int(sp.x)),\(Int(sp.y)))→(\(Int(ep.x)),\(Int(ep.y)))")
                    } else {
                        Text("(\(Int(sp.x)), \(Int(sp.y)))")
                    }
                } else {
                    Text("—").foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: EventCol.pos, alignment: .center)

            Group {
                if g.kind.editsKeyboardInput, let kc = g.keyCode {
                    Text(shortcutName(keyCode: kc, flags: g.keyFlags ?? 0))
                } else {
                    Text("—").foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: EventCol.key, alignment: .center)
        }
	        .padding(.horizontal, 12)
	        .padding(.vertical, 8)
	        .background(
	            ZStack(alignment: .leading) {
	                let accent = Brand.accent(library.currentMacro?.accent)
	                Rectangle().fill(
	                    selected ? accent.opacity(0.08)
	                             : (hovered ? Color.primary.opacity(0.035) : Color.clear))
	                if selected {
	                    Rectangle().fill(accent).frame(width: 3)
	                }
	            }
	        )
        .opacity(isMoving ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onTap(NSApp.currentEvent?.modifierFlags ?? []) }
    }
}
