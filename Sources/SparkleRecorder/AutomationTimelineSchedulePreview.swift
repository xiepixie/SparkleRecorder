import SwiftUI

struct AutomationTimelineSchedulePreview: View {
    let date: Date?
    let taskName: String?
    let onApplySchedule: ((Date) -> Void)?
    
    @State private var isPopoverPresented = false
    @State private var selectedDate = Date()

    var body: some View {
        if let date {
            Button(action: {
                selectedDate = date
                isPopoverPresented = true
            }) {
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
                    
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Brand.sigAmber.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Brand.sigAmber.opacity(0.16), lineWidth: 0.6)
                    )
            )
            .accessibilityElement(children: .combine)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                VStack(spacing: 16) {
                    DatePicker(
                        NSLocalizedString("Reschedule To", comment: ""),
                        selection: $selectedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    
                    Button(NSLocalizedString("Apply", comment: "")) {
                        onApplySchedule?(selectedDate)
                        isPopoverPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()
                .frame(minWidth: 260)
            }
        }
    }
}
