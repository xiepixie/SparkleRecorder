import Foundation
import ScreenCaptureKit
import CoreGraphics
import OSLog
import AppKit

public enum ScreenCaptureError: Error {
    case noMatchingWindow
    case noMatchingDisplay
    case captureFailed(Error?)
}

struct ScreenCaptureWindowDescriptor: Equatable, Sendable {
    var windowID: CGWindowID
    var bundleIdentifier: String?
    var title: String?
    var frame: CGRect
    var hasOwningApplication: Bool
}

struct ScreenCaptureWindowRequest: Equatable, Sendable {
    var bundleIdentifier: String?
    var title: String?
    var recordedWindowID: CGWindowID?
    var expectedFrame: CGRect?
}

enum ScreenCaptureWindowMatcher {
    static func bestMatchIndex(
        candidates: [ScreenCaptureWindowDescriptor],
        request: ScreenCaptureWindowRequest
    ) -> Int? {
        let eligible = candidates.indices.filter { index in
            let candidate = candidates[index]
            guard candidate.hasOwningApplication else { return false }
            guard let expectedBundle = nonEmpty(request.bundleIdentifier) else { return true }
            return nonEmpty(candidate.bundleIdentifier) == expectedBundle
        }
        guard !eligible.isEmpty else { return nil }

        // A window title is mutable state in browsers. Once a recording has a
        // WindowServer id, prefer that stable identity and only use title as a
        // fallback for recordings that no longer resolve to the same OS window.
        if let recordedWindowID = request.recordedWindowID,
           let index = eligible.first(where: { candidates[$0].windowID == recordedWindowID }) {
            return index
        }

        // Locator playback already resolved a concrete current window frame.
        // Reuse that geometry before historical title matching so capture and
        // click projection cannot silently refer to two different windows from
        // the same application after a browser title change.
        if let expectedFrame = request.expectedFrame,
           let index = eligible.min(by: {
               frameDistance(candidates[$0].frame, expectedFrame) < frameDistance(candidates[$1].frame, expectedFrame)
           }),
           frameDistance(candidates[index].frame, expectedFrame) <= 8 {
            return index
        }

        if let expectedTitle = nonEmpty(request.title) {
            let titleMatches = eligible.filter { nonEmpty(candidates[$0].title) == expectedTitle }
            if let index = closestIndex(in: titleMatches, candidates: candidates, expectedFrame: request.expectedFrame) {
                return index
            }
        }

        return nil
    }

    private static func closestIndex(
        in indices: [Int],
        candidates: [ScreenCaptureWindowDescriptor],
        expectedFrame: CGRect?
    ) -> Int? {
        guard !indices.isEmpty else { return nil }
        guard let expectedFrame else { return indices.first }
        return indices.min {
            frameDistance(candidates[$0].frame, expectedFrame) < frameDistance(candidates[$1].frame, expectedFrame)
        }
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@available(macOS 14.0, *)
public actor ScreenCaptureService {
    private let logger = Logger(subsystem: "com.sparklerecorder.mac", category: "ScreenCaptureService")
    public static let shared = ScreenCaptureService()
    
    private init() {}
    
    /// Captures a screenshot of a specific window. Stable window identity and the
    /// already-resolved playback frame take precedence over mutable browser titles.
    public func captureWindow(
        bundleIdentifier: String?,
        title: String?,
        recordedWindowID: CGWindowID? = nil,
        expectedFrame: CGRect? = nil
    ) async throws -> CGImage {
        let availableContent = try await SCShareableContent.current
        let descriptors = availableContent.windows.map { window in
            ScreenCaptureWindowDescriptor(
                windowID: window.windowID,
                bundleIdentifier: window.owningApplication?.bundleIdentifier,
                title: window.title,
                frame: window.frame,
                hasOwningApplication: window.owningApplication != nil
            )
        }
        let request = ScreenCaptureWindowRequest(
            bundleIdentifier: bundleIdentifier,
            title: title,
            recordedWindowID: recordedWindowID,
            expectedFrame: expectedFrame
        )
        guard let targetIndex = ScreenCaptureWindowMatcher.bestMatchIndex(candidates: descriptors, request: request),
              availableContent.windows.indices.contains(targetIndex) else {
            throw ScreenCaptureError.noMatchingWindow
        }
        let targetWindow = availableContent.windows[targetIndex]
        
        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        let config = SCStreamConfiguration()
        config.width = Int(targetWindow.frame.width * scale)
        config.height = Int(targetWindow.frame.height * scale)
        config.scalesToFit = false
        
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            logger.error("Failed to capture window image: \(error.localizedDescription)")
            throw ScreenCaptureError.captureFailed(error)
        }
    }
    
    /// Captures the full screen
    public func captureDisplay(displayID: CGDirectDisplayID = CGMainDisplayID()) async throws -> CGImage {
        let availableContent = try await SCShareableContent.current
        
        guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.noMatchingDisplay
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            logger.error("Failed to capture display: \(error.localizedDescription)")
            throw ScreenCaptureError.captureFailed(error)
        }
    }
    
    /// Utility to save CGImage to a fallback URL in AppSupport
    public func saveFailureSnapshot(image: CGImage, reason: String) -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sparkleRecorderDir = appSupport.appendingPathComponent("SparkleRecorder")
        
        try? FileManager.default.createDirectory(at: sparkleRecorderDir, withIntermediateDirectories: true)
        
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = sparkleRecorderDir.appendingPathComponent("Failure-\(timestamp).png")
        
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        do {
            try data.write(to: fileURL)
            logger.info("Saved failure snapshot to \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Failed to save snapshot: \(error.localizedDescription)")
            return nil
        }
    }
}
