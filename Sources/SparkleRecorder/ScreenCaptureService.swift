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

@available(macOS 14.0, *)
public actor ScreenCaptureService {
    private let logger = Logger(subsystem: "com.sparklerecorder.mac", category: "ScreenCaptureService")
    public static let shared = ScreenCaptureService()
    
    private init() {}
    
    /// Captures a screenshot of a specific window by its bundle identifier and window title
    public func captureWindow(bundleIdentifier: String?, title: String?) async throws -> CGImage {
        let availableContent = try await SCShareableContent.current
        
        let window = availableContent.windows.first { w in
            // Basic heuristic to match window. 
            // In a real app we might match frame too, but bundleIdentifier is best effort
            let bidMatch = bundleIdentifier == nil || w.owningApplication?.bundleIdentifier == bundleIdentifier
            let titleMatch = title == nil || w.title == title
            // Skip SparkleRecorder's own overlay windows if possible, but SCShareableContent handles basic windows
            return bidMatch && titleMatch && w.owningApplication != nil
        }
        
        guard let targetWindow = window else {
            throw ScreenCaptureError.noMatchingWindow
        }
        
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
