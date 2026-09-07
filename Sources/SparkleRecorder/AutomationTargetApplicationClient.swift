import AppKit
import Foundation
import os
import SparkleRecorderCore

struct AutomationTargetApplicationPreparationFailure: Error, Equatable, LocalizedError, Sendable {
    var message: String
    var session: AutomationTargetApplicationSession = .empty

    var errorDescription: String? { message }
}

struct AutomationRunLaunchedApplication: Equatable, Hashable, Sendable {
    var bundleIdentifier: String
    var processIdentifier: pid_t
}

struct AutomationTargetApplicationSession: Equatable, Sendable {
    var launchedApplications: Set<AutomationRunLaunchedApplication> = []

    static let empty = AutomationTargetApplicationSession()
}

extension AutomationTargetApplicationSession {
    func applicationsToQuit(
        under policy: AutomationTargetApplicationCleanupPolicy
    ) -> [AutomationRunLaunchedApplication] {
        guard policy == .quitIfLaunched else { return [] }
        return launchedApplications.sorted { lhs, rhs in
            lhs.processIdentifier < rhs.processIdentifier
        }
    }
}

struct AutomationTargetApplicationCleanupResult: Equatable, Sendable {
    var gracefullyTerminated: [pid_t] = []
    var forceTerminated: [pid_t] = []
    var unresolved: [pid_t] = []
}

struct AutomationApplicationProcessClient: Sendable {
    var terminate: @Sendable (pid_t) async -> Bool
    var forceTerminate: @Sendable (pid_t) async -> Bool
    var waitUntilTerminated: @Sendable (pid_t, TimeInterval) async -> Bool

    @MainActor
    static func live(pollInterval: TimeInterval = 0.2) -> Self {
        Self(
            terminate: { processIdentifier in
                NSRunningApplication(processIdentifier: processIdentifier)?.terminate() ?? true
            },
            forceTerminate: { processIdentifier in
                NSRunningApplication(processIdentifier: processIdentifier)?.forceTerminate() ?? true
            },
            waitUntilTerminated: { processIdentifier, timeout in
                let deadline = Date().addingTimeInterval(max(0, timeout))
                repeat {
                    guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
                        return true
                    }
                    if application.isTerminated { return true }
                    try? await Task.sleep(for: .seconds(pollInterval))
                } while Date() < deadline
                return NSRunningApplication(processIdentifier: processIdentifier)?.isTerminated ?? true
            }
        )
    }
}

struct AutomationTargetApplicationClient: Sendable {
    var prepare: @Sendable (
        _ surfaces: [String: PlaybackSurface],
        _ policy: AutomationTargetApplicationPolicy
    ) async -> Result<AutomationTargetApplicationSession, AutomationTargetApplicationPreparationFailure>
    var cleanup: @Sendable (
        _ session: AutomationTargetApplicationSession,
        _ policy: AutomationTargetApplicationCleanupPolicy,
        _ timeout: TimeInterval,
        _ forceQuitOnTimeout: Bool
    ) async -> AutomationTargetApplicationCleanupResult

    init(
        prepare: @escaping @Sendable (
            [String: PlaybackSurface],
            AutomationTargetApplicationPolicy
        ) async -> Result<AutomationTargetApplicationSession, AutomationTargetApplicationPreparationFailure>,
        cleanup: @escaping @Sendable (
            AutomationTargetApplicationSession,
            AutomationTargetApplicationCleanupPolicy,
            TimeInterval,
            Bool
        ) async -> AutomationTargetApplicationCleanupResult = { _, _, _, _ in .init() }
    ) {
        self.prepare = prepare
        self.cleanup = cleanup
    }

    static let noOp = AutomationTargetApplicationClient { _, _ in .success(.empty) }

