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
                    Text(NSLocalizedString("Diagnostic artifacts", comment: ""))
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
                    title: NSLocalizedString("Target", comment: ""),
                    value: evidence.targetDescription
                )
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Samples", comment: ""),
                    value: String(format: NSLocalizedString("%d", comment: ""), evidence.sampleCount)
                )
                if let score = evidence.score {
                    AutomationTaskRunDetailRowView(
                        title: scoreTitle,
                        value: scoreLabel(score)
                    )
                }
                if let threshold = evidence.threshold {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Threshold", comment: ""),
                        value: scoreLabel(threshold)
                    )
                }
                if let region = evidence.resolvedSearchRegion {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Region", comment: ""),
                        value: rectLabel(region)
                    )
                }
                if let lastSampleAt = evidence.lastSampleAt {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Last sample", comment: ""),
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
            return NSLocalizedString("Text diagnostics", comment: "")
        case .regionChanged, .imageAppeared, .imageDisappeared, .pixelMatched:
            return NSLocalizedString("Visual diagnostics", comment: "")
        case .previousOutcome, .externalSignal, .manualApproval:
            return NSLocalizedString("Condition diagnostics", comment: "")
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
            return NSLocalizedString("Matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Not matched", comment: "")
        case .permissionDenied:
            return NSLocalizedString("Permission", comment: "")
        case .rejected:
            return NSLocalizedString("Rejected", comment: "")
        case .succeeded:
            return NSLocalizedString("Success", comment: "")
        case .failed:
            return NSLocalizedString("Failure", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .timedOut:
            return NSLocalizedString("Timeout", comment: "")
        case .resourceConflict:
            return NSLocalizedString("Resource conflict", comment: "")
        case .missingMacro:
            return NSLocalizedString("Missing macro", comment: "")
        }
    }

    private var scoreTitle: String {
        switch evidence.kind {
        case .regionChanged:
            return NSLocalizedString("Change score", comment: "")
        case .imageAppeared, .imageDisappeared:
            return NSLocalizedString("Similarity", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Similarity", comment: "")
        case .ocrText, .previousOutcome, .externalSignal, .manualApproval:
            return NSLocalizedString("Score", comment: "")
        }
    }

    private func title(for field: AutomationConditionDiagnosticField) -> String {
        switch field.id {
        case "baselineRef":
            return NSLocalizedString("Baseline", comment: "")
        case "condition":
            return NSLocalizedString("Condition", comment: "")
        case "currentColor":
            return NSLocalizedString("Current color", comment: "")
        case "detections":
            return NSLocalizedString("Detected text count", comment: "")
        case "imageRef":
            return NSLocalizedString("Image", comment: "")
        case "lastTexts":
            return NSLocalizedString("Last texts", comment: "")
        case "matchedText":
            return NSLocalizedString("Matched text", comment: "")
        case "matchMode":
            return NSLocalizedString("Match mode", comment: "")
        case "pixel":
            return NSLocalizedString("Pixel", comment: "")
        case "regionRef":
            return NSLocalizedString("Region", comment: "")
        case "samples":
            return NSLocalizedString("Samples", comment: "")
        case "score":
            return scoreTitle
        case "searchRegion":
            return NSLocalizedString("Search region", comment: "")
        case "targetColor":
            return NSLocalizedString("Target color", comment: "")
        case "targetText":
            return NSLocalizedString("Target text", comment: "")
        case "threshold":
            return NSLocalizedString("Threshold", comment: "")
        default:
            return field.title
        }
    }

    private func title(for artifact: AutomationConditionDiagnosticArtifact) -> String {
        switch artifact.kind {
        case .displaySampleImage:
            return NSLocalizedString("Last sample image", comment: "")
        case .regionSampleImage:
            return NSLocalizedString("Region sample image", comment: "")
        case .templateImage:
            return NSLocalizedString("Template image", comment: "")
        case .baselineImage:
            return NSLocalizedString("Baseline image", comment: "")
        }
    }

    private func rectLabel(_ rect: RectValue) -> String {
        String(format: NSLocalizedString("%.0f, %.0f %.0fx%.0f", comment: ""), rect.x, rect.y, rect.width, rect.height)
    }

    private func scoreLabel(_ score: Double) -> String {
        String(format: NSLocalizedString("%.2f", comment: ""), score)
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
                    title: NSLocalizedString("Path", comment: ""),
                    value: artifact.relativePath
                )
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Type", comment: ""),
                    value: artifact.contentType
                )
                if let pixelBounds = artifact.pixelBounds {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Bounds", comment: ""),
                        value: rectLabel(pixelBounds)
                    )
                }
                if let createdAt = artifact.createdAt {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Captured", comment: ""),
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
            return NSLocalizedString("Last sample", comment: "")
        case .regionSampleImage:
            return NSLocalizedString("Watched region", comment: "")
        case .templateImage:
            return NSLocalizedString("Template image", comment: "")
        case .baselineImage:
            return NSLocalizedString("Baseline image", comment: "")
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
            return NSLocalizedString("Loading", comment: "")
        }
        switch payload.state {
        case .loaded:
            return NSLocalizedString("Ready", comment: "")
        case .missing:
            return NSLocalizedString("Missing", comment: "")
        case .invalidPath:
            return NSLocalizedString("Invalid path", comment: "")
        case .unreadable:
            return NSLocalizedString("Unreadable", comment: "")
        }
    }

    @ViewBuilder
    private func artifactActionButtons(_ payload: AutomationConditionEvidenceArtifactPayload) -> some View {
        Button(NSLocalizedString("Open", comment: ""), systemImage: "arrow.up.right.square") {
            actionFeedback = AutomationConditionEvidenceArtifactPresenter.open(payload)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button(NSLocalizedString("Reveal", comment: ""), systemImage: "folder") {
            actionFeedback = AutomationConditionEvidenceArtifactPresenter.reveal(payload)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func unavailableLabel(for state: AutomationConditionEvidenceArtifactLoadState) -> String {
        switch state {
        case .loaded:
            return NSLocalizedString("Artifact preview unavailable", comment: "")
        case .missing:
            return NSLocalizedString("Artifact file is missing", comment: "")
        case .invalidPath:
            return NSLocalizedString("Artifact path is invalid", comment: "")
        case .unreadable:
            return NSLocalizedString("Artifact preview unavailable", comment: "")
        }
    }

    private func actionFeedbackMessage(
        _ feedback: AutomationConditionEvidenceArtifactActionFeedback
    ) -> String {
        switch feedback {
        case .succeeded(.open):
            return NSLocalizedString("Artifact opened in the default viewer.", comment: "")
        case .succeeded(.reveal):
            return NSLocalizedString("Artifact revealed in Finder.", comment: "")
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
        String(format: NSLocalizedString("%.0f, %.0f %.0fx%.0f", comment: ""), rect.x, rect.y, rect.width, rect.height)
    }
}
