import CoreGraphics
import Foundation
import SparkleRecorderCore

typealias AutomationVisualImageProvider = @Sendable (
    _ request: AutomationConditionEvaluationRequest,
    _ reference: String
) async throws -> CGImage?

struct AutomationVisualConditionEvaluatorClient: Sendable {
    var evaluate: @Sendable (
        _ request: AutomationConditionEvaluationRequest,
        _ condition: AutomationVisualCondition
    ) async -> AutomationConditionEvaluationResult

    init(
        evaluate: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ condition: AutomationVisualCondition
        ) async -> AutomationConditionEvaluationResult
    ) {
        self.evaluate = evaluate
    }

    static func live(
        captureDisplay: @escaping @Sendable () async throws -> CGImage = {
            try await ScreenCaptureService.shared.captureDisplay()
        },
        imageProvider: @escaping AutomationVisualImageProvider = { _, _ in nil },
        baselineProvider: @escaping AutomationVisualImageProvider = { _, _ in nil },
        searchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext = { _, displayBounds in
            AutomationOCRSearchRegionContext(displayBounds: displayBounds)
        },
        artifactWriter: AutomationConditionEvidenceArtifactWriter = .fileBacked(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { duration in
            guard duration > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    ) -> AutomationVisualConditionEvaluatorClient {
        let evaluator = LiveAutomationVisualConditionEvaluator(
            captureDisplay: captureDisplay,
            imageProvider: imageProvider,
            baselineProvider: baselineProvider,
            searchRegionContext: searchRegionContext,
            artifactWriter: artifactWriter,
            now: now,
            sleep: sleep
        )
        return AutomationVisualConditionEvaluatorClient { request, condition in
            await evaluator.evaluate(request, condition: condition)
        }
    }
}

private final class LiveAutomationVisualConditionEvaluator: @unchecked Sendable {
    private let captureDisplay: @Sendable () async throws -> CGImage
    private let imageProvider: AutomationVisualImageProvider
    private let baselineProvider: AutomationVisualImageProvider
    private let searchRegionContext: @Sendable (
        _ request: AutomationConditionEvaluationRequest,
        _ displayBounds: RectValue
    ) async -> AutomationOCRSearchRegionContext
    private let artifactWriter: AutomationConditionEvidenceArtifactWriter
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        captureDisplay: @escaping @Sendable () async throws -> CGImage,
        imageProvider: @escaping AutomationVisualImageProvider,
        baselineProvider: @escaping AutomationVisualImageProvider,
        searchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext,
        artifactWriter: AutomationConditionEvidenceArtifactWriter,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.captureDisplay = captureDisplay
        self.imageProvider = imageProvider
        self.baselineProvider = baselineProvider
        self.searchRegionContext = searchRegionContext
        self.artifactWriter = artifactWriter
        self.now = now
        self.sleep = sleep
    }

    func evaluate(
        _ request: AutomationConditionEvaluationRequest,
        condition: AutomationVisualCondition
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

            switch await scan(
                request,
                condition: condition,
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

    private func scan(
        _ request: AutomationConditionEvaluationRequest,
        condition: AutomationVisualCondition,
        sampleCount: Int,
        firstSampleAt: Date?,
        sampleAt: Date
    ) async -> VisualConditionScanResult {
        let image: CGImage
        do {
            image = try await captureDisplay()
        } catch {
            let outcome = await screenCaptureOutcome(for: error)
            return .failed(AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: makeFailureEvidence(
                    request: request,
                    condition: condition,
                    outcome: outcome,
                    sampleCount: sampleCount,
                    firstSampleAt: firstSampleAt,
                    sampleAt: sampleAt,
                    displayBounds: nil,
                    resolvedSearchRegion: nil,
                    artifacts: [],
                    summary: diagnosticSummary(
                        for: outcome,
                        fallback: "Visual condition could not capture the display"
                    ),
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
        let resolvedSearchRegion = resolvedRegion(
            for: condition.searchRegionResolution(in: regionContext)
        )
        guard let bitmap = VisualBitmap(image: image) else {
            let outcome = AutomationOutcome.rejected(
                reason: "Visual condition could not decode the display snapshot"
            )
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
            return .failed(AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: makeFailureEvidence(
                    request: request,
                    condition: condition,
                    outcome: outcome,
                    sampleCount: sampleCount,
                    firstSampleAt: firstSampleAt,
                    sampleAt: sampleAt,
                    displayBounds: displayBounds,
                    resolvedSearchRegion: resolvedSearchRegion,
                    artifacts: artifacts,
                    summary: diagnosticSummary(
                        for: outcome,
                        fallback: "Visual condition could not decode the display snapshot"
                    ),
                    errorDescription: nil
                )
            ))
        }

        guard let searchTarget = searchTarget(for: condition, context: regionContext, bitmap: bitmap) else {
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
            let evidence = makeEvidence(
                request: request,
                condition: condition,
                outcome: .conditionNotMatched,
                sampleCount: sampleCount,
                firstSampleAt: firstSampleAt,
                sampleAt: sampleAt,
                displayBounds: displayBounds,
                resolvedSearchRegion: resolvedSearchRegion,
                artifacts: artifacts,
                observation: VisualConditionObservation(
                    observedSummary: "Search region unavailable",
                    score: nil,
                    threshold: condition.threshold,
                    fields: [
                        AutomationConditionDiagnosticField(
                            id: "searchRegion",
                            title: "Search region",
                            value: "Unavailable"
                        )
                    ]
                )
            )
            return .notMatched(evidence)
        }

        let artifacts = await artifactWriter.saveSample(AutomationConditionEvidenceArtifactSample(
            runID: request.runID,
            workflowID: request.workflowID,
            taskID: request.taskID,
            conditionID: request.condition.id,
            image: image,
            displayBounds: displayBounds,
            resolvedSearchRegion: searchTarget.rect.rectValue,
            sampleAt: sampleAt
        ))

        do {
            let observation: VisualConditionObservation
            switch condition.type {
            case .pixelMatched:
                observation = try evaluatePixel(condition: condition, bitmap: bitmap, searchTarget: searchTarget)

            case .imageAppeared, .imageDisappeared:
                observation = try await evaluateImage(
                    request: request,
                    condition: condition,
                    bitmap: bitmap,
                    searchTarget: searchTarget
                )

            case .regionChanged:
                observation = try await evaluateRegionChanged(
                    request: request,
                    condition: condition,
                    bitmap: bitmap,
                    searchTarget: searchTarget
                )
            }
            let outcome: AutomationOutcome = observation.matched ? .conditionMatched : .conditionNotMatched
            let evidence = makeEvidence(
                request: request,
                condition: condition,
                outcome: outcome,
                sampleCount: sampleCount,
                firstSampleAt: firstSampleAt,
                sampleAt: sampleAt,
                displayBounds: displayBounds,
                resolvedSearchRegion: searchTarget.rect.rectValue,
                artifacts: artifacts,
                observation: observation
            )
            return observation.matched ? .matched(evidence) : .notMatched(evidence)
        } catch let error as VisualConditionConfigurationError {
            let outcome = AutomationOutcome.rejected(reason: error.description)
            return .failed(AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: makeFailureEvidence(
                    request: request,
                    condition: condition,
                    outcome: outcome,
                    sampleCount: sampleCount,
                    firstSampleAt: firstSampleAt,
                    sampleAt: sampleAt,
                    displayBounds: displayBounds,
                    resolvedSearchRegion: searchTarget.rect.rectValue,
                    artifacts: artifacts,
                    summary: error.description,
                    errorDescription: nil
                )
            ))
        } catch {
            let outcome = AutomationOutcome.rejected(reason: String(describing: error))
            return .failed(AutomationConditionEvaluationResult(
                outcome: outcome,
                evidence: makeFailureEvidence(
                    request: request,
                    condition: condition,
                    outcome: outcome,
                    sampleCount: sampleCount,
                    firstSampleAt: firstSampleAt,
                    sampleAt: sampleAt,
                    displayBounds: displayBounds,
                    resolvedSearchRegion: searchTarget.rect.rectValue,
                    artifacts: artifacts,
                    summary: diagnosticSummary(
                        for: outcome,
                        fallback: "Visual condition failed during evaluation"
                    ),
                    errorDescription: String(describing: error)
                )
            ))
        }
    }

    private func resolvedRegion(for resolution: AutomationOCRSearchRegionResolution) -> RectValue? {
        switch resolution {
        case .unrestricted, .unavailable:
            return nil
        case .resolved(let region):
            return region
        }
    }

    private func evaluatePixel(
        condition: AutomationVisualCondition,
        bitmap: VisualBitmap,
        searchTarget: VisualSearchTarget
    ) throws -> VisualConditionObservation {
        guard let targetColor = condition.targetColorHex.flatMap({ VisualRGBAColor(hex: $0) }) else {
            throw VisualConditionConfigurationError.missingTargetColor
        }

        let sampleRadius = condition.pixelSampleRadius.map(AutomationVisualCondition.clampedPixelSampleRadius)
            ?? AutomationVisualCondition.defaultPixelSampleRadius
        guard let point = pixelPoint(for: condition, searchTarget: searchTarget, bitmap: bitmap),
              let sample = bitmap.colorSample(centeredAt: point, radius: sampleRadius) else {
            throw VisualConditionConfigurationError.missingPixelTarget
        }

        let threshold = condition.threshold ?? 0.95
        let score = sample.averageColor.similarity(to: targetColor)
        return VisualConditionObservation(
            matched: score >= threshold,
            observedSummary: String(
                format: "Pixel similarity %.2f (%@ avg vs %@, samples %d)",
                score,
                sample.averageColor.hexDescription,
                targetColor.hexDescription,
                sample.sampleCount
            ),
            score: score,
            threshold: threshold,
            fields: [
                AutomationConditionDiagnosticField(id: "pixel", title: "Pixel", value: point.coordinateLabel),
                AutomationConditionDiagnosticField(
                    id: "sampledColor",
                    title: "Sampled color",
                    value: sample.averageColor.hexDescription
                ),
                AutomationConditionDiagnosticField(
                    id: "targetColor",
                    title: "Target color",
                    value: targetColor.hexDescription
                ),
                AutomationConditionDiagnosticField(id: "similarity", title: "Similarity", value: score.scoreLabel),
                AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: threshold.scoreLabel),
                AutomationConditionDiagnosticField(
                    id: "sampleRadius",
                    title: "Sample radius",
                    value: "\(sample.radius)"
                ),
                AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "\(sample.sampleCount)")
            ]
        )
    }

    private func evaluateImage(
        request: AutomationConditionEvaluationRequest,
        condition: AutomationVisualCondition,
        bitmap: VisualBitmap,
        searchTarget: VisualSearchTarget
    ) async throws -> VisualConditionObservation {
        guard let imageRef = condition.imageRef else {
            throw VisualConditionConfigurationError.missingImageReference
        }
        guard let templateImage = try await imageProvider(request, imageRef) else {
            throw VisualConditionConfigurationError.unavailableImageReference(imageRef)
        }
        guard let template = VisualBitmap(image: templateImage) else {
            throw VisualConditionConfigurationError.unreadableImageReference(imageRef)
        }

        let threshold = condition.threshold ?? 0.92
        let match = VisualImageMatcher.bestMatch(
            template: template,
            in: bitmap,
            searchRect: searchTarget.rect,
            threshold: threshold
        )
        let score = match.similarity
        let found = score >= threshold

        switch condition.type {
        case .imageAppeared:
            return VisualConditionObservation(
                matched: found,
                observedSummary: String(format: "Template similarity %.2f", score),
                score: score,
                threshold: threshold,
                fields: imageMatchFields(
                    imageRef: imageRef,
                    score: score,
                    threshold: threshold,
                    thresholdTitle: "Threshold",
                    match: match,
                    searchTarget: searchTarget
                )
            )
        case .imageDisappeared:
            return VisualConditionObservation(
                matched: !found,
                observedSummary: found
                    ? String(format: "Template still visible %.2f", score)
                    : String(format: "Template absent %.2f", score),
                score: score,
                threshold: threshold,
                fields: imageMatchFields(
                    imageRef: imageRef,
                    score: score,
                    threshold: threshold,
                    thresholdTitle: "Disappearance threshold",
                    match: match,
                    searchTarget: searchTarget
                )
            )
        case .pixelMatched, .regionChanged:
            return VisualConditionObservation(matched: false, observedSummary: "Unsupported image observation")
        }
    }

    private func imageMatchFields(
        imageRef: String,
        score: Double,
        threshold: Double,
        thresholdTitle: String,
        match: VisualImageMatchResult,
        searchTarget: VisualSearchTarget
    ) -> [AutomationConditionDiagnosticField] {
        var fields = [
            AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: imageRef),
            AutomationConditionDiagnosticField(id: "score", title: "Best similarity", value: score.scoreLabel),
            AutomationConditionDiagnosticField(id: "threshold", title: thresholdTitle, value: threshold.scoreLabel),
            AutomationConditionDiagnosticField(
                id: "locatorSimilarity",
                title: "Locator similarity",
                value: match.similarity.scoreLabel
            ),
            AutomationConditionDiagnosticField(
                id: "locatorThreshold",
                title: "Locator threshold",
                value: match.threshold.scoreLabel
            )
        ]

        if let matchedRect = match.matchedRect {
            let localRect = CGRect(
                x: matchedRect.minX - searchTarget.rect.minX,
                y: matchedRect.minY - searchTarget.rect.minY,
                width: matchedRect.width,
                height: matchedRect.height
            )
            fields.append(contentsOf: [
                AutomationConditionDiagnosticField(
                    id: "locatorX",
                    title: "Locator x",
                    value: Double(localRect.minX).scoreLabel
                ),
                AutomationConditionDiagnosticField(
                    id: "locatorY",
                    title: "Locator y",
                    value: Double(localRect.minY).scoreLabel
                ),
                AutomationConditionDiagnosticField(
                    id: "locatorWidth",
                    title: "Locator width",
                    value: Double(localRect.width).scoreLabel
                ),
                AutomationConditionDiagnosticField(
                    id: "locatorHeight",
                    title: "Locator height",
                    value: Double(localRect.height).scoreLabel
                )
            ])
        }

        return fields
    }

    private func evaluateRegionChanged(
        request: AutomationConditionEvaluationRequest,
        condition: AutomationVisualCondition,
        bitmap: VisualBitmap,
        searchTarget: VisualSearchTarget
    ) async throws -> VisualConditionObservation {
        guard let baselineRef = condition.baselineRef else {
            throw VisualConditionConfigurationError.missingBaselineReference
        }
        guard let baselineImage = try await baselineProvider(request, baselineRef) else {
            throw VisualConditionConfigurationError.unavailableBaselineReference(baselineRef)
        }
        guard let baseline = VisualBitmap(image: baselineImage) else {
            throw VisualConditionConfigurationError.unreadableBaselineReference(baselineRef)
        }

        let changeScore = VisualImageMatcher.changeScore(
            current: bitmap,
            baseline: baseline,
            currentRect: searchTarget.rect
        )
        let threshold = condition.threshold ?? 0.08
        return VisualConditionObservation(
            matched: changeScore >= threshold,
            observedSummary: String(format: "Region change %.2f", changeScore),
            score: changeScore,
            threshold: threshold,
            fields: [
                AutomationConditionDiagnosticField(id: "baselineRef", title: "Baseline", value: baselineRef),
                AutomationConditionDiagnosticField(id: "score", title: "Change score", value: changeScore.scoreLabel),
                AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: threshold.scoreLabel)
            ]
        )
    }

    private func makeEvidence(
        request: AutomationConditionEvaluationRequest,
        condition: AutomationVisualCondition,
        outcome: AutomationOutcome,
        sampleCount: Int,
        firstSampleAt: Date?,
        sampleAt: Date,
        displayBounds: RectValue,
        resolvedSearchRegion: RectValue?,
        artifacts: [AutomationConditionDiagnosticArtifact],
        observation: VisualConditionObservation
    ) -> AutomationConditionEvaluationEvidence {
        var fields = [
            AutomationConditionDiagnosticField(id: "condition", title: "Condition", value: condition.type.rawValue),
            AutomationConditionDiagnosticField(id: "samples", title: "Samples", value: "\(sampleCount)")
        ]
        if let regionRef = condition.regionRef {
            fields.append(AutomationConditionDiagnosticField(id: "regionRef", title: "Region", value: regionRef))
        }
        fields.append(contentsOf: observation.fields)

        return AutomationConditionEvaluationEvidence(
            runID: request.runID,
            workflowID: request.workflowID,
            taskID: request.taskID,
            conditionID: request.condition.id,
            kind: evidenceKind(for: condition.type),
            outcome: outcome,
            evaluatedAt: sampleAt,
            firstSampleAt: firstSampleAt,
            lastSampleAt: sampleAt,
            sampleCount: sampleCount,
            displayBounds: displayBounds,
            resolvedSearchRegion: resolvedSearchRegion,
            searchRegionSpace: condition.searchRegionSpace,
            targetDescription: targetDescription(for: condition),
            observedSummary: observation.observedSummary,
            score: observation.score,
            threshold: observation.threshold,
            fields: fields,
            artifacts: artifacts
        )
    }

    private func makeFailureEvidence(
        request: AutomationConditionEvaluationRequest,
        condition: AutomationVisualCondition,
        outcome: AutomationOutcome,
        sampleCount: Int,
        firstSampleAt: Date?,
        sampleAt: Date,
        displayBounds: RectValue?,
        resolvedSearchRegion: RectValue?,
        artifacts: [AutomationConditionDiagnosticArtifact],
        summary: String,
        errorDescription: String?
    ) -> AutomationConditionEvaluationEvidence {
        var fields = [
            AutomationConditionDiagnosticField(id: "condition", title: "Condition", value: condition.type.rawValue),
            AutomationConditionDiagnosticField(id: "samples", title: "Samples", value: "\(sampleCount)"),
            AutomationConditionDiagnosticField(id: "failure", title: "Failure", value: summary)
        ]
        if let regionRef = condition.regionRef {
            fields.append(AutomationConditionDiagnosticField(id: "regionRef", title: "Region", value: regionRef))
        }
        if let imageRef = condition.imageRef {
            fields.append(AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: imageRef))
        }
        if let baselineRef = condition.baselineRef {
            fields.append(AutomationConditionDiagnosticField(id: "baselineRef", title: "Baseline", value: baselineRef))
        }
        if let targetColorHex = condition.targetColorHex {
            fields.append(AutomationConditionDiagnosticField(
                id: "targetColor",
                title: "Target color",
                value: targetColorHex
            ))
        }
        if let errorDescription, !errorDescription.isEmpty {
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
            kind: evidenceKind(for: condition.type),
            outcome: outcome,
            evaluatedAt: sampleAt,
            firstSampleAt: firstSampleAt,
            lastSampleAt: sampleAt,
            sampleCount: sampleCount,
            displayBounds: displayBounds,
            resolvedSearchRegion: resolvedSearchRegion,
            searchRegionSpace: condition.searchRegionSpace,
            targetDescription: targetDescription(for: condition),
            observedSummary: summary,
            threshold: condition.threshold,
            fields: fields,
            artifacts: artifacts
        )
    }

    private func evidenceKind(for type: AutomationVisualConditionType) -> AutomationConditionEvidenceKind {
        switch type {
        case .regionChanged:
            return .regionChanged
        case .imageAppeared:
            return .imageAppeared
        case .imageDisappeared:
            return .imageDisappeared
        case .pixelMatched:
            return .pixelMatched
        }
    }

    private func targetDescription(for condition: AutomationVisualCondition) -> String {
        switch condition.type {
        case .regionChanged:
            return condition.baselineRef ?? condition.regionRef ?? "Watched region"
        case .imageAppeared, .imageDisappeared:
            return condition.imageRef ?? "Image reference"
        case .pixelMatched:
            return condition.targetColorHex ?? condition.regionRef ?? "Target pixel"
        }
    }

    private func searchTarget(
        for condition: AutomationVisualCondition,
        context: AutomationOCRSearchRegionContext,
        bitmap: VisualBitmap
    ) -> VisualSearchTarget? {
        switch condition.searchRegionResolution(in: context) {
        case .unrestricted:
            return VisualSearchTarget(rect: bitmap.bounds, isUnrestricted: true)
        case .unavailable:
            return nil
        case .resolved(let region):
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
            guard let pixelRect = bitmap.pixelRect(for: rect) else {
                return nil
            }
            return VisualSearchTarget(rect: pixelRect, isUnrestricted: false)
        }
    }

    private func pixelPoint(
        for condition: AutomationVisualCondition,
        searchTarget: VisualSearchTarget,
        bitmap: VisualBitmap
    ) -> CGPoint? {
        if let pixel = condition.pixel {
            let usesNormalizedPoint = pixel.x >= 0
                && pixel.x <= 1
                && pixel.y >= 0
                && pixel.y <= 1
            if usesNormalizedPoint {
                return CGPoint(
                    x: searchTarget.rect.minX + CGFloat(pixel.x) * searchTarget.rect.width,
                    y: searchTarget.rect.minY + CGFloat(pixel.y) * searchTarget.rect.height
                )
                .clamped(to: bitmap.bounds)
            }
            return CGPoint(x: pixel.x, y: pixel.y).clamped(to: bitmap.bounds)
        }

        guard !searchTarget.isUnrestricted else {
            return nil
        }
        return CGPoint(x: searchTarget.rect.midX, y: searchTarget.rect.midY).clamped(to: bitmap.bounds)
    }

    private func screenCaptureOutcome(for error: Error) async -> AutomationOutcome {
        let screenCaptureStatus = await MainActor.run {
            PermissionCenter.shared.checkScreenCaptureAccess()
        }

        if screenCaptureStatus != .authorized {
            return .permissionDenied(
                permission: .screenRecording,
                message: "Screen Recording permission is required for visual conditions"
            )
        }

        if let screenError = error as? ScreenCaptureError {
            switch screenError {
            case .noMatchingDisplay:
                return .rejected(reason: "No matching display for visual condition")
            case .noMatchingWindow:
                return .rejected(reason: "No matching window for visual condition")
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
}

private struct VisualSearchTarget: Sendable {
    var rect: CGRect
    var isUnrestricted: Bool
}

private struct VisualConditionObservation: Sendable {
    var matched: Bool
    var observedSummary: String
    var score: Double?
    var threshold: Double?
    var fields: [AutomationConditionDiagnosticField]

    init(
        matched: Bool = false,
        observedSummary: String,
        score: Double? = nil,
        threshold: Double? = nil,
        fields: [AutomationConditionDiagnosticField] = []
    ) {
        self.matched = matched
        self.observedSummary = observedSummary
        self.score = score
        self.threshold = threshold
        self.fields = fields
    }
}

private enum VisualConditionScanResult: Sendable {
    case matched(AutomationConditionEvaluationEvidence)
    case notMatched(AutomationConditionEvaluationEvidence)
    case failed(AutomationConditionEvaluationResult)
}

private enum VisualConditionConfigurationError: Error, CustomStringConvertible, Sendable {
    case missingTargetColor
    case missingPixelTarget
    case missingImageReference
    case unavailableImageReference(String)
    case unreadableImageReference(String)
    case missingBaselineReference
    case unavailableBaselineReference(String)
    case unreadableBaselineReference(String)

    var description: String {
        switch self {
        case .missingTargetColor:
            return "Pixel visual conditions require a target color"
        case .missingPixelTarget:
            return "Pixel visual conditions require a pixel point or concrete search region"
        case .missingImageReference:
            return "Image visual conditions require an image reference"
        case .unavailableImageReference(let reference):
            return "Image reference '\(reference)' is not available for visual evaluation"
        case .unreadableImageReference(let reference):
            return "Image reference '\(reference)' could not be decoded for visual evaluation"
        case .missingBaselineReference:
            return "Region change visual conditions require a baseline reference"
        case .unavailableBaselineReference(let reference):
            return "Baseline reference '\(reference)' is not available for visual evaluation"
        case .unreadableBaselineReference(let reference):
            return "Baseline reference '\(reference)' could not be decoded for visual evaluation"
        }
    }
}

private struct VisualBitmap: Sendable {
    var width: Int
    var height: Int
    var bytes: [UInt8]

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    init?(image: CGImage) {
        guard image.width > 0, image.height > 0 else {
            return nil
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        let didDraw = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard didDraw else {
            return nil
        }

        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func color(atX x: Int, y: Int) -> VisualRGBAColor? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }

        let offset = (y * width + x) * 4
        guard offset + 3 < bytes.count else {
            return nil
        }

        return VisualRGBAColor(
            red: Double(bytes[offset]),
            green: Double(bytes[offset + 1]),
            blue: Double(bytes[offset + 2]),
            alpha: Double(bytes[offset + 3])
        )
    }

    func colorSample(centeredAt point: CGPoint, radius: Int) -> VisualPixelSample? {
        let centerX = min(max(Int(point.x), 0), width - 1)
        let centerY = min(max(Int(point.y), 0), height - 1)
        let sampleRadius = AutomationVisualCondition.clampedPixelSampleRadius(radius)
        let minX = max(0, centerX - sampleRadius)
        let maxX = min(width - 1, centerX + sampleRadius)
        let minY = max(0, centerY - sampleRadius)
        let maxY = min(height - 1, centerY + sampleRadius)

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var alpha = 0.0
        var count = 0
        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = color(atX: x, y: y) else {
                    continue
                }
                red += color.red
                green += color.green
                blue += color.blue
                alpha += color.alpha
                count += 1
            }
        }
        guard count > 0 else {
            return nil
        }

        return VisualPixelSample(
            center: CGPoint(x: centerX, y: centerY),
            radius: sampleRadius,
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            sampleCount: count,
            averageColor: VisualRGBAColor(
                red: red / Double(count),
                green: green / Double(count),
                blue: blue / Double(count),
                alpha: alpha / Double(count)
            )
        )
    }

    func pixelRect(for rect: CGRect) -> CGRect? {
        let clipped = rect.standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }

        let minX = max(0, min(width, Int(floor(clipped.minX))))
        let minY = max(0, min(height, Int(floor(clipped.minY))))
        let maxX = max(0, min(width, Int(ceil(clipped.maxX))))
        let maxY = max(0, min(height, Int(ceil(clipped.maxY))))
        guard maxX > minX, maxY > minY else {
            return nil
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private struct VisualPixelSample: Equatable, Sendable {
    var center: CGPoint
    var radius: Int
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var sampleCount: Int
    var averageColor: VisualRGBAColor
}

private struct VisualRGBAColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let expanded: String
        switch value.count {
        case 3:
            expanded = value.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = value
        default:
            return nil
        }

        guard let numeric = UInt64(expanded, radix: 16) else {
            return nil
        }

        if expanded.count == 8 {
            self.red = Double((numeric >> 24) & 0xFF)
            self.green = Double((numeric >> 16) & 0xFF)
            self.blue = Double((numeric >> 8) & 0xFF)
            self.alpha = Double(numeric & 0xFF)
        } else {
            self.red = Double((numeric >> 16) & 0xFF)
            self.green = Double((numeric >> 8) & 0xFF)
            self.blue = Double(numeric & 0xFF)
            self.alpha = 255
        }
    }

    func similarity(to other: VisualRGBAColor) -> Double {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        let distance = sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
        let maxDistance = sqrt(3 * 255.0 * 255.0)
        return max(0, min(1, 1 - distance / maxDistance))
    }
}

