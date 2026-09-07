import Foundation
import SwiftUI
import Combine
import ApplicationServices
import SparkleRecorderCore

enum SemanticRecordingCaptureScope: String, CaseIterable, Identifiable, Hashable {
    case frontmostWindow
    case display

    var id: String { rawValue }
}

enum RecordingHUDMode: String, CaseIterable, Identifiable {
    case compact
    case expanded
    case menuBar

    var id: String { rawValue }

    var showsFloatingPanel: Bool {
        self != .menuBar
    }

    var title: String {
        switch self {
        case .compact:
            return String(localized: "Compact", table: "Common")
        case .expanded:
            return String(localized: "Expanded", table: "Common")
        case .menuBar:
            return String(localized: "Menu bar", table: "Common")
        }
    }
}

struct AutomationWorkspaceDestination: Equatable {
    var workflowID: UUID
    var taskID: UUID?
}

/// User-configurable settings persisted in UserDefaults.
@MainActor
final class AppState: ObservableObject {
    @Published var loops: Int {
        didSet { UserDefaults.standard.set(loops, forKey: "loops") }
    }
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "speed") }
    }
    @Published var recordHotkey: HotkeyBinding {
        didSet { persist(recordHotkey, key: "hk_record") }
    }
    @Published var stopHotkey: HotkeyBinding {
        didSet { persist(stopHotkey, key: "hk_stop") }
    }
    @Published var playHotkey: HotkeyBinding {
        didSet { persist(playHotkey, key: "hk_play") }
    }
    @Published private(set) var statusFeedback: AppStatusFeedback?
    /// Presentation projection owned by MenuBarController. Windows render this as
    /// read-only/disabled while recording, playback, or screen picking owns input.
    @Published private(set) var appInteractionLocked = false

    func setAppInteractionLocked(_ locked: Bool) {
        if appInteractionLocked != locked {
            appInteractionLocked = locked
        }
    }

    func presentStatus(
        _ message: String,
        tone: AppStatusFeedback.Tone = .info,
        dismissAfter: TimeInterval? = nil
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusFeedback = nil
            return
        }
        statusFeedback = AppStatusFeedback(
            message: trimmed,
            tone: tone,
            dismissAfter: dismissAfter
        )
    }

    func dismissStatus(_ id: UUID? = nil) {
        guard id == nil || statusFeedback?.id == id else { return }
        statusFeedback = nil
    }
    @Published var isRecording: Bool = false
    /// True from the moment a recording request begins through preflight/countdown
    /// and the live recording itself. This lets callers distinguish a cancelled
    /// recording attempt from an unrelated later recording.
    @Published var recordingFlowActive: Bool = false
    /// True after live input stops while visual evidence, redaction, and its
    /// macro attachment are still being finalized. App windows and new input
    /// sessions stay locked until this completes.
    @Published var recordingFinalizationActive: Bool = false
    /// True while user-initiated playback owns or is preparing the foreground
    /// input target, including preflight before Player.isPlaying becomes true.
    @Published var playbackFlowActive: Bool = false
    @Published var isPlaying: Bool = false
    /// The product surface currently shown in the main window.
    @Published var workspace: WorkspaceMode = .library
    /// One-shot selection used when Library creates or opens a specific automation.
    @Published var automationWorkspaceDestination: AutomationWorkspaceDestination?
    @Published var accessibilityGranted: Bool = AXIsProcessTrusted()
    /// Input Monitoring is a separate TCC permission from Accessibility; both are
    /// required to record. Polled live alongside Accessibility so the UI reflects
    /// grants made in System Settings without a relaunch.
    @Published var inputMonitoringGranted: Bool = false
    @Published var screenCaptureGranted: Bool = false

    /// Pre-record countdown seconds. 0 disables.
    @Published var countdownSeconds: Int {
        didSet { UserDefaults.standard.set(countdownSeconds, forKey: "countdownSeconds") }
    }
    /// Optional sound feedback on record/stop/play.
    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
            SoundController.shared.enabled = soundEnabled
        }
    }
    /// How much recording status UI should float over the user's work area.
    @Published var recordingHUDMode: RecordingHUDMode {
        didSet {
            UserDefaults.standard.set(recordingHUDMode.rawValue, forKey: Self.recordingHUDModeKey)
        }
    }
    /// Whether to log unclicked mouse moves (can result in very large files).
    @Published var recordMouseMoves: Bool {
        didSet { UserDefaults.standard.set(recordMouseMoves, forKey: "recordMouseMoves") }
    }
    /// Pair playable macro events with local video/keyframe semantic evidence.
    @Published var semanticRecordingEnabled: Bool {
        didSet { UserDefaults.standard.set(semanticRecordingEnabled, forKey: "semanticRecordingEnabled") }
    }
    @Published var semanticRecordingCaptureMode: RecordingCaptureMode {
        didSet {
            UserDefaults.standard.set(
                semanticRecordingCaptureMode.rawValue,
                forKey: Self.semanticRecordingCaptureModeKey
            )
        }
    }
    @Published var semanticRecordingCaptureScope: SemanticRecordingCaptureScope {
        didSet {
            UserDefaults.standard.set(
                semanticRecordingCaptureScope.rawValue,
                forKey: Self.semanticRecordingCaptureScopeKey
            )
        }
    }

    var semanticRecordingCapturePolicy: RecordingCapturePolicy {
        RecordingCapturePolicy(mode: semanticRecordingCaptureMode)
    }
    @Published var semanticRecordingRetentionMaximumArtifactAgeDays: Int {
        didSet {
            UserDefaults.standard.set(
                max(0, semanticRecordingRetentionMaximumArtifactAgeDays),
                forKey: "semanticRecordingRetentionMaximumArtifactAgeDays"
            )
        }
    }
    @Published var semanticRecordingExpiredDisposition: SemanticRecordingRetentionDisposition {
        didSet {
            UserDefaults.standard.set(
                semanticRecordingExpiredDisposition.rawValue,
                forKey: "semanticRecordingExpiredDisposition"
            )
        }
    }
    @Published var semanticRecordingExcludedApplicationBundleIDsText: String {
        didSet { persistSemanticRecordingSuppressionSettings() }
    }
    @Published var semanticRecordingExcludedWindowTitleFragmentsText: String {
        didSet { persistSemanticRecordingSuppressionSettings() }
    }
    @Published var semanticRecordingExcludedDomainsText: String {
        didSet { persistSemanticRecordingSuppressionSettings() }
    }
    @Published var semanticRecordingMaximumArtifactMegabytes: Int {
        didSet { persistSemanticRecordingSuppressionSettings() }
    }
    @Published var semanticRecordingLastScheduledRetentionCleanupAt: Date? {
        didSet {
            if let semanticRecordingLastScheduledRetentionCleanupAt {
                UserDefaults.standard.set(
                    semanticRecordingLastScheduledRetentionCleanupAt,
                    forKey: Self.semanticRecordingLastScheduledRetentionCleanupAtKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: Self.semanticRecordingLastScheduledRetentionCleanupAtKey
                )
            }
        }
    }
    @Published var automationRunSuccessEvidenceAgeDays: Int {
        didSet { UserDefaults.standard.set(max(0, automationRunSuccessEvidenceAgeDays), forKey: Self.automationRunSuccessEvidenceAgeDaysKey) }
    }
    @Published var automationRunAttentionEvidenceAgeDays: Int {
        didSet { UserDefaults.standard.set(max(0, automationRunAttentionEvidenceAgeDays), forKey: Self.automationRunAttentionEvidenceAgeDaysKey) }
    }
    @Published var automationRunMetadataAgeDays: Int {
        didSet { UserDefaults.standard.set(max(0, automationRunMetadataAgeDays), forKey: Self.automationRunMetadataAgeDaysKey) }
    }
    @Published var automationRunCaptureScreenshots: Bool {
        didSet { UserDefaults.standard.set(automationRunCaptureScreenshots, forKey: Self.automationRunCaptureScreenshotsKey) }
    }
    @Published var automationRunAutomaticCleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(automationRunAutomaticCleanupEnabled, forKey: Self.automationRunAutomaticCleanupEnabledKey) }
    }
    @Published var automationRunLastScheduledRetentionCleanupAt: Date? {
        didSet {
            if let automationRunLastScheduledRetentionCleanupAt {
                UserDefaults.standard.set(automationRunLastScheduledRetentionCleanupAt, forKey: Self.automationRunLastScheduledRetentionCleanupAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.automationRunLastScheduledRetentionCleanupAtKey)
            }
        }
    }
    @Published var automationRunLastCleanupEvidenceCount: Int {
        didSet { UserDefaults.standard.set(max(0, automationRunLastCleanupEvidenceCount), forKey: Self.automationRunLastCleanupEvidenceCountKey) }
    }
    @Published var automationRunLastCleanupHistoryCount: Int {
        didSet { UserDefaults.standard.set(max(0, automationRunLastCleanupHistoryCount), forKey: Self.automationRunLastCleanupHistoryCountKey) }
    }
    @Published var automationRunLastCleanupFreedByteCount: Int64 {
        didSet { UserDefaults.standard.set(max(0, automationRunLastCleanupFreedByteCount), forKey: Self.automationRunLastCleanupFreedByteCountKey) }
    }
    @Published var semanticRecordingPreflightPresentation: SemanticRecordingPreflightPresentation?
    /// Has the user finished onboarding?
    @Published var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: "onboardingComplete") }
    }
    /// When true, the app runs menu-bar-only (no Dock icon, `.accessory`);
    /// when false it's a full Dock app (`.regular`).
    @Published var menuBarOnly: Bool {
        didSet { UserDefaults.standard.set(menuBarOnly, forKey: "menuBarOnly") }
    }

    private var refreshTimer: Timer?

    init() {
        let d = UserDefaults.standard
        self.loops = d.object(forKey: "loops") as? Int ?? 1
        self.speed = d.object(forKey: "speed") as? Double ?? 1.0
        self.recordHotkey = AppState.load(key: "hk_record")
            ?? HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048)
        self.stopHotkey = AppState.load(key: "hk_stop")
            ?? HotkeyBinding(keyCode: 1, name: "⌥S", modifiers: 2048)
        self.playHotkey = AppState.load(key: "hk_play")
            ?? HotkeyBinding(keyCode: 35, name: "⌥P", modifiers: 2048)

        self.countdownSeconds = d.object(forKey: "countdownSeconds") as? Int ?? 3
        self.soundEnabled = d.object(forKey: "soundEnabled") as? Bool ?? false
        if let rawHUDMode = d.string(forKey: Self.recordingHUDModeKey),
           let hudMode = RecordingHUDMode(rawValue: rawHUDMode) {
            self.recordingHUDMode = hudMode
        } else {
            let legacyShowsHUD = d.object(forKey: "showRecordingHUD") as? Bool ?? true
            let migratedHUDMode: RecordingHUDMode = legacyShowsHUD ? .compact : .menuBar
            self.recordingHUDMode = migratedHUDMode
            d.set(migratedHUDMode.rawValue, forKey: Self.recordingHUDModeKey)
        }
        // One-way migration: once the enum-backed preference exists, stop keeping
        // the old boolean key alive. Future mode changes only write the new key.
        d.removeObject(forKey: "showRecordingHUD")
        self.recordMouseMoves = d.object(forKey: "recordMouseMoves") as? Bool ?? false
        self.semanticRecordingEnabled = d.object(forKey: "semanticRecordingEnabled") as? Bool ?? false
        self.semanticRecordingCaptureMode = RecordingCaptureMode(
            rawValue: d.string(forKey: Self.semanticRecordingCaptureModeKey) ?? ""
        ) ?? .videoAndKeyframes
        self.semanticRecordingCaptureScope = SemanticRecordingCaptureScope(
            rawValue: d.string(forKey: Self.semanticRecordingCaptureScopeKey) ?? ""
        ) ?? .frontmostWindow
        self.semanticRecordingRetentionMaximumArtifactAgeDays = max(
            0,
            d.object(forKey: "semanticRecordingRetentionMaximumArtifactAgeDays") as? Int
                ?? SemanticRecordingRetentionSettings.defaultMaximumArtifactAgeDays
        )
        self.semanticRecordingExpiredDisposition = SemanticRecordingRetentionDisposition(
            rawValue: d.string(forKey: "semanticRecordingExpiredDisposition") ?? ""
        ) ?? .pruneArtifacts
        let suppressionSettings = SemanticRecordingSuppressionSettings(
            excludedApplicationBundleIDs: d.stringArray(
                forKey: Self.semanticRecordingExcludedApplicationBundleIDsKey
            ) ?? [],
            excludedWindowTitleFragments: d.stringArray(
                forKey: Self.semanticRecordingExcludedWindowTitleFragmentsKey
            ) ?? [],
            excludedDomains: d.stringArray(
                forKey: Self.semanticRecordingExcludedDomainsKey
            ) ?? [],
            maximumArtifactByteCount: d.object(
                forKey: Self.semanticRecordingMaximumArtifactByteCountKey
            ) as? Int
        )
        self.semanticRecordingExcludedApplicationBundleIDsText = SemanticRecordingSuppressionSettings
            .listText(suppressionSettings.excludedApplicationBundleIDs)
        self.semanticRecordingExcludedWindowTitleFragmentsText = SemanticRecordingSuppressionSettings
            .listText(suppressionSettings.excludedWindowTitleFragments)
        self.semanticRecordingExcludedDomainsText = SemanticRecordingSuppressionSettings
            .listText(suppressionSettings.excludedDomains)
        if let maximumArtifactByteCount = suppressionSettings.maximumArtifactByteCount {
            self.semanticRecordingMaximumArtifactMegabytes = max(
                1,
                Int(ceil(Double(maximumArtifactByteCount) / Double(Self.bytesPerMegabyte)))
            )
        } else {
            self.semanticRecordingMaximumArtifactMegabytes = 0
        }
        self.semanticRecordingLastScheduledRetentionCleanupAt = d.object(
            forKey: Self.semanticRecordingLastScheduledRetentionCleanupAtKey
        ) as? Date
        self.automationRunSuccessEvidenceAgeDays = max(
            0,
            d.object(forKey: Self.automationRunSuccessEvidenceAgeDaysKey) as? Int
                ?? AutomationRunRetentionSettings.defaultSuccessEvidenceAgeDays
        )
        self.automationRunAttentionEvidenceAgeDays = max(
            0,
            d.object(forKey: Self.automationRunAttentionEvidenceAgeDaysKey) as? Int
                ?? AutomationRunRetentionSettings.defaultAttentionEvidenceAgeDays
        )
        self.automationRunMetadataAgeDays = max(
            0,
            d.object(forKey: Self.automationRunMetadataAgeDaysKey) as? Int
                ?? AutomationRunRetentionSettings.defaultMetadataAgeDays
        )
        self.automationRunCaptureScreenshots = d.object(forKey: Self.automationRunCaptureScreenshotsKey) as? Bool ?? true
        self.automationRunAutomaticCleanupEnabled = d.object(forKey: Self.automationRunAutomaticCleanupEnabledKey) as? Bool ?? true
        self.automationRunLastScheduledRetentionCleanupAt = d.object(
            forKey: Self.automationRunLastScheduledRetentionCleanupAtKey
        ) as? Date
        self.automationRunLastCleanupEvidenceCount = max(
            0,
            d.object(forKey: Self.automationRunLastCleanupEvidenceCountKey) as? Int ?? 0
        )
        self.automationRunLastCleanupHistoryCount = max(
            0,
            d.object(forKey: Self.automationRunLastCleanupHistoryCountKey) as? Int ?? 0
        )
        self.automationRunLastCleanupFreedByteCount = max(
            0,
            d.object(forKey: Self.automationRunLastCleanupFreedByteCountKey) as? Int64 ?? 0
        )
        self.onboardingComplete = d.object(forKey: "onboardingComplete") as? Bool ?? false
        self.menuBarOnly = d.object(forKey: "menuBarOnly") as? Bool ?? false

        SoundController.shared.enabled = self.soundEnabled

        self.screenCaptureGranted = PermissionCenter.shared.checkScreenCaptureAccess() == .authorized
        refreshPermissions()

        // Poll only while access is missing. AppDelegate also refreshes when the
        // app becomes active, so fully authorized idle sessions avoid TCC IPC.
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.needsPermissionRefresh else { return }
                self.refreshPermissions()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    deinit {
        MainActor.assumeIsolated {
            refreshTimer?.invalidate()
        }
    }

    func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
        }

        let inputOK = PermissionCenter.shared.checkListenEventAccess() == .authorized
        if inputOK != inputMonitoringGranted {
            inputMonitoringGranted = inputOK
        }

        let screenOK = PermissionCenter.shared.checkScreenCaptureAccess() == .authorized
        if screenOK != screenCaptureGranted {
            screenCaptureGranted = screenOK
        }
    }

    var recordingPermissionReadiness: RecordingPermissionReadiness {
        RecordingPermissionReadiness(
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted,
            screenCaptureGranted: screenCaptureGranted,
            visualEvidenceEnabled: semanticRecordingEnabled
        )
    }

    var coreRecordingPermissionsGranted: Bool {
        recordingPermissionReadiness.canRecordAndReplay
    }

    var requiredPermissionsGranted: Bool {
        recordingPermissionReadiness.allEnabledFeaturesReady
    }

    private var needsPermissionRefresh: Bool {
        isRecording || !requiredPermissionsGranted
    }

    var semanticRecordingRetentionSettings: SemanticRecordingRetentionSettings {
        SemanticRecordingRetentionSettings(
            maximumArtifactAgeDays: semanticRecordingRetentionMaximumArtifactAgeDays,
            expiredDisposition: semanticRecordingExpiredDisposition
        )
    }

    var semanticRecordingSuppressionSettings: SemanticRecordingSuppressionSettings {
        SemanticRecordingSuppressionSettings(
            excludedApplicationBundleIDs: SemanticRecordingSuppressionSettings.parseListText(
                semanticRecordingExcludedApplicationBundleIDsText
            ),
            excludedWindowTitleFragments: SemanticRecordingSuppressionSettings.parseListText(
                semanticRecordingExcludedWindowTitleFragmentsText
            ),
            excludedDomains: SemanticRecordingSuppressionSettings.parseListText(
                semanticRecordingExcludedDomainsText
            ),
            maximumArtifactByteCount: semanticRecordingMaximumArtifactMegabytes > 0
                ? semanticRecordingMaximumArtifactMegabytes * Self.bytesPerMegabyte
                : nil
        )
    }

    var automationRunRetentionSettings: AutomationRunRetentionSettings {
        AutomationRunRetentionSettings(
            successEvidenceAgeDays: automationRunSuccessEvidenceAgeDays,
            attentionEvidenceAgeDays: automationRunAttentionEvidenceAgeDays,
            metadataAgeDays: automationRunMetadataAgeDays
        )
    }

    private func persistSemanticRecordingSuppressionSettings() {
        let settings = semanticRecordingSuppressionSettings
        UserDefaults.standard.set(
            settings.excludedApplicationBundleIDs,
            forKey: Self.semanticRecordingExcludedApplicationBundleIDsKey
        )
        UserDefaults.standard.set(
            settings.excludedWindowTitleFragments,
            forKey: Self.semanticRecordingExcludedWindowTitleFragmentsKey
        )
        UserDefaults.standard.set(
            settings.excludedDomains,
            forKey: Self.semanticRecordingExcludedDomainsKey
        )
        if let maximumArtifactByteCount = settings.maximumArtifactByteCount {
            UserDefaults.standard.set(
                maximumArtifactByteCount,
                forKey: Self.semanticRecordingMaximumArtifactByteCountKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: Self.semanticRecordingMaximumArtifactByteCountKey
            )
        }
    }

    private func persist(_ binding: HotkeyBinding, key: String) {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load(key: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let b = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else {
            return nil
        }
        return b
    }

    private static let bytesPerMegabyte = 1_048_576
    private static let semanticRecordingExcludedApplicationBundleIDsKey = "semanticRecordingExcludedApplicationBundleIDs"
    private static let semanticRecordingExcludedWindowTitleFragmentsKey = "semanticRecordingExcludedWindowTitleFragments"
    private static let semanticRecordingExcludedDomainsKey = "semanticRecordingExcludedDomains"
    private static let semanticRecordingMaximumArtifactByteCountKey = "semanticRecordingMaximumArtifactByteCount"
    private static let semanticRecordingLastScheduledRetentionCleanupAtKey = "semanticRecordingLastScheduledRetentionCleanupAt"
    private static let automationRunSuccessEvidenceAgeDaysKey = "automationRunSuccessEvidenceAgeDays"
    private static let automationRunAttentionEvidenceAgeDaysKey = "automationRunAttentionEvidenceAgeDays"
    private static let automationRunMetadataAgeDaysKey = "automationRunMetadataAgeDays"
    private static let automationRunCaptureScreenshotsKey = "automationRunCaptureScreenshots"
    private static let automationRunAutomaticCleanupEnabledKey = "automationRunAutomaticCleanupEnabled"
    private static let automationRunLastScheduledRetentionCleanupAtKey = "automationRunLastScheduledRetentionCleanupAt"
    private static let automationRunLastCleanupEvidenceCountKey = "automationRunLastCleanupEvidenceCount"
    private static let automationRunLastCleanupHistoryCountKey = "automationRunLastCleanupHistoryCount"
    private static let automationRunLastCleanupFreedByteCountKey = "automationRunLastCleanupFreedByteCount"
    private static let recordingHUDModeKey = "recordingHUDMode"
    private static let semanticRecordingCaptureModeKey = "semanticRecordingCaptureMode"
    private static let semanticRecordingCaptureScopeKey = "semanticRecordingCaptureScope"
}
