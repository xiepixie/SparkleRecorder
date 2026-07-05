import Foundation
import SparkleRecorderCore
import AppKit

public actor EvidenceClient {
    public static let shared = EvidenceClient()
    
    public init() {}
    
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
        
        do {
            try await MacroRepository.shared.saveRunEvidence(id: macroID, report: report, screenshot: screenshotData)
        } catch {
            NSLog("SparkleRecorder: Failed to save run evidence for macro \(macroID): \(error)")
        }
    }
}
