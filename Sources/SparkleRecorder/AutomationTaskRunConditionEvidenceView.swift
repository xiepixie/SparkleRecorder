import AppKit
import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunConditionEvidenceView: View {
    let evidence: AutomationConditionEvaluationEvidence
    @Environment(\.automationConditionDiagnosticArtifactBaseURL) private var artifactBaseURL

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(outcomeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(evidence.observedSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !evidence.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostic artifacts", tableName: "Common")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.secondary)

                    ForEach(evidence.artifacts) { artifact in
                        AutomationConditionDiagnosticArtifactCardView(
                            artifact: artifact,
                            baseURL: artifactBaseURL
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Target", table: "Common"),
                    value: evidence.targetDescription
                )
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Samples", table: "Common"),
                    value: String(format: String(localized: "%d", table: "Common"), evidence.sampleCount)
                )
                if let score = evidence.score {
                    AutomationTaskRunDetailRowView(
                        title: scoreTitle,
                        value: scoreLabel(score)
                    )
                }
                if let threshold = evidence.threshold {
                    AutomationTaskRunDetailRowView(
                        title: String(localized: "Threshold", table: "Common"),
                        value: scoreLabel(threshold)
                    )
                }
                if let region = evidence.resolvedSearchRegion {
                    AutomationTaskRunDetailRowView(
                        title: String(localized: "Region", table: "EditorUX"),
                        value: rectLabel(region)
                    )
                }
                if let lastSampleAt = evidence.lastSampleAt {
                    AutomationTaskRunDetailRowView(
                        title: String(localized: "Last sample", table: "Common"),
                        value: timeSummary(lastSampleAt)
                    )
                }
            }

            ForEach(evidence.fields) { field in
                AutomationTaskRunDetailRowView(
                    title: title(for: field),
                    value: field.value
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.opacity(0.16), lineWidth: 0.7)
                )
        )
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch evidence.kind {
        case .ocrText:
            return String(localized: "Text diagnostics", table: "Common")
        case .regionChanged, .imageAppeared, .imageDisappeared, .pixelMatched:
            return String(localized: "Visual diagnostics", table: "Common")
        case .previousOutcome, .externalSignal, .manualApproval:
            return String(localized: "Condition diagnostics", table: "Common")
        }
    }

    private var systemImage: String {
        switch evidence.kind {
        case .ocrText:
            return "text.viewfinder"
        case .regionChanged:
            return "rectangle.dashed"
        case .imageAppeared:
            return "photo.badge.checkmark"
        case .imageDisappeared:
            return "photo.badge.minus"
        case .pixelMatched:
            return "eyedropper"
        case .previousOutcome:
            return "clock.arrow.circlepath"
        case .externalSignal:
            return "antenna.radiowaves.left.and.right"
        case .manualApproval:
            return "person.crop.circle.badge.checkmark"
        }
    }

    private var tint: Color {
        switch evidence.outcome {
        case .conditionMatched:
            return Brand.libraryGreen
        case .conditionNotMatched:
            return Brand.sigAmber
        case .permissionDenied, .rejected:
            return Brand.sigPink
        case .succeeded, .failed, .cancelled, .timedOut, .resourceConflict, .missingMacro:
            return .secondary
        }
    }

    private var outcomeLabel: String {
        switch evidence.outcome {
        case .conditionMatched:
            return String(localized: "Matched", table: "Common")
        case .conditionNotMatched:
            return String(localized: "Not matched", table: "Common")
        case .permissionDenied:
            return String(localized: "Permission", table: "Common")
        case .rejected:
            return String(localized: "Rejected", table: "Common")
        case .succeeded:
            return String(localized: "Success", table: "Common")
        case .failed:
            return String(localized: "Failure", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .timedOut:
            return String(localized: "Timeout", table: "Common")
        case .resourceConflict:
            return String(localized: "Resource conflict", table: "Common")
        case .missingMacro:
            return String(localized: "Missing macro", table: "EditorUX")
        }
    }

    private var scoreTitle: String {
        switch evidence.kind {
        case .regionChanged:
            return String(localized: "Change score", table: "Common")
        case .imageAppeared, .imageDisappeared:
            return String(localized: "Similarity", table: "Common")
        case .pixelMatched:
            return String(localized: "Similarity", table: "Common")
        case .ocrText, .previousOutcome, .externalSignal, .manualApproval:
            return String(localized: "Score", table: "Common")
        }
    }

    private func title(for field: AutomationConditionDiagnosticField) -> String {
        switch field.id {
        case "baselineRef":
            return String(localized: "Baseline", table: "Common")
        case "condition":
            return String(localized: "Condition", table: "Automation")
        case "currentColor":
            return String(localized: "Current color", table: "Common")
        case "detections":
            return String(localized: "Detected text count", table: "Common")
        case "imageRef":
            return String(localized: "Image", table: "Common")
        case "lastTexts":
            return String(localized: "Last texts", table: "Common")
        case "matchedText":
            return String(localized: "Matched text", table: "Common")
        case "matchMode":
            return String(localized: "Match mode", table: "Common")
        case "pixel":
            return String(localized: "Pixel", table: "Common")
        case "regionRef":
            return String(localized: "Region", table: "EditorUX")
        case "samples":
            return String(localized: "Samples", table: "Common")
        case "score":
            return scoreTitle
        case "searchRegion":
            return String(localized: "Search region", table: "EditorUX")
        case "targetColor":
            return String(localized: "Target color", table: "Common")
        case "targetText":
            return String(localized: "Target text", table: "Common")
        case "threshold":
            return String(localized: "Threshold", table: "Common")
        default:
            return field.title
        }
    }

    private func title(for artifact: AutomationConditionDiagnosticArtifact) -> String {
        switch artifact.kind {
        case .displaySampleImage:
            return String(localized: "Last sample image", table: "Common")
        case .regionSampleImage:
            return String(localized: "Region sample image", table: "Common")
        case .templateImage:
            return String(localized: "Template image", table: "Common")
        case .baselineImage:
            return String(localized: "Baseline image", table: "Common")
        }
    }

    private func rectLabel(_ rect: RectValue) -> String {
        String(format: String(localized: "%.0f, %.0f %.0fx%.0f", table: "Common"), rect.x, rect.y, rect.width, rect.height)
    }

    private func scoreLabel(_ score: Double) -> String {
        String(format: String(localized: "%.2f", table: "Common"), score)
    }

    private func timeSummary(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}

private struct AutomationConditionDiagnosticArtifactBaseURLKey: EnvironmentKey {
    static let defaultValue: URL = {
        AutomationPersistence.defaultFileURL.deletingLastPathComponent()
    }()
}

private struct AutomationConditionDiagnosticArtifactInitialFeedbacksKey: EnvironmentKey {
    static let defaultValue: [String: AutomationConditionEvidenceArtifactActionFeedback] = [:]
}

extension EnvironmentValues {
    var automationConditionDiagnosticArtifactBaseURL: URL {
        get { self[AutomationConditionDiagnosticArtifactBaseURLKey.self] }
        set { self[AutomationConditionDiagnosticArtifactBaseURLKey.self] = newValue }
    }

    var automationConditionDiagnosticArtifactInitialFeedbacks: [String: AutomationConditionEvidenceArtifactActionFeedback] {
        get { self[AutomationConditionDiagnosticArtifactInitialFeedbacksKey.self] }
        set { self[AutomationConditionDiagnosticArtifactInitialFeedbacksKey.self] = newValue }
    }
}

private struct AutomationConditionDiagnosticArtifactCardView: View {
    let artifact: AutomationConditionDiagnosticArtifact
    let baseURL: URL

    @State private var payload: AutomationConditionEvidenceArtifactPayload?
    @State private var actionFeedback: AutomationConditionEvidenceArtifactActionFeedback?
    @Environment(\.automationConditionDiagnosticArtifactInitialFeedbacks) private var initialFeedbacks

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let imageData = payload?.data,
               let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
                    .accessibilityLabel(title)
            } else if let payload {
                Label(unavailableLabel(for: payload.state), systemImage: unavailableSystemImage(for: payload.state))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 3) {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Path", table: "Common"),
                    value: artifact.relativePath
                )
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Type", table: "Common"),
                    value: artifact.contentType
                )
                if let pixelBounds = artifact.pixelBounds {
                    AutomationTaskRunDetailRowView(
                        title: String(localized: "Bounds", table: "Common"),
                        value: rectLabel(pixelBounds)
                    )
                }
                if let createdAt = artifact.createdAt {
                    AutomationTaskRunDetailRowView(
                        title: String(localized: "Captured", table: "Common"),
                        value: createdAt.formatted(date: .abbreviated, time: .standard)
                    )
                }
            }

            if let payload, payload.url != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        artifactActionButtons(payload)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        artifactActionButtons(payload)
                    }
                }
            }

            if let actionFeedback {
                Label(
                    actionFeedbackMessage(actionFeedback),
                    systemImage: actionFeedbackSystemImage(actionFeedback)
                )
                .font(.caption)
                .foregroundStyle(actionFeedbackTint(actionFeedback))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(actionFeedbackMessage(actionFeedback))
            }
        }
        .padding(8)
        .automationSubsurface(cornerRadius: 8, tint: tint)
        .onAppear {
            if actionFeedback == nil {
                actionFeedback = initialFeedbacks[artifact.id]
            }
        }
        .onChange(of: artifact.id) {
            actionFeedback = initialFeedbacks[artifact.id]
        }
        .task(id: artifact.relativePath) {
            payload = await AutomationConditionEvidenceArtifactPresenter
                .loadArtifacts([artifact], supportDirectory: baseURL)
                .first
        }
    }

    private var title: String {
        if !artifact.title.isEmpty {
            return artifact.title
        }

        switch artifact.kind {
        case .displaySampleImage:
            return String(localized: "Last sample", table: "Common")
        case .regionSampleImage:
            return String(localized: "Watched region", table: "Common")
        case .templateImage:
            return String(localized: "Template image", table: "Common")
        case .baselineImage:
            return String(localized: "Baseline image", table: "Common")
        }
    }

    private var systemImage: String {
        switch artifact.kind {
        case .displaySampleImage:
            return "display"
        case .regionSampleImage:
            return "rectangle.dashed"
        case .templateImage:
            return "photo"
        case .baselineImage:
            return "photo.on.rectangle"
        }
    }

    private var tint: Color {
        switch artifact.kind {
        case .displaySampleImage:
            return Brand.sigBlue
        case .regionSampleImage:
            return Brand.sigAmber
        case .templateImage:
            return Brand.libraryGreen
        case .baselineImage:
            return Brand.sigPink
        }
    }

    private var imageHeight: CGFloat {
        switch artifact.kind {
        case .regionSampleImage:
            return 118
        case .displaySampleImage, .templateImage, .baselineImage:
            return 150
        }
    }

    private var status: String {
        guard let payload else {
            return String(localized: "Loading", table: "Common")
        }
        switch payload.state {
        case .loaded:
            return String(localized: "Ready", table: "Common")
        case .missing:
            return String(localized: "Missing", table: "Common")
        case .invalidPath:
            return String(localized: "Invalid path", table: "Common")
        case .unreadable:
            return String(localized: "Unreadable", table: "Common")
        }
    }

    @ViewBuilder
    private func artifactActionButtons(_ payload: AutomationConditionEvidenceArtifactPayload) -> some View {
        Button(String(localized: "Open", table: "Common"), systemImage: "arrow.up.right.square") {
            actionFeedback = AutomationConditionEvidenceArtifactPresenter.open(payload)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button(String(localized: "Reveal", table: "Common"), systemImage: "folder") {
            actionFeedback = AutomationConditionEvidenceArtifactPresenter.reveal(payload)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func unavailableLabel(for state: AutomationConditionEvidenceArtifactLoadState) -> String {
        switch state {
        case .loaded:
            return String(localized: "Artifact preview unavailable", table: "Common")
        case .missing:
            return String(localized: "Artifact file is missing", table: "Common")
        case .invalidPath:
            return String(localized: "Artifact path is invalid", table: "Common")
        case .unreadable:
            return String(localized: "Artifact preview unavailable", table: "Common")
        }
    }

    private func actionFeedbackMessage(
        _ feedback: AutomationConditionEvidenceArtifactActionFeedback
    ) -> String {
        switch feedback {
        case .succeeded(.open):
            return String(localized: "Artifact opened in the default viewer.", table: "Common")
        case .succeeded(.reveal):
            return String(localized: "Artifact revealed in Finder.", table: "Common")
        case .failed(.open, let message), .failed(.reveal, let message):
            return message
        }
    }

    private func actionFeedbackSystemImage(
        _ feedback: AutomationConditionEvidenceArtifactActionFeedback
    ) -> String {
        switch feedback {
        case .succeeded(.open):
            return "photo.badge.checkmark"
        case .succeeded(.reveal):
            return "folder.badge.gearshape"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func actionFeedbackTint(
        _ feedback: AutomationConditionEvidenceArtifactActionFeedback
    ) -> Color {
        switch feedback {
        case .succeeded:
            return Brand.libraryGreen
        case .failed:
            return Brand.sigAmber
        }
    }

    private func unavailableSystemImage(for state: AutomationConditionEvidenceArtifactLoadState) -> String {
        switch state {
        case .loaded, .unreadable:
            return "photo.badge.exclamationmark"
        case .missing:
            return "questionmark.folder"
        case .invalidPath:
            return "exclamationmark.triangle"
        }
    }

    private func rectLabel(_ rect: RectValue) -> String {
        String(format: String(localized: "%.0f, %.0f %.0fx%.0f", table: "Common"), rect.x, rect.y, rect.width, rect.height)
    }
}
