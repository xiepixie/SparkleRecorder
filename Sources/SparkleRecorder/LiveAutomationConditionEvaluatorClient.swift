import Foundation
import CoreGraphics
import SparkleRecorderCore

private final class LiveAutomationConditionEvaluator: @unchecked Sendable {
    private let visionDetector = VisionDetector()
    private let externalSignal: AutomationExternalSignalClient
    private let manualApproval: AutomationManualApprovalClient
    private let searchRegionContext: @Sendable (
        _ request: AutomationConditionEvaluationRequest,
        _ displayBounds: RectValue
    ) async -> AutomationOCRSearchRegionContext
    private let visual: @Sendable (
        _ request: AutomationConditionEvaluationRequest,
        _ condition: AutomationVisualCondition
    ) async -> AutomationConditionEvaluationResult
    private let artifactWriter: AutomationConditionEvidenceArtifactWriter
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        externalSignal: AutomationExternalSignalClient,
        manualApproval: AutomationManualApprovalClient,
        searchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext,
        visual: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ condition: AutomationVisualCondition
        ) async -> AutomationConditionEvaluationResult,
        artifactWriter: AutomationConditionEvidenceArtifactWriter,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.externalSignal = externalSignal
        self.manualApproval = manualApproval
        self.searchRegionContext = searchRegionContext
        self.visual = visual
        self.artifactWriter = artifactWriter
        self.now = now
        self.sleep = sleep
    }

    func evaluate(_ request: AutomationConditionEvaluationRequest) async -> AutomationConditionEvaluationResult {
        switch request.condition.kind {
        case .ocrText(let condition):
            return await evaluateOCR(condition, request: request)
        case .visual(let condition):
            return await visual(request, condition)
        case .previousOutcome(let predicate):
            let outcome: AutomationOutcome = request.previousOutcomes.contains(where: predicate.matches)
                ? .conditionMatched
                : .conditionNotMatched
            return AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: AutomationConditionEvaluationEvidence.contextual(
                    request: request,
                    outcome: outcome,
                    evaluatedAt: now()
                )
            )
        case .externalSignal(let signalName):
            let outcome: AutomationOutcome = await externalSignal.isActive(signalName)
                ? .conditionMatched
                : .conditionNotMatched
            return AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: AutomationConditionEvaluationEvidence.contextual(
                    request: request,
                    outcome: outcome,
                    evaluatedAt: now()
                )
            )
        case .manualApproval:
            let outcome: AutomationOutcome = await manualApproval.requestApproval(request)
                ? .conditionMatched
                : .conditionNotMatched
            return AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: AutomationConditionEvaluationEvidence.contextual(
                    request: request,
                    outcome: outcome,
                    evaluatedAt: now()
                )
            )
        }
    }

    private func evaluateOCR(
        _ condition: AutomationOCRCondition,
        request: AutomationConditionEvaluationRequest
    ) async -> AutomationConditionEvaluationResult {
        let spec = request.condition
        let deadline = spec.timeout.map { now().addingTimeInterval($0) }
        var sampleCount = 0
        var firstSampleAt: Date?
        var lastEvidence: AutomationConditionEvaluationEvidence?

        while true {
            sampleCount += 1
            let sampleAt = now()
            if firstSampleAt == nil {
                firstSampleAt = sampleAt
            }

            switch await scanScreen(
                condition,
                request: request,
                sampleCount: sampleCount,
                firstSampleAt: firstSampleAt,
                sampleAt: sampleAt
            ) {
            case .matched(let evidence):
                return AutomationConditionEvaluationResult(outcome: .conditionMatched, evidence: evidence)
            case .notMatched(let evidence):
                lastEvidence = evidence
            case .failed(let result):
                return result
            }

            guard let deadline, now() < deadline else {
                return AutomationConditionEvaluationResult(
                    outcome: .conditionNotMatched,
                    evidence: lastEvidence
                )
            }

            await sleep(spec.pollingInterval)
        }
    }

    private func scanScreen(
        _ condition: AutomationOCRCondition,
        request: AutomationConditionEvaluationRequest,
        sampleCount: Int,
        firstSampleAt: Date?,
        sampleAt: Date
    ) async -> OCRScanResult {
        let image: CGImage
        do {
            image = try await ScreenCaptureService.shared.captureDisplay()
        } catch {
            let outcome = await outcome(for: error)
            return .failed(AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: makeOCRFailureEvidence(
                    request: request,
                    condition: condition,
                    outcome: outcome,
                    sampleCount: sampleCount,
                    firstSampleAt: firstSampleAt,
                    sampleAt: sampleAt,
                    displayBounds: nil,
                    resolution: nil,
                    artifacts: [],
                    errorDescription: String(describing: error)
                )
            ))
        }

        let displayBounds = RectValue(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        let regionContext = await searchRegionContext(request, displayBounds)
        let resolution = condition.searchRegionResolution(in: regionContext)
        let resolvedSearchRegion = resolvedRegion(for: resolution)
        let artifacts = await artifactWriter.saveSample(AutomationConditionEvidenceArtifactSample(
            runID: request.runID,
            workflowID: request.workflowID,
            taskID: request.taskID,
            conditionID: request.condition.id,
            image: image,
            displayBounds: displayBounds,
            resolvedSearchRegion: resolvedSearchRegion,
            sampleAt: sampleAt
        ))

        guard let detectionInput = ocrDetectionInput(
            image: image,
            resolution: resolution
        ) else {
            let evidence = makeOCREvidence(
                request: request,
                condition: condition,
                outcome: .conditionNotMatched,
                sampleCount: sampleCount,
                firstSampleAt: firstSampleAt,
                sampleAt: sampleAt,
                displayBounds: displayBounds,
                resolution: resolution,
                detections: [],
                matchedText: nil,
                artifacts: artifacts
            )
            return .notMatched(evidence)
        }

        let detections: [TextDetection]
        do {
            detections = try await visionDetector.detectText(in: detectionInput.image)
        } catch {
            let outcome = await outcome(for: error)
            return .failed(AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: makeOCRFailureEvidence(
                    request: request,
                    condition: condition,
                    outcome: outcome,
                    sampleCount: sampleCount,
                    firstSampleAt: firstSampleAt,
                    sampleAt: sampleAt,
                    displayBounds: displayBounds,
                    resolution: resolution,
                    artifacts: artifacts,
                    errorDescription: String(describing: error)
                )
            ))
        }

        let regionDetections = detections
        let matched = regionDetections.first { detection in
            matches(candidate: detection.text, target: condition.text, mode: condition.matchMode)
        }
        let outcome: AutomationOutcome = matched == nil ? .conditionNotMatched : .conditionMatched
        let evidence = makeOCREvidence(
            request: request,
            condition: condition,
            outcome: outcome,
            sampleCount: sampleCount,
            firstSampleAt: firstSampleAt,
            sampleAt: sampleAt,
            displayBounds: displayBounds,
            resolution: resolution,
            detections: regionDetections,
            matchedText: matched?.text,
            artifacts: artifacts
        )
        return matched == nil ? .notMatched(evidence) : .matched(evidence)
    }

    private func ocrDetectionInput(
        image: CGImage,
        resolution: AutomationOCRSearchRegionResolution
    ) -> OCRDetectionInput? {
        switch resolution {
        case .unrestricted:
            return OCRDetectionInput(image: image)
        case .unavailable:
            return nil
        case .resolved(let region):
            let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let cropRect = CGRect(
                x: region.x,
                y: region.y,
                width: region.width,
                height: region.height
            )
            .integral
            .intersection(imageBounds)

            guard !cropRect.isNull,
                  cropRect.width > 1,
                  cropRect.height > 1,
                  let cropped = image.cropping(to: cropRect) else {
                return nil
            }

            return OCRDetectionInput(image: cropped)
        }
    }

    private func resolvedRegion(for resolution: AutomationOCRSearchRegionResolution) -> RectValue? {
        switch resolution {
        case .resolved(let region):
            return region
        case .unrestricted, .unavailable:
            return nil
        }
    }

    private func makeOCREvidence(
        request: AutomationConditionEvaluationRequest,
        condition: AutomationOCRCondition,
        outcome: AutomationOutcome,
        sampleCount: Int,
        firstSampleAt: Date?,
        sampleAt: Date,
        displayBounds: RectValue,
        resolution: AutomationOCRSearchRegionResolution,
        detections: [TextDetection],
        matchedText: String?,
        artifacts: [AutomationConditionDiagnosticArtifact]
    ) -> AutomationConditionEvaluationEvidence {
        let resolvedSearchRegion: RectValue?
        let regionLabel: String
        switch resolution {
        case .unrestricted:
            resolvedSearchRegion = nil
            regionLabel = "Full display"
        case .resolved(let region):
            resolvedSearchRegion = region
            regionLabel = rectLabel(region)
        case .unavailable:
            resolvedSearchRegion = nil
            regionLabel = "Unavailable"
        }

        let detectedTexts = detections.map(\.text).filter { !$0.isEmpty }
        let observedSummary: String
        if let matchedText {
            observedSummary = "Matched text: \(matchedText)"
        } else if detectedTexts.isEmpty {
            observedSummary = "No text detected in search region"
        } else {
            observedSummary = "Detected text: " + detectedTexts.prefix(3).joined(separator: ", ")
        }

        var fields = [
            AutomationConditionDiagnosticField(id: "targetText", title: "Target text", value: condition.text),
            AutomationConditionDiagnosticField(id: "matchMode", title: "Match mode", value: condition.matchMode.rawValue),
            AutomationConditionDiagnosticField(id: "searchRegion", title: "Search region", value: regionLabel),
            AutomationConditionDiagnosticField(id: "detections", title: "Detected text count", value: "\(detectedTexts.count)"),
            AutomationConditionDiagnosticField(id: "samples", title: "Samples", value: "\(sampleCount)")
        ]
        if let matchedText {
            fields.append(AutomationConditionDiagnosticField(id: "matchedText", title: "Matched text", value: matchedText))
        } else if !detectedTexts.isEmpty {
            fields.append(AutomationConditionDiagnosticField(
                id: "lastTexts",
                title: "Last texts",
                value: detectedTexts.prefix(5).joined(separator: " | ")
            ))
        }

        return AutomationConditionEvaluationEvidence(
            runID: request.runID,
            workflowID: request.workflowID,
            taskID: request.taskID,
            conditionID: request.condition.id,
            kind: .ocrText,
            outcome: outcome,
            evaluatedAt: sampleAt,
            firstSampleAt: firstSampleAt,
            lastSampleAt: sampleAt,
            sampleCount: sampleCount,
            displayBounds: displayBounds,
            resolvedSearchRegion: resolvedSearchRegion,
            searchRegionSpace: condition.searchRegionSpace,
            targetDescription: condition.text,
            observedSummary: observedSummary,
            fields: fields,
            artifacts: artifacts
        )
    }

    private func makeOCRFailureEvidence(
        request: AutomationConditionEvaluationRequest,
        condition: AutomationOCRCondition,
        outcome: AutomationOutcome,
        sampleCount: Int,
        firstSampleAt: Date?,
        sampleAt: Date,
        displayBounds: RectValue?,
        resolution: AutomationOCRSearchRegionResolution?,
        artifacts: [AutomationConditionDiagnosticArtifact],
        errorDescription: String
    ) -> AutomationConditionEvaluationEvidence {
        let resolvedSearchRegion: RectValue?
        let regionLabel: String
        switch resolution {
        case .unrestricted:
            resolvedSearchRegion = nil
            regionLabel = "Full display"
        case .resolved(let region):
            resolvedSearchRegion = region
            regionLabel = rectLabel(region)
        case .unavailable:
            resolvedSearchRegion = nil
            regionLabel = "Unavailable"
        case nil:
            resolvedSearchRegion = nil
            regionLabel = "Not captured"
        }

        let summary = diagnosticSummary(
            for: outcome,
            fallback: "OCR evaluation failed before text could be detected"
        )
        var fields = [
            AutomationConditionDiagnosticField(id: "targetText", title: "Target text", value: condition.text),
            AutomationConditionDiagnosticField(id: "matchMode", title: "Match mode", value: condition.matchMode.rawValue),
            AutomationConditionDiagnosticField(id: "searchRegion", title: "Search region", value: regionLabel),
            AutomationConditionDiagnosticField(id: "samples", title: "Samples", value: "\(sampleCount)"),
            AutomationConditionDiagnosticField(id: "failure", title: "Failure", value: summary)
        ]
        if !errorDescription.isEmpty {
            fields.append(AutomationConditionDiagnosticField(
                id: "error",
                title: "Error",
                value: errorDescription
            ))
        }

        return AutomationConditionEvaluationEvidence(
            runID: request.runID,
            workflowID: request.workflowID,
            taskID: request.taskID,
            conditionID: request.condition.id,
            kind: .ocrText,
            outcome: outcome,
            evaluatedAt: sampleAt,
            firstSampleAt: firstSampleAt,
            lastSampleAt: sampleAt,
            sampleCount: sampleCount,
            displayBounds: displayBounds,
            resolvedSearchRegion: resolvedSearchRegion,
            searchRegionSpace: condition.searchRegionSpace,
            targetDescription: condition.text,
            observedSummary: summary,
            fields: fields,
            artifacts: artifacts
        )
    }

    private func rectLabel(_ rect: RectValue) -> String {
        String(format: "%.0f, %.0f %.0fx%.0f", rect.x, rect.y, rect.width, rect.height)
    }

    private func outcome(for error: Error) async -> AutomationOutcome {
        let screenCaptureStatus = await MainActor.run {
            PermissionCenter.shared.checkScreenCaptureAccess()
        }

        if screenCaptureStatus != .authorized {
            return .permissionDenied(
                permission: .screenRecording,
                message: "Screen Recording permission is required for OCR conditions"
            )
        }

        if let screenError = error as? ScreenCaptureError {
            switch screenError {
            case .noMatchingDisplay:
                return .rejected(reason: "No matching display for OCR condition")
            case .noMatchingWindow:
                return .rejected(reason: "No matching window for OCR condition")
            case .captureFailed(let underlyingError):
                return .rejected(reason: String(describing: underlyingError ?? screenError))
            }
        }

        return .rejected(reason: String(describing: error))
    }

    private func diagnosticSummary(
        for outcome: AutomationOutcome,
        fallback: String
    ) -> String {
        switch outcome {
        case .permissionDenied(_, let message):
            return message
        case .rejected(let reason):
            return reason
        case .timedOut(let deadline):
            if let deadline {
                return "Condition timed out at \(deadline)"
            }
            return "Condition timed out"
        case .resourceConflict(let resource):
            return resource.map { "Resource conflict: \($0.rawValue)" } ?? "Resource conflict"
        case .missingMacro(let macroID):
            return "Missing macro \(macroID.uuidString)"
        case .cancelled(let reason):
            return reason ?? "Condition was cancelled"
        case .failed:
            return "Condition failed"
        case .succeeded:
            return "Condition completed"
        case .conditionMatched, .conditionNotMatched:
            return fallback
        }
    }

    private func matches(candidate: String, target: String, mode: TextMatchMode) -> Bool {
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTarget.isEmpty else {
            return false
        }

        switch mode {
        case .contains:
            return normalizedCandidate.contains(normalizedTarget)
        case .exact:
            return normalizedCandidate == normalizedTarget
        }
    }

    private enum OCRScanResult {
        case matched(AutomationConditionEvaluationEvidence)
        case notMatched(AutomationConditionEvaluationEvidence)
        case failed(AutomationConditionEvaluationResult)
    }

    private struct OCRDetectionInput {
        var image: CGImage
    }
}

