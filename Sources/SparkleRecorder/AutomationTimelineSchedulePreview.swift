import SwiftUI

struct AutomationTimelineSchedulePreview: View {
    let date: Date?
    let taskName: String?

    var body: some View {
        if let date {
            HStack(spacing: 8) {
                AutomationNextScheduleBadge(
                    date: date,
                    title: NSLocalizedString("Next", comment: ""),
                    detail: taskName
                )

                Spacer(minLength: 0)

                Text(NSLocalizedString("Scheduled", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Brand.sigAmber.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Brand.sigAmber.opacity(0.16), lineWidth: 0.6)
                    )
            )
            .accessibilityElement(children: .combine)
        }
    }
}
