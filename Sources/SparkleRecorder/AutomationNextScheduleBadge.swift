import SwiftUI

struct AutomationNextScheduleBadge: View {
    let date: Date?
    let title: String
    var detail: String?
    var isCompact = false

    var body: some View {
        if let date {
            Label {
                HStack(spacing: 4) {
                    Text(title)
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    if let detail, !detail.isEmpty, !isCompact {
                        Text("·")
                        Text(detail)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } icon: {
                Image(systemName: "calendar.badge.clock")
            }
            .font(isCompact ? .caption2 : .caption)
            .foregroundStyle(Brand.sigAmber)
            .lineLimit(1)
            .padding(.horizontal, isCompact ? 0 : 7)
            .padding(.vertical, isCompact ? 0 : 3)
            .background {
                if !isCompact {
                    Capsule()
                        .fill(Brand.sigAmber.opacity(0.08))
                        .overlay(
                            Capsule()
                                .strokeBorder(Brand.sigAmber.opacity(0.22), lineWidth: 0.6)
                        )
                }
            }
            .help(accessibilityText(for: date))
            .accessibilityLabel(accessibilityText(for: date))
        }
    }

    private func accessibilityText(for date: Date) -> String {
        var parts = [
            title,
            date.formatted(date: .abbreviated, time: .shortened)
        ]
        if let detail, !detail.isEmpty, !isCompact {
            parts.append(detail)
        }
        return parts.joined(separator: ", ")
    }
}
