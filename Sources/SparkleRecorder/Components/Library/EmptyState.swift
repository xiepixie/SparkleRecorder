import Cocoa
import SwiftUI
import SparkleRecorderCore

struct EmptyState: View {
    let filter: LibraryFilter
    let hasSearch: Bool
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 88, height: 88)
                Image(systemName: emptyIcon)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                    .scaleEffect(bounce ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.55), value: bounce)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(40)
        .onAppear { bounce = true }
    }

    private var title: String {
        if hasSearch { return String(localized: "No matches", table: "Common") }
        switch filter {
        case .favorites:  return String(localized: "No favorites yet", table: "Common")
        case .recent:     return String(localized: "Nothing recent", table: "Common")
        case .mostPlayed: return String(localized: "No playback history", table: "Common")
        case .withHotkey: return String(localized: "No macros with hotkeys", table: "EditorUX")
        case .tag(let t): return String(format: String(localized: "No macros tagged %@", table: "EditorUX"), t)
        case .accent(let name): return String(format: String(localized: "No %@ macros", table: "EditorUX"), accentDisplayName(name))
        case .all:        return String(localized: "No macros yet", table: "EditorUX")
        }
    }

    private var subtitle: String {
        if hasSearch { return String(localized: "Try a different search term.", table: "Automation") }
        switch filter {
        case .favorites: return String(localized: "Tap the ★ on any card to favorite it.", table: "Automation")
        case .all:       return String(localized: "Record a repeatable task, then review or combine it in a workflow.", table: "Automation")
        default:         return String(localized: "Try the All filter.", table: "Common")
        }
    }

    private var emptyIcon: String {
        if hasSearch { return "magnifyingglass" }
        switch filter {
        case .favorites: return "star"
        case .accent: return "circle.hexagongrid"
        default: return "tray"
        }
    }
}
