import Foundation
import SwiftUI
import SparkleRecorderCore

struct AutomationSequentialBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialMacros: [SavedMacro]
    let onCreate: (AutomationWorkflowDraftDocument) -> Void
    
    @State private var sequence: [SavedMacro] = []
    @State private var workflowName: String = ""
    
    @State private var scheduleType = "manual"
    @State private var startAt = Date()
    @State private var every = 1
    @State private var unit = "days"
    
    private let scheduleTypes = ["manual", "once", "repeating"]
    private let units = ["minutes", "hours", "days", "weeks"]
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sequenceList
                Divider()
                schedulePanel
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 450)
        .onAppear {
            sequence = initialMacros
            if let first = initialMacros.first {
                workflowName = String(localized: "Sequence: ", table: "Common") + first.name
            } else {
                workflowName = String(localized: "New Sequence", table: "Common")
            }
        }
    }
    
    private var header: some View {
        HStack {
            Text("Create Scheduled Sequence", tableName: "Common")
                .font(.headline)
            Spacer()
            TextField(String(localized: "Workflow Name", table: "Common"), text: $workflowName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var sequenceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXECUTION SEQUENCE", tableName: "Common")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            List {
                ForEach(Array(sequence.enumerated()), id: \.element.id) { index, macro in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                            .imageScale(.small)
                            .padding(.trailing, 4)
                        
                        Text("\(index + 1).")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        Text(macro.name)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .onMove { indices, newOffset in
                    sequence.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 350)
    }
    
    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SCHEDULE & TRIGGER", tableName: "Common")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            Picker(String(localized: "Type", table: "Common"), selection: $scheduleType) {
                ForEach(scheduleTypes, id: \.self) { type in
                    Text(LocalizedStringKey(type.capitalized), tableName: "Common").tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if scheduleType != "manual" {
                DatePicker(String(localized: "Start Date & Time", table: "Common"), selection: $startAt)
                    .datePickerStyle(.compact)
                
                if scheduleType == "repeating" {
                    HStack {
                        Text("Repeat every", tableName: "Common")
                        TextField("", value: $every, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Picker("", selection: $unit) {
                            ForEach(units, id: \.self) { u in
                                Text(LocalizedStringKey(u), tableName: "Common").tag(u)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }
                
                Text("The schedule will be attached to the first task in the sequence.", tableName: "Common")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                Text("This workflow will only run when manually started.", tableName: "Common")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 350)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var footer: some View {
        HStack {
            Button(String(localized: "Cancel", table: "Common")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button(String(localized: "Create & Activate", table: "Common")) {
                generateAndCreate()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(sequence.isEmpty)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func generateAndCreate() {
        var draft = AutomationWorkflowDraft(
            name: workflowName.isEmpty ? String(localized: "New Sequence", table: "Common") : workflowName
        )
        
        var previousTaskKey: String? = nil
        
        for (index, macro) in sequence.enumerated() {
            let taskKey = "task_\(UUID().uuidString.prefix(8).lowercased())"
            
            var task = AutomationWorkflowDraftTask(
                key: taskKey,
                type: "macro",
                name: macro.name,
                macroRef: AutomationWorkflowDraftMacroRef(id: macro.id),
                graphPosition: AutomationGraphPoint(x: Double(index * 250), y: 0)
            )
            
            // Attach schedule to the first task
            if index == 0 && scheduleType != "manual" {
                task.schedule = AutomationWorkflowDraftSchedule(
                    type: scheduleType,
                    startAt: startAt,
                    every: scheduleType == "repeating" ? every : nil,
                    unit: scheduleType == "repeating" ? unit : nil,
                    timeZone: TimeZone.current.identifier
                )
            }
            
            draft.tasks.append(task)
            
            // Link to the previous task
            if let prev = previousTaskKey {
                let dep = AutomationWorkflowDraftDependency(
                    from: prev,
                    to: taskKey,
                    trigger: "success"
                )
                draft.dependencies.append(dep)
            }
            
            previousTaskKey = taskKey
        }
        
        let doc = AutomationWorkflowDraftDocument(workflow: draft)
        onCreate(doc)
        dismiss()
    }
}
