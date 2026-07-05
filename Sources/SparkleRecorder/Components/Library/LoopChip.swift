import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LoopChip: View {
    let loops: Int
    let onChange: (Int) -> Void
    @State private var showCustom = false
    @State private var customText = ""
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            Section(NSLocalizedString("Repeat", comment: "")) {
                Button(NSLocalizedString("Once", comment: "")) { onChange(1) }
                Button("2×")           { onChange(2) }
                Button("5×")           { onChange(5) }
                Button("10×")          { onChange(10) }
                Button("25×")          { onChange(25) }
                Button("100×")         { onChange(100) }
            }
            Divider()
            Button { onChange(0) } label: { Label(NSLocalizedString("Continuous", comment: ""), systemImage: "infinity") }
            Divider()
            Button(NSLocalizedString("Custom…", comment: "")) {
                customText = loops > 0 ? "\(loops)" : ""
                showCustom = true
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: loops <= 0 ? "infinity" : "repeat")
                    .font(.system(size: 8, weight: .black))
                Text(loops <= 0 ? "∞" : "\(loops)×")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(hovered ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary))
            .frame(width: 68, height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 68, height: 22)
        .libraryControlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: hovered, activeFillOpacity: 0.72)
        .help(loops <= 0 ? NSLocalizedString("Repeats continuously", comment: "") : (loops == 1 ? NSLocalizedString("Plays once", comment: "") : String(format: NSLocalizedString("Repeats %d times", comment: ""), loops)))
        .accessibilityLabel(loops <= 0 ? NSLocalizedString("Repeat: continuous", comment: "") : String(format: NSLocalizedString("Repeat: %d times", comment: ""), loops))
        .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
        .onHover { hovered = $0 }
        .alert(NSLocalizedString("Custom repeat count", comment: ""), isPresented: $showCustom) {
            TextField(NSLocalizedString("e.g. 42", comment: ""), text: $customText)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Set", comment: "")) {
                let trimmed = customText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed == "∞" { onChange(0) }
                else if let n = Int(trimmed) { onChange(max(0, n)) }
            }
        } message: {
            Text(NSLocalizedString("Enter a number, or 0 (or leave blank) for continuous.", comment: ""))
        }
    }
}
