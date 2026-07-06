import AppKit
import SwiftUI

struct AutomationVisualColorPickerView: View {
    @Binding var colorHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker(
                NSLocalizedString("Target color", comment: ""),
                selection: colorSelection,
                supportsOpacity: false
            )
            .font(.caption)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(displayColor)
                    .frame(width: 34, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(borderTint, lineWidth: 0.8)
                    )
                    .accessibilityHidden(true)

                TextField(NSLocalizedString("Hex", comment: ""), text: hexBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .monospaced()
                    .frame(width: 96)
                    .accessibilityLabel(NSLocalizedString("Target color hex", comment: ""))

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var colorSelection: Binding<Color> {
        Binding(
            get: {
                Self.color(from: colorHex) ?? .white
            },
            set: { newColor in
                if let hex = Self.hexString(for: newColor) {
                    colorHex = hex
                }
            }
        )
    }

    private var hexBinding: Binding<String> {
        Binding(
            get: { colorHex },
            set: { newValue in
                colorHex = Self.sanitizedHexInput(newValue)
            }
        )
    }

    private var displayColor: Color {
        Self.color(from: colorHex) ?? Color.primary.opacity(0.08)
    }

    private var borderTint: Color {
        Self.color(from: colorHex) == nil ? Brand.sigAmber.opacity(0.55) : Color.primary.opacity(0.16)
    }

    private var accessibilitySummary: String {
        if Self.color(from: colorHex) == nil {
            return NSLocalizedString("Target color is not set", comment: "")
        }
        return String(
            format: NSLocalizedString("Target color %@", comment: ""),
            colorHex
        )
    }

    private static func sanitizedHexInput(_ value: String) -> String {
        let allowed = Set("0123456789ABCDEFabcdef#")
        var result = value.filter { allowed.contains($0) }.uppercased()
        if result.filter({ $0 == "#" }).count > 1 {
            result = result.replacingOccurrences(of: "#", with: "")
        }
        if !result.isEmpty, !result.hasPrefix("#") {
            result = "#" + result
        }
        return String(result.prefix(7))
    }

    private static func color(from hex: String) -> Color? {
        guard let components = rgbComponents(from: hex) else {
            return nil
        }
        return Color(
            red: Double(components.red) / 255,
            green: Double(components.green) / 255,
            blue: Double(components.blue) / 255
        )
    }

    private static func rgbComponents(from hex: String) -> (red: Int, green: Int, blue: Int)? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard value.count == 6,
              let rawValue = Int(value, radix: 16) else {
            return nil
        }

        return (
            red: (rawValue >> 16) & 0xFF,
            green: (rawValue >> 8) & 0xFF,
            blue: rawValue & 0xFF
        )
    }

    private static func hexString(for color: Color) -> String? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }

        let red = clampedByte(converted.redComponent)
        let green = clampedByte(converted.greenComponent)
        let blue = clampedByte(converted.blueComponent)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func clampedByte(_ value: CGFloat) -> Int {
        min(max(Int((value * 255).rounded()), 0), 255)
    }
}
