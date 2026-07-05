import SwiftUI

struct EditorExportButton: View {
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Label(NSLocalizedString("Export", comment: ""), systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
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
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfo) {
                Text(NSLocalizedString("Exports a double-clickable .command script", comment: ""))
                    .font(.system(size: 11))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: 220)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Brand.libraryBlue.opacity(hovered ? 0.9 : 0.8))
        )
        .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
        .onHover { hovered = $0 }
        .accessibilityLabel(NSLocalizedString("Export", comment: ""))
    }
}
