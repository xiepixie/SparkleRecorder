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
                    title: String(localized: "Inspect task", table: "Automation"),
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
                        title: String(localized: "Cancel run", table: "Automation"),
                        systemImage: "xmark",
                        tint: Brand.red500,
                        isActive: true,
                        action: { onCancelRun(runID) }
                    )
                } else {
                    AutomationNodeToolButton(
                        title: String(localized: "Run task now", table: "Automation"),
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
                        title: String(localized: "Next", table: "Common"),
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
        .help(String(localized: "Drag to move task", table: "Automation"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(String(localized: "Drag to move task", table: "Automation"))
    }

    private var connectButtonTitle: String {
        if canCompleteConnection {
            return String(
                format: String(localized: "Connect with %@", table: "Common"),
                connectionTriggerTitle
            )
        }
        return String(localized: "Start dependency", table: "Automation")
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
            format: String(localized: "%@, %@, %@", table: "Common"),
            node.title,
            node.status.label,
            node.resourceLabel
        )
        if node.hasEvidence {
            summary += ", " + String(localized: "Evidence available", table: "Automation")
        }
        if showsJoinPolicy {
            summary += ", " + String(
                format: String(localized: "Join policy: %@", table: "Common"),
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