private struct VisualImageMatchResult: Equatable, Sendable {
    var similarity: Double
    var threshold: Double
    var matchedRect: CGRect?

    init(similarity: Double, threshold: Double, matchedRect: CGRect?) {
        self.similarity = max(0, min(1, similarity))
        self.threshold = max(0, min(1, threshold))
        self.matchedRect = matchedRect
    }
}

private enum VisualImageMatcher {
    static func contains(
        template: VisualBitmap,
        in haystack: VisualBitmap,
        searchRect: CGRect,
        threshold: Double
    ) -> Bool {
        bestMatch(
            template: template,
            in: haystack,
            searchRect: searchRect,
            threshold: threshold
        )
        .matchedRect != nil
    }

    static func bestSimilarity(
        template: VisualBitmap,
        in haystack: VisualBitmap,
        searchRect: CGRect
    ) -> Double {
        bestMatch(template: template, in: haystack, searchRect: searchRect, threshold: 1).similarity
    }

    static func bestMatch(
        template: VisualBitmap,
        in haystack: VisualBitmap,
        searchRect: CGRect,
        threshold: Double
    ) -> VisualImageMatchResult {
        guard let rect = haystack.pixelRect(for: searchRect) else {
            return VisualImageMatchResult(similarity: 0, threshold: threshold, matchedRect: nil)
        }

        let templateWidth = template.width
        let templateHeight = template.height
        guard templateWidth > 0,
              templateHeight > 0,
              templateWidth <= Int(rect.width),
              templateHeight <= Int(rect.height) else {
            return VisualImageMatchResult(similarity: 0, threshold: threshold, matchedRect: nil)
        }

        let minX = Int(rect.minX)
        let minY = Int(rect.minY)
        let maxX = Int(rect.maxX) - templateWidth
        let maxY = Int(rect.maxY) - templateHeight
        let step = max(1, min(templateWidth, templateHeight) / 6)
        var best = 0.0
        var bestRect: CGRect?

        for y in candidatePositions(from: minY, through: maxY, step: step) {
            for x in candidatePositions(from: minX, through: maxX, step: step) {
                let candidate = similarity(template: template, in: haystack, originX: x, originY: y)
                if candidate > best {
                    best = candidate
                    bestRect = CGRect(x: x, y: y, width: templateWidth, height: templateHeight)
                }
            }
        }

        return VisualImageMatchResult(
            similarity: best,
            threshold: threshold,
            matchedRect: best >= threshold ? bestRect : nil
        )
    }

