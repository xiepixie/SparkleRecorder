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
    case manual
    case once
    case repeating

    var id: Self { self }

    var title: String {
        switch self {
        case .manual:
            return String(localized: "Off", table: "Common")
        case .once:
            return String(localized: "Once", table: "Common")
        case .repeating:
            return String(localized: "Repeat", table: "Common")
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
            return String(localized: "Minutes", table: "Common")
        case .hours:
            return String(localized: "Hours", table: "Common")
        case .days:
            return String(localized: "Days", table: "Common")
        case .weeks:
            return String(localized: "Weeks", table: "Common")
        }
    }

    func detailTitle(count: Int) -> String {
        switch self {
        case .minutes:
            return count == 1
                ? String(localized: "minute", table: "Common")
                : String(localized: "minutes", table: "Common")
        case .hours:
            return count == 1
                ? String(localized: "hour", table: "Common")
                : String(localized: "hours", table: "Common")
        case .days:
            return count == 1
                ? String(localized: "day", table: "Common")
                : String(localized: "days", table: "Common")
        case .weeks:
            return count == 1
                ? String(localized: "week", table: "Common")
                : String(localized: "weeks", table: "Common")
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
    let isTaskEnabled: Bool
    let hasBoundTargetApplication: Bool
    let targetApplicationPolicy: AutomationTargetApplicationPolicy
    let onApplySchedule: ((AutomationTimelineScheduleEdit) -> Void)?
    let onSetTaskEnabled: ((Bool) -> Void)?
    let onSetTargetApplicationPolicy: ((AutomationTargetApplicationPolicy) -> Void)?

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

            HStack(spacing: 10) {
                Toggle(isOn: taskEnabledBinding) {
                    Text("Task enabled", tableName: "Automation")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()

                if hasBoundTargetApplication {
                    Picker(
                        String(localized: "Target application", table: "Automation"),
                        selection: targetApplicationPolicyBinding
                    ) {
                        ForEach(AutomationTargetApplicationPolicy.allCases, id: \.self) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 142)
                }

                Label(
                    String(localized: "Runs while SparkleRecorder is open", table: "Automation"),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.leading, 30)
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
        Picker(String(localized: "Schedule", table: "Common"), selection: $scheduleMode) {
            ForEach(AutomationTimelineScheduleMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 184)
        .controlSize(.small)
    }

    @ViewBuilder
    private var datePicker: some View {
        if scheduleMode != .manual {
            DatePicker(
                String(localized: "Start", table: "Common"),
                selection: $selectedDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var repeatControls: some View {
        if scheduleMode == .repeating {
            HStack(spacing: 6) {
                Text("Every", tableName: "Common")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(String(localized: "Count", table: "Common"), value: $repeatEveryDraft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospacedDigit())
                    .frame(width: 48)

                Picker(String(localized: "Unit", table: "Common"), selection: $repeatUnitDraft) {
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
                Text("Next", tableName: "Common")
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
        if scheduleMode == .manual {
            return String(localized: "Manual start only", table: "Common")
        }
        if scheduleMode == .repeating {
            return String(localized: "Repeating start", table: "Common")
        }
        return date == nil
            ? String(localized: "Workflow start", table: "Automation")
            : String(localized: "Next start", table: "Common")
    }

    private var titleIcon: String {
        if scheduleMode == .manual {
            return "hand.tap"
        }
        if scheduleMode == .repeating {
            return "calendar.badge.clock"
        }
        return date == nil ? "calendar.badge.plus" : "calendar.badge.clock"
    }

    private var scheduleDetail: String {
        if scheduleMode == .manual {
            return taskName?.isEmpty == false
                ? taskName!
                : String(localized: "Workflow", table: "Automation")
        }
        let time = selectedDate.formatted(date: .abbreviated, time: .shortened)
        let subject = taskName?.isEmpty == false ? taskName! : String(localized: "Workflow", table: "Automation")
        if scheduleMode == .repeating {
            let format = String(localized: "%@ · %@ · Every %d %@", table: "Common")
            let count = max(1, repeatEveryDraft)
            return String(format: format, subject, time, count, repeatUnitDraft.detailTitle(count: count))
        }
        return "\(subject) · \(time)"
    }

    private var repeatPreviewDates: [Date] {
        AutomationSchedule.repeating(AutomationRepeatRule(
            anchor: selectedDate,
            interval: repeatUnitDraft.interval(count: repeatEveryDraft)
        ))
        .previewOccurrences(startingAt: selectedDate)
        .map(\.scheduledAt)
    }

    private func repeatPreviewTitle(for date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    private var applyTitle: String {
        schedule == nil || schedule == .manual
            ? String(localized: "Schedule", table: "Common")
            : String(localized: "Apply", table: "Common")
    }

    private var taskEnabledBinding: Binding<Bool> {
        Binding(
            get: { isTaskEnabled },
            set: { onSetTaskEnabled?($0) }
        )
    }

    private var targetApplicationPolicyBinding: Binding<AutomationTargetApplicationPolicy> {
        Binding(
            get: { targetApplicationPolicy },
            set: { onSetTargetApplicationPolicy?($0) }
        )
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
            scheduleMode = .manual
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
