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
    @State private var semanticRetentionCleanupPreview: SemanticRecordingRetentionCleanupPreview?
    @State private var semanticRetentionCleanupBusy = false
    @State private var showSemanticRetentionCleanupConfirmation = false

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
    private let semanticRecordingRetentionDayOptions: [Int] = [0, 7, 30, 90, 180, 365]
    private let semanticRecordingMaximumArtifactMegabyteOptions: [Int] = [0, 25, 100, 500, 1024]

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
                    HStack {
                        Text(NSLocalizedString("Status UI", comment: "")).font(.system(size: 11.5))
                        Spacer()
                        Picker("", selection: $state.recordingHUDMode) {
                            ForEach(RecordingHUDMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }
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
                    Toggle(isOn: semanticRecordingEnabledBinding) {
                        Text(NSLocalizedString("Record visual evidence", comment: "")).font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    if state.semanticRecordingEnabled {
                        Divider()
                        semanticRecordingPreflightPanel(state.semanticRecordingPreflightPresentation)
                        Divider()
                        semanticRecordingRetentionPanel()
                        Divider()
                        semanticRecordingSuppressionPanel()
                    }
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
        .onAppear {
            if state.semanticRecordingEnabled,
               state.semanticRecordingPreflightPresentation == nil {
                controller.refreshSemanticRecordingPreflightPresentation()
            }
        }
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
        .alert(NSLocalizedString("Clean up visual evidence?", comment: ""), isPresented: $showSemanticRetentionCleanupConfirmation) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                Task {
                    await confirmSemanticRecordingRetentionCleanup()
                }
            }
        } message: {
            Text(semanticRecordingRetentionCleanupConfirmationMessage())
        }
    }

    private var semanticRecordingEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.semanticRecordingEnabled },
            set: { enabled in
                state.semanticRecordingEnabled = enabled
                if enabled {
                    controller.refreshSemanticRecordingPreflightPresentation()
                } else {
                    state.semanticRecordingPreflightPresentation = nil
                }
            }
        )
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

    @ViewBuilder
    func semanticRecordingPreflightPanel(
        _ presentation: SemanticRecordingPreflightPresentation?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let presentation {
                HStack(spacing: 7) {
                    Image(systemName: semanticRecordingPreflightIcon(presentation.status))
                        .foregroundStyle(semanticRecordingPreflightColor(presentation.status))
                    Text(NSLocalizedString(presentation.title, comment: ""))
                        .font(.system(size: 11.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        controller.refreshSemanticRecordingPreflightPresentation()
                    } label: {
                        Label(NSLocalizedString("Check", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))
                    .help(NSLocalizedString("Check semantic recording permissions again", comment: ""))
                }

                Text(NSLocalizedString(presentation.summary, comment: ""))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !presentation.decisionRows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(presentation.decisionRows) { row in
                            semanticRecordingDecisionRow(row, status: presentation.status)
                        }
                    }
                    .padding(.top, 1)
                }

                ForEach(presentation.issues) { issue in
                    semanticRecordingIssueRow(issue)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Visual evidence status has not been checked.", comment: ""))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        controller.refreshSemanticRecordingPreflightPresentation()
                    } label: {
                        Label(NSLocalizedString("Check", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))
                }
            }
        }
    }

    @ViewBuilder
    func semanticRecordingRetentionPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("Keep visual evidence", comment: "")).font(.system(size: 11.5))
                Spacer()
                Picker("", selection: $state.semanticRecordingRetentionMaximumArtifactAgeDays) {
                    ForEach(semanticRecordingRetentionDayOptions, id: \.self) { days in
                        Text(semanticRecordingRetentionDayLabel(days))
                            .tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if state.semanticRecordingRetentionMaximumArtifactAgeDays > 0 {
                HStack {
                    Text(NSLocalizedString("When expired", comment: "")).font(.system(size: 11.5))
                    Spacer()
                    Picker("", selection: $state.semanticRecordingExpiredDisposition) {
                        Text(NSLocalizedString("Delete evidence", comment: ""))
                            .tag(SemanticRecordingRetentionDisposition.pruneArtifacts)
                        Text(NSLocalizedString("Delete bundle", comment: ""))
                            .tag(SemanticRecordingRetentionDisposition.deleteBundle)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        await reviewSemanticRecordingRetentionCleanup()
                    }
                } label: {
                    Label(NSLocalizedString("Review cleanup", comment: ""), systemImage: "trash")
                }
                .buttonStyle(PillButtonStyle(tint: .orange))
                .disabled(
                    semanticRetentionCleanupBusy ||
                        state.semanticRecordingRetentionMaximumArtifactAgeDays <= 0
                )
            }
        }
    }

    func semanticRecordingRetentionDayLabel(_ days: Int) -> String {
        switch days {
        case 0:
            return NSLocalizedString("Until I delete", comment: "")
        case 1:
            return NSLocalizedString("1 day", comment: "")
        default:
            return String(format: NSLocalizedString("%d days", comment: ""), days)
        }
    }

    @ViewBuilder
    func semanticRecordingSuppressionPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Privacy exclusions", comment: ""))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            semanticRecordingTextSettingRow(
                title: NSLocalizedString("Apps", comment: ""),
                placeholder: "com.example.Bank",
                text: $state.semanticRecordingExcludedApplicationBundleIDsText
            )
            semanticRecordingTextSettingRow(
                title: NSLocalizedString("Windows", comment: ""),
                placeholder: NSLocalizedString("Private Checkout", comment: ""),
                text: $state.semanticRecordingExcludedWindowTitleFragmentsText
            )
            semanticRecordingTextSettingRow(
                title: NSLocalizedString("Domains", comment: ""),
                placeholder: "bank.example.com",
                text: $state.semanticRecordingExcludedDomainsText
            )

            HStack {
                Text(NSLocalizedString("Max artifact", comment: ""))
                    .font(.system(size: 11.5))
                Spacer()
                Picker("", selection: $state.semanticRecordingMaximumArtifactMegabytes) {
                    ForEach(semanticRecordingMaximumArtifactMegabyteOptions, id: \.self) { megabytes in
                        Text(semanticRecordingArtifactLimitLabel(megabytes))
                            .tag(megabytes)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    func semanticRecordingTextSettingRow(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11.5))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: 11))
        }
    }

    func semanticRecordingArtifactLimitLabel(_ megabytes: Int) -> String {
        switch megabytes {
        case 0:
            return NSLocalizedString("No limit", comment: "")
        case 1024:
            return NSLocalizedString("1 GB", comment: "")
        default:
            return String(format: NSLocalizedString("%d MB", comment: ""), megabytes)
        }
    }

    func semanticRecordingRetentionCleanupConfirmationMessage() -> String {
        guard let preview = semanticRetentionCleanupPreview else {
            return ""
        }
        if preview.deleteBundleCount > 0 {
            return String(
                format: NSLocalizedString(
                    "This will delete evidence from %d recording(s), including %d full bundle(s) and %d artifact reference(s). %d metadata file(s) stay listed for pruned recordings.",
                    comment: ""
                ),
                preview.items.count,
                preview.deleteBundleCount,
                preview.artifactRefCount,
                preview.preservedMetadataFileCount
            )
        }
        return String(
            format: NSLocalizedString(
                "This will delete %d visual evidence artifact reference(s) from %d recording(s). %d metadata file(s) stay listed for history and explainability.",
                comment: ""
            ),
            preview.artifactRefCount,
            preview.items.count,
            preview.preservedMetadataFileCount
        )
    }

    @MainActor
    func reviewSemanticRecordingRetentionCleanup() async {
        semanticRetentionCleanupBusy = true
        defer { semanticRetentionCleanupBusy = false }
        do {
            let preview = try await controller.semanticRecordingRetentionCleanupPreview()
            if preview.isEmpty {
                semanticRetentionCleanupPreview = nil
                state.statusMessage = NSLocalizedString("No expired visual evidence to clean up.", comment: "")
                return
            }
            semanticRetentionCleanupPreview = preview
            showSemanticRetentionCleanupConfirmation = true
            state.statusMessage = String(
                format: NSLocalizedString("Found %d recording(s) with expired visual evidence.", comment: ""),
                preview.items.count
            )
        } catch {
            state.statusMessage = String(
                format: NSLocalizedString("Visual evidence cleanup check failed: %@", comment: ""),
                error.localizedDescription
            )
        }
    }

    @MainActor
    func confirmSemanticRecordingRetentionCleanup() async {
        guard let preview = semanticRetentionCleanupPreview else {
            return
        }
        semanticRetentionCleanupBusy = true
        defer { semanticRetentionCleanupBusy = false }
        do {
            let results = try await controller.applySemanticRecordingRetentionCleanup(preview)
            let deletedArtifacts = results.reduce(0) { total, result in
                total + result.deletedRelativePaths.count
            }
            let deletedBundles = results.filter(\.deletedBundleDirectory).count
            semanticRetentionCleanupPreview = nil
            state.statusMessage = String(
                format: NSLocalizedString("Cleaned up %d artifact(s) and %d bundle(s).", comment: ""),
                deletedArtifacts,
                deletedBundles
            )
        } catch {
            state.statusMessage = String(
                format: NSLocalizedString("Visual evidence cleanup failed: %@", comment: ""),
                error.localizedDescription
            )
        }
    }

    @ViewBuilder
    func semanticRecordingDecisionRow(
        _ row: SemanticRecordingPreflightDecisionRow,
        status: SemanticRecordingPreflightPresentationStatus
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: semanticRecordingDecisionIcon(row.role))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(semanticRecordingDecisionColor(row.role, status: status))
                .frame(width: 15, height: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(row.title, comment: ""))
                    .font(.system(size: 10.5, weight: .semibold))
                Text(NSLocalizedString(row.detail, comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    func semanticRecordingDecisionIcon(
        _ role: SemanticRecordingPreflightDecisionRole
    ) -> String {
        switch role {
        case .nextStep:
            return "arrow.right.circle.fill"
        case .evidenceImpact:
            return "film.stack.fill"
        case .privacyBoundary:
            return "lock.shield.fill"
        }
    }

    func semanticRecordingDecisionColor(
        _ role: SemanticRecordingPreflightDecisionRole,
        status: SemanticRecordingPreflightPresentationStatus
    ) -> Color {
        switch role {
        case .nextStep:
            return semanticRecordingPreflightColor(status)
        case .evidenceImpact:
            return .blue
        case .privacyBoundary:
            return .purple
        }
    }

    @ViewBuilder
    func semanticRecordingIssueRow(
        _ issue: SemanticRecordingPreflightIssuePresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .blocking ? .red : .orange)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString(issue.title, comment: ""))
                    .font(.system(size: 10.5, weight: .semibold))
                Text(NSLocalizedString(issue.detail, comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !issue.affectedCapabilityLabels.isEmpty {
                    Text(issue.affectedCapabilityLabels.joined(separator: ", "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button {
                performSemanticRecordingPreflightAction(issue.action)
            } label: {
                Label(NSLocalizedString("Open", comment: ""), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(PillButtonStyle(tint: issue.severity == .blocking ? .red : .orange))
            .help(NSLocalizedString(issue.action.label, comment: ""))
            .accessibilityLabel(NSLocalizedString(issue.action.label, comment: ""))
        }
        .padding(.top, 2)
    }

    func performSemanticRecordingPreflightAction(
        _ action: SemanticRecordingPreflightPresentationAction
    ) {
        switch action.kind {
        case .openPermissionSettings:
            if let permission = action.permission {
                controller.openSemanticRecordingPermissionSettings(permission)
            }
        case .retryPreflight:
            controller.refreshSemanticRecordingPreflightPresentation()
        case .startRecording, .continueDegraded:
            break
        }
    }

    func semanticRecordingPreflightIcon(
        _ status: SemanticRecordingPreflightPresentationStatus
    ) -> String {
        switch status {
        case .ready:
            return "checkmark.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        }
    }

    func semanticRecordingPreflightColor(
        _ status: SemanticRecordingPreflightPresentationStatus
    ) -> Color {
        switch status {
        case .ready:
            return .green
        case .degraded:
            return .orange
        case .blocked:
            return .red
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