    static func changeScore(
        current: VisualBitmap,
        baseline: VisualBitmap,
        currentRect: CGRect
    ) -> Double {
        guard let rect = current.pixelRect(for: currentRect) else {
            return 0
        }

        let samplesX = sampleCount(for: Int(rect.width))
        let samplesY = sampleCount(for: Int(rect.height))
        var totalSimilarity = 0.0
        var samples = 0
        let baselineIsFullDisplay = baseline.width == current.width && baseline.height == current.height

        for sampleY in 0..<samplesY {
            let normalizedY = (Double(sampleY) + 0.5) / Double(samplesY)
            let currentY = clamp(Int(rect.minY + normalizedY * rect.height), lower: 0, upper: current.height - 1)
            let baselineY = baselineIsFullDisplay
                ? currentY
                : clamp(Int(normalizedY * Double(baseline.height)), lower: 0, upper: baseline.height - 1)

            for sampleX in 0..<samplesX {
                let normalizedX = (Double(sampleX) + 0.5) / Double(samplesX)
                let currentX = clamp(Int(rect.minX + normalizedX * rect.width), lower: 0, upper: current.width - 1)
                let baselineX = baselineIsFullDisplay
                    ? currentX
                    : clamp(Int(normalizedX * Double(baseline.width)), lower: 0, upper: baseline.width - 1)

                guard let currentColor = current.color(atX: currentX, y: currentY),
                      let baselineColor = baseline.color(atX: baselineX, y: baselineY) else {
                    continue
                }

                totalSimilarity += currentColor.similarity(to: baselineColor)
                samples += 1
            }
        }

        guard samples > 0 else {
            return 0
        }

        return max(0, min(1, 1 - totalSimilarity / Double(samples)))
    }

