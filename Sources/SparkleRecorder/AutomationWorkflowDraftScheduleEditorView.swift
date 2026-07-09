import Foundation
import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowDraftScheduleEditorView: View {
    let document: AutomationWorkflowDraftDocument
    let onApply: (AutomationWorkflowDraftScheduleEdit) -> Void

    @State private var selectedTaskKey = ""
    @State private var scheduleType = "manual"
    @State private var startAt = Date()
    @State private var every = 1
    @State private var unit = "days"
    @State private var timeZone = TimeZone.current.identifier

    private let scheduleTypes = ["manual", "once", "repeating"]
    private let units = ["minutes", "hours", "days", "weeks"]

    var body: some View {
        if !document.workflow.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: String(localized: "DRAFT SCHEDULE", table: "Common"),
                    count: scheduledTaskCount
                )

                HStack(spacing: 8) {
                    Picker(String(localized: "Task", table: "Automation"), selection: $selectedTaskKey) {
                        ForEach(document.workflow.tasks, id: \.key) { task in
                            Text(task.name ?? task.key).tag(task.key)
                        }
                    }
                    .frame(maxWidth: 220)
                    .onChange(of: selectedTaskKey) {
                        loadSelectedTask()
                    }

                    Picker(String(localized: "Schedule", table: "Common"), selection: $scheduleType) {
                        ForEach(scheduleTypes, id: \.self) { type in
                            Text(scheduleTitle(for: type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                if scheduleType != "manual" {
                    DatePicker(
                        String(localized: "Start", table: "Common"),
                        selection: $startAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }

                if scheduleType == "repeating" {
                    HStack(spacing: 8) {
                        Label(String(localized: "Every", table: "Common"), systemImage: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "Every", table: "Common"), value: $every, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Picker(String(localized: "Unit", table: "Common"), selection: $unit) {
                            ForEach(units, id: \.self) { unit in
                                Text(unitTitle(for: unit)).tag(unit)
                            }
                        }
                        .frame(width: 130)
                        TextField(String(localized: "Time zone", table: "Common"), text: $timeZone)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    Button(String(localized: "Apply Schedule", table: "Common"), systemImage: "calendar.badge.checkmark", action: applyEdit)
                        .buttonStyle(.bordered)
                        .disabled(selectedTaskKey.isEmpty)
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)
            .onAppear(perform: selectInitialTaskIfNeeded)
            .onChange(of: document) {
                selectInitialTaskIfNeeded()
            }
        }
    }

    private var selectedTask: AutomationWorkflowDraftTask? {
        document.workflow.tasks.first { $0.key == selectedTaskKey }
    }

    private var scheduledTaskCount: Int {
        document.workflow.tasks.filter { $0.schedule != nil }.count
    }

    private func selectInitialTaskIfNeeded() {
        if selectedTask == nil {
            selectedTaskKey = document.workflow.tasks.first?.key ?? ""
        }
        loadSelectedTask()
    }

    private func loadSelectedTask() {
        guard let selectedTask else {
            scheduleType = "manual"
            startAt = Date()
            every = 1
            unit = "days"
            timeZone = TimeZone.current.identifier
            return
        }

        guard let schedule = selectedTask.schedule else {
            scheduleType = "manual"
            return
        }

        scheduleType = schedule.type
        startAt = schedule.startAt ?? startAt
        every = max(1, schedule.every ?? every)
        unit = schedule.unit ?? unit
        timeZone = schedule.timeZone ?? timeZone
    }

    private func applyEdit() {
        guard let selectedTask else {
            return
        }

        let schedule: AutomationWorkflowDraftSchedule?
        switch scheduleType {
        case "once":
            schedule = AutomationWorkflowDraftSchedule(type: "once", startAt: startAt)
        case "repeating":
            schedule = AutomationWorkflowDraftSchedule(
                type: "repeating",
                startAt: startAt,
                every: max(1, every),
                unit: unit,
                timeZone: timeZone.trimmedForDraftScheduleEdit.nilIfEmptyForDraftScheduleEdit
            )
        default:
            schedule = nil
        }

        onApply(AutomationWorkflowDraftScheduleEdit(
            taskKey: selectedTask.key,
            schedule: schedule
        ))
    }

    private func scheduleTitle(for type: String) -> String {
        switch type {
        case "once":
            return String(localized: "Once", table: "Common")
        case "repeating":
            return String(localized: "Repeating", table: "Common")
        default:
            return String(localized: "Manual", table: "Common")
        }
    }

    private func unitTitle(for unit: String) -> String {
        switch unit {
        case "minutes":
            return String(localized: "Minutes", table: "Common")
        case "hours":
            return String(localized: "Hours", table: "Common")
        case "weeks":
            return String(localized: "Weeks", table: "Common")
        default:
            return String(localized: "Days", table: "Common")
        }
    }
}

private extension String {
    var trimmedForDraftScheduleEdit: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftScheduleEdit: String? {
        isEmpty ? nil : self
    }
}
