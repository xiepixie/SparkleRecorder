import Cocoa
import SwiftUI
import SparkleRecorderCore

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case recording
    case playback
    case visualEvidence
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General", table: "Common")
        case .shortcuts: return String(localized: "Keyboard Shortcuts", table: "Settings")
        case .recording: return String(localized: "Recording", table: "Recording")
        case .playback: return String(localized: "Playback", table: "Settings")
        case .visualEvidence: return String(localized: "Visual Evidence", table: "Automation")
        case .permissions: return String(localized: "Permissions", table: "Settings")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "Appearance and application language.", table: "Settings")
        case .shortcuts: return String(localized: "Global shortcuts for recording and playback.", table: "Settings")
        case .recording: return String(localized: "Capture behavior and status feedback.", table: "Settings")
        case .playback: return String(localized: "Default repeat count and playback speed.", table: "Settings")
        case .visualEvidence: return String(localized: "Optional visual context, privacy, and retention.", table: "Settings")
        case .permissions: return String(localized: "System access required to record and replay.", table: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .recording: return "record.circle"
        case .playback: return "play.circle"
        case .visualEvidence: return "film.stack"
        case .permissions: return "lock.shield"
        }
    }
}

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
    @State private var languagePreferenceDraft = AppLanguagePreference.current()
    @State private var selectedCategory: SettingsCategory = .general

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
            if inWindow {
                settingsWindowContent
            } else {
                compactSettingsContent
            }
        }
        .frame(
            minWidth: inWindow ? 640 : 340,
            idealWidth: inWindow ? 760 : 340,
            maxWidth: inWindow ? .infinity : 340
        )
        .onAppear {
            languagePreferenceDraft = AppLanguagePreference.current()
            if state.semanticRecordingEnabled,
               state.semanticRecordingPreflightPresentation == nil {
                controller.refreshSemanticRecordingPreflightPresentation()
            }
        }
        .alert(String(localized: "Custom repeat count", table: "Common"), isPresented: $showCustomLoop) {
            TextField(String(localized: "e.g. 42", table: "Common"), text: $customLoopText)
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
            Button(String(localized: "Set", table: "Common")) {
                let trimmed = customLoopText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed == "∞" { state.loops = 0 }
                else if let n = Int(trimmed) { state.loops = max(0, n) }
            }
        } message: {
            Text("Enter a number, or 0 (or leave blank) for continuous.", tableName: "Automation")
        }
        .alert(String(localized: "Clean up visual evidence?", table: "Common"), isPresented: $showSemanticRetentionCleanupConfirmation) {
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
            Button(String(localized: "Delete", table: "Common"), role: .destructive) {
                Task {
                    await confirmSemanticRecordingRetentionCleanup()
                }
            }
        } message: {
            Text(semanticRecordingRetentionCleanupConfirmationMessage())
        }
    }

    private var settingsWindowContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(SettingsCategory.allCases) { category in
                        settingsSidebarButton(category)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .top)

                Spacer(minLength: 20)

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    sidebarStatusRow(
                        title: permissionsReady
                            ? String(localized: "Ready", table: "Common")
                            : String(localized: "Needs access", table: "Settings"),
                        systemImage: permissionsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: permissionsReady ? .green : .orange
                    )
                    sidebarStatusRow(
                        title: state.semanticRecordingEnabled
                            ? String(localized: "Evidence on", table: "Automation")
                            : String(localized: "Evidence off", table: "Automation"),
                        systemImage: state.semanticRecordingEnabled ? "film.stack.fill" : "film.stack",
                        tint: Brand.libraryBlue
                    )
                    Text(appVersion)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 196)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(selectedCategory.title, systemImage: selectedCategory.systemImage)
                            .font(.system(size: 21, weight: .semibold))
                        Text(selectedCategory.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    selectedSettingsGroup

                    if selectedCategory == .general {
                        Divider()
                        settingsFooter
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func settingsSidebarButton(_ category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 9) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18, height: 18)
                Text(category.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.075 : 0))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Brand.libraryBlue)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var compactSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader
                settingsSections
                settingsFooter
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var selectedSettingsGroup: some View {
        switch selectedCategory {
        case .general: applicationSettingsGroup
        case .shortcuts: hotkeySettingsGroup
        case .recording: recordingSettingsGroup
        case .playback: replaySettingsGroup
        case .visualEvidence: visualEvidenceSettingsGroup
        case .permissions: permissionsSettingsGroup
        }
    }

    private var settingsFooter: some View {
        HStack {
            Button(String(localized: "Replay welcome", table: "Common")) { controller.showWelcome() }
                .buttonStyle(.borderless)
                .controlSize(.small)
            Spacer()
            Button(String(localized: "Quit", table: "Common")) { controller.quit() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private func sidebarStatusRow(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var settingsSections: some View {
        hotkeySettingsGroup
        applicationSettingsGroup
        recordingSettingsGroup
        visualEvidenceSettingsGroup
        replaySettingsGroup
        permissionsSettingsGroup
    }

    private var applicationSettingsGroup: some View {
        settingsGroup(String(localized: "General", table: "Common"), systemImage: "macwindow") {
            settingRow(String(localized: "Show as", table: "Common")) {
                Picker("", selection: Binding(
                    get: { state.menuBarOnly },
                    set: { controller.setMenuBarOnly($0) }
                )) {
                    Text("Dock app", tableName: "Common").tag(false)
                    Text("Menu bar only", tableName: "Common").tag(true)
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Text("Menu bar only hides the Dock icon. Use the menu-bar icon to reopen SparkleRecorder.", tableName: "Recording")
                .settingsDescriptionStyle()

            Divider()

            settingRow(String(localized: "Language", table: "Settings")) {
                Picker("", selection: $languagePreferenceDraft) {
                    ForEach(AppLanguagePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            Text("The selected language applies after SparkleRecorder relaunches.", tableName: "Settings")
                .settingsDescriptionStyle()

            if languagePreferenceNeedsRelaunch {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Relaunch required", tableName: "Settings")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(String(localized: "Apply and Relaunch", table: "Settings")) {
                        controller.applyLanguagePreferenceAndRelaunch(languagePreferenceDraft)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var hotkeySettingsGroup: some View {
        settingsGroup(String(localized: "Hotkeys", table: "Common"), systemImage: "keyboard") {
            hotkeyRow(title: String(localized: "Record / Stop", table: "Recording"), binding: Binding(
                get: { state.recordHotkey },
                set: { state.recordHotkey = $0; controller.reapplyHotkeys() }
            ))
            hotkeyRow(title: String(localized: "Stop everything", table: "Common"), binding: Binding(
                get: { state.stopHotkey },
                set: { state.stopHotkey = $0; controller.reapplyHotkeys() }
            ))
            hotkeyRow(title: String(localized: "Play", table: "Common"), binding: Binding(
                get: { state.playHotkey },
                set: { state.playHotkey = $0; controller.reapplyHotkeys() }
            ))
        }
    }

    private var languagePreferenceNeedsRelaunch: Bool {
        languagePreferenceDraft != AppLanguagePreference.current()
            || !languagePreferenceDraft.matches(languageIdentifiers: Locale.preferredLanguages)
    }

    private var recordingSettingsGroup: some View {
        settingsGroup(String(localized: "Recording", table: "Recording"), systemImage: "record.circle") {
            settingRow(String(localized: "Countdown", table: "Common")) {
                Picker("", selection: $state.countdownSeconds) {
                    Text("Off", tableName: "Common").tag(0)
                    Text("1s").tag(1)
                    Text("3s").tag(3)
                    Text("5s").tag(5)
                }
                .labelsHidden()
                .frame(width: 112)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Status UI", tableName: "Common")
                    .font(.system(size: 11.5))
                Picker("", selection: $state.recordingHUDMode) {
                    ForEach(RecordingHUDMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }
            Toggle(isOn: $state.soundEnabled) {
                Text("Sound effects", tableName: "Common").font(.system(size: 11.5))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Toggle(isOn: $state.recordMouseMoves) {
                Text("Record mouse moves", tableName: "Recording").font(.system(size: 11.5))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private var visualEvidenceSettingsGroup: some View {
        settingsGroup(String(localized: "Visual Evidence", table: "Automation"), systemImage: "film.stack") {
            Toggle(isOn: semanticRecordingEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record visual evidence", tableName: "Automation")
                        .font(.system(size: 11.5))
                    Text("Frames, OCR, and privacy exclusions stay separate from playable macro events.", tableName: "EditorUX")
                        .settingsDescriptionStyle()
                }
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
    }

    private var replaySettingsGroup: some View {
        settingsGroup(String(localized: "Replay Defaults", table: "Common"), systemImage: "play.circle") {
            settingRow(String(localized: "Repeat", table: "Common")) {
                Menu {
                    Button(String(localized: "Once", table: "Common")) { state.loops = 1 }
                    Button("2×") { state.loops = 2 }
                    Button("5×") { state.loops = 5 }
                    Button("10×") { state.loops = 10 }
                    Button("25×") { state.loops = 25 }
                    Button("100×") { state.loops = 100 }
                    Divider()
                    Button { state.loops = 0 } label: { Label(String(localized: "Continuous", table: "Common"), systemImage: "infinity") }
                    Divider()
                    Button(String(localized: "Custom…", table: "Common")) {
                        customLoopText = state.loops > 0 ? "\(state.loops)" : ""
                        showCustomLoop = true
                    }
                } label: {
                    Text(state.loops <= 0 ? String(localized: "Continuous", table: "Common") : "\(state.loops)×")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 120)
            }
            settingRow(String(localized: "Speed", table: "Common")) {
                Picker("", selection: $state.speed) {
                    Text("0.5×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("4×").tag(4.0)
                }
                .labelsHidden()
                .frame(width: 112)
            }
        }
    }

    private var permissionsSettingsGroup: some View {
        settingsGroup(String(localized: "Permissions", table: "Settings"), systemImage: "lock.shield") {
            permissionRow(title: String(localized: "Accessibility", table: "Settings"),
                          granted: state.accessibilityGranted,
                          action: controller.openAccessibilityPrefs)
            permissionRow(title: String(localized: "Input Monitoring", table: "Common"),
                          granted: state.inputMonitoringGranted,
                          action: controller.openInputMonitoringPrefs)
            permissionRow(title: String(localized: "Screen Recording", table: "Recording"),
                          granted: state.screenCaptureGranted,
                          action: controller.openScreenCapturePrefs)
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11.5))
            Spacer(minLength: 12)
            control()
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Settings", tableName: "Settings")
                    .font(.system(size: 15, weight: .semibold))
                Text(settingsSummaryText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { settingsStatusBadges }
                VStack(alignment: .trailing, spacing: 5) { settingsStatusBadges }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var settingsStatusBadges: some View {
        settingsStatusBadge(
            title: permissionsReady
                ? String(localized: "Ready", table: "Common")
                : String(localized: "Needs access", table: "Settings"),
            systemImage: permissionsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            tint: permissionsReady ? .green : .orange
        )
        settingsStatusBadge(
            title: state.semanticRecordingEnabled
                ? String(localized: "Evidence on", table: "Automation")
                : String(localized: "Evidence off", table: "Automation"),
            systemImage: state.semanticRecordingEnabled ? "film.stack.fill" : "film.stack",
            tint: Brand.libraryBlue
        )
    }

    private var permissionsReady: Bool {
        state.accessibilityGranted && state.inputMonitoringGranted && state.screenCaptureGranted
    }

    private var settingsSummaryText: String {
        let repeatText = state.loops <= 0
            ? String(localized: "continuous replay", table: "Common")
            : String(format: String(localized: "%d× replay", table: "Common"), state.loops)
        return String(
            format: String(localized: "%@ · %@ status UI", table: "Common"),
            repeatText,
            state.recordingHUDMode.title
        )
    }

    private func settingsStatusBadge(
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
        )
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
            if !inWindow {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(inWindow ? 18 : 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(inWindow ? 0.035 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("Granted", tableName: "Settings")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
            } else {
                Button(String(localized: "Grant…", table: "Settings")) { action() }
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
                    Text(LocalizedStringKey(presentation.title), tableName: "Common")
                        .font(.system(size: 11.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        controller.refreshSemanticRecordingPreflightPresentation()
                    } label: {
                        Label(String(localized: "Check", table: "Common"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))
                    .help(String(localized: "Check semantic recording permissions again", table: "Common"))
                }

                Text(LocalizedStringKey(presentation.summary), tableName: "Common")
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
                    Text("Visual evidence status has not been checked.", tableName: "Common")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        controller.refreshSemanticRecordingPreflightPresentation()
                    } label: {
                        Label(String(localized: "Check", table: "Common"), systemImage: "arrow.clockwise")
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
                Text("Keep visual evidence", tableName: "Common").font(.system(size: 11.5))
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
                    Text("When expired", tableName: "Common").font(.system(size: 11.5))
                    Spacer()
                    Picker("", selection: $state.semanticRecordingExpiredDisposition) {
                        Text("Delete evidence", tableName: "Common")
                            .tag(SemanticRecordingRetentionDisposition.pruneArtifacts)
                        Text("Delete bundle", tableName: "Common")
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
                    Label(String(localized: "Review cleanup", table: "Common"), systemImage: "trash")
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
            return String(localized: "Until I delete", table: "Common")
        case 1:
            return String(localized: "1 day", table: "Common")
        default:
            return String(format: String(localized: "%d days", table: "Common"), days)
        }
    }

    @ViewBuilder
    func semanticRecordingSuppressionPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy exclusions", tableName: "Common")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            semanticRecordingTextSettingRow(
                title: String(localized: "Apps", table: "Common"),
                placeholder: "com.example.Bank",
                text: $state.semanticRecordingExcludedApplicationBundleIDsText
            )
            semanticRecordingTextSettingRow(
                title: String(localized: "Windows", table: "Common"),
                placeholder: String(localized: "Private Checkout", table: "Common"),
                text: $state.semanticRecordingExcludedWindowTitleFragmentsText
            )
            semanticRecordingTextSettingRow(
                title: String(localized: "Domains", table: "Common"),
                placeholder: "bank.example.com",
                text: $state.semanticRecordingExcludedDomainsText
            )

            HStack {
                Text("Max artifact", tableName: "Common")
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
            return String(localized: "No limit", table: "Common")
        case 1024:
            return String(localized: "1 GB", table: "Common")
        default:
            return String(format: String(localized: "%d MB", table: "Common"), megabytes)
        }
    }

    func semanticRecordingRetentionCleanupConfirmationMessage() -> String {
        guard let preview = semanticRetentionCleanupPreview else {
            return ""
        }
        if preview.deleteBundleCount > 0 {
            return String(
                format: String(localized: "This will delete evidence from %d recording(s), including %d full bundle(s) and %d artifact reference(s). %d metadata file(s) stay listed for pruned recordings.", table: "Common"),
                preview.items.count,
                preview.deleteBundleCount,
                preview.artifactRefCount,
                preview.preservedMetadataFileCount
            )
        }
        return String(
            format: String(localized: "This will delete %d visual evidence artifact reference(s) from %d recording(s). %d metadata file(s) stay listed for history and explainability.", table: "Common"),
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
                state.statusMessage = String(localized: "No expired visual evidence to clean up.", table: "Common")
                return
            }
            semanticRetentionCleanupPreview = preview
            showSemanticRetentionCleanupConfirmation = true
            state.statusMessage = String(
                format: String(localized: "Found %d recording(s) with expired visual evidence.", table: "Common"),
                preview.items.count
            )
        } catch {
            state.statusMessage = String(
                format: String(localized: "Visual evidence cleanup check failed: %@", table: "Common"),
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
                format: String(localized: "Cleaned up %d artifact(s) and %d bundle(s).", table: "Common"),
                deletedArtifacts,
                deletedBundles
            )
        } catch {
            state.statusMessage = String(
                format: String(localized: "Visual evidence cleanup failed: %@", table: "Common"),
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
                Text(LocalizedStringKey(row.title), tableName: "Common")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(LocalizedStringKey(row.detail), tableName: "Common")
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
                Text(LocalizedStringKey(issue.title), tableName: "Common")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(LocalizedStringKey(issue.detail), tableName: "Common")
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
                Label(String(localized: "Open", table: "Common"), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(PillButtonStyle(tint: issue.severity == .blocking ? .red : .orange))
            .help(String(localized: String.LocalizationValue(issue.action.label), table: "Common"))
            .accessibilityLabel(String(localized: String.LocalizationValue(issue.action.label), table: "Common"))
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
                        state.statusMessage = String(localized: "That key is already assigned.", table: "Automation")
                        return
                    }
                    binding.wrappedValue = newValue
                }
            )) {
                ForEach(localOptions, id: \.self) { option in
                    Text(taken.contains(option.keyCode) ? String(format: String(localized: "%@ (in use)", table: "Common"), option.name) : option.name)
                        .tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }
}

private extension View {
    func settingsDescriptionStyle() -> some View {
        font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
