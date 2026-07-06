import SwiftUI
import AppKit
import SparkleRecorderCore

// MARK: - Brand design tokens (ported from the Claude Design system)

enum Brand {
    // Signature red — richer, more confident (rec scale)
    static let red400 = Color(red: 255/255, green: 105/255, blue: 97/255) // System Red light
    static let red500 = Color(red: 255/255, green: 69/255, blue: 58/255)  // System Red dark
    static let red600 = Color(red: 215/255, green: 0/255, blue: 21/255)
    static let red700 = Color(red: 160/255, green: 0/255, blue: 15/255)

    static let redTop    = red400
    static let redBottom = red600

    /// The signature record-button gradient.
    static var redGradient: LinearGradient {
        LinearGradient(colors: [red400, red600], startPoint: .top, endPoint: .bottom)
    }

    /// A flat tint approximating the brand red, for tinting Liquid Glass.
    static let redTint = Color(red: 255/255, green: 69/255, blue: 58/255)

    // Signal accents — modern, vibrant but harmonious (Apple HIG Dark Mode colors)
    static let sigBlue   = Color(red: 10/255, green: 132/255, blue: 255/255)
    static let sigGreen  = Color(red: 48/255, green: 209/255, blue: 88/255)
    static let sigAmber  = Color(red: 255/255, green: 159/255, blue: 10/255)
    static let sigViolet = Color(red: 191/255, green: 90/255, blue: 242/255)
    static let sigTeal   = Color(red: 100/255, green: 210/255, blue: 255/255)
    static let sigPink   = Color(red: 255/255, green: 55/255, blue: 95/255)

    // Library screen accents: calmer than the global signal palette so the
    // macro grid reads like a work surface instead of an alert panel.
    static let libraryRecordTop = Color(red: 142/255, green: 36/255, blue: 42/255)
    static let libraryRecordBottom = Color(red: 92/255, green: 22/255, blue: 28/255)
    static let libraryRecordTint = Color(red: 172/255, green: 50/255, blue: 58/255)
    static let libraryBlue = Color(red: 86/255, green: 145/255, blue: 214/255)
    static let libraryGreen = Color(red: 70/255, green: 172/255, blue: 104/255)

