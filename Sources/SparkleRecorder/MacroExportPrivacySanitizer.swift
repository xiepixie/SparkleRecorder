import Foundation
import SparkleRecorderCore

struct MacroExportPrivacySanitizer: Sendable {
    var loadBundle: @Sendable (UUID) async throws -> SemanticRecordingBundle

    func prepare(_ events: [RecordedEvent], macro: SavedMacro?) async throws -> [RecordedEvent] {
        guard let reference = macro?.semanticRecording else {
            return events
        }

        do {
            let bundle = try await loadBundle(reference.recordingID)
            let plan = SemanticRecordingPlayableSanitizationPlanner.plan(
                for: events,
                bundle: bundle
            )
            return plan.playbackPreservingSanitizedEvents(from: events)
        } catch {
            NSLog("SparkleRecorder: Export privacy verification failed: \(error)")
            throw MacroExportPrivacyFailure()
        }
    }

    static let live = MacroExportPrivacySanitizer(loadBundle: { recordingID in
        try await RecordingBundleStore().loadBundle(recordingID: recordingID)
    })
}
