import AppKit
import Foundation
import SparkleRecorderCore

@MainActor
enum AutomationTaskRunEvidencePresenter {
    static func loadEvidence(
        for run: AutomationTaskRun,
        macroPackageBaseURL: URL? = nil
    ) async throws -> AutomationTaskRunEvidencePayload? {
        guard let macroID = run.macroID else {
            return nil
        }

        let packageURL = packageURL(for: macroID, macroPackageBaseURL: macroPackageBaseURL)
        let evidenceID = run.evidenceID
        return try await Task.detached(priority: .userInitiated) {
            if let evidenceID {
                if let payload = try perRunEvidencePayload(in: packageURL, evidenceID: evidenceID) {
                    return payload
                }

                guard let latestPayload = try latestEvidencePayload(in: packageURL),
                      latestPayload.report.runID == evidenceID else {
                    return nil
                }
                return AutomationTaskRunEvidencePayload(
                    source: .latestMatchingRun,
                    manifest: latestPayload.manifest,
                    report: latestPayload.report,
                    reportURL: latestPayload.reportURL,
                    screenshotURL: latestPayload.screenshotURL,
                    screenshotData: latestPayload.screenshotData,
                    packageURL: latestPayload.packageURL,
                    loadedAt: latestPayload.loadedAt
                )
            }

            return try latestEvidencePayload(in: packageURL)
        }.value
    }

    static func loadLatestEvidence(macroID: UUID) async throws -> AutomationTaskRunEvidencePayload? {
        let packageURL = MacroRepository.shared.packageURL(for: macroID)
        return try await Task.detached(priority: .userInitiated) {
            try latestEvidencePayload(in: packageURL)
        }.value
    }

    private static func packageURL(for macroID: UUID, macroPackageBaseURL: URL?) -> URL {
        if let macroPackageBaseURL {
            return macroPackageBaseURL.appendingPathComponent("\(macroID.uuidString).sparkrec", isDirectory: true)
        }
        return MacroRepository.shared.packageURL(for: macroID)
    }

    static func revealReport(_ url: URL) -> AutomationTaskRunEvidenceActionFeedback {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failed(
                .revealReport,
                message: NSLocalizedString("Report file no longer exists.", comment: "")
            )
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .succeeded(.revealReport)
    }

    static func openScreenshot(_ url: URL) -> AutomationTaskRunEvidenceActionFeedback {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failed(
                .openScreenshot,
                message: NSLocalizedString("Screenshot file no longer exists.", comment: "")
            )
        }

        guard NSWorkspace.shared.open(url) else {
            return .failed(
                .openScreenshot,
                message: NSLocalizedString("macOS could not open the screenshot.", comment: "")
            )
        }

        return .succeeded(.openScreenshot)
    }

    nonisolated private static func latestEvidencePayload(
        in packageURL: URL
    ) throws -> AutomationTaskRunEvidencePayload? {
        let runsURL = packageURL.appendingPathComponent("runs", isDirectory: true)
        let reportURL = runsURL.appendingPathComponent("latest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: reportURL.path) else {
            return nil
        }

        let reportData = try Data(contentsOf: reportURL)
        let report = try JSONDecoder().decode(RunReport.self, from: reportData)
        let screenshotURL = runsURL.appendingPathComponent("failure.png", isDirectory: false)
        let resolvedScreenshotURL = FileManager.default.fileExists(atPath: screenshotURL.path)
            ? screenshotURL
            : nil
        let screenshotData: Data?
        if let resolvedScreenshotURL {
            screenshotData = try? Data(contentsOf: resolvedScreenshotURL)
        } else {
            screenshotData = nil
        }

        return AutomationTaskRunEvidencePayload(
            source: .latestMacro,
            manifest: nil,
            report: report,
            reportURL: reportURL,
            screenshotURL: resolvedScreenshotURL,
            screenshotData: screenshotData,
            packageURL: packageURL,
            loadedAt: Date.now
        )
    }

    nonisolated private static func perRunEvidencePayload(
        in packageURL: URL,
        evidenceID: UUID
    ) throws -> AutomationTaskRunEvidencePayload? {
        let evidenceURL = packageURL
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(evidenceID.uuidString, isDirectory: true)
        let manifestURL = evidenceURL.appendingPathComponent("manifest.json", isDirectory: false)
        let reportURL: URL
        let manifest: RunEvidenceManifest?

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let manifestData = try Data(contentsOf: manifestURL)
            let decodedManifest = try JSONDecoder().decode(RunEvidenceManifest.self, from: manifestData)
            reportURL = evidenceURL.appendingPathComponent(decodedManifest.reportFilename, isDirectory: false)
            manifest = decodedManifest
        } else {
            reportURL = evidenceURL.appendingPathComponent("report.json", isDirectory: false)
            manifest = nil
        }

        guard FileManager.default.fileExists(atPath: reportURL.path) else {
            return nil
        }

        let reportData = try Data(contentsOf: reportURL)
        let report = try JSONDecoder().decode(RunReport.self, from: reportData)
        let screenshotFilename = manifest?.screenshotFilename ?? "failure.png"
        let screenshotURL = evidenceURL.appendingPathComponent(screenshotFilename, isDirectory: false)
        let resolvedScreenshotURL = FileManager.default.fileExists(atPath: screenshotURL.path)
            ? screenshotURL
            : nil
        let screenshotData: Data?
        if let resolvedScreenshotURL {
            screenshotData = try? Data(contentsOf: resolvedScreenshotURL)
        } else {
            screenshotData = nil
        }

        return AutomationTaskRunEvidencePayload(
            source: .perRun,
            manifest: manifest,
            report: report,
            reportURL: reportURL,
            screenshotURL: resolvedScreenshotURL,
            screenshotData: screenshotData,
            packageURL: packageURL,
            loadedAt: Date.now
        )
    }
}
