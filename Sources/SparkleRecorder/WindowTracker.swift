import Cocoa
import ApplicationServices
import SparkleRecorderCore

public final class WindowTracker: Sendable {
    public init() {}

    public func resolveCurrentFrames(for surfaces: [String: PlaybackSurface]) -> [String: RectValue] {
        resolveCurrentWindows(for: surfaces).mapValues(\.frame)
    }

    /// Resolves the concrete WindowServer window as well as its frame. Callers
    /// that need AX/content geometry must use this owner PID instead of choosing
    /// an arbitrary process from a multi-process application bundle.
    public func resolveCurrentWindows(
        for surfaces: [String: PlaybackSurface]
    ) -> [String: PlaybackForegroundWindowObservation] {
        var windows: [String: PlaybackForegroundWindowObservation] = [:]
        
        let workspace = NSWorkspace.shared
        
        guard let winInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return windows
        }
        
        for (surfaceId, recordedSurface) in surfaces {
            guard let bid = recordedSurface.bundleIdentifier else { continue }
            
            // Find running apps for this bundle identifier
            let apps = workspace.runningApplications.filter { $0.bundleIdentifier == bid }
            let pids = Set(apps.map { $0.processIdentifier })
            
            var bestMatch: PlaybackForegroundWindowObservation?
            var bestScore = -1
            
            for winInfo in winInfoList {
                guard let winPid = winInfo[kCGWindowOwnerPID as String] as? Int32,
                      pids.contains(winPid) else {
                    continue
                }
                
                // Exclude system elements, non-standard window layers
                let layer = winInfo[kCGWindowLayer as String] as? Int32 ?? 0
                guard layer == 0 else { continue }
                
                guard let windowID = winInfo[kCGWindowNumber as String] as? CGWindowID,
                      let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                      let bx = boundsDict["X"] as? CGFloat,
                      let by = boundsDict["Y"] as? CGFloat,
                      let bw = boundsDict["Width"] as? CGFloat,
                      let bh = boundsDict["Height"] as? CGFloat else {
                    continue
                }
                
                var score = 100 // Matches bundle ID
                
                // 1. Title matching
                if let title = winInfo[kCGWindowName as String] as? String {
                    if title == recordedSurface.windowTitle {
                        score += 80
                    } else if let pattern = recordedSurface.windowTitlePattern,
                              let regex = try? NSRegularExpression(pattern: pattern),
                              regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                        score += 80
                    }
                }
                
                // 2. Size similarity
                let dw = abs(bw - recordedSurface.recordedFrame.width)
                let dh = abs(bh - recordedSurface.recordedFrame.height)
                if dw < 10 && dh < 10 {
                    score += 40
                } else if dw < 50 && dh < 50 {
                    score += 20
                }
                
                // 3. Display ID matching
                let centerPt = CGPoint(x: bx + bw / 2, y: by + bh / 2)
                var displayCount: UInt32 = 0
                var displays = [CGDirectDisplayID](repeating: 0, count: 1)
                if CGGetDisplaysWithPoint(centerPt, 1, &displays, &displayCount) == .success, displayCount > 0 {
                    if displays[0] == recordedSurface.recordedDisplayId {
                        score += 20
                    }
                }
                
                // 4. Window ID matching. Browser/document titles are mutable;
                // when the original WindowServer id still exists inside the same
                // bundle it is the strongest identity signal by far.
                if let recWinId = recordedSurface.recordedWindowId,
                   windowID == recWinId {
                    score += 1_000
                }
                
                if score > bestScore {
                    bestScore = score
                    bestMatch = PlaybackForegroundWindowObservation(
                        id: windowID,
                        processID: winPid,
                        frame: RectValue(x: bx, y: by, width: bw, height: bh)
                    )
                }
            }
            
            if let match = bestMatch {
                windows[surfaceId] = match
            }
        }
        
        return windows
    }
}
