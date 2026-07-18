import AppKit
import Foundation
import SparkleRecorderCore

struct AutomationTargetApplicationPreparationFailure: Error, Equatable, LocalizedError, Sendable {
    var message: String

    var errorDescription: String? { message }
}

struct AutomationTargetApplicationSession: Equatable, Sendable {
    var launchedBundleIdentifiers: Set<String> = []

    static let empty = AutomationTargetApplicationSession()
}

extension AutomationTargetApplicationSession {
    func bundleIdentifiersToQuit(
        under policy: AutomationTargetApplicationCleanupPolicy
    ) -> [String] {
        guard policy == .quitIfLaunched else { return [] }
        return launchedBundleIdentifiers.sorted()
    }
}

struct AutomationTargetApplicationClient: Sendable {
    var prepare: @Sendable (
        _ surfaces: [String: PlaybackSurface],
        _ policy: AutomationTargetApplicationPolicy
    ) async -> Result<AutomationTargetApplicationSession, AutomationTargetApplicationPreparationFailure>
    var cleanup: @Sendable (
        _ session: AutomationTargetApplicationSession,
        _ policy: AutomationTargetApplicationCleanupPolicy
    ) async -> Void

    init(
        prepare: @escaping @Sendable (
            [String: PlaybackSurface],
            AutomationTargetApplicationPolicy
        ) async -> Result<AutomationTargetApplicationSession, AutomationTargetApplicationPreparationFailure>,
        cleanup: @escaping @Sendable (
            AutomationTargetApplicationSession,
            AutomationTargetApplicationCleanupPolicy
        ) async -> Void = { _, _ in }
    ) {
        self.prepare = prepare
        self.cleanup = cleanup
    }

    static let noOp = AutomationTargetApplicationClient { _, _ in .success(.empty) }

    @MainActor
    static func live(
        windowTracker: WindowTracker?,
        launchTimeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.2
    ) -> AutomationTargetApplicationClient {
        AutomationTargetApplicationClient(prepare: { surfaces, policy in
            await prepareLive(
                surfaces: surfaces,
                policy: policy,
                windowTracker: windowTracker,
                launchTimeout: launchTimeout,
                pollInterval: pollInterval
            )
        }, cleanup: { session, policy in
            for bundleIdentifier in session.bundleIdentifiersToQuit(under: policy) {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                    .forEach { $0.terminate() }
            }
        })
    }

    @MainActor
    private static func prepareLive(
        surfaces: [String: PlaybackSurface],
        policy: AutomationTargetApplicationPolicy,
        windowTracker: WindowTracker?,
        launchTimeout: TimeInterval,
        pollInterval: TimeInterval
    ) async -> Result<AutomationTargetApplicationSession, AutomationTargetApplicationPreparationFailure> {
        guard policy != .doNotActivate, !surfaces.isEmpty else {
            return .success(.empty)
        }

        let grouped = Dictionary(grouping: surfaces) { entry in
            entry.value.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let bundleIdentifiers = grouped.keys.filter { !$0.isEmpty }.sorted()
        if policy == .launchIfNeeded, bundleIdentifiers.isEmpty {
            return .failure(.init(message: String(
                localized: "The bound window does not identify an application to open.",
                table: "Automation"
            )))
        }

        var launchedBundleIdentifiers = Set<String>()
        for bundleIdentifier in bundleIdentifiers {
            let entries = grouped[bundleIdentifier] ?? []
            let appName = entries.compactMap(\.value.appName).first ?? bundleIdentifier
            var app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first

            if app == nil, policy == .launchIfNeeded {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                    return .failure(.init(message: String(
                        format: String(localized: "Could not find the bound application %@.", table: "Automation"),
                        appName
                    )))
                }
                guard NSWorkspace.shared.open(appURL) else {
                    return .failure(.init(message: String(
                        format: String(localized: "Could not open the bound application %@.", table: "Automation"),
                        appName
                    )))
                }
                launchedBundleIdentifiers.insert(bundleIdentifier)
                app = await waitForApplication(
                    bundleIdentifier: bundleIdentifier,
                    timeout: launchTimeout,
                    pollInterval: pollInterval
                )
                guard app != nil else {
                    return .failure(.init(message: String(
                        format: String(localized: "Timed out while opening the bound application %@.", table: "Automation"),
                        appName
                    )))
                }
            }

            guard let app else {
                continue
            }
            app.activate()

            if policy == .launchIfNeeded, let windowTracker {
                let didFindWindow = await waitForWindow(
                    entries: entries,
                    windowTracker: windowTracker,
                    timeout: launchTimeout,
                    pollInterval: pollInterval
                )
                if !didFindWindow {
                    return .failure(.init(message: String(
                        format: String(localized: "The bound window for %@ did not appear in time.", table: "Automation"),
                        appName
                    )))
                }
            }
        }
        return .success(AutomationTargetApplicationSession(
            launchedBundleIdentifiers: launchedBundleIdentifiers
        ))
    }

    @MainActor
    private static func waitForApplication(
        bundleIdentifier: String,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return app
            }
            await sleep(pollInterval)
        } while Date() < deadline
        return nil
    }

    @MainActor
    private static func waitForWindow(
        entries: [(key: String, value: PlaybackSurface)],
        windowTracker: WindowTracker,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async -> Bool {
        let surfaces = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if !windowTracker.resolveCurrentFrames(for: surfaces).isEmpty {
                return true
            }
            await sleep(pollInterval)
        } while Date() < deadline
        return false
    }

    private static func sleep(_ interval: TimeInterval) async {
        let nanoseconds = UInt64(max(0.01, interval) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
