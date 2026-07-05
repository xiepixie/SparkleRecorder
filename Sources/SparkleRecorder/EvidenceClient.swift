import Foundation
import SparkleRecorderCore
import AppKit

public actor EvidenceClient {
    public static let shared = EvidenceClient()
    
    public init() {}
    
    public func recordFailure(_ evidence: PlaybackFailureEvidence) async {
        let screenshotData = await captureFailureScreenshot(
            bundleIdentifier: evidence.bundleIdentifier,
            title: evidence.windowTitle
        )
        await savePlaybackEvidence(
            macroID: evidence.macroID,
            report: evidence.report,
            screenshotData: screenshotData
        )
    }

    /// Records the outcome of a macro playback.
    public func recordPlayback(macroID: UUID, startTime: Date, duration: TimeInterval, success: Bool, failedEventIndex: Int?, errorMessage: String?, screenshotData: Data? = nil) async {
        
        let report = RunReport(
            runID: UUID(),
            startTime: startTime,
            duration: duration,
            isSuccess: success,
            failedEventIndex: failedEventIndex,
            errorMessage: errorMessage
        )
        await savePlaybackEvidence(macroID: macroID, report: report, screenshotData: screenshotData)
    }

    private func savePlaybackEvidence(macroID: UUID, report: RunReport, screenshotData: Data?) async {
        do {
            try await MacroRepository.shared.saveRunEvidence(id: macroID, report: report, screenshot: screenshotData)
        } catch {
            NSLog("SparkleRecorder: Failed to save run evidence for macro \(macroID): \(error)")
        }
    }

    private func captureFailureScreenshot(bundleIdentifier: String?, title: String?) async -> Data? {
        guard #available(macOS 14.0, *) else { return nil }
        do {
            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bundleIdentifier, title: title)
            let bitmap = NSBitmapImageRep(cgImage: image)
            return bitmap.representation(using: .png, properties: [:])
        } catch {
            return nil
        }
    }
}
