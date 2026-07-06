import Foundation
import SwiftUI
import Combine
import ApplicationServices
import SparkleRecorderCore

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
    @Published var statusMessage: String = ""
    @Published var isRecording: Bool = false
    @Published var isPlaying: Bool = false
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
    /// Show floating recording HUD when recording.
    @Published var showRecordingHUD: Bool {
        didSet { UserDefaults.standard.set(showRecordingHUD, forKey: "showRecordingHUD") }
    }
    /// Whether to log unclicked mouse moves (can result in very large files).
    @Published var recordMouseMoves: Bool {
        didSet { UserDefaults.standard.set(recordMouseMoves, forKey: "recordMouseMoves") }
    }
    /// Experimental: pair playable macro events with video/keyframe semantic evidence.
    @Published var semanticRecordingEnabled: Bool {
        didSet { UserDefaults.standard.set(semanticRecordingEnabled, forKey: "semanticRecordingEnabled") }
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
        self.showRecordingHUD = d.object(forKey: "showRecordingHUD") as? Bool ?? true
        self.recordMouseMoves = d.object(forKey: "recordMouseMoves") as? Bool ?? false
        self.semanticRecordingEnabled = d.object(forKey: "semanticRecordingEnabled") as? Bool ?? false
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
        self.onboardingComplete = d.object(forKey: "onboardingComplete") as? Bool ?? false
        self.menuBarOnly = d.object(forKey: "menuBarOnly") as? Bool ?? false

        SoundController.shared.enabled = self.soundEnabled

        self.screenCaptureGranted = PermissionCenter.shared.checkScreenCaptureAccess() == .authorized
        refreshPermissions()

        // Poll permission state while the app is alive so the warning banner
        // disappears shortly after the user grants access in System Settings.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
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
}
