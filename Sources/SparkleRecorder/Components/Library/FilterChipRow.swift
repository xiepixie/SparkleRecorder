import Cocoa
import SwiftUI
import SparkleRecorderCore

struct FilterChipRow: View {
    @Binding var filter: LibraryFilter
    let tags: [String]

    private let primaryFilters: [LibraryFilter] = [.all, .favorites, .recent]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(primaryFilters, id: \.self) { item in
                    chip(item)
                }
                if !tags.isEmpty {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 14)
                    ForEach(tags, id: \.self) { t in
                        chip(.tag(t))
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // Filter chips are content-layer controls: plain capsules, with only the
    // selected one carrying the brand accent (a single emphasis, not glass).
    @ViewBuilder
    func chip(_ item: LibraryFilter) -> some View {
        let selected = filter == item
        Button {
            withAnimation(Brand.spring) { filter = item }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? AnyShapeStyle(Brand.libraryBlue) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(Brand.libraryBlue.opacity(0.12)) : AnyShapeStyle(Color.primary.opacity(0.06)))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(selected ? Brand.libraryBlue.opacity(0.2) : Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(HoverPressButtonStyle(hoverScale: 1.05))
        .accessibilityLabel(Text(String(format: NSLocalizedString("Filter: %@", comment: ""), item.label)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
