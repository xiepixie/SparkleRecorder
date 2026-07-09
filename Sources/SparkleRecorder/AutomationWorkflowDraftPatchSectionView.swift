import SwiftUI

struct AutomationWorkflowDraftPatchSectionView: View {
    let changedTaskKeys: [String]
    let changedDependencyKeys: [String]
    let message: String
    let onApplyPatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: String(localized: "DRAFT PATCH", table: "Common"),
                count: changedTaskKeys.count + changedDependencyKeys.count
            )

            HStack(spacing: 8) {
                Label(String(localized: "Patch", table: "Common"), systemImage: "doc.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button(String(localized: "Apply Patch…", table: "Common"), systemImage: "square.and.arrow.down", action: onApplyPatch)
                    .buttonStyle(.bordered)
                    .help(String(localized: "Apply workflow draft patch", table: "Automation"))
            }

            if !changedTaskKeys.isEmpty || !changedDependencyKeys.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    changedKeysGroup(
                        title: String(localized: "Tasks", table: "Automation"),
                        keys: changedTaskKeys
                    )
                    changedKeysGroup(
                        title: String(localized: "Dependencies", table: "Common"),
                        keys: changedDependencyKeys
                    )
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private func changedKeysGroup(title: String, keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .bold()
                .foregroundStyle(.secondary)
            if keys.isEmpty {
                Text("No changes", tableName: "Common")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(keys.prefix(4), id: \.self) { key in
                    Text(key)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if keys.count > 4 {
                    Text(String(format: String(localized: "+%d more", table: "Common"), keys.count - 4))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                )
        )
    }
}