    /// Named accent (from `SavedMacro.accent`) → a vibrant signal color.
    static func accent(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "red":    return red500
        case "orange", "amber": return sigAmber
        case "yellow": return sigAmber
        case "green":  return sigGreen
        case "teal":   return sigTeal
        case "blue":   return sigBlue
        case "indigo", "violet", "purple": return sigViolet
        case "pink":   return sigPink
        case "gray", "grey": return Color(white: 0.55)
        default:       return red500
        }
    }

    /// Event-kind → signal color (the design's waveform legend).
    static func eventColor(_ kind: RecordedEvent.Kind, dark: Bool = true) -> Color {
        switch kind {
        case .leftMouseDown, .leftMouseUp:       return sigGreen          // click
        case .rightMouseDown, .rightMouseUp:     return sigAmber          // right-click
        case .otherMouseDown, .otherMouseUp:     return sigAmber
        case .keyDown, .keyUp, .flagsChanged:    return sigBlue           // key
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                                                 return sigViolet          // drag
        case .scrollWheel:                       return sigTeal           // scroll
        case .mouseMoved:                        return Color.primary.opacity(0.22) // move
        case .waitForText:                       return sigAmber
        case .verifyText:                        return sigViolet
        }
    }

    /// Whether an event kind is an "impact" (taller tick) vs a move.
    static func isImpact(_ kind: RecordedEvent.Kind) -> Bool {
        WaveformProjection.isImpact(kind)
    }

    /// The one spring used for state changes app-wide — consistent motion.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let hoverAnimation = Animation.easeOut(duration: 0.16)
    static let pressAnimation = Animation.easeOut(duration: 0.08)

    /// Builds a configured Liquid Glass variant. macOS 26+ only.
    @available(macOS 26.0, *)
    static func glass(tint: Color? = nil, interactive: Bool = false) -> Glass {
        var g: Glass = .regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

// MARK: - Liquid Glass (macOS 26+) with graceful fallback

extension View {
    /// Prominent, tinted capsule control: interactive tinted Liquid Glass on
    /// macOS 26+, a tinted gradient capsule on earlier systems. Reserved for the
    /// app's primary actions (e.g. the Record button) — glass belongs to the
    /// floating control layer, used sparingly.
    @ViewBuilder
    func prominentGlassCapsule(tint: Color, gradientFallback: [Color]? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Brand.glass(tint: tint, interactive: true), in: Capsule(style: .continuous))
        } else {
            background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: gradientFallback ?? [tint.opacity(0.95), tint.opacity(0.78)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    )
                    .shadow(color: tint.opacity(0.30), radius: 3, x: 0, y: 2)
            )
        }
    }
    
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 10, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(Brand.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(
                shape
                    .fill(.regularMaterial)
                    .overlay(
                        shape.fill((tint ?? Color.primary).opacity(tint == nil ? 0.0 : 0.04))
                    )
                    .overlay(
                        shape.strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.1 : 0.2), lineWidth: 0.5)
                    )
            )
        }
    }
    
    @ViewBuilder
    func controlSurface(cornerRadius: CGFloat = 8, tint: Color? = nil, isActive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(Brand.glass(tint: isActive ? (tint ?? Color.accentColor) : tint, interactive: true), in: shape)
        } else {
            self.background(
                shape
                    .fill(isActive ? (tint ?? Color.accentColor).opacity(0.15) : Color.primary.opacity(0.04))
                    .overlay(
                        shape.strokeBorder(isActive ? (tint ?? Color.accentColor).opacity(0.3) : Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }

    @ViewBuilder
    func libraryControlSurface(
        cornerRadius: CGFloat = 8,
        tint: Color? = nil,
        isActive: Bool = false,
        activeFillOpacity: Double = 0.095
    ) -> some View {
        let accent = tint ?? Brand.libraryBlue
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.background(
            shape
                .fill(isActive ? accent.opacity(activeFillOpacity) : Color.primary.opacity(0.040))
                .overlay(
                    shape.strokeBorder(
                        isActive ? Color.white.opacity(activeFillOpacity > 0.4 ? 0.20 : 0.0) : Color.primary.opacity(0.10),
                        lineWidth: 0.5
                    )
                )
                .shadow(color: accent.opacity(isActive ? 0.14 : 0), radius: 4, x: 0, y: 1)
        )
    }
}

// MARK: - Wordmark

/// The "sparkle Recorder" wordmark
struct Wordmark: View {
    var size: CGFloat = 13
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.05) {
            Text("sparkle")
                .font(.system(size: size * 1.15, weight: .semibold, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [Brand.libraryBlue, Brand.sigTeal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("Recorder")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(.primary)
                .tracking(0.3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SparkleRecorder")
    }
}

// MARK: - Material backgrounds (NSVisualEffectView)

/// Wraps NSVisualEffectView so SwiftUI views get real macOS vibrancy/translucency.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = isEmphasized
        v.autoresizingMask = [.width, .height]
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

// MARK: - Card styles

extension View {
    /// Subtle layered card on top of vibrancy — adapts to light/dark.
    func cardSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
    
    func sectionSurface(cornerRadius: CGFloat = 10) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    func automationSubsurface(
        cornerRadius: CGFloat = 8,
        tint: Color? = nil,
        isActive: Bool = false
    ) -> some View {
        modifier(AutomationSubsurface(cornerRadius: cornerRadius, tint: tint, isActive: isActive))
    }
}

private struct CardSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let fill = isDark
            ? Color(red: 0.075, green: 0.085, blue: 0.095).opacity(0.94)
            : Color.primary.opacity(0.04)
        let stroke = isDark
            ? Color.white.opacity(0.10)
            : Color.primary.opacity(0.10)

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 0.5)
                    )
            )
    }
}

private struct AutomationSubsurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseFill = isDark
            ? Color(red: 0.065, green: 0.075, blue: 0.085).opacity(0.96)
            : Color.primary.opacity(isActive ? 0.055 : 0.035)
        let accent = tint ?? (isDark ? Color.white : Color.primary)
        let accentFill = tint?.opacity(isActive ? 0.09 : 0.035) ?? Color.clear
        let stroke = accent.opacity(isActive ? 0.26 : (tint == nil ? 0.10 : 0.18))

        content
            .background(
                shape
                    .fill(baseFill)
                    .overlay(shape.fill(accentFill))
                    .overlay(shape.strokeBorder(stroke, lineWidth: 0.6))
            )
    }
}

// MARK: - Hoverable button style (used on round action buttons)

