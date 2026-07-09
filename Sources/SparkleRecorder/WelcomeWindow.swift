import Cocoa
import SwiftUI
import ApplicationServices
import SparkleRecorderCore

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private var onClose: (() -> Void)?
    private var closed = false

    /// `onDone`: the user pressed "Get Started" (should close the window).
    /// `onClose`: the window closed by ANY means — Done button or the red
    /// close button. Fired exactly once.
    init(controller: MenuBarController, onDone: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let host = NSHostingController(
            rootView: WelcomeView(controller: controller, onDone: onDone)
                .frame(width: 560, height: 520)
        )
        let win = NSWindow(contentViewController: host)
        win.title = String(localized: "Welcome to SparkleRecorder", table: "Recording")
        win.setContentSize(NSSize(width: 560, height: 520))
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.backgroundColor = .clear
        win.center()
        super.init(window: win)
        win.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        onClose?()
        onClose = nil
    }
}

/// True when macOS Input Monitoring is granted (separate from Accessibility).
@MainActor
func inputMonitoringGranted() -> Bool {
    PermissionCenter.shared.checkListenEventAccess() == .authorized
}

private enum Step: Int, CaseIterable {
    case welcome
    case permissions
    case hotkeys
    case ready
}

private struct WelcomeView: View {
    let controller: MenuBarController
    let onDone: () -> Void

    @State private var step: Step = .welcome
    @State private var accessibility: Bool = AXIsProcessTrusted()
    @State private var inputMonitoring: Bool = inputMonitoringGranted()
    @State private var screenCapture: Bool = PermissionCenter.shared.checkScreenCaptureAccess() == .authorized
    @State private var refreshTimer: Timer?

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top progress bar
                StepIndicator(current: step.rawValue + 1, total: Step.allCases.count)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                Spacer(minLength: 0)

                Group {
                    switch step {
                    case .welcome:     WelcomeStep()
                    case .permissions: PermissionsStep(accessibility: $accessibility,
                                                       inputMonitoring: $inputMonitoring,
                                                       screenCapture: $screenCapture,
                                                       controller: controller)
                    case .hotkeys:     HotkeysStep(controller: controller)
                    case .ready:       ReadyStep(controller: controller, onDone: onDone)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .padding(.horizontal, 32)

                Spacer(minLength: 0)

                // Bottom controls
                HStack {
                    if step != .welcome {
                        Button(String(localized: "Back", table: "Common")) { withAnimation(.spring(response: 0.4)) { step = Step(rawValue: step.rawValue - 1) ?? .welcome } }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    Spacer()
                    if step == .ready {
                        Button {
                            onDone()
                        } label: {
                            Text("Get Started", tableName: "Common").frame(minWidth: 140)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.red)
                    } else {
                        // Never trap the user: permissions can be skipped and
                        // granted later from Settings.
                        if step == .permissions && !(accessibility && inputMonitoring && screenCapture) {
                            Button(String(localized: "Skip for Now", table: "Common")) {
                                withAnimation(.spring(response: 0.4)) { step = .hotkeys }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        Button {
                            withAnimation(.spring(response: 0.4)) {
                                step = Step(rawValue: step.rawValue + 1) ?? .ready
                            }
                        } label: {
                            Text(nextLabel).frame(minWidth: 110)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(step == .permissions && !(accessibility && inputMonitoring && screenCapture))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
        .onAppear { startRefresh() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private var nextLabel: String {
        switch step {
        case .welcome:     return String(localized: "Next", table: "Common")
        case .permissions: return (accessibility && inputMonitoring && screenCapture) ? String(localized: "Continue", table: "Common") : String(localized: "Waiting…", table: "EditorUX")
        case .hotkeys:     return String(localized: "Next", table: "Common")
        case .ready:       return String(localized: "Get Started", table: "Common")
        }
    }

    private func startRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                let ax = AXIsProcessTrusted()
                let im = inputMonitoringGranted()
                let sc = PermissionCenter.shared.checkScreenCaptureAccess() == .authorized
                accessibility = ax
                inputMonitoring = im
                screenCapture = sc
            }
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 76)
                .scaleEffect(bounce ? 1.0 : 0.85)
                .animation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.1), value: bounce)
                .onAppear { bounce = true }

            Text("Welcome to SparkleRecorder", tableName: "Recording")
                .font(.system(size: 26, weight: .bold))
            Text("The little macro recorder for macOS that's quietly doing your repetitive work.", tableName: "Recording")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
 
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "wave.3.right", tint: .red,
                           title: String(localized: "Capture anything", table: "Recording"),
                           subtitle: String(localized: "Mouse clicks, drags, scrolls, and the keyboard.", table: "EditorUX"))
                FeatureRow(icon: "infinity", tint: .green,
                           title: String(localized: "Replay on demand", table: "Common"),
                           subtitle: String(localized: "Once, N times, or forever — at any speed.", table: "Automation"))
                FeatureRow(icon: "keyboard", tint: .blue,
                           title: String(localized: "Trigger from anywhere", table: "Automation"),
                           subtitle: String(localized: "Assign a global hotkey to any macro.", table: "EditorUX"))
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }
}

private struct PermissionsStep: View {
    @Binding var accessibility: Bool
    @Binding var inputMonitoring: Bool
    @Binding var screenCapture: Bool
    let controller: MenuBarController

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            Text("Two quick permissions", tableName: "Settings")
                .font(.system(size: 22, weight: .bold))
            Text("macOS requires explicit consent to capture and post input events. We never see what you type or click outside of recordings you initiate.", tableName: "Recording")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
 
            VStack(spacing: 10) {
                PermissionCard(
                    title: String(localized: "Accessibility", table: "Settings"),
                    subtitle: String(localized: "Required to play back your recordings.", table: "Recording"),
                    granted: accessibility,
                    action: { controller.openAccessibilityPrefs() }
                )
                PermissionCard(
                    title: String(localized: "Input Monitoring", table: "Common"),
                    subtitle: String(localized: "Required to record your inputs.", table: "Recording"),
                    granted: inputMonitoring,
                    action: { controller.openInputMonitoringPrefs() }
                )
                PermissionCard(
                    title: String(localized: "Screen Recording", table: "Recording"),
                    subtitle: String(localized: "Required for visual window mapping & OCR.", table: "EditorUX"),
                    granted: screenCapture,
                    action: { controller.openScreenCapturePrefs() }
                )
            }
            .frame(maxWidth: 440)
        }
    }
}

private struct HotkeysStep: View {
    let controller: MenuBarController

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            Text("Global hotkeys", tableName: "Common")
                .font(.system(size: 22, weight: .bold))
            Text("Trigger recording, stop, and play from any app — without bringing SparkleRecorder to the front. You can change these in Preferences.", tableName: "Automation")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(spacing: 10) {
                HotkeyExplain(label: String(localized: "Record / Stop", table: "Recording"), binding: controller.state.recordHotkey, tint: .red, systemImage: "record.circle")
                HotkeyExplain(label: String(localized: "Stop everything", table: "Common"), binding: controller.state.stopHotkey, tint: .orange, systemImage: "stop.circle")
                HotkeyExplain(label: String(localized: "Play current", table: "Common"), binding: controller.state.playHotkey, tint: .green, systemImage: "play.circle")
            }
            .frame(maxWidth: 440)

