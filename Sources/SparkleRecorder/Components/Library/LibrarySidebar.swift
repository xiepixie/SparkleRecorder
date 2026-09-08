import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LibrarySidebar: View {
    @Binding var filter: LibraryFilter
    @EnvironmentObject var library: MacroLibrary

    private let filterItems: [LibraryFilter] = [.all, .favorites, .recent, .mostPlayed, .withHotkey]

    var body: some View {
        let projection = LibrarySidebarProjection(macros: library.macros)

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader(String(localized: "Library", table: "Common"))
                    ForEach(filterItems, id: \.self) { item in
                        sidebarRow(item, count: projection.count(for: item))
                    }

                    if !projection.accents.isEmpty {
                        sectionHeader(String(localized: "Colors", table: "Common"))
                            .padding(.top, 14)
                        ForEach(projection.accents, id: \.self) { name in
                            sidebarRow(.accent(name), count: projection.count(for: .accent(name)))
                        }
                    }

                    if !projection.tags.isEmpty {
                        sectionHeader(String(localized: "Tags", table: "Common"))
                            .padding(.top, 14)
                        ForEach(projection.tags, id: \.self) { tag in
                            sidebarRow(.tag(tag), count: projection.count(for: .tag(tag)))
                        }
                    }

	                    sectionHeader(String(localized: "Stats", table: "Common"))
	                        .padding(.top, 14)
	                    StatsSummary(
                            totalMacros: projection.totalMacros,
                            totalPlays: projection.totalPlays,
                            totalSaved: projection.totalSaved
                        )
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
        }
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow))
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
    func sidebarRow(_ item: LibraryFilter, count: Int) -> some View {
        let selected = filter == item
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

struct LibrarySidebarProjection {
    var counts: [LibraryFilter: Int]
    var tags: [String]
    var accents: [String]
    var totalMacros: Int
    var totalPlays: Int
    var totalSaved: TimeInterval

    init(macros: [SavedMacro], now: Date = Date()) {
        let recentCutoff = now.addingTimeInterval(-86_400 * 7)
        var counts: [LibraryFilter: Int] = [.all: macros.count]
        var tagNames = Set<String>()
        var accentNamesInUse = Set<String>()
        var totalPlays = 0
        var totalSaved: TimeInterval = 0

        for macro in macros {
            if macro.favorite {
                counts[.favorites, default: 0] += 1
            }
            if (macro.lastPlayedAt ?? macro.modifiedAt) >= recentCutoff {
                counts[.recent, default: 0] += 1
            }
            if macro.playCount > 0 {
                counts[.mostPlayed, default: 0] += 1
            }
            if macro.hotkey != nil {
                counts[.withHotkey, default: 0] += 1
            }

            for tag in Set(macro.tags) {
                tagNames.insert(tag)
                counts[.tag(tag), default: 0] += 1
            }
            if let accent = normalizedAccentName(macro.accent) {
                accentNamesInUse.insert(accent)
                counts[.accent(accent), default: 0] += 1
            }

            totalPlays += macro.playCount
            totalSaved += macro.totalRunTime
        }

        self.counts = counts
        self.tags = tagNames.sorted()
        self.accents = accentNamesInUse.sorted {
            let left = accentSortIndex($0)
            let right = accentSortIndex($1)
            if left != right { return left < right }
            return accentDisplayName($0).localizedCaseInsensitiveCompare(accentDisplayName($1)) == .orderedAscending
        }
        self.totalMacros = macros.count
        self.totalPlays = totalPlays
        self.totalSaved = totalSaved
    }

    func count(for filter: LibraryFilter) -> Int {
        counts[filter, default: 0]
    }
}
