import SwiftUI

struct EditorToolbarToggle: View {
    @Binding var isOn: Bool
    let title: String
    let help: String
    let icon: String
    var tint: Color = Brand.libraryBlue

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation) {
                    isOn.toggle()
                }
            } label: {
                Label(title, systemImage: icon)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(hovered ? Color.primary : Color.secondary))
                    .lineLimit(1)
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Info popover button
            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? Color.white.opacity(0.8) : Color.secondary.opacity(0.5))
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfo) {
                Text(help)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: 220)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? tint.opacity(0.8) : (hovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
        .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: isOn)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
