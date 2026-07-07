import Cocoa
import SwiftUI
import Combine
import SparkleRecorderCore

// MARK: - Window controller

@MainActor
final class RecordingHUDController {
    private var window: NSPanel?
    private let recorder: Recorder
    private let onDiscard: @MainActor @Sendable () -> Void
    private let onStop: @MainActor @Sendable () -> Void
    private weak var state: AppState?
    private var currentMode: RecordingHUDMode = .compact

    init(recorder: Recorder,
         state: AppState?,
         onDiscard: @escaping @MainActor @Sendable () -> Void,
         onStop: @escaping @MainActor @Sendable () -> Void) {
        self.recorder = recorder
        self.state = state
        self.onDiscard = onDiscard
        self.onStop = onStop
    }

    func show(mode: RecordingHUDMode) {
        guard mode.showsFloatingPanel else {
            hide()
            return
        }
        if currentMode != mode {
            window?.orderOut(nil)
            window = nil
        }
        currentMode = mode
        if window == nil { create(mode: mode) }
        position()
        window?.alphaValue = 0
        window?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.window?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.window?.orderOut(nil)
            }
        })
    }

    private func expandFromCompact() {
        guard currentMode == .compact else { return }
        show(mode: .expanded)
    }

    private func collapseToCompact() {
        guard currentMode == .expanded else { return }
        show(mode: .compact)
    }

    private func create(mode: RecordingHUDMode) {
        let view = RecordingHUDView(
            mode: mode,
            recorder: recorder,
            state: state,
            onDiscard: onDiscard,
            onStop: onStop,
            onExpand: { [weak self] in self?.expandFromCompact() },
            onCollapse: { [weak self] in self?.collapseToCompact() }
        )
        let host = NSHostingView(rootView: view)
        let fitting = host.fittingSize
        let w: CGFloat = fitting.width  > 0 ? fitting.width  : 320
        let h: CGFloat = fitting.height > 0 ? fitting.height : 240

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = mode == .expanded
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = mode == .expanded

        // The HUD floats over the live desktop — the one place real Liquid Glass
        // refraction shines. Host the SwiftUI body INSIDE an NSGlassEffectView so
        // the glass samples real content behind it (macOS 26+); fall back to the
        // HUD vibrancy material on earlier systems.
        let cornerRadius: CGFloat = mode == .compact ? 22 : 16
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = host
            panel.contentView = glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = .hudWindow
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = cornerRadius
            fx.layer?.masksToBounds = true
            host.frame = fx.bounds
            host.autoresizingMask = [.width, .height]
            fx.addSubview(host)
            panel.contentView = fx
        }
        window = panel
    }

    private func position() {
        guard let win = window else { return }
        // Position on the screen the user is actually working on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = win.frame.size
        // Top-right with menu-bar gap. Compact mode stays close to the menu bar;
        // expanded mode keeps a little more breathing room for its shadow.
        let margin: CGFloat = currentMode == .compact ? 12 : 24
        let topGap: CGFloat = currentMode == .compact ? 8 : 12
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - topGap
        win.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}

// MARK: - View

struct RecordingHUDView: View {
    let mode: RecordingHUDMode
    @ObservedObject var recorder: Recorder
    weak var state: AppState?
    let onDiscard: @MainActor @Sendable () -> Void
    let onStop: @MainActor @Sendable () -> Void
    let onExpand: @MainActor @Sendable () -> Void
    let onCollapse: @MainActor @Sendable () -> Void

    /// The actual configured "stop recording" hotkey — pressing record again toggles off.
    private var stopHotkeyName: String {
        state?.recordHotkey.name ?? "F6"
    }
    /// The "stop everything" hotkey, shown as the discard shortcut affordance.
    private var emergencyHotkeyName: String {
        state?.stopHotkey.name ?? "F7"
    }

    private var minutes: String { String(format: "%02d", Int(recorder.liveDuration) / 60) }
    private var seconds: String { String(format: "%02d", Int(recorder.liveDuration) % 60) }
    private var hundredths: String {
        String(format: "%02d", Int((recorder.liveDuration - floor(recorder.liveDuration)) * 100))
    }

    private var stats: RecordingStats {
        recorder.liveStats
    }

    private var durationLabel: String {
        String(format: "%.1fs", recorder.liveDuration)
    }

    private var eventCount: Int {
        stats.clicks + stats.keys + stats.scrolls + stats.drags
    }

