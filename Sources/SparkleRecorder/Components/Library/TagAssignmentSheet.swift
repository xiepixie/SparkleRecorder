import Cocoa
import SwiftUI
import SparkleRecorderCore

struct TagAssignmentSheet: View {
    let macro: SavedMacro
    let allTags: [String]
    @Binding var tagText: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tags", tableName: "Common").font(.system(size: 14, weight: .semibold))
                Text(String(format: String(localized: "Tag %@ to organize your library.", table: "Automation"), macro.name))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField(String(localized: "New tag", table: "Common"), text: $tagText, onCommit: {
                    onAdd(tagText)
                })
                .textFieldStyle(.roundedBorder)
                Button(String(localized: "Add", table: "Common")) { onAdd(tagText) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !macro.tags.isEmpty {
                Text("Current", tableName: "Common").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                FlowChips(items: macro.tags, onRemove: onRemove)
            }
            if !allTags.isEmpty {
                Text("Suggestions", tableName: "Common").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 2)
                FlowChips(items: allTags.filter { !macro.tags.contains($0) }, onRemove: nil, onAdd: onAdd)
            }

            HStack {
                Spacer()
                Button(String(localized: "Done", table: "Common"), action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
