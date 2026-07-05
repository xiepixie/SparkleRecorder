import SwiftUI
import SparkleRecorderCore

struct AutomationResourceTimelineView: View {
    let items: [AutomationResourceTimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: NSLocalizedString("RESOURCES", comment: ""),
                count: items.count
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                if items.isEmpty {
                    AutomationEmptyState(
                        systemImage: "clock.badge.questionmark",
                        title: NSLocalizedString("No resource activity", comment: ""),
                        subtitle: NSLocalizedString("Runs will appear here when scheduler or manual starts create task history.", comment: "")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 8) {
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