    private static func similarity(
        template: VisualBitmap,
        in haystack: VisualBitmap,
        originX: Int,
        originY: Int
    ) -> Double {
        let samplesX = imageSampleCount(for: template.width)
        let samplesY = imageSampleCount(for: template.height)
        var totalSimilarity = 0.0
        var samples = 0

        for sampleY in 0..<samplesY {
            let templateY = sampleCoordinate(sampleY, size: template.height, count: samplesY)
            let haystackY = originY + templateY

            for sampleX in 0..<samplesX {
                let templateX = sampleCoordinate(sampleX, size: template.width, count: samplesX)
                let haystackX = originX + templateX

                guard let templateColor = template.color(atX: templateX, y: templateY),
                      let haystackColor = haystack.color(atX: haystackX, y: haystackY) else {
                    continue
                }

                totalSimilarity += templateColor.similarity(to: haystackColor)
                samples += 1
            }
        }

        guard samples > 0 else {
            return 0
        }

        return totalSimilarity / Double(samples)
    }

    private static func sampleCount(for size: Int) -> Int {
        min(12, max(3, size / 16))
    }

    private static func imageSampleCount(for size: Int) -> Int {
        min(16, max(3, size))
    }

    private static func sampleCoordinate(_ index: Int, size: Int, count: Int) -> Int {
        clamp(
            Int((Double(index) + 0.5) * Double(size) / Double(count)),
            lower: 0,
            upper: size - 1
        )
    }

    private static func candidatePositions(from start: Int, through end: Int, step: Int) -> [Int] {
        guard end >= start else {
            return []
        }

        var positions: [Int] = []
        var position = start
        while position <= end {
            positions.append(position)
            position += max(1, step)
        }
        if positions.last != end {
            positions.append(end)
        }
        return positions
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), max(rect.minX, rect.maxX - 1)),
            y: min(max(y, rect.minY), max(rect.minY, rect.maxY - 1))
        )
    }

    var coordinateLabel: String {
        String(format: "%.0f, %.0f", x, y)
    }
}

private extension CGRect {
    var rectValue: RectValue {
        RectValue(x: minX, y: minY, width: width, height: height)
    }
}

private extension Double {
    var scoreLabel: String {
        String(format: "%.2f", self)
    }
}

private extension VisualRGBAColor {
    var hexDescription: String {
        String(
            format: "#%02X%02X%02X",
            Int(red.rounded()).clampedColorComponent,
            Int(green.rounded()).clampedColorComponent,
            Int(blue.rounded()).clampedColorComponent
        )
    }
}

private extension Int {
    var clampedColorComponent: Int {
        Swift.min(Swift.max(self, 0), 255)
    }
}
