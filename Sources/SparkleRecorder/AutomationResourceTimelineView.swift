import SwiftUI
import SparkleRecorderCore

struct AutomationResourceTimelineView: View {
    let items: [AutomationResourceTimelineItem]
    let nextScheduledOccurrence: Date?
    let nextScheduledTaskName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: NSLocalizedString("RESOURCES", comment: ""),
                count: items.count
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    AutomationTimelineSchedulePreview(
                        date: nextScheduledOccurrence,
                        taskName: nextScheduledTaskName
                    )

                    if items.isEmpty {
                        AutomationEmptyState(
                            systemImage: "clock.badge.questionmark",
                            title: NSLocalizedString("No resource activity", comment: ""),
                            subtitle: NSLocalizedString("Runs will appear here when scheduler or manual starts create task history.", comment: "")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(items) { item in
                            AutomationTimelineItemView(item: item)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }
}