    @MainActor
    static func live(
        windowTracker: WindowTracker?,
        launchTimeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.2,
        processClient: AutomationApplicationProcessClient? = nil
    ) -> AutomationTargetApplicationClient {
        let processClient = processClient ?? .live(pollInterval: pollInterval)
        return AutomationTargetApplicationClient(prepare: { surfaces, policy in
            await prepareLive(
                surfaces: surfaces,
                policy: policy,
                windowTracker: windowTracker,
                launchTimeout: launchTimeout,
                pollInterval: pollInterval
            )
        }, cleanup: { session, policy, timeout, forceQuitOnTimeout in
            await cleanupLive(
                session: session,
                policy: policy,
                timeout: timeout,
                forceQuitOnTimeout: forceQuitOnTimeout,
                processClient: processClient
            )
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
                localized: "The target window does not identify an application to open.",
                table: "Automation"
            )))
        }

        var launchedApplications = Set<AutomationRunLaunchedApplication>()
        for bundleIdentifier in bundleIdentifiers {
            let entries = grouped[bundleIdentifier] ?? []
            let appName = entries.compactMap(\.value.appName).first ?? bundleIdentifier
            let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            var app = PlaybackTargetWindowForeground.selectApplication(candidates: candidates,
                surfaces: Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) }))
            if !candidates.isEmpty, app == nil {
                return .failure(.init(message: String(
                    format: String(localized: "Could not find the target window for %@. Open it, or choose a different target window for this macro, then try again. No actions were run.", table: "Automation"), appName
                ), session: .init(launchedApplications: launchedApplications)))
            }

            if app == nil, policy == .launchIfNeeded {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                    return .failure(.init(message: String(
                        format: String(localized: "Could not find the target application %@.", table: "Automation"),
                        appName
                    )))
                }
                NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleIdentifier)
                guard NSWorkspace.shared.open(appURL) else {
                    return .failure(.init(message: String(
                        format: String(localized: "Could not open the target application %@.", table: "Automation"),
                        appName
                    )))
                }
                app = await waitForApplication(
                    bundleIdentifier: bundleIdentifier,
                    timeout: launchTimeout,
                    pollInterval: pollInterval
                )
                guard app != nil else {
                    return .failure(.init(message: String(
                        format: String(localized: "Timed out while opening the target application %@.", table: "Automation"),
                        appName
                    )))
                }
                if let app {
                    launchedApplications.insert(.init(
                        bundleIdentifier: bundleIdentifier,
                        processIdentifier: app.processIdentifier
                    ))
                }
            }

            guard let app else {
                continue
            }
            guard await PlaybackTargetWindowForeground.prepare(app: app,
                surfaces: Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })) else {
                return .failure(.init(message: String(
                    format: String(localized: "Could not find the target window for %@. Open it, or choose a different target window for this macro, then try again. No actions were run.", table: "Automation"), appName
                ), session: .init(launchedApplications: launchedApplications)))
            }

            if policy == .launchIfNeeded, let windowTracker {
                let didFindWindow = await waitForWindow(
                    entries: entries,
                    windowTracker: windowTracker,
                    timeout: launchTimeout,
                    pollInterval: pollInterval
                )
                if !didFindWindow {
                    return .failure(.init(message: String(
                        format: String(localized: "The target window for %@ did not appear in time.", table: "Automation"),
                        appName
                    ), session: .init(launchedApplications: launchedApplications)))
                }
            }
        }
        return .success(AutomationTargetApplicationSession(
            launchedApplications: launchedApplications
        ))
    }

    private static func cleanupLive(
        session: AutomationTargetApplicationSession,
        policy: AutomationTargetApplicationCleanupPolicy,
        timeout: TimeInterval,
        forceQuitOnTimeout: Bool,
        processClient: AutomationApplicationProcessClient
    ) async -> AutomationTargetApplicationCleanupResult {
        let logger = Logger(subsystem: "com.sparklerecorder.app", category: "ScheduledAppCleanup")
        var result = AutomationTargetApplicationCleanupResult()
        for application in session.applicationsToQuit(under: policy) {
            let pid = application.processIdentifier
            let accepted = await processClient.terminate(pid)
            logger.info("Requested graceful termination for pid=\(pid, privacy: .public), accepted=\(accepted, privacy: .public)")
            if await processClient.waitUntilTerminated(pid, timeout) {
                result.gracefullyTerminated.append(pid)
                continue
            }
            guard forceQuitOnTimeout else {
                result.unresolved.append(pid)
                logger.error("Graceful termination timed out for pid=\(pid, privacy: .public)")
                continue
            }
            let forceAccepted = await processClient.forceTerminate(pid)
            logger.notice("Requested force termination for pid=\(pid, privacy: .public), accepted=\(forceAccepted, privacy: .public)")
            if await processClient.waitUntilTerminated(pid, 2) {
                result.forceTerminated.append(pid)
            } else {
                result.unresolved.append(pid)
                logger.error("Force termination did not resolve pid=\(pid, privacy: .public)")
            }
        }
        return result
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

    static func allRequiredSurfacesResolved(
        required: [String: PlaybackSurface],
        resolvedFrames: [String: RectValue]
    ) -> Bool {
        required.keys.allSatisfy { resolvedFrames[$0] != nil }
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
            let resolvedFrames = windowTracker.resolveCurrentFrames(for: surfaces)
            if allRequiredSurfacesResolved(required: surfaces, resolvedFrames: resolvedFrames) {
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