            Text("Pro tip: each saved macro can also have its OWN hotkey from the card menu — set one and that macro plays from anywhere.", tableName: "EditorUX")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 4)
        }
    }
}

private struct ReadyStep: View {
    let controller: MenuBarController
    let onDone: () -> Void

    private var countdownSentence: String {
        let secs = controller.state.countdownSeconds
        if secs > 0 {
            let format = String(localized: "Click the menu-bar icon or this Dock icon to open the library. Press Record to capture your first macro — SparkleRecorder will count down %d seconds before it starts so you have time to switch to the right window.", table: "Recording")
            return String(format: format, secs)
        }
        return String(localized: "Click the menu-bar icon or this Dock icon to open the library. Press Record to capture your first macro — recording starts immediately.", table: "Recording")
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.green.opacity(0.5), .green.opacity(0.2)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text("You're all set", tableName: "Common")
                .font(.system(size: 22, weight: .bold))
            Text(countdownSentence)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 8) {
                KeyCapView(text: controller.state.recordHotkey.name)
                Text("to record · ", tableName: "Recording")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                KeyCapView(text: controller.state.playHotkey.name)
                Text("to play · ", tableName: "Common")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                KeyCapView(text: controller.state.stopHotkey.name)
                Text("to stop", tableName: "Common")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Pieces

private struct StepIndicator: View {
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.red : Color.primary.opacity(0.15))
                    .frame(width: i == current ? 24 : 10, height: 5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct PermissionCard: View {
    let title: String
    let subtitle: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                Image(systemName: granted ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(granted ? .green : .orange)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? String(localized: "Granted", table: "Settings") : String(localized: "Open Settings", table: "Settings"), action: action)
                .controlSize(.small)
                .disabled(granted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

private struct HotkeyExplain: View {
    let label: String
    let binding: HotkeyBinding
    let tint: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.15))
                )
            Text(label).font(.system(size: 12.5, weight: .medium))
            Spacer()
            KeyCapView(text: binding.name)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
