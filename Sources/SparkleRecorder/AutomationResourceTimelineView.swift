import SwiftUI
import SparkleRecorderCore

struct AutomationResourceTimelineView: View {
    let items: [AutomationResourceTimelineItem]
    let nextScheduledOccurrence: Date?
    let nextSchedule: AutomationSchedule?
    let nextScheduledTaskName: String?
    var selectedRunID: UUID?
    let onUpdateNextSchedule: ((AutomationTimelineScheduleEdit) -> Void)?
    let onSelectItem: (AutomationResourceTimelineItem) -> Void

    private let cardWidth = 268.0
    private let nodeDiameter = 16.0
    private let connectorHeight = 2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nextScheduledOccurrence != nil || nextScheduledTaskName != nil {
                AutomationTimelineSchedulePreview(
                    date: nextScheduledOccurrence,
                    schedule: nextSchedule,
                    taskName: nextScheduledTaskName,
                    onApplySchedule: onUpdateNextSchedule
                )
                .frame(maxWidth: 780, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            if items.isEmpty {
                AutomationEmptyState(
                    systemImage: "clock.badge.questionmark",
                    title: String(localized: "No runs yet", table: "Common"),
                    subtitle: String(localized: "Manual or scheduled starts will appear here as timed checkpoints.", table: "Common")
                )
                .frame(maxWidth: .infinity, minHeight: 118)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                            AutomationTimelineColumn(
                                item: item,
                                previousItem: index > 0 ? displayItems[index - 1] : nil,
                                isFirst: index == 0,
                                isLast: index == displayItems.count - 1,
                                hasConflict: conflictIDs.contains(item.id),
                                isSelected: selectedRunID == item.runID,
                                cardWidth: cardWidth,
                                nodeDiameter: nodeDiameter,
                                connectorHeight: connectorHeight,
                                onSelect: {
                                    onSelectItem(item)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, nextScheduledOccurrence == nil ? 10 : 2)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var displayItems: [AutomationResourceTimelineItem] {
        items.sorted { left, right in
            let leftStart = left.timelineStart ?? .distantPast
            let rightStart = right.timelineStart ?? .distantPast
            if leftStart == rightStart {
                return left.title < right.title
            }
            return leftStart < rightStart
        }
    }

    private var conflictIDs: Set<UUID> {
        var ids = Set<UUID>()
        for leftIndex in displayItems.indices {
            for rightIndex in displayItems.indices where rightIndex > leftIndex {
                let left = displayItems[leftIndex]
                let right = displayItems[rightIndex]
                guard sharesExclusiveResource(left, right), intervalsOverlap(left, right) else {
                    continue
                }
                ids.insert(left.id)
                ids.insert(right.id)
            }
        }
        return ids
    }

    private func sharesExclusiveResource(
        _ left: AutomationResourceTimelineItem,
        _ right: AutomationResourceTimelineItem
    ) -> Bool {
        let leftKeys = Set(left.resourceKeys ?? [])
        let rightKeys = Set(right.resourceKeys ?? [])
        return !leftKeys.isEmpty && !leftKeys.intersection(rightKeys).isEmpty
    }

    private func intervalsOverlap(
        _ left: AutomationResourceTimelineItem,
        _ right: AutomationResourceTimelineItem
    ) -> Bool {
        guard let leftInterval = interval(for: left),
              let rightInterval = interval(for: right) else {
            return false
        }
        let startsTogether = abs(leftInterval.start.timeIntervalSince(rightInterval.start)) < 1
        let overlaps = leftInterval.start < rightInterval.end && rightInterval.start < leftInterval.end
        return startsTogether || overlaps
    }

    private func interval(for item: AutomationResourceTimelineItem) -> (start: Date, end: Date)? {
        guard let start = item.timelineStart else {
            return nil
        }
        if item.status == .running {
            return (start, .distantFuture)
        }
        let end = item.completedAt ?? start
        return (start, max(start, end))
    }
}

private struct AutomationTimelineColumn: View {
    let item: AutomationResourceTimelineItem
    let previousItem: AutomationResourceTimelineItem?
    let isFirst: Bool
    let isLast: Bool
    let hasConflict: Bool
    let isSelected: Bool
    let cardWidth: CGFloat
    let nodeDiameter: CGFloat
    let connectorHeight: CGFloat
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            timelineTimeLabel

            HStack(spacing: 0) {
                connector(isLeading: true)
                    .overlay(alignment: .top) {
                        if let transitionLabel {
                            Text(transitionLabel)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(hasConflict ? Brand.red500 : Color.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill((hasConflict ? Brand.red500 : Color.secondary).opacity(0.10))
                                )
                                .offset(y: -12)
                        }
                    }

                ZStack {
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: nodeDiameter + 6, height: nodeDiameter + 6)

                    Circle()
                        .fill(hasConflict ? Brand.red500 : item.status.tint)
                        .frame(width: nodeDiameter, height: nodeDiameter)

                    Circle()
                        .strokeBorder(.white.opacity(hasConflict ? 0.45 : 0.22), lineWidth: 1)
                        .frame(width: nodeDiameter, height: nodeDiameter)
                }
                .accessibilityHidden(true)

                connector(isLeading: false)
            }
            .frame(width: cardWidth, height: 24)

            Button(action: onSelect) {
                AutomationTimelineItemView(
                    item: item,
                    hasConflict: hasConflict,
                    isSelected: isSelected
                )
            }
            .buttonStyle(.plain)
            .frame(width: cardWidth)
            .accessibilityHint(String(localized: "Shows the task and run details in the inspector", table: "Automation"))
        }
        .frame(width: cardWidth + 16, alignment: .leading)
    }

    private var timelineTimeLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: item.startedAt == nil ? "clock" : "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.startedAt == nil ? .secondary : item.status.tint)

            Text(item.timelineStart.map(AutomationTimelineTimeFormatter.timeString) ?? "--:--:--")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    private var transitionLabel: String? {
        guard let previousItem else {
            return nil
        }

        if hasConflict {
            return String(localized: "Conflict", table: "Common")
        }

        guard let previousCompletedAt = previousItem.completedAt,
              let startedAt = item.timelineStart else {
            return nil
        }

        let wait = startedAt.timeIntervalSince(previousCompletedAt)
        guard wait >= 1 else {
            return nil
        }
        return "+" + AutomationTimelineTimeFormatter.compactDurationString(wait)
    }

    private func connector(isLeading: Bool) -> some View {
        Rectangle()
            .fill(connectorTint(isLeading: isLeading))
            .frame(width: (cardWidth - nodeDiameter) / 2, height: connectorHeight)
    }

    private func connectorTint(isLeading: Bool) -> Color {
        if isFirst && isLeading {
            return .clear
        }
        if isLast && !isLeading {
            return .clear
        }
        return hasConflict ? Brand.red500.opacity(0.55) : Color.secondary.opacity(0.24)
    }
}

extension AutomationResourceTimelineItem {
    var timelineStart: Date? {
        startedAt ?? earliestStartAt ?? scheduledAt ?? createdAt ?? completedAt
    }
}

enum AutomationTimelineTimeFormatter {
    static func timeString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    static func compactDurationString(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return String(format: "%d:%02d:%02d", hours, remainingMinutes, remainingSeconds)
    }
}
