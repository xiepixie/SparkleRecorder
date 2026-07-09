import Cocoa
import SwiftUI
import Combine

/// Compact floating "3 · 2 · 1" overlay shown before recording starts so the user
/// can switch to the right window before keyboard/mouse is being captured.
@MainActor
final class CountdownOverlayController {
    private var window: NSPanel?
    private var timer: Timer?
    private let model = CountdownModel()
    /// Bumped on every start()/cancel(). Timer ticks and the dismiss animation
    /// completion both check it, so a cancelled countdown can never fire
    /// onComplete — even if cancel lands during the final fade.
    private var session: UInt64 = 0

    private enum Metrics {
        static let size = NSSize(width: 200, height: 200)
        static let cornerRadius: CGFloat = 100
    }

    /// True while a countdown is pending (used to make the record hotkey toggle).
    private(set) var isActive = false

    /// `seconds` ticks before completion. `onComplete` runs on the main queue.
    func start(seconds: Int = 3, onComplete: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        session &+= 1
        let mySession = session
        isActive = true
        model.reset(to: seconds)

        if window == nil { create() }
        position()
        window?.alphaValue = 0
        window?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.window?.animator().alphaValue = 1
        }
        SoundController.shared.play(.tick)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session == mySession else { return }
                let next = self.model.remaining - 1
                if next <= 0 {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.dismiss(session: mySession) { [weak self] in
                        Task { @MainActor in
                            guard let self, self.session == mySession else { return }
                            self.isActive = false
                            onComplete()
                        }
                    }
                } else {
                    SoundController.shared.play(.tick)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.model.remaining = next
                    }
                }
            }
        }
    }

    func cancel() {
        session &+= 1
        isActive = false
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }

    private func dismiss(session expected: UInt64, _ then: @escaping @MainActor @Sendable () -> Void) {
        guard let win = window else { then(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.session == expected else { return }
                self.window?.orderOut(nil)
                then()
            }
        })
    }

    private func create() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isMovable = false

        // Built once; the view observes the model so ticks animate properly
        // instead of swapping in a brand-new hosting controller every second.
        let host = NSHostingView(rootView: CountdownView(model: model))

        // A small Liquid Glass capsule leaves the target window visible while the
        // countdown is still obvious enough to trust.
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Metrics.cornerRadius
            glass.contentView = host
            panel.contentView = glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = .hudWindow
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = Metrics.cornerRadius
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
        // Show on the screen the user is actually working on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = win.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 // Center it on screen for more impact
        win.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}

// MARK: - Model

final class CountdownModel: ObservableObject {
    @Published var remaining: Int = 3
    /// Bumped per countdown session so the pulse ring restarts cleanly.
    @Published var sessionSeed: Int = 0

    func reset(to seconds: Int) {
        remaining = seconds
        sessionSeed &+= 1
    }
}

// MARK: - View

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Subtle glowing background
            Circle()
                .fill(Color.red.opacity(0.12))
                .blur(radius: 24)

            // Outer pulsing ring
            Circle()
                .strokeBorder(Color.red.opacity(0.4), lineWidth: 3)
                .scaleEffect(pulse ? 1.08 : 0.95)
                .opacity(pulse ? 0.0 : 1.0)
                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: pulse)

            // Sleek inner ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.red.opacity(0.85), Color.orange.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: 180, height: 180)

            // Content
            VStack(spacing: -6) {
                Text("\(model.remaining)")
                    .font(.system(size: 96, weight: .light, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                Text("RECORDING IN", tableName: "Recording")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(3.5)
                    .padding(.top, 4)
            }
        }
        .frame(width: 200, height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "Recording starts in %d seconds", table: "Recording"), model.remaining)))
        .onAppear { pulse = true }
        .onChange(of: model.sessionSeed) {
            // Restart the pulse for each new countdown session.
            pulse = false
            DispatchQueue.main.async { pulse = true }
        }
    }
}
