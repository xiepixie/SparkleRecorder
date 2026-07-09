import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LibrarySidebar: View {
    @Binding var filter: LibraryFilter
    @EnvironmentObject var library: MacroLibrary

    private let filterItems: [LibraryFilter] = [.all, .favorites, .recent, .mostPlayed, .withHotkey]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader(String(localized: "Library", table: "Common"))
                    ForEach(filterItems, id: \.self) { item in
                        sidebarRow(item)
                    }

                    if !library.allAccents.isEmpty {
                        sectionHeader(String(localized: "Colors", table: "Common"))
                            .padding(.top, 14)
                        ForEach(library.allAccents, id: \.self) { name in
                            sidebarRow(.accent(name))
                        }
                    }

                    if !library.allTags.isEmpty {
                        sectionHeader(String(localized: "Tags", table: "Common"))
                            .padding(.top, 14)
                        ForEach(library.allTags, id: \.self) { t in
                            sidebarRow(.tag(t))
                        }
                    }

	                    sectionHeader(String(localized: "Stats", table: "Common"))
	                        .padding(.top, 14)
	                    StatsSummary()
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
        }
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
    }

    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    func sidebarRow(_ item: LibraryFilter) -> some View {
        let selected = filter == item
        let count: Int = library.macros(for: item, search: "").count
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = item }
        } label: {
            HStack(spacing: 8) {
                sidebarIcon(for: item, selected: selected)
                Text(item.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                Spacer()
	                Text("\(count)")
	                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
	                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
	                    .padding(.horizontal, 5)
	                    .padding(.vertical, 1.5)
	                    .background(
	                        Capsule(style: .continuous)
	                            .fill(selected ? Color.white.opacity(0.14) : Color.primary.opacity(0.055))
	                    )
	            }
	            .padding(.horizontal, 8)
	            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
	                RoundedRectangle(cornerRadius: 8, style: .continuous)
	                    .fill(selected ? AnyShapeStyle(Brand.libraryBlue.opacity(0.13)) : AnyShapeStyle(Color.clear))
	            )
	        }
	        .buttonStyle(.plain)
    }

    @ViewBuilder
    func sidebarIcon(for item: LibraryFilter, selected: Bool) -> some View {
        if case .accent(let name) = item {
            AccentSwatch(name: name, size: 12, selected: selected)
                .frame(width: 16)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 16)
        }
    }
}
