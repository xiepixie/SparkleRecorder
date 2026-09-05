import Foundation
import SparkleRecorderCore
import AppKit

public actor EvidenceClient {
    public static let shared = EvidenceClient()

    private let shouldCaptureScreenshot: @Sendable () -> Bool

    private init() {
        self.shouldCaptureScreenshot = {
            UserDefaults.standard.object(forKey: "automationRunCaptureScreenshots") as? Bool ?? true
        }
    }

    public init(
        shouldCaptureScreenshot: @escaping @Sendable () -> Bool
    ) {
        self.shouldCaptureScreenshot = shouldCaptureScreenshot
    }
    
    @discardableResult
    public func recordFailure(_ evidence: PlaybackFailureEvidence) async -> AutomationRunEvidencePersistence {
        let screenshotData = shouldCaptureScreenshot()
            ? await captureFailureScreenshot(
                bundleIdentifier: evidence.bundleIdentifier,
                title: evidence.windowTitle
            )
            : nil
        return await savePlaybackEvidence(
            macroID: evidence.macroID,
            report: evidence.report,
            screenshotData: screenshotData
        )
    }

    public func recordSuccess(
        macroID: UUID,
        report: RunReport,
        surfaces: [String: PlaybackSurface]
    ) async -> AutomationRunEvidencePersistence {
        let preferredSurface = surfaces.values.first
        let screenshotData = shouldCaptureScreenshot()
            ? await captureWindowScreenshot(
                bundleIdentifier: preferredSurface?.bundleIdentifier,
                title: preferredSurface?.windowTitle
            )
            : nil
        return await savePlaybackEvidence(
            macroID: macroID,
            report: report,
            screenshotData: screenshotData
        )
    }

    /// Records the outcome of a macro playback.
    public func recordPlayback(macroID: UUID, startTime: Date, duration: TimeInterval, success: Bool, failedEventIndex: Int?, errorMessage: String?, screenshotData: Data? = nil) async -> AutomationRunEvidencePersistence {
        
        let report = RunReport(
            runID: UUID(),
            startTime: startTime,
            duration: duration,
            isSuccess: success,
            failedEventIndex: failedEventIndex,
            errorMessage: errorMessage
        )
        return await savePlaybackEvidence(macroID: macroID, report: report, screenshotData: screenshotData)
    }

    private func savePlaybackEvidence(macroID: UUID, report: RunReport, screenshotData: Data?) async -> AutomationRunEvidencePersistence {
        let persistence = await MacroRepository.shared.saveRunEvidenceWithStatus(
            id: macroID,
            report: report,
            screenshot: screenshotData
        )
        if persistence.health == .failed {
            NSLog("SparkleRecorder: Failed to save run evidence for macro \(macroID): \(persistence.failureMessage ?? "Unknown error")")
        }
        return persistence
    }

    private func captureFailureScreenshot(bundleIdentifier: String?, title: String?) async -> Data? {
        await captureWindowScreenshot(bundleIdentifier: bundleIdentifier, title: title)
    }

    private func captureWindowScreenshot(bundleIdentifier: String?, title: String?) async -> Data? {
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