extension AutomationConditionEvaluatorClient {
    static func live(
        externalSignal: AutomationExternalSignalClient = .inactive,
        manualApproval: AutomationManualApprovalClient = .rejecting,
        imageProvider: @escaping AutomationVisualImageProvider = { _, _ in nil },
        baselineProvider: @escaping AutomationVisualImageProvider = { _, _ in nil },
        searchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext = { _, displayBounds in
            AutomationOCRSearchRegionContext(displayBounds: displayBounds)
        },
        visual: (@Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ condition: AutomationVisualCondition
        ) async -> AutomationConditionEvaluationResult)? = nil,
        artifactWriter: AutomationConditionEvidenceArtifactWriter = .fileBacked(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { duration in
            guard duration > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    ) -> AutomationConditionEvaluatorClient {
        let visualEvaluator = visual ?? AutomationVisualConditionEvaluatorClient.live(
            imageProvider: imageProvider,
            baselineProvider: baselineProvider,
            searchRegionContext: searchRegionContext,
            artifactWriter: artifactWriter,
            now: now,
            sleep: sleep
        ).evaluate
        let evaluator = LiveAutomationConditionEvaluator(
            externalSignal: externalSignal,
            manualApproval: manualApproval,
            searchRegionContext: searchRegionContext,
            visual: visualEvaluator,
            artifactWriter: artifactWriter,
            now: now,
            sleep: sleep
        )
        return AutomationConditionEvaluatorClient(evaluateResult: { request in
            await evaluator.evaluate(request)
        })
    }
}