struct HoverPressButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var hoverScale: CGFloat = 1.05
    var pressScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        let resolvedHoverScale = reduceMotion ? 1.0 : min(hoverScale, 1.018)
        let resolvedPressScale = reduceMotion ? 1.0 : max(pressScale, 0.985)
        configuration.label
            .scaleEffect(configuration.isPressed ? resolvedPressScale : (hovered ? resolvedHoverScale : 1.0))
            .brightness(hovered && !configuration.isPressed ? 0.025 : 0)
            .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
            .animation(reduceMotion ? .linear(duration: 0.01) : Brand.pressAnimation, value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

// MARK: - Key-cap chip (chiseled, multi-size, glass variant)

struct KeyCapView: View {
    enum Size { case sm, md, lg }
    enum Variant { case standard, glass }

    let text: String
    var size: Size = .md
    var variant: Variant = .standard
    @Environment(\.colorScheme) private var scheme

    private var height: CGFloat { size == .sm ? 18 : (size == .lg ? 28 : 22) }
    private var minW: CGFloat   { size == .sm ? 18 : (size == .lg ? 30 : 22) }
    private var font: CGFloat   { size == .sm ? 10 : (size == .lg ? 13 : 11) }
    private var radius: CGFloat { size == .sm ? 4 : 6 }
    private var horizontalPadding: CGFloat { size == .lg ? 8 : (size == .sm ? 5 : 6) }

    var body: some View {
        Text(text)
            .font(.system(size: font, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .foregroundStyle(foregroundStyle)
            .frame(minWidth: minW, minHeight: height)
            .padding(.horizontal, horizontalPadding)
            .background(background)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(bottomLipColor)
                    .frame(height: 1)
                    .padding(.horizontal, 2)
                    .opacity(size == .sm ? 0.55 : 0.7)
            }
            .shadow(color: keyShadowColor, radius: variant == .glass ? 0 : 1, x: 0, y: 1)
            .accessibilityLabel("Shortcut \(text)")
    }

    private var foregroundStyle: AnyShapeStyle {
        if variant == .glass {
            return AnyShapeStyle(.white)
        }
        return AnyShapeStyle(scheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.78))
    }

    private var bottomLipColor: Color {
        if variant == .glass {
            return Color.white.opacity(0.20)
        }
        return scheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.16)
    }

    private var keyShadowColor: Color {
        scheme == .dark ? Color.black.opacity(0.38) : Color.black.opacity(0.12)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if variant == .glass {
            shape
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.11)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
                .overlay(
                    shape.fill(LinearGradient(
                        colors: [Color.white.opacity(0.26), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ))
                )
        } else {
            let isDark = scheme == .dark
            shape
                .fill(LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.205, green: 0.218, blue: 0.255), Color(red: 0.115, green: 0.127, blue: 0.153)]
                        : [Color.white, Color(red: 0.918, green: 0.932, blue: 0.956)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(
                    isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.18), lineWidth: 0.5))
                .overlay(
                    shape.fill(LinearGradient(
                        colors: [Color.white.opacity(isDark ? 0.13 : 0.82), .clear],
                        startPoint: .top, endPoint: .center)).blendMode(.plusLighter).opacity(0.6))
        }
    }
}

// MARK: - Pulsing record dot

struct RecDot: View {
    var size: CGFloat = 8
    var color: Color = Brand.red500
    var glassWhite: Bool = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = glassWhite ? Color.white : color
        ZStack {
            Circle()
                .stroke(c.opacity(0.55), lineWidth: 1.5)
                .scaleEffect(reduceMotion ? 1.0 : (pulse ? 2.2 : 1.0))
                .opacity(reduceMotion ? 0.35 : (pulse ? 0 : 0.8))
            Circle()
                .fill(c)
                .shadow(color: c.opacity(0.6), radius: size * 0.6)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Brand mark (Sparkles inside a dark liquid glass circle)

struct BrandMark: View {
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
extension View {
    @ViewBuilder
    func disableFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    /// Prevents the window from being dragged when clicking on this view,
    /// even if the window has `isMovableByWindowBackground = true`.
    func preventWindowDrag() -> some View {
        self.background(WindowDragPreventionView())
    }
}

private struct WindowDragPreventionView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragPreventingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class DragPreventingView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            return false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only capture the hit if it hit us directly, not subviews
            let hit = super.hitTest(point)
            return hit == self ? self : hit
        }
    }
}
