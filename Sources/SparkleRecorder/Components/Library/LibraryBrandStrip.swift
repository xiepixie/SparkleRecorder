import SwiftUI

struct LibraryBrandStrip: View {
    let statusText: String
    let isRecording: Bool
    let onSettings: () -> Void

    @State private var settingsHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
                .shadow(color: Brand.libraryBlue.opacity(0.16), radius: 7, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Wordmark(size: 14)
                HStack(spacing: 6) {
                    if isRecording {
                        RecDot(size: 6)
                    }
                    Text(statusText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button("Settings", systemImage: "gearshape.fill", action: onSettings)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(settingsHovered ? AnyShapeStyle(Brand.libraryBlue) : AnyShapeStyle(Color.secondary))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .libraryControlSurface(cornerRadius: 10, tint: Brand.libraryBlue, isActive: settingsHovered)
                .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: settingsHovered)
                .onHover { settingsHovered = $0 }
                .accessibilityLabel(NSLocalizedString("Settings", comment: ""))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape
                .fill(.thinMaterial)
                .overlay(
                    shape.fill(LinearGradient(
                        colors: [
                            Brand.libraryBlue.opacity(0.13),
                            Brand.sigTeal.opacity(0.045),
                            Brand.red500.opacity(0.035),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [
                        Color.white.opacity(0.20),
                        Brand.libraryBlue.opacity(0.22),
                        Color.primary.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 0.6)
        }
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.libraryBlue.opacity(0.72), Brand.sigTeal.opacity(0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 128, height: 1)
                .padding(.leading, 12)
                .padding(.top, 1)
        }
    }
}
