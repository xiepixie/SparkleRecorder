import SwiftUI
import SparkleRecorderCore

struct AutomationTimelineScheduleEdit: Equatable {
    var mode: AutomationTimelineScheduleMode
    var startAt: Date
    var repeatEvery: Int
    var repeatUnit: AutomationTimelineRepeatUnit

    var repeatInterval: AutomationRepeatInterval {
        repeatUnit.interval(count: max(1, repeatEvery))
    }
}

enum AutomationTimelineScheduleMode: String, CaseIterable, Identifiable {
    case once
    case repeating

    var id: Self { self }

    var title: String {
        switch self {
        case .once:
            return NSLocalizedString("Once", comment: "")
        case .repeating:
            return NSLocalizedString("Repeat", comment: "")
        }
    }
}

enum AutomationTimelineRepeatUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days
    case weeks

    var id: Self { self }

    var title: String {
        switch self {
        case .minutes:
            return NSLocalizedString("Minutes", comment: "")
        case .hours:
            return NSLocalizedString("Hours", comment: "")
        case .days:
            return NSLocalizedString("Days", comment: "")
        case .weeks:
            return NSLocalizedString("Weeks", comment: "")
        }
    }

    func detailTitle(count: Int) -> String {
        switch self {
        case .minutes:
            return count == 1
                ? NSLocalizedString("minute", comment: "")
                : NSLocalizedString("minutes", comment: "")
        case .hours:
            return count == 1
                ? NSLocalizedString("hour", comment: "")
                : NSLocalizedString("hours", comment: "")
        case .days:
            return count == 1
                ? NSLocalizedString("day", comment: "")
                : NSLocalizedString("days", comment: "")
        case .weeks:
            return count == 1
                ? NSLocalizedString("week", comment: "")
                : NSLocalizedString("weeks", comment: "")
        }
    }

    func interval(count: Int) -> AutomationRepeatInterval {
        let safeCount = max(1, count)
        switch self {
        case .minutes:
            return .minutes(safeCount)
        case .hours:
            return .hours(safeCount)
        case .days:
            return .days(safeCount)
        case .weeks:
            return .weeks(safeCount)
        }
    }

    static func draft(for interval: AutomationRepeatInterval) -> (count: Int, unit: AutomationTimelineRepeatUnit) {
        switch interval {
        case .minutes(let count):
            return (count, .minutes)
        case .hours(let count):
            return (count, .hours)
        case .days(let count):
            return (count, .days)
        case .weeks(let count):
            return (count, .weeks)
        }
    }
}

struct AutomationTimelineSchedulePreview: View {
    let date: Date?
    let schedule: AutomationSchedule?
    let taskName: String?
    let onApplySchedule: ((AutomationTimelineScheduleEdit) -> Void)?

    @State private var selectedDate = Date().addingTimeInterval(3600)
    @State private var scheduleMode: AutomationTimelineScheduleMode = .once
    @State private var repeatEveryDraft = 1
    @State private var repeatUnitDraft: AutomationTimelineRepeatUnit = .hours

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                titleBlock

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        modePicker
                        datePicker
                        repeatControls
                        applyButton
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            modePicker
                            datePicker
                            applyButton
                        }
                        repeatControls
                    }
                }
            }

            repeatPreviewRow
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
        .accessibilityElement(children: .contain)
        .onAppear(perform: syncDraft)
        .onChange(of: date) {
            syncDraft()
        }
        .onChange(of: schedule) {
            syncDraft()
        }
    }

    private var titleBlock: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(scheduleDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: titleIcon)
                .foregroundStyle(Brand.sigAmber)
        }
        .frame(minWidth: 154, maxWidth: 206, alignment: .leading)
    }

    private var modePicker: some View {
        Picker(NSLocalizedString("Schedule", comment: ""), selection: $scheduleMode) {
            ForEach(AutomationTimelineScheduleMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 132)
        .controlSize(.small)
    }

    private var datePicker: some View {
        DatePicker(
            NSLocalizedString("Start", comment: ""),
            selection: $selectedDate,
            displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .controlSize(.small)
    }

    @ViewBuilder
    private var repeatControls: some View {
        if scheduleMode == .repeating {
            HStack(spacing: 6) {
                Text(NSLocalizedString("Every", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(NSLocalizedString("Count", comment: ""), value: $repeatEveryDraft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospacedDigit())
                    .frame(width: 48)

                Picker(NSLocalizedString("Unit", comment: ""), selection: $repeatUnitDraft) {
                    ForEach(AutomationTimelineRepeatUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)
                .controlSize(.small)
            }
            .fixedSize(horizontal: true, vertical: false)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    @ViewBuilder
    private var repeatPreviewRow: some View {
        if scheduleMode == .repeating {
            HStack(spacing: 6) {
                Text(NSLocalizedString("Next", comment: ""))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(repeatPreviewDates, id: \.self) { date in
                    Text(repeatPreviewTitle(for: date))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.055))
                        )
                }
            }
            .padding(.leading, 30)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var applyButton: some View {
        Button(action: applySchedule) {
            Label(applyTitle, systemImage: "checkmark")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(onApplySchedule == nil)
    }

    private var title: String {
        if scheduleMode == .repeating {
            return NSLocalizedString("Repeating start", comment: "")
        }
        return date == nil
            ? NSLocalizedString("Workflow start", comment: "")
            : NSLocalizedString("Next start", comment: "")
    }

    private var titleIcon: String {
        if scheduleMode == .repeating {
            return "calendar.badge.clock"
        }
        return date == nil ? "calendar.badge.plus" : "calendar.badge.clock"
    }

    private var scheduleDetail: String {
        let time = selectedDate.formatted(date: .abbreviated, time: .shortened)
        let subject = taskName?.isEmpty == false ? taskName! : NSLocalizedString("Workflow", comment: "")
        if scheduleMode == .repeating {
            let format = NSLocalizedString("%@ · %@ · Every %d %@", comment: "")
            let count = max(1, repeatEveryDraft)
            return String(format: format, subject, time, count, repeatUnitDraft.detailTitle(count: count))
        }
        return "\(subject) · \(time)"
    }

    private var repeatPreviewDates: [Date] {
        let step = repeatUnitDraft.interval(count: max(1, repeatEveryDraft)).timeInterval
        guard step > 0 else {
            return []
        }
        return (0..<3).map { index in
            selectedDate.addingTimeInterval(Double(index) * step)
        }
    }

    private func repeatPreviewTitle(for date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    private var applyTitle: String {
        schedule == nil || schedule == .manual
            ? NSLocalizedString("Schedule", comment: "")
            : NSLocalizedString("Apply", comment: "")
    }

    private func syncDraft() {
        selectedDate = date ?? schedule?.initialScheduledStart ?? Date().addingTimeInterval(3600)
        switch schedule {
        case .repeating(let rule):
            scheduleMode = .repeating
            let draft = AutomationTimelineRepeatUnit.draft(for: rule.interval)
            repeatEveryDraft = max(1, draft.count)
            repeatUnitDraft = draft.unit
        case .once:
            scheduleMode = .once
        case .manual, nil:
            scheduleMode = .once
            repeatEveryDraft = 1
            repeatUnitDraft = .hours
        }
    }

    private func applySchedule() {
        onApplySchedule?(
            AutomationTimelineScheduleEdit(
                mode: scheduleMode,
                startAt: selectedDate,
                repeatEvery: repeatEveryDraft,
                repeatUnit: repeatUnitDraft
            )
        )
    }
}
