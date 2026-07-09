import AppKit
import Foundation
import SparkleRecorderCore

enum AutomationConditionEvidenceArtifactLoadState: Equatable, Sendable {
    case loaded
    case missing
    case invalidPath
    case unreadable
}

struct AutomationConditionEvidenceArtifactPayload: Identifiable, Sendable {
    var id: String { artifact.id }
    var artifact: AutomationConditionDiagnosticArtifact
    var url: URL?
    var state: AutomationConditionEvidenceArtifactLoadState
    var data: Data?
    var loadedAt: Date
}

enum AutomationConditionEvidenceArtifactAction: Equatable, Sendable {
    case open
    case reveal
}

enum AutomationConditionEvidenceArtifactActionFeedback: Equatable, Sendable {
    case succeeded(AutomationConditionEvidenceArtifactAction)
    case failed(AutomationConditionEvidenceArtifactAction, message: String)
}

@MainActor
enum AutomationConditionEvidenceArtifactPresenter {
    static func loadArtifacts(
        for evidence: AutomationConditionEvaluationEvidence,
        supportDirectory: URL = AutomationPersistence.defaultFileURL.deletingLastPathComponent()
    ) async -> [AutomationConditionEvidenceArtifactPayload] {
        await loadArtifacts(evidence.artifacts, supportDirectory: supportDirectory)
    }

    static func loadArtifacts(
        _ artifacts: [AutomationConditionDiagnosticArtifact],
        supportDirectory: URL = AutomationPersistence.defaultFileURL.deletingLastPathComponent()
    ) async -> [AutomationConditionEvidenceArtifactPayload] {
        await Task.detached(priority: .userInitiated) {
            artifacts.map { artifactPayload($0, supportDirectory: supportDirectory) }
        }.value
    }

    static func reveal(
        _ payload: AutomationConditionEvidenceArtifactPayload
    ) -> AutomationConditionEvidenceArtifactActionFeedback {
        guard let url = payload.url else {
            return .failed(
                .reveal,
                message: String(localized: "Artifact path is unavailable.", table: "Common")
            )
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failed(
                .reveal,
                message: String(localized: "Artifact file no longer exists.", table: "Common")
            )
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .succeeded(.reveal)
    }

    static func open(
        _ payload: AutomationConditionEvidenceArtifactPayload
    ) -> AutomationConditionEvidenceArtifactActionFeedback {
        guard let url = payload.url else {
            return .failed(
                .open,
                message: String(localized: "Artifact path is unavailable.", table: "Common")
            )
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failed(
                .open,
                message: String(localized: "Artifact file no longer exists.", table: "Common")
            )
        }
        guard NSWorkspace.shared.open(url) else {
            return .failed(
                .open,
                message: String(localized: "macOS could not open the artifact.", table: "Common")
            )
        }

        return .succeeded(.open)
    }

    nonisolated private static func artifactPayload(
        _ artifact: AutomationConditionDiagnosticArtifact,
        supportDirectory: URL
    ) -> AutomationConditionEvidenceArtifactPayload {
        let loadedAt = Date.now
        guard let url = artifact.resolvedURL(relativeTo: supportDirectory) else {
            return AutomationConditionEvidenceArtifactPayload(
                artifact: artifact,
                url: nil,
                state: .invalidPath,
                data: nil,
                loadedAt: loadedAt
            )
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return AutomationConditionEvidenceArtifactPayload(
                artifact: artifact,
                url: url,
                state: .missing,
                data: nil,
                loadedAt: loadedAt
            )
        }

        guard let data = try? Data(contentsOf: url),
              NSImage(data: data) != nil else {
            return AutomationConditionEvidenceArtifactPayload(
                artifact: artifact,
                url: url,
                state: .unreadable,
                data: nil,
                loadedAt: loadedAt
            )
        }

        return AutomationConditionEvidenceArtifactPayload(
            artifact: artifact,
            url: url,
            state: .loaded,
            data: data,
            loadedAt: loadedAt
        )
    }
}
