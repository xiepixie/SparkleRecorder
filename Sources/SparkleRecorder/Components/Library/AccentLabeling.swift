import SwiftUI

/// Named accent options shown in the per-macro Color submenu.
let accentNames: [String] = [
    "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Indigo", "Purple", "Pink", "Gray",
]

/// Maps a stored accent name to the app's vibrant signal palette.
func cardAccentColor(for accent: String?) -> Color {
    Brand.accent(accent)
}

func normalizedAccentName(_ name: String?) -> String? {
    guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return accentNames.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
}

func accentDisplayName(_ name: String) -> String {
    switch normalizedAccentName(name) ?? name {
    case "Red": return NSLocalizedString("Red", comment: "")
    case "Orange": return NSLocalizedString("Orange", comment: "")
    case "Yellow": return NSLocalizedString("Yellow", comment: "")
    case "Green": return NSLocalizedString("Green", comment: "")
    case "Teal": return NSLocalizedString("Teal", comment: "")
    case "Blue": return NSLocalizedString("Blue", comment: "")
    case "Indigo": return NSLocalizedString("Indigo", comment: "")
    case "Purple": return NSLocalizedString("Purple", comment: "")
    case "Pink": return NSLocalizedString("Pink", comment: "")
    case "Gray": return NSLocalizedString("Gray", comment: "")
    default: return name
    }
}

func accentSortIndex(_ name: String) -> Int {
    guard let normalized = normalizedAccentName(name),
          let index = accentNames.firstIndex(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
        return Int.max
    }
    return index
}

struct AccentSwatch: View {
    let name: String?
    var size: CGFloat = 12
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(3, size * 0.28), style: .continuous)
        shape
            .fill(fill)
            .overlay(
                shape.strokeBorder(selected ? Color.white.opacity(0.72) : Color.primary.opacity(0.18), lineWidth: selected ? 1.2 : 0.6)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var fill: LinearGradient {
        if let name {
            let color = cardAccentColor(for: name)
            return LinearGradient(
                colors: [color.opacity(0.98), color.opacity(0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AccentBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            AccentSwatch(name: name, size: 8)
            Text(accentDisplayName(name))
                .font(.system(size: 8.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .frame(maxWidth: 76)
        .background(
            Capsule(style: .continuous)
                .fill(cardAccentColor(for: name).opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(cardAccentColor(for: name).opacity(0.22), lineWidth: 0.5)
                )
        )
        .accessibilityLabel(Text(String(format: NSLocalizedString("Color: %@", comment: ""), accentDisplayName(name))))
    }
}

struct AccentMenuLabel: View {
    let name: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let name {
                AccentSwatch(name: name, size: 12)
                Text(accentDisplayName(name))
            } else {
                Image(systemName: "circle.dashed")
                    .frame(width: 14)
                Text(NSLocalizedString("Default", comment: ""))
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}
