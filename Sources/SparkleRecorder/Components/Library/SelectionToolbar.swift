import Cocoa
import SwiftUI
import SparkleRecorderCore

struct SelectionToolbar: View {
    let selectionCount: Int
    let onClearSelection: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onAddTag: () -> Void
    let onCreateSequence: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onClearSelection) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Clear selection", table: "Common"))
            Text(String(format: String(localized: "%d selected", table: "Common"), selectionCount))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(String(localized: "Create Sequence…", table: "Common"), systemImage: "arrow.right.circle", action: onCreateSequence)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(String(localized: "Add Tag…", table: "Common"), systemImage: "tag", action: onAddTag)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectionCount != 1)

            Button(String(localized: "Export", table: "Common"), systemImage: "square.and.arrow.up", action: onExport)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(String(localized: "Delete", table: "Common"), systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .confirmationDialog(
                String(format: String(localized: "Delete %d macros?", table: "EditorUX"), selectionCount),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete", table: "Common"), role: .destructive) { onDelete() }
                Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
            } message: {
                Text("This can't be undone.", tableName: "Common")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
	        .glassSurface(cornerRadius: 10, tint: Brand.sigBlue, interactive: false)
	    }
}
