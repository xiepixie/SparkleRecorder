import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphNodeView: View {
    let node: AutomationTaskNodeProjection
    let size: AutomationGraphSize
    let isSelected: Bool
    let isConnectionSource: Bool
    let canCompleteConnection: Bool
    let connectionTriggerTitle: String
    let onSelect: () -> Void
    let onRun: () -> Void
    let onCancelRun: (UUID) -> Void
    let onConnect: () -> Void
    let isDragging: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(node.kindLabel, systemImage: node.status.systemImage)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(node.status.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                AutomationNodeToolButton(
                    title: NSLocalizedString("Inspect task", comment: ""),
                    systemImage: "sidebar.right",
                    tint: Brand.libraryBlue,
                    isActive: isSelected,
                    action: onSelect
                )

                AutomationNodeToolButton(
                    title: connectButtonTitle,
                    systemImage: connectButtonImage,
                    tint: Brand.sigAmber,
                    isActive: isConnectionSource || canCompleteConnection,
                    action: onConnect
                )

                if let runID = node.runID, canCancel {
                    AutomationNodeToolButton(
                        title: NSLocalizedString("Cancel run", comment: ""),
                        systemImage: "xmark",
                        tint: Brand.red500,
                        isActive: true,
                        action: { onCancelRun(runID) }
                    )
                } else {
                    AutomationNodeToolButton(
                        title: NSLocalizedString("Run task now", comment: ""),
                        systemImage: "play.fill",
                        tint: Brand.libraryGreen,
                        isActive: false,
                        action: onRun
                    )
                        .disabled(!canRun)
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

            AutomationRuntimeDetailStrip(
                statusDetail: node.statusDetail,
                statusTint: node.status.tint,
                timeoutCountdown: node.timeoutCountdown,
                retryAttemptSummary: node.retryAttemptSummary,
                density: .node
            )

            if let conditionProgress = node.conditionProgress {
                AutomationConditionProgressView(
                    progress: conditionProgress,
                    tint: node.status.tint,
                    density: .compact
                )
            }

            if showsJoinPolicy {
                AutomationJoinPolicyBadgeView(
                    policy: node.joinPolicy,
                    label: node.joinPolicyLabel,
                    incomingDependencyCount: node.incomingDependencyCount
                )
            }

            HStack(spacing: 5) {
                Text(node.resourceLabel)
                if let nextScheduledOccurrence = node.nextScheduledOccurrence {
                    AutomationNextScheduleBadge(
                        date: nextScheduledOccurrence,
                        title: NSLocalizedString("Next", comment: ""),
                        isCompact: true
                    )
                } else {
                    Text(node.scheduleLabel)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(10)
        .frame(width: CGFloat(size.width), height: CGFloat(size.height), alignment: .topLeading)
        .sectionSurface(cornerRadius: 10)
        .overlay(alignment: .top) {
            AutomationRuntimeStatusHairline(status: node.status)
                .padding(.horizontal, 12)
                .padding(.top, 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selectionTint.opacity(isSelected || isConnectionSource ? 0.9 : 0), lineWidth: 1.4)
        )
        .scaleEffect(isDragging ? 1.015 : 1)
        .zIndex(isDragging ? 1 : 0)
        .preventWindowDrag()
        .help(NSLocalizedString("Drag to move task", comment: ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(NSLocalizedString("Drag to move task", comment: ""))
    }

    private var connectButtonTitle: String {
        if canCompleteConnection {
            return String(
                format: NSLocalizedString("Connect with %@", comment: ""),
                connectionTriggerTitle
            )
        }
        return NSLocalizedString("Start dependency", comment: "")
    }

    private var showsJoinPolicy: Bool {
        node.incomingDependencyCount > 1 || node.joinPolicy != .all
    }

    private var connectButtonImage: String {
        canCompleteConnection ? "link.badge.plus" : "link"
    }

    private var selectionTint: Color {
        isConnectionSource ? Brand.sigAmber : Brand.libraryBlue
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
        if showsJoinPolicy {
            summary += ", " + String(
                format: NSLocalizedString("Join policy: %@", comment: ""),
                node.joinPolicyLabel
            )
        }
        if let runtimeSummary = AutomationRuntimeDetailFormatter.accessibilitySummary(
            timeoutCountdown: node.timeoutCountdown,
            retryAttemptSummary: node.retryAttemptSummary
        ) {
            summary += ", " + runtimeSummary
        }
        if let conditionProgress = node.conditionProgress {
            summary += ", " + AutomationConditionProgressFormatter.accessibilitySummary(for: conditionProgress)
        }
        return summary
    }
}
