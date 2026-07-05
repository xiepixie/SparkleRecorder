import Cocoa
import SwiftUI
import SparkleRecorderCore

struct SettingsPanel: View {
    let controller: MenuBarController
    /// True when hosted in the dedicated Settings window.
    var inWindow: Bool = false
    @EnvironmentObject var state: AppState

    @State private var showCustomLoop = false
    @State private var customLoopText = ""

    private let hotkeyOptions: [HotkeyBinding] = [
        HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048),
        HotkeyBinding(keyCode: 1, name: "⌥S", modifiers: 2048),
        HotkeyBinding(keyCode: 35, name: "⌥P", modifiers: 2048),
        HotkeyBinding(keyCode: KeyCode.f1, name: "F1"),
        HotkeyBinding(keyCode: KeyCode.f2, name: "F2"),
        HotkeyBinding(keyCode: KeyCode.f3, name: "F3"),
        HotkeyBinding(keyCode: KeyCode.f4, name: "F4"),
        HotkeyBinding(keyCode: KeyCode.f5, name: "F5"),
        HotkeyBinding(keyCode: KeyCode.f6, name: "F6"),
        HotkeyBinding(keyCode: KeyCode.f7, name: "F7"),
        HotkeyBinding(keyCode: KeyCode.f8, name: "F8"),
        HotkeyBinding(keyCode: KeyCode.f9, name: "F9"),
        HotkeyBinding(keyCode: KeyCode.f10, name: "F10"),
        HotkeyBinding(keyCode: KeyCode.f11, name: "F11"),
        HotkeyBinding(keyCode: KeyCode.f12, name: "F12"),
    ]

    private var appVersion: String {
        let short = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        return "v" + short
    }

    /// F-keys that another binding already owns (other globals + macro hotkeys).
    func takenKeyCodes(excluding current: UInt32) -> Set<UInt32> {
        var taken: Set<UInt32> = [
            state.recordHotkey.keyCode,
            state.stopHotkey.keyCode,
            state.playHotkey.keyCode,
        ]
        for m in controller.library.macros {
            if let hk = m.hotkey { taken.insert(hk.keyCode) }
        }
        taken.remove(current)
        return taken
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: inWindow ? .windowBackground : .popover)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Settings", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                }

                settingsGroup(NSLocalizedString("Hotkeys", comment: ""), systemImage: "keyboard") {
                    hotkeyRow(title: NSLocalizedString("Record / Stop", comment: ""), binding: Binding(
                        get: { state.recordHotkey },
                        set: { state.recordHotkey = $0; controller.reapplyHotkeys() }
                    ))
                    hotkeyRow(title: NSLocalizedString("Stop everything", comment: ""), binding: Binding(
                        get: { state.stopHotkey },
                        set: { state.stopHotkey = $0; controller.reapplyHotkeys() }
                    ))
                    hotkeyRow(title: NSLocalizedString("Play", comment: ""), binding: Binding(
                        get: { state.playHotkey },
                        set: { state.playHotkey = $0; controller.reapplyHotkeys() }
                    ))
                }

                settingsGroup(NSLocalizedString("General", comment: ""), systemImage: "macwindow") {
                    HStack {
                        Text(NSLocalizedString("Show as", comment: "")).font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { state.menuBarOnly },
                            set: { controller.setMenuBarOnly($0) }
                        )) {
                            Text(NSLocalizedString("Dock app", comment: "")).tag(false)
                            Text(NSLocalizedString("Menu bar only", comment: "")).tag(true)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    Text(NSLocalizedString("Menu bar only hides the Dock icon — open SparkleRecorder from the menu-bar icon.", comment: ""))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup(NSLocalizedString("Recording", comment: ""), systemImage: "record.circle") {
                    HStack {
                        Text(NSLocalizedString("Countdown", comment: "")).font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $state.countdownSeconds) {
                            Text(NSLocalizedString("Off", comment: "")).tag(0)
                            Text("1s").tag(1)
                            Text("3s").tag(3)
                            Text("5s").tag(5)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    Toggle(isOn: $state.showRecordingHUD) {
                        Text(NSLocalizedString("Show floating HUD", comment: "")).font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Toggle(isOn: $state.soundEnabled) {
                        Text(NSLocalizedString("Sound effects", comment: "")).font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Toggle(isOn: $state.recordMouseMoves) {
                        Text(NSLocalizedString("Record mouse moves", comment: "")).font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                settingsGroup(NSLocalizedString("Default playback", comment: ""), systemImage: "play.circle") {
                    HStack {
                        Text(NSLocalizedString("Repeat", comment: "")).font(.system(size: 11.5))
                        Spacer()
                        Menu {
                            Button(NSLocalizedString("Once", comment: "")) { state.loops = 1 }
                            Button("2×") { state.loops = 2 }
                            Button("5×") { state.loops = 5 }
                            Button("10×") { state.loops = 10 }
                            Button("25×") { state.loops = 25 }
                            Button("100×") { state.loops = 100 }
                            Divider()
                            Button { state.loops = 0 } label: { Label(NSLocalizedString("Continuous", comment: ""), systemImage: "infinity") }
                            Divider()
                            Button(NSLocalizedString("Custom…", comment: "")) {
                                customLoopText = state.loops > 0 ? "\(state.loops)" : ""
                                showCustomLoop = true
                            }
                        } label: {
                            Text(state.loops <= 0 ? NSLocalizedString("Continuous", comment: "") : "\(state.loops)×")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 120)
                    }
                    HStack {
                        Text(NSLocalizedString("Speed", comment: "")).font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $state.speed) {
                            Text("0.5×").tag(0.5)
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                            Text("4×").tag(4.0)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }

                settingsGroup(NSLocalizedString("Permissions", comment: ""), systemImage: "lock.shield") {
                    permissionRow(title: NSLocalizedString("Accessibility", comment: ""),
                                  granted: state.accessibilityGranted,
                                  action: controller.openAccessibilityPrefs)
                    permissionRow(title: NSLocalizedString("Input Monitoring", comment: ""),
                                  granted: state.inputMonitoringGranted,
                                  action: controller.openInputMonitoringPrefs)
                    permissionRow(title: NSLocalizedString("Screen Recording", comment: ""),
                                  granted: state.screenCaptureGranted,
                                  action: controller.openScreenCapturePrefs)
                }

                HStack {
                    Button(NSLocalizedString("Replay welcome", comment: "")) { controller.showWelcome() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    Spacer()
                    Text(appVersion)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button(NSLocalizedString("Quit", comment: "")) { controller.quit() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            .padding(14)
        }
        .frame(width: 340)
        .alert(NSLocalizedString("Custom repeat count", comment: ""), isPresented: $showCustomLoop) {
            TextField(NSLocalizedString("e.g. 42", comment: ""), text: $customLoopText)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Set", comment: "")) {
                let trimmed = customLoopText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed == "∞" { state.loops = 0 }
                else if let n = Int(trimmed) { state.loops = max(0, n) }
            }
        } message: {
            Text(NSLocalizedString("Enter a number, or 0 (or leave blank) for continuous.", comment: ""))
        }
    }

    @ViewBuilder
    func settingsGroup<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(10)
                .cardSurface(cornerRadius: 10)
        }
    }

    /// One permission row: shows a green "Granted" status when the permission is
    /// held, or a blue "Grant…" button (opens System Settings) when it isn't — so
    /// an already-granted permission never lingers looking like an open prompt.
    @ViewBuilder
    func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11.5))
            Spacer()
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(NSLocalizedString("Granted", comment: ""))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
            } else {
                Button(NSLocalizedString("Grant…", comment: "")) { action() }
                    .buttonStyle(PillButtonStyle(tint: .blue))
            }
        }
    }

    func hotkeyRow(title: String, binding: Binding<HotkeyBinding>) -> some View {
        let taken = takenKeyCodes(excluding: binding.wrappedValue.keyCode)
        
        var localOptions = hotkeyOptions
        if !localOptions.contains(binding.wrappedValue) {
            localOptions.insert(binding.wrappedValue, at: 0)
        }
        
        return HStack {
            Text(title).font(.system(size: 11.5))
            Spacer()
            Picker("", selection: Binding(
                get: { binding.wrappedValue },
                set: { newValue in
                    guard !taken.contains(newValue.keyCode) else {
                        state.statusMessage = NSLocalizedString("That key is already assigned.", comment: "")
                        return
                    }
                    binding.wrappedValue = newValue
                }
            )) {
                ForEach(localOptions, id: \.self) { option in
                    Text(taken.contains(option.keyCode) ? String(format: NSLocalizedString("%@ (in use)", comment: ""), option.name) : option.name)
                        .tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }
}
