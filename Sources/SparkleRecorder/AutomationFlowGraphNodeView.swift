import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphNodeView: View {
    let node: AutomationTaskNodeProjection
    let size: AutomationGraphSize
    let isSelected: Bool
    let isConnectionSource: Bool
    let canCompleteConnection: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onCancelRun: (UUID) -> Void
    let onConnect: () -> Void
    let onMoveEnded: (AutomationGraphPoint) -> Void

    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(node.kindLabel, systemImage: node.status.systemImage)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(node.status.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button("Inspect task", systemImage: "sidebar.right", action: onSelect)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 22, height: 22)
                    .controlSurface(cornerRadius: 7, tint: Brand.libraryBlue, isActive: isSelected)
                    .help(NSLocalizedString("Inspect task", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Inspect task", comment: ""))

                Button(connectButtonTitle, systemImage: connectButtonImage, action: onConnect)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 22, height: 22)
                    .controlSurface(cornerRadius: 7, tint: Brand.sigAmber, isActive: isConnectionSource || canCompleteConnection)
                    .help(connectButtonTitle)
                    .accessibilityLabel(connectButtonTitle)

                if let runID = node.runID, canCancel {
                    Button("Cancel run", systemImage: "xmark", action: { onCancelRun(runID) })
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 22, height: 22)
                        .controlSurface(cornerRadius: 7, tint: Brand.red500, isActive: false)
                        .help(NSLocalizedString("Cancel run", comment: ""))
                        .accessibilityLabel(NSLocalizedString("Cancel run", comment: ""))
                } else {
                    Button("Run task now", systemImage: "play.fill", action: onRun)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 22, height: 22)
                        .controlSurface(cornerRadius: 7, tint: Brand.libraryGreen, isActive: false)
                        .disabled(!canRun)
                        .help(NSLocalizedString("Run task now", comment: ""))
                        .accessibilityLabel(NSLocalizedString("Run task now", comment: ""))
                }

                if node.hasEvidence {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            Text(node.title)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(node.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Text(node.resourceLabel)
                Text(node.scheduleLabel)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(10)
        .frame(width: CGFloat(size.width), height: CGFloat(size.height), alignment: .topLeading)
        .sectionSurface(cornerRadius: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selectionTint.opacity(isSelected || isConnectionSource ? 0.9 : 0), lineWidth: 1.4)
        )
        .offset(dragTranslation)
        .scaleEffect(isDragging ? 1.015 : 1)
        .zIndex(isDragging ? 1 : 0)
        .gesture(dragGesture)
        .help(NSLocalizedString("Drag to move task", comment: ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(NSLocalizedString("Drag to move task", comment: ""))
    }

    private var connectButtonTitle: String {
        canCompleteConnection
            ? NSLocalizedString("Connect task", comment: "")
            : NSLocalizedString("Start dependency", comment: "")
    }

    private var connectButtonImage: String {
        canCompleteConnection ? "link.badge.plus" : "link"
    }

    private var selectionTint: Color {
        isConnectionSource ? Brand.sigAmber : Brand.libraryBlue
    }

    private var isDragging: Bool {
        abs(dragTranslation.width) > 0.5 || abs(dragTranslation.height) > 0.5
    }

    private var canRun: Bool {
        switch node.status {
        case .scheduled:
            return node.runID == nil
        case .waiting, .queued, .running:
            return false
        case .completed, .failed, .cancelled, .timedOut, .blocked:
            return true
        }
    }

    private var canCancel: Bool {
        switch node.status {
        case .scheduled, .waiting, .queued, .running:
            return node.runID != nil
        case .completed, .failed, .cancelled, .timedOut, .blocked:
            return false
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                guard abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5 else {
                    return
                }
                onMoveEnded(snappedPosition(for: value.translation))
            }
    }

    private func snappedPosition(for translation: CGSize) -> AutomationGraphPoint {
        AutomationGraphPoint(
            x: snap(node.position.x + Double(translation.width)),
            y: snap(node.position.y + Double(translation.height))
        )
    }

    private func snap(_ value: Double) -> Double {
        let gridSize = 24.0
        return max(0, (value / gridSize).rounded() * gridSize)
    }

    private var accessibilitySummary: String {
        var summary = String(
            format: NSLocalizedString("%@, %@, %@", comment: ""),
            node.title,
            node.status.label,
            node.resourceLabel
        )
        if node.hasEvidence {
            summary += ", " + NSLocalizedString("Evidence available", comment: "")
        }
        return summary
    }
}
