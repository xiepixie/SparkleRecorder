import SwiftUI

/// Shared instruction surface for full-screen point pickers.
/// Feature-specific adapters provide concise task copy while this view owns layout.
struct PickerInstructionView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    init(
        title: String = String(localized: "Double-click anywhere to pick coordinate", table: "EditorUX"),
        subtitle: String = String(localized: "Press ESC to cancel", table: "Common"),
        systemImage: String = "scope"
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                }
        )
        .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
    }
}