    @ViewBuilder
    var body: some View {
        switch mode {
        case .compact:
            compactBody
        case .expanded:
            expandedBody
        case .menuBar:
            EmptyView()
        }
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    RecDot(size: 9)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("Recording", comment: "").uppercased())
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.54))
                            .lineLimit(1)
                        Text("\(minutes):\(seconds)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .frame(width: 58, alignment: .leading)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    CompactEventCount(value: eventCount)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("Expand", comment: ""))

            HStack(spacing: 4) {
                HUDIconButton(
                    icon: "trash",
                    shortcut: emergencyHotkeyName,
                    tint: nil,
                    accessibilityTitle: NSLocalizedString("Discard", comment: ""),
                    action: onDiscard
                )
                HUDIconButton(
                    icon: "stop.fill",
                    shortcut: stopHotkeyName,
                    tint: Brand.red500,
                    accessibilityTitle: NSLocalizedString("Stop", comment: ""),
                    action: onStop
                )
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 7)
        .frame(width: 288, height: 52)
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.70),
                        Color(red: 0.045, green: 0.050, blue: 0.070).opacity(0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, y: 3)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(compactAccessibilityLabel)
    }

    private var expandedBody: some View {
        let s = stats
        return ZStack {
            // Inky translucent layer over the host glass: guarantees legible white
            // content over any desktop, while the NSGlassEffectView behind still
            // refracts. (This is the design's exact approach.)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.52),
                             Color(red: 0.047, green: 0.051, blue: 0.071).opacity(0.52)],
                    startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 10) {
                // Top row: status + big gradient timer
                HStack(spacing: 10) {
                    RecDot(size: 10)
                    Text(NSLocalizedString("Recording", comment: "").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.60))
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(minutes):\(seconds)")
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                        Text(".\(hundredths)")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .opacity(0.55)
                    }
                    .foregroundStyle(LinearGradient(
                        colors: [.white, Color(red: 0.77, green: 0.78, blue: 0.82)],
                        startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                    .frame(width: 96, alignment: .trailing)
                    HUDIconButton(
                        icon: "chevron.up",
                        shortcut: "",
                        tint: nil,
                        accessibilityTitle: NSLocalizedString("Collapse", comment: ""),
                        action: onCollapse
                    )
                }

                // Event-track panel
                VStack(spacing: 2) {
                    LiveWaveform(events: recorder.liveWaveformEvents)
                        .equatable()
                        .frame(height: 28)
                    HStack {
                        Text("0s")
                        Spacer()
                        Text(durationLabel).foregroundStyle(Color.white.opacity(0.55))
                        Spacer()
                        Text("30s")
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)))

                // 4-stat grid
                HStack(spacing: 6) {
                    HUDStat(icon: "cursorarrow.click", value: s.clicks, label: NSLocalizedString("Clicks", comment: ""), tint: Brand.sigGreen)
                    HUDStat(icon: "keyboard",          value: s.keys,   label: NSLocalizedString("Keys", comment: ""),   tint: Brand.sigBlue)
                    HUDStat(icon: "arrow.up.and.down", value: s.scrolls, label: NSLocalizedString("Scrolls", comment: ""), tint: Brand.sigTeal)
                    HUDStat(icon: "hand.draw",         value: s.drags,  label: NSLocalizedString("Drags", comment: ""),   tint: Brand.sigViolet)
                }

                // Action bar
                HStack(spacing: 6) {
                    HUDButton(title: NSLocalizedString("Discard", comment: ""), icon: "trash", shortcut: emergencyHotkeyName, tint: nil, action: onDiscard)
                    HUDButton(title: NSLocalizedString("Stop", comment: ""), icon: "stop.fill", shortcut: stopHotkeyName, tint: Brand.red500, action: onStop)
                }
            }
            .padding(14)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
    }

    private var compactAccessibilityLabel: Text {
        Text("\(NSLocalizedString("Recording", comment: "")), \(minutes):\(seconds), \(eventCount) \(NSLocalizedString("events", comment: ""))")
    }
}

// MARK: - HUD pieces

private struct LiveWaveform: View, Equatable {
    let events: [RecordedEvent]

    var body: some View {
        GeometryReader { _ in
            let bars = WaveformProjection.indexedBars(from: events)

            Canvas { context, size in
                context.fill(
                    Capsule(style: .continuous).path(in: CGRect(origin: .zero, size: size)),
                    with: .color(Color.primary.opacity(0.06))
                )

                for bar in bars {
                    let barWidth: CGFloat = bar.isImpact ? 2 : 1.2
                    let barHeight = bar.isImpact ? size.height : size.height * 0.45
                    let x = min(max(0, CGFloat(bar.positionFraction) * size.width), max(0, size.width - barWidth))
                    let rect = CGRect(
                        x: x,
                        y: (size.height - barHeight) / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(
                        RoundedRectangle(cornerRadius: 1, style: .continuous).path(in: rect),
                        with: .color(Brand.eventColor(bar.kind).opacity(bar.isImpact ? 1.0 : 0.6))
                    )
                }
            }
        }
    }
}

private struct HUDStat: View {
    let icon: String
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: value)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct CompactEventCount: View {
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.sigTeal)
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.88))
                .contentTransition(.numericText())
        }
        .frame(width: 60, height: 30)
        .padding(.horizontal, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(NSLocalizedString("events", comment: ""))")
    }
}

private struct HUDIconButton: View {
    let icon: String
    let shortcut: String
    let tint: Color?
    let accessibilityTitle: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(
                            tint != nil
                                ? AnyShapeStyle(Brand.redGradient)
                                : AnyShapeStyle(Color.white.opacity(hovered ? 0.14 : 0.08))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(tint != nil ? 0.24 : 0.12), lineWidth: 0.5)
                        )
                        .shadow(
                            color: (tint ?? .black).opacity(hovered ? 0.32 : (tint != nil ? 0.24 : 0.12)),
                            radius: hovered ? 6 : 3,
                            y: 2
                        )
                )
        }
        .buttonStyle(HoverPressButtonStyle(hoverScale: 1.04))
        .onHover { hovered = $0 }
        .help(shortcut.isEmpty ? accessibilityTitle : "\(accessibilityTitle) \(shortcut)")
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(shortcut)
    }
}

private struct HUDButton: View {
    let title: String
    let icon: String
    let shortcut: String
    let tint: Color?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                KeyCapView(text: shortcut, size: .sm, variant: .glass)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        tint != nil
                            ? AnyShapeStyle(Brand.redGradient)
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(tint != nil ? 0.22 : 0.10), lineWidth: 0.5)
                    )
                    .shadow(
                        color: (tint ?? .black).opacity(hovered ? 0.32 : (tint != nil ? 0.28 : 0.14)),
                        radius: hovered ? 7 : 4, y: 2
                    )
            )
        }
        .buttonStyle(HoverPressButtonStyle(hoverScale: 1.03))
        .onHover { hovered = $0 }
    }
}
