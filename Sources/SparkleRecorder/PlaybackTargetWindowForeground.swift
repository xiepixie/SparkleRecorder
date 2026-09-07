import AppKit
import ApplicationServices
import OSLog
import SparkleRecorderCore

@MainActor
enum PlaybackTargetWindowForeground {
    private static let logger = Logger(subsystem: "com.sparklerecorder.app", category: "PlaybackForeground")
    static func selectApplication(candidates: [NSRunningApplication], surfaces: [String: PlaybackSurface]) -> NSRunningApplication? {
        guard candidates.count > 1 else { return candidates.first }
        guard let surface = surfaces.sorted(by: { $0.key < $1.key }).first?.value else { return nil }
        let processes = Set(candidates.map(\.processIdentifier))
        let windows = WindowServerObservationAdapter.visibleWindows(onScreenOnly: false)
            .filter { processes.contains($0.processID) }
        guard let pid = PlaybackForegroundWindowVerification.targetProcessID(
            recordedFrame: surface.recordedFrame, recordedWindowID: surface.recordedWindowId, windows: windows) else { return nil }
        return candidates.first { $0.processIdentifier == pid }
    }

    static func prepare(app: NSRunningApplication, surfaces: [String: PlaybackSurface]) async -> Bool {
        guard let surface = surfaces.sorted(by: { $0.key < $1.key }).first?.value else { return false }
        let allWindows = WindowServerObservationAdapter.visibleWindows(onScreenOnly: false)
        let liveRecordedWindow = surface.recordedWindowId.flatMap { windowID in
            allWindows.first { $0.id == windowID && $0.processID == app.processIdentifier }
        }
        let expectedFrame = liveRecordedWindow?.frame ?? surface.recordedFrame
        let allowTitleFallback = liveRecordedWindow == nil
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        // Wake and activate before querying AX: hidden Chromium windows may
        // otherwise time out before an activation request is even issued.
        let handles = ForegroundWindowHandles(application: application)
        let handoff = PlaybackForegroundPreparation(request: {
            await MainActor.run {
                NSApp.yieldActivation(to: app)
                app.unhide()
                _ = app.activate(from: .current, options: [])
                if liveRecordedWindow != nil {
                    if handles.exactWindowCandidates.isEmpty {
                        handles.exactWindowCandidates = windowCandidates(
                            application: handles.application,
                            frame: expectedFrame
                        )
                        .filter { $0.distance < 8 }
                        .map(\.window)
                    }
                    if handles.target == nil || handles.shouldAdvanceExactCandidate {
                        handles.target = handles.nextExactCandidate()
                    }
                } else if handles.target == nil {
                    handles.target = matchingWindow(
                        application: handles.application,
                        surface: surface,
                        frame: expectedFrame,
                        allowTitleFallback: allowTitleFallback
                    )
                }
                guard let target = handles.target else { return }
                AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(handles.application, kAXFocusedWindowAttribute as CFString, target)
            }
        }, isReady: {
            await MainActor.run {
                guard app.isActive, let target = handles.target else {
                    guard let entry = surfaces.sorted(by: { $0.key < $1.key }).first else { return false }
                    let ready = PlaybackForegroundWindowVerification.isReady(active: app.isActive,
                        targetProcessID: app.processIdentifier, recordedFrame: entry.value.recordedFrame,
                        recordedWindowID: entry.value.recordedWindowId,
                        windows: WindowServerObservationAdapter.visibleWindows())
                    if ready { logger.notice("Foreground verified by window-server ordering") }
                    return ready
                }
                var focused: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(handles.application, kAXFocusedWindowAttribute as CFString, &focused)
                let matches = focused.map { CFEqual($0, target) } ?? false
                guard status == .success, matches else {
                    logger.notice("Foreground readiness: focusedStatus=\(status.rawValue, privacy: .public), matches=\(matches, privacy: .public)")
                    return false
                }
                if liveRecordedWindow != nil {
                    let ready = PlaybackForegroundWindowVerification.isReady(
                        active: app.isActive,
                        targetProcessID: app.processIdentifier,
                        recordedFrame: surface.recordedFrame,
                        recordedWindowID: surface.recordedWindowId,
                        windows: WindowServerObservationAdapter.visibleWindows()
                    )
                    if !ready {
                        handles.noteExactCandidateVerificationFailure()
                    }
                    return ready
                }
                // The recorded CGWindowID is no longer live. At this point AX has
                // already verified that the uniquely matched replacement window is
                // focused, so do not fail solely because the old window ID changed.
                return true
            }
        }, sleep: { try await Task.sleep(for: .milliseconds(100)) })
        return await handoff.prepare()
    }

    private static func windowCandidates(
        application: AXUIElement,
        frame: RectValue
    ) -> [ForegroundAXWindowCandidate] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard status == .success, let windows = value as? [AXUIElement] else {
            logger.notice("Window enumeration status=\(status.rawValue, privacy: .public)")
            return []
        }

        return windows.compactMap { window in
            AXUIElementSetMessagingTimeout(window, 0.3)
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)

            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue,
                  let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(),
                  CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
                return nil
            }

            var point = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }

            let distance = abs(point.x - frame.x) + abs(point.y - frame.y)
                + abs(size.width - frame.width) + abs(size.height - frame.height)
            return ForegroundAXWindowCandidate(
                window: window,
                title: titleValue as? String,
                distance: distance
            )
        }
    }

    private static func matchingWindow(
        application: AXUIElement,
        surface: PlaybackSurface,
        frame: RectValue,
        allowTitleFallback: Bool
    ) -> AXUIElement? {
        var best: AXUIElement?
        var bestScore = -Double.infinity
        var ambiguous = false
        for candidate in windowCandidates(application: application, frame: frame) {
            let titleMatches = candidate.title?.isEmpty == false && candidate.title == surface.windowTitle
            guard candidate.distance < 8 || (allowTitleFallback && titleMatches) else { continue }
            let score = (candidate.distance < 8 ? 10_000.0 : 0)
                + (titleMatches ? 1_000.0 : 0)
                - Double(candidate.distance)
            if score > bestScore {
                bestScore = score
                best = candidate.window
                ambiguous = false
            } else if abs(score - bestScore) < 0.001 {
                ambiguous = true
            }
        }
        return ambiguous ? nil : best
    }
}

private struct ForegroundAXWindowCandidate {
    let window: AXUIElement
    let title: String?
    let distance: CGFloat
}

@MainActor
private final class ForegroundWindowHandles {
    let application: AXUIElement
    var target: AXUIElement?
    var exactWindowCandidates: [AXUIElement] = []
    var shouldAdvanceExactCandidate = false
    private var nextExactCandidateIndex = 0
    private var exactCandidateVerificationFailures = 0

    init(application: AXUIElement) {
        self.application = application
    }

    func nextExactCandidate() -> AXUIElement? {
        guard !exactWindowCandidates.isEmpty else { return nil }
        let candidate = exactWindowCandidates[nextExactCandidateIndex % exactWindowCandidates.count]
        nextExactCandidateIndex += 1
        shouldAdvanceExactCandidate = false
        exactCandidateVerificationFailures = 0
        return candidate
    }

    func noteExactCandidateVerificationFailure() {
        exactCandidateVerificationFailures += 1
        if exactCandidateVerificationFailures >= 2 {
            shouldAdvanceExactCandidate = true
        }
    }
}
