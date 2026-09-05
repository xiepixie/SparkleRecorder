import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Run Center Localization Tests")
struct AutomationRunCenterLocalizationTests {
    @Test("Run center strings have English and Simplified Chinese translations")
    func runCenterStringsAreLocalized() throws {
        let root = repositoryRoot()
        let catalogURL = root.appendingPathComponent("Sources/SparkleRecorder/Automation.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(rootObject["strings"] as? [String: Any])

        var missingEnglish: [String] = []
        var missingSimplifiedChinese: [String] = []
        for key in Self.runCenterKeys {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any]
            if localizations?["en"] == nil {
                missingEnglish.append(key)
            }
            if localizations?["zh-Hans"] == nil {
                missingSimplifiedChinese.append(key)
            }
        }

        #expect(missingEnglish.isEmpty, "Missing English run-center translations: \(missingEnglish)")
        #expect(missingSimplifiedChinese.isEmpty, "Missing Simplified Chinese run-center translations: \(missingSimplifiedChinese)")
    }

    @Test("Known internal playback errors use user-facing localized copy")
    func playbackAbortUsesLocalizedCopy() {
        let completedAt = Date(timeIntervalSince1970: 100)
        let run = AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            actualStartTime: completedAt.addingTimeInterval(-1),
            completedAt: completedAt,
            status: .completed,
            outcome: .failed(report: RunReport(
                runID: UUID(),
                startTime: completedAt.addingTimeInterval(-1),
                duration: 1,
                isSuccess: false,
                errorMessage: "Playback aborted"
            )),
            createdAt: completedAt.addingTimeInterval(-2)
        )

        #expect(AutomationTaskRunDisplay(run: run).detail != "Playback aborted")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let runCenterKeys = [
        "%@, %d runs",
        "%d steps · %d attempts",
        "All runs",
        "Attempts",
        "Available",
        "Choose another run filter.",
        "Every step in this run completed successfully.",
        "Evidence",
        "Latest activity",
        "Needs attention",
        "No matching runs",
        "None",
        "Open Workflow",
        "Playback was cancelled by the user.",
        "Playback was cancelled.",
        "Playback was interrupted.",
        "Recommended next step",
        "Run details",
        "Run ID",
        "Run history keeps at most 10,000 records. Choosing Never disables the age limit, not this capacity limit.",
        "Review Evidence",
        "Review Failure",
        "Run Again",
        "Open Run History Settings",
        "Cancel this execution?",
        "Every active step in this execution will be stopped. Completed steps and saved evidence will remain in history.",
        "Report only",
        "Save failed",
        "Not verified",
        "Report saved; screenshot unavailable",
        "Evidence save failed",
        "No evidence recorded",
        "Evidence not verified",
        "Run evidence",
        "Failed at event #%d",
        "The saved evidence files could not be found.",
        "Evidence could not be opened.",
        "Stopped %d active step(s).",
        "Stopped %d step(s); %d could not be stopped.",
        "The run could not be stopped: %@",
        "A new run started.",
        "The workflow could not start: %@",
        "System Settings opened.",
        "Wait for completion, or cancel every active step in this run.",
        "Running",
        "SparkleRecorder is tracking this run live. If the app closes, the run will be marked as interrupted when it reopens.",
        "Steps and attempts",
        "Succeeded",
        "This run ended before all steps completed.",
        "What happened",
        "Automatic cleanup is off. Manual cleanup remains available.",
        "Automatic cleanup will check when the app is running.",
        "Automatically manage run storage",
        "Condition evidence",
        "Delete Evidence",
        "Delete evidence?",
        "Delete Run History",
        "Delete Screenshots",
        "Delete screenshots?",
        "Delete this run history?",
        "Deleted %d run record(s) and associated evidence, freeing about %@.",
        "Deleted evidence from %d run(s) and freed about %@.",
        "Deleted screenshots from %d run(s) and freed about %@.",
        "Diagnostics",
        "Evidence size",
        "History index",
        "Last checked %@ · removed %d evidence item(s) and %d record(s) · freed %@ · next check %@",
        "Manage run data",
        "Other evidence",
        "Refresh storage usage",
        "Reports",
        "Reports are still saved when screenshots are off or unavailable.",
        "Run data could not be deleted: %@",
        "Run records",
        "Save ending screenshots",
        "Screenshots",
        "Storage used",
        "Storage usage could not be calculated: %@",
        "This permanently removes %d run record(s) and about %@ of associated evidence.",
        "This removes about %@ of ending screenshots. Reports and run history stay available.",
        "This removes about %@ of reports, screenshots, and diagnostic evidence. A lightweight run record stays in history."
    ]
}
