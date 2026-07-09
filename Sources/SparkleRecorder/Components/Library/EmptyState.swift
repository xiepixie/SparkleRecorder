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
        if hasSearch { return NSLocalizedString("No matches", comment: "") }
        switch filter {
        case .favorites:  return NSLocalizedString("No favorites yet", comment: "")
        case .recent:     return NSLocalizedString("Nothing recent", comment: "")
        case .mostPlayed: return NSLocalizedString("No playback history", comment: "")
        case .withHotkey: return NSLocalizedString("No macros with hotkeys", comment: "")
        case .tag(let t): return String(format: NSLocalizedString("No macros tagged %@", comment: ""), t)
        case .accent(let name): return String(format: NSLocalizedString("No %@ macros", comment: ""), accentDisplayName(name))
        case .all:        return NSLocalizedString("No macros yet", comment: "")
        }
    }

    private var subtitle: String {
        if hasSearch { return NSLocalizedString("Try a different search term.", comment: "") }
        switch filter {
        case .favorites: return NSLocalizedString("Tap the ★ on any card to favorite it.", comment: "")
        case .all:       return NSLocalizedString("Record a repeatable task, then review or combine it in a workflow.", comment: "")
        default:         return NSLocalizedString("Try the All filter.", comment: "")
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
