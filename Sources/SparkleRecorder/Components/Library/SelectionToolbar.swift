import Cocoa
import SwiftUI
import SparkleRecorderCore

struct SelectionToolbar: View {
    let selectionCount: Int
    let onClearSelection: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onAddTag: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onClearSelection) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Clear selection", comment: ""))
            Text(String(format: NSLocalizedString("%d selected", comment: ""), selectionCount))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(NSLocalizedString("Add Tag…", comment: ""), systemImage: "tag", action: onAddTag)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectionCount != 1)

            Button(NSLocalizedString("Export", comment: ""), systemImage: "square.and.arrow.up", action: onExport)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(NSLocalizedString("Delete", comment: ""), systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .confirmationDialog(
                String(format: NSLocalizedString("Delete %d macros?", comment: ""), selectionCount),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) { onDelete() }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("This can't be undone.", comment: ""))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
	        .glassSurface(cornerRadius: 10, tint: Brand.sigBlue, interactive: false)
	    }
}
