import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import SparkleRecorderCore
import Vision

final class AutomationVisualCGImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

struct AutomationVisualImageFrame: Sendable {
    var sample: AutomationVisualFrameSample
    var image: AutomationVisualCGImage

    init(sample: AutomationVisualFrameSample, image: CGImage) {
        self.sample = sample
        self.image = AutomationVisualCGImage(image)
    }
}

struct AutomationVisualRoutedFrame: Sendable {
    var request: AutomationVisualDetectorRequest
    var route: AutomationVisualFrameRoute
    var croppedImage: AutomationVisualCGImage
    var cropRect: RectValue
    var sourcePixelRect: RectValue
    var isFullFrame: Bool
}

enum AutomationVisualLiveFrameRouterError: Error, Equatable {
    case noLatestFrame
    case noFreshFrame(UUID)
    case unsupportedCondition
    case routeUnavailable(AutomationVisualFrameRouteUnavailableReason)
    case cropUnavailable
}

struct AutomationVisualFrameDetectorClient: Sendable {
    var evaluate: @Sendable (AutomationVisualRoutedFrame) async -> AutomationVisualDetectorResult

    init(
        evaluate: @escaping @Sendable (AutomationVisualRoutedFrame) async -> AutomationVisualDetectorResult
    ) {
        self.evaluate = evaluate
    }
}

struct AutomationVisualTextDetectorClient: Sendable {
    var detectText: @Sendable (AutomationVisualRoutedFrame) async throws -> [TextDetection]

    init(
        detectText: @escaping @Sendable (AutomationVisualRoutedFrame) async throws -> [TextDetection]
    ) {
        self.detectText = detectText
    }

    static func vision(_ detector: VisionDetector = VisionDetector()) -> AutomationVisualTextDetectorClient {
        AutomationVisualTextDetectorClient { routedFrame in
            try await detector.detectText(in: routedFrame.croppedImage.image)
        }
    }
}

typealias AutomationVisualTemplateImageProvider = @Sendable (
    _ routedFrame: AutomationVisualRoutedFrame,
    _ reference: String
) async throws -> CGImage?

struct AutomationVisualFeaturePrintClient: Sendable {
    var distance: @Sendable (_ source: CGImage, _ runtime: CGImage) async throws -> Double

    init(
        distance: @escaping @Sendable (_ source: CGImage, _ runtime: CGImage) async throws -> Double
    ) {
        self.distance = distance
    }

    static func vision() -> AutomationVisualFeaturePrintClient {
        AutomationVisualFeaturePrintClient { source, runtime in
            try await Task.detached(priority: .userInitiated) {
                let sourcePrint = try featurePrint(for: source)
                let runtimePrint = try featurePrint(for: runtime)
                var distance: Float = 0
                try sourcePrint.computeDistance(&distance, to: runtimePrint)
                return Double(distance)
            }.value
        }
    }

    private static func featurePrint(for image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw AutomationVisualFeaturePrintError.missingObservation
        }
        return observation
    }
}

private enum AutomationVisualFeaturePrintError: Error {
    case missingObservation
}

struct AutomationVisualImageVerificationResult: Equatable, Sendable {
    var similarity: Double
    var threshold: Double

    init(similarity: Double, threshold: Double) {
        self.similarity = max(0, min(1, similarity))
        self.threshold = max(0, min(1, threshold))
    }

    var isMatched: Bool {
        similarity >= threshold
    }
}

struct AutomationVisualImageVerifierClient: Sendable {
    var verify: @Sendable (_ template: CGImage, _ runtime: CGImage) async throws -> AutomationVisualImageVerificationResult

    init(
        verify: @escaping @Sendable (_ template: CGImage, _ runtime: CGImage) async throws -> AutomationVisualImageVerificationResult
    ) {
        self.verify = verify
    }

    static func pixelSimilarity(threshold: Double = 0.85) -> AutomationVisualImageVerifierClient {
        AutomationVisualImageVerifierClient { template, runtime in
            AutomationVisualImageVerificationResult(
                similarity: AutomationVisualPixelBitmap.imageSimilarity(template: template, runtime: runtime),
                threshold: threshold
            )
        }
    }
}

struct AutomationVisualImageLocationResult: Equatable, Sendable {
    var similarity: Double
    var threshold: Double
    var matchedRect: RectValue?

    init(similarity: Double, threshold: Double, matchedRect: RectValue?) {
        self.similarity = max(0, min(1, similarity))
        self.threshold = max(0, min(1, threshold))
        self.matchedRect = matchedRect
    }

    var isMatched: Bool {
        matchedRect != nil && similarity >= threshold
    }
}

struct AutomationVisualImageLocatorClient: Sendable {
    var locate: @Sendable (_ template: CGImage, _ runtime: CGImage) async throws -> AutomationVisualImageLocationResult

    init(
        locate: @escaping @Sendable (_ template: CGImage, _ runtime: CGImage) async throws -> AutomationVisualImageLocationResult
    ) {
        self.locate = locate
    }

    static func pixelSimilarity(
        threshold: Double = 0.92,
        stride: Int = 2
    ) -> AutomationVisualImageLocatorClient {
        AutomationVisualImageLocatorClient { template, runtime in
            AutomationVisualPixelBitmap.locate(
                template: template,
                runtime: runtime,
                threshold: threshold,
                stride: stride
            )
        }
    }
}

extension AutomationVisualFrameDetectorClient {
    static func ocrText(
        textDetector: AutomationVisualTextDetectorClient = .vision(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationVisualFrameDetectorClient {
        AutomationVisualFrameDetectorClient { routedFrame in
            await evaluateOCRText(
                routedFrame,
                textDetector: textDetector,
                evaluatedAt: now()
            )
        }
    }

    static func featurePrintImage(
        imageProvider: @escaping AutomationVisualTemplateImageProvider = { _, _ in nil },
        featurePrint: AutomationVisualFeaturePrintClient = .vision(),
        verifier: AutomationVisualImageVerifierClient? = nil,
        locator: AutomationVisualImageLocatorClient? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationVisualFrameDetectorClient {
        AutomationVisualFrameDetectorClient { routedFrame in
            await evaluateFeaturePrintImage(
                routedFrame,
                imageProvider: imageProvider,
                featurePrint: featurePrint,
                verifier: verifier,
                locator: locator,
                evaluatedAt: now()
            )
        }
    }

    static func pixelColor(
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationVisualFrameDetectorClient {
        AutomationVisualFrameDetectorClient { routedFrame in
            evaluatePixelColor(routedFrame, evaluatedAt: now())
        }
    }

    static func regionDiff(
        baselineProvider: @escaping AutomationVisualTemplateImageProvider = { _, _ in nil },
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationVisualFrameDetectorClient {
        AutomationVisualFrameDetectorClient { routedFrame in
            await evaluateRegionDiff(
                routedFrame,
                baselineProvider: baselineProvider,
                evaluatedAt: now()
            )
        }
    }

    private static func evaluateOCRText(
        _ routedFrame: AutomationVisualRoutedFrame,
        textDetector: AutomationVisualTextDetectorClient,
        evaluatedAt: Date
    ) async -> AutomationVisualDetectorResult {
        guard case .ocrText(let condition) = routedFrame.request.condition.kind else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: routedFrame.request.detectorKind,
                outcome: .rejected(reason: "OCR detector received a non-OCR condition"),
                observedSummary: "Unsupported routed condition for OCR detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        do {
            let detections = try await textDetector.detectText(routedFrame)
            let matched = detections.first { detection in
                matches(candidate: detection.text, target: condition.text, mode: condition.matchMode)
            }
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .ocrText,
                outcome: matched == nil ? .conditionNotMatched : .conditionMatched,
                observedSummary: observedSummary(detections: detections, matched: matched),
                sampleCount: 1,
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                matchedRegion: matched.map { matchedRegion(for: $0, in: routedFrame.cropRect) },
                evaluatedAt: evaluatedAt
            )
        } catch {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .ocrText,
                outcome: .rejected(reason: "OCR detector failed: \(String(describing: error))"),
                observedSummary: "OCR detector failed before producing text observations",
                sampleCount: 1,
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }
    }

    private static func evaluateFeaturePrintImage(
        _ routedFrame: AutomationVisualRoutedFrame,
        imageProvider: AutomationVisualTemplateImageProvider,
        featurePrint: AutomationVisualFeaturePrintClient,
        verifier: AutomationVisualImageVerifierClient?,
        locator: AutomationVisualImageLocatorClient?,
        evaluatedAt: Date
    ) async -> AutomationVisualDetectorResult {
        guard case .visual(let condition) = routedFrame.request.condition.kind,
              condition.type == .imageAppeared || condition.type == .imageDisappeared else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: routedFrame.request.detectorKind,
                outcome: .rejected(reason: "Feature-print detector received a non-image condition"),
                observedSummary: "Unsupported routed condition for feature-print detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        guard let imageRef = condition.imageRef else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .featurePrintImage,
                outcome: .rejected(reason: "Feature-print detector missing image reference"),
                observedSummary: "No image reference configured for feature-print detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        let templateImage: CGImage
        do {
            guard let image = try await imageProvider(routedFrame, imageRef) else {
                return AutomationVisualDetectorResult(
                    requestID: routedFrame.request.id,
                    detectorKind: .featurePrintImage,
                    outcome: .rejected(reason: "Feature-print detector unavailable image reference: \(imageRef)"),
                    observedSummary: "Image reference unavailable: \(imageRef)",
                    runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                    evaluatedAt: evaluatedAt
                )
            }
            templateImage = image
        } catch {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .featurePrintImage,
                outcome: .rejected(reason: "Feature-print detector failed to load image reference: \(imageRef)"),
                observedSummary: "Image reference load failed: \(String(describing: error))",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        do {
            let distance = try await featurePrint.distance(templateImage, routedFrame.croppedImage.image)
            let threshold = featurePrintDistanceThreshold(for: condition)
            let score = AutomationVisualDetectorScore(
                value: distance,
                threshold: threshold,
                comparison: .lessThanOrEqual
            )
            let coarseFound = score.isMatched
            let location = try await locator?.locate(templateImage, routedFrame.croppedImage.image)
            let verification = location == nil && coarseFound
                ? try await verifier?.verify(templateImage, routedFrame.croppedImage.image)
                : nil
            let found = location?.isMatched ?? (coarseFound && (verification?.isMatched ?? true))
            let outcome: AutomationOutcome
            switch condition.type {
            case .imageAppeared:
                outcome = found ? .conditionMatched : .conditionNotMatched
            case .imageDisappeared:
                outcome = found ? .conditionNotMatched : .conditionMatched
            case .pixelMatched, .regionChanged:
                outcome = .rejected(reason: "Feature-print detector received a non-image condition")
            }

            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .featurePrintImage,
                outcome: outcome,
                score: featurePrintResultScore(featureScore: score, location: location),
                observedSummary: featurePrintSummary(
                    condition: condition,
                    imageRef: imageRef,
                    distance: distance,
                    threshold: threshold,
                    coarseFound: coarseFound,
                    found: found,
                    verification: verification,
                    location: location
                ),
                sampleCount: 1,
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                matchedRegion: found
                    ? matchedImageRegion(location: location, routedFrame: routedFrame)
                    : nil,
                fields: featurePrintFields(
                    imageRef: imageRef,
                    distance: distance,
                    threshold: threshold,
                    verification: verification,
                    location: location
                ),
                evaluatedAt: evaluatedAt
            )
        } catch {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .featurePrintImage,
                outcome: .rejected(reason: "Feature-print detector failed: \(String(describing: error))"),
                observedSummary: "Feature-print comparison failed for image reference: \(imageRef)",
                sampleCount: 1,
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }
    }

    private static func evaluatePixelColor(
        _ routedFrame: AutomationVisualRoutedFrame,
        evaluatedAt: Date
    ) -> AutomationVisualDetectorResult {
        guard case .visual(let condition) = routedFrame.request.condition.kind,
              condition.type == .pixelMatched else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: routedFrame.request.detectorKind,
                outcome: .rejected(reason: "Pixel detector received a non-pixel condition"),
                observedSummary: "Unsupported routed condition for pixel detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        guard let targetHex = condition.targetColorHex,
              let targetColor = AutomationVisualRGBAColor(hex: targetHex) else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .pixelColor,
                outcome: .rejected(reason: "Pixel detector missing target color"),
                observedSummary: "No target color configured for pixel detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        let sampleRadius = pixelSampleRadius(for: condition)
        guard let bitmap = AutomationVisualPixelBitmap(image: routedFrame.croppedImage.image),
              let point = pixelPoint(for: condition, routedFrame: routedFrame, bitmap: bitmap),
              let sample = bitmap.colorSample(centeredAt: point, radius: sampleRadius) else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .pixelColor,
                outcome: .rejected(reason: "Pixel detector missing sample point"),
                observedSummary: "No valid sample point available for pixel detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        let threshold = condition.threshold ?? 0.95
        let similarity = sample.averageColor.similarity(to: targetColor)
        let score = AutomationVisualDetectorScore(
            value: similarity,
            threshold: threshold,
            comparison: .greaterThanOrEqual
        )
        return AutomationVisualDetectorResult(
            requestID: routedFrame.request.id,
            detectorKind: .pixelColor,
            outcome: score.isMatched ? .conditionMatched : .conditionNotMatched,
            score: score,
            observedSummary: String(
                format: "Pixel similarity %.2f (%@ avg vs %@, samples %d)",
                similarity,
                sample.averageColor.hexDescription,
                targetColor.hexDescription,
                sample.sampleCount
            ),
            sampleCount: 1,
            runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
            matchedRegion: score.isMatched
                ? sampledRegion(for: sample, routedFrame: routedFrame, bitmap: bitmap)
                : nil,
            fields: pixelColorFields(
                sample: sample,
                targetColor: targetColor,
                similarity: similarity,
                threshold: threshold
            ),
            evaluatedAt: evaluatedAt
        )
    }

    private static func evaluateRegionDiff(
        _ routedFrame: AutomationVisualRoutedFrame,
        baselineProvider: AutomationVisualTemplateImageProvider,
        evaluatedAt: Date
    ) async -> AutomationVisualDetectorResult {
        guard case .visual(let condition) = routedFrame.request.condition.kind,
              condition.type == .regionChanged else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: routedFrame.request.detectorKind,
                outcome: .rejected(reason: "Region-diff detector received a non-region condition"),
                observedSummary: "Unsupported routed condition for region-diff detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        guard let baselineRef = condition.baselineRef else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .regionDiff,
                outcome: .rejected(reason: "Region-diff detector missing baseline reference"),
                observedSummary: "No baseline reference configured for region-diff detector",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        let baselineImage: CGImage
        do {
            guard let image = try await baselineProvider(routedFrame, baselineRef) else {
                return AutomationVisualDetectorResult(
                    requestID: routedFrame.request.id,
                    detectorKind: .regionDiff,
                    outcome: .rejected(reason: "Region-diff detector unavailable baseline reference: \(baselineRef)"),
                    observedSummary: "Baseline reference unavailable: \(baselineRef)",
                    runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                    evaluatedAt: evaluatedAt
                )
            }
            baselineImage = image
        } catch {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .regionDiff,
                outcome: .rejected(reason: "Region-diff detector failed to load baseline reference: \(baselineRef)"),
                observedSummary: "Baseline reference load failed: \(String(describing: error))",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        guard let current = AutomationVisualPixelBitmap(image: routedFrame.croppedImage.image),
              let baseline = AutomationVisualPixelBitmap(image: baselineImage) else {
            return AutomationVisualDetectorResult(
                requestID: routedFrame.request.id,
                detectorKind: .regionDiff,
                outcome: .rejected(reason: "Region-diff detector could not decode current or baseline image"),
                observedSummary: "Current or baseline image could not be decoded for region diff",
                runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
                evaluatedAt: evaluatedAt
            )
        }

        let metrics = current.regionDiffMetrics(comparedTo: baseline)
        let threshold = condition.threshold ?? 0.08
        let score = AutomationVisualDetectorScore(
            value: metrics.changeScore,
            threshold: threshold,
            comparison: .greaterThanOrEqual
        )
        return AutomationVisualDetectorResult(
            requestID: routedFrame.request.id,
            detectorKind: .regionDiff,
            outcome: score.isMatched ? .conditionMatched : .conditionNotMatched,
            score: score,
            observedSummary: String(
                format: "Region change %.2f (changed %.2f, max %.2f, samples %d)",
                metrics.changeScore,
                metrics.changedPixelRatio,
                metrics.maxDelta,
                metrics.sampleCount
            ),
            sampleCount: 1,
            runtimeArtifactRef: runtimeArtifactRef(for: routedFrame),
            matchedRegion: score.isMatched ? routedFrame.cropRect : nil,
            fields: regionDiffFields(
                baselineRef: baselineRef,
                metrics: metrics,
                threshold: threshold
            ),
            evaluatedAt: evaluatedAt
        )
    }

    private static func matches(candidate: String, target: String, mode: TextMatchMode) -> Bool {
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

    private static func observedSummary(
        detections: [TextDetection],
        matched: TextDetection?
    ) -> String {
        if let matched {
            return "Matched text: \(matched.text)"
        }

        let detectedTexts = detections
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !detectedTexts.isEmpty else {
            return "No text detected in routed crop"
        }

        return "Detected text: " + detectedTexts.prefix(3).joined(separator: ", ")
    }

    private static func matchedRegion(
        for detection: TextDetection,
        in cropRect: RectValue
    ) -> RectValue {
        let minX = max(cropRect.x, cropRect.x + detection.boundingBox.minX * cropRect.width)
        let minY = max(cropRect.y, cropRect.y + detection.boundingBox.minY * cropRect.height)
        let cropMaxX = cropRect.x + cropRect.width
        let cropMaxY = cropRect.y + cropRect.height
        let maxX = min(cropMaxX, cropRect.x + detection.boundingBox.maxX * cropRect.width)
        let maxY = min(cropMaxY, cropRect.y + detection.boundingBox.maxY * cropRect.height)
        guard maxX > minX, maxY > minY else {
            return RectValue(x: cropRect.x, y: cropRect.y, width: 0, height: 0)
        }

        return RectValue(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func featurePrintDistanceThreshold(for condition: AutomationVisualCondition) -> Double {
        guard let normalized = condition.threshold else {
            return 15
        }

        return max(0, (1 - normalized) * 30)
    }

    private static func featurePrintSummary(
        condition: AutomationVisualCondition,
        imageRef: String,
        distance: Double,
        threshold: Double,
        coarseFound: Bool,
        found: Bool,
        verification: AutomationVisualImageVerificationResult?,
        location: AutomationVisualImageLocationResult?
    ) -> String {
        let comparison = coarseFound ? "<=" : ">"
        let verifierSummary = verification.map { result in
            String(
                format: " verified %.2f %@ %.2f",
                result.similarity,
                result.isMatched ? ">=" : "<",
                result.threshold
            )
        } ?? ""
        let locationSummary = location.map { result in
            String(
                format: " located %.2f %@ %.2f",
                result.similarity,
                result.isMatched ? ">=" : "<",
                result.threshold
            )
        } ?? ""
        switch condition.type {
        case .imageAppeared:
            return String(
                format: "Image %@ distance %.2f %@ %.2f%@%@",
                imageRef,
                distance,
                comparison,
                threshold,
                verifierSummary,
                locationSummary
            )
        case .imageDisappeared:
            return found
                ? String(
                    format: "Image %@ still visible distance %.2f %@ %.2f%@%@",
                    imageRef,
                    distance,
                    comparison,
                    threshold,
                    verifierSummary,
                    locationSummary
                )
                : String(
                    format: "Image %@ absent distance %.2f %@ %.2f%@%@",
                    imageRef,
                    distance,
                    comparison,
                    threshold,
                    verifierSummary,
                    locationSummary
                )
        case .pixelMatched, .regionChanged:
            return "Unsupported feature-print condition"
        }
    }

    private static func featurePrintResultScore(
        featureScore: AutomationVisualDetectorScore,
        location: AutomationVisualImageLocationResult?
    ) -> AutomationVisualDetectorScore {
        guard let location else {
            return featureScore
        }

        return AutomationVisualDetectorScore(
            value: location.similarity,
            threshold: location.threshold,
            comparison: .greaterThanOrEqual
        )
    }

    private static func matchedImageRegion(
        location: AutomationVisualImageLocationResult?,
        routedFrame: AutomationVisualRoutedFrame
    ) -> RectValue {
        guard let matchedRect = location?.matchedRect,
              routedFrame.croppedImage.image.width > 0,
              routedFrame.croppedImage.image.height > 0 else {
            return routedFrame.cropRect
        }

        let scaleX = routedFrame.cropRect.width / CGFloat(routedFrame.croppedImage.image.width)
        let scaleY = routedFrame.cropRect.height / CGFloat(routedFrame.croppedImage.image.height)
        return RectValue(
            x: routedFrame.cropRect.x + matchedRect.x * scaleX,
            y: routedFrame.cropRect.y + matchedRect.y * scaleY,
            width: matchedRect.width * scaleX,
            height: matchedRect.height * scaleY
        )
    }

    private static func featurePrintFields(
        imageRef: String,
        distance: Double,
        threshold: Double,
        verification: AutomationVisualImageVerificationResult?,
        location: AutomationVisualImageLocationResult?
    ) -> [AutomationConditionDiagnosticField] {
        var fields = [
            AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: imageRef),
            AutomationConditionDiagnosticField(id: "distance", title: "Feature distance", value: distance.metricLabel),
            AutomationConditionDiagnosticField(id: "threshold", title: "Feature threshold", value: threshold.metricLabel)
        ]
        if let verification {
            fields.append(contentsOf: [
                AutomationConditionDiagnosticField(
                    id: "verifierSimilarity",
                    title: "Verifier similarity",
                    value: verification.similarity.metricLabel
                ),
                AutomationConditionDiagnosticField(
                    id: "verifierThreshold",
                    title: "Verifier threshold",
                    value: verification.threshold.metricLabel
                )
            ])
        }
        if let location {
            fields.append(contentsOf: [
                AutomationConditionDiagnosticField(
                    id: "locatorSimilarity",
                    title: "Locator similarity",
                    value: location.similarity.metricLabel
                ),
                AutomationConditionDiagnosticField(
                    id: "locatorThreshold",
                    title: "Locator threshold",
                    value: location.threshold.metricLabel
                )
            ])
            if let matchedRect = location.matchedRect {
                fields.append(contentsOf: [
                    AutomationConditionDiagnosticField(
                        id: "locatorX",
                        title: "Locator x",
                        value: Double(matchedRect.x).metricLabel
                    ),
                    AutomationConditionDiagnosticField(
                        id: "locatorY",
                        title: "Locator y",
                        value: Double(matchedRect.y).metricLabel
                    ),
                    AutomationConditionDiagnosticField(
                        id: "locatorWidth",
                        title: "Locator width",
                        value: Double(matchedRect.width).metricLabel
                    ),
                    AutomationConditionDiagnosticField(
                        id: "locatorHeight",
                        title: "Locator height",
                        value: Double(matchedRect.height).metricLabel
                    )
                ])
            }
        }
        return fields
    }

    private static func pixelPoint(
        for condition: AutomationVisualCondition,
        routedFrame: AutomationVisualRoutedFrame,
        bitmap: AutomationVisualPixelBitmap
    ) -> AutomationVisualPixelPoint? {
        if let pixel = condition.pixel {
            let usesNormalizedPoint = pixel.x >= 0
                && pixel.x <= 1
                && pixel.y >= 0
                && pixel.y <= 1
            if usesNormalizedPoint {
                return AutomationVisualPixelPoint(
                    x: Int(pixel.x * Double(bitmap.width)),
                    y: Int(pixel.y * Double(bitmap.height))
                )
                .clamped(width: bitmap.width, height: bitmap.height)
            }

            if displayPointIsInsideCrop(pixel, cropRect: routedFrame.cropRect) {
                let localX = (pixel.x - Double(routedFrame.cropRect.x)) / Double(routedFrame.cropRect.width)
                let localY = (pixel.y - Double(routedFrame.cropRect.y)) / Double(routedFrame.cropRect.height)
                return AutomationVisualPixelPoint(
                    x: Int(localX * Double(bitmap.width)),
                    y: Int(localY * Double(bitmap.height))
                )
                .clamped(width: bitmap.width, height: bitmap.height)
            }

            return AutomationVisualPixelPoint(
                x: Int(pixel.x),
                y: Int(pixel.y)
            )
            .clamped(width: bitmap.width, height: bitmap.height)
        }

        guard routedFrame.request.scope.kind == .selectedRegion else {
            return nil
        }

        return AutomationVisualPixelPoint(
            x: bitmap.width / 2,
            y: bitmap.height / 2
        )
        .clamped(width: bitmap.width, height: bitmap.height)
    }

    private static func displayPointIsInsideCrop(
        _ point: AutomationGraphPoint,
        cropRect: RectValue
    ) -> Bool {
        let x = CGFloat(point.x)
        let y = CGFloat(point.y)
        return x >= cropRect.x
            && y >= cropRect.y
            && x < cropRect.x + cropRect.width
            && y < cropRect.y + cropRect.height
    }

    private static func pixelSampleRadius(for condition: AutomationVisualCondition) -> Int {
        condition.pixelSampleRadius.map(AutomationVisualCondition.clampedPixelSampleRadius)
            ?? AutomationVisualCondition.defaultPixelSampleRadius
    }

    private static func sampledRegion(
        for sample: AutomationVisualPixelSample,
        routedFrame: AutomationVisualRoutedFrame,
        bitmap: AutomationVisualPixelBitmap
    ) -> RectValue {
        let width = routedFrame.cropRect.width / CGFloat(bitmap.width)
        let height = routedFrame.cropRect.height / CGFloat(bitmap.height)
        return RectValue(
            x: routedFrame.cropRect.x + CGFloat(sample.minX) * width,
            y: routedFrame.cropRect.y + CGFloat(sample.minY) * height,
            width: CGFloat(sample.width) * width,
            height: CGFloat(sample.height) * height
        )
    }

    private static func runtimeArtifactRef(for routedFrame: AutomationVisualRoutedFrame) -> String? {
        routedFrame.request.sample.artifactRef ?? routedFrame.request.sourceArtifactRef
    }

    private static func pixelColorFields(
        sample: AutomationVisualPixelSample,
        targetColor: AutomationVisualRGBAColor,
        similarity: Double,
        threshold: Double
    ) -> [AutomationConditionDiagnosticField] {
        [
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
            AutomationConditionDiagnosticField(
                id: "similarity",
                title: "Similarity",
                value: similarity.metricLabel
            ),
            AutomationConditionDiagnosticField(
                id: "threshold",
                title: "Threshold",
                value: threshold.metricLabel
            ),
            AutomationConditionDiagnosticField(
                id: "sampleRadius",
                title: "Sample radius",
                value: "\(sample.radius)"
            ),
            AutomationConditionDiagnosticField(
                id: "sampleCount",
                title: "Samples",
                value: "\(sample.sampleCount)"
            )
        ]
    }

    private static func regionDiffFields(
        baselineRef: String,
        metrics: AutomationVisualRegionDiffMetrics,
        threshold: Double
    ) -> [AutomationConditionDiagnosticField] {
        [
            AutomationConditionDiagnosticField(id: "baselineRef", title: "Baseline", value: baselineRef),
            AutomationConditionDiagnosticField(
                id: "changeScore",
                title: "Change score",
                value: metrics.changeScore.metricLabel
            ),
            AutomationConditionDiagnosticField(
                id: "changedRatio",
                title: "Changed ratio",
                value: metrics.changedPixelRatio.metricLabel
            ),
            AutomationConditionDiagnosticField(
                id: "maxDelta",
                title: "Max delta",
                value: metrics.maxDelta.metricLabel
            ),
            AutomationConditionDiagnosticField(
                id: "sampleCount",
                title: "Samples",
                value: "\(metrics.sampleCount)"
            ),
            AutomationConditionDiagnosticField(
                id: "threshold",
                title: "Threshold",
                value: threshold.metricLabel
            )
        ]
    }
}

private struct AutomationVisualPixelPoint: Equatable, Sendable {
    var x: Int
    var y: Int

    func clamped(width: Int, height: Int) -> AutomationVisualPixelPoint? {
        guard width > 0, height > 0 else {
            return nil
        }
        return AutomationVisualPixelPoint(
            x: min(max(x, 0), width - 1),
            y: min(max(y, 0), height - 1)
        )
    }
}

private struct AutomationVisualPixelBitmap: Sendable {
    var width: Int
    var height: Int
    var bytes: [UInt8]

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

    func color(atX x: Int, y: Int) -> AutomationVisualRGBAColor? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }

        let offset = (y * width + x) * 4
        guard offset + 3 < bytes.count else {
            return nil
        }

        return AutomationVisualRGBAColor(
            red: Double(bytes[offset]),
            green: Double(bytes[offset + 1]),
            blue: Double(bytes[offset + 2]),
            alpha: Double(bytes[offset + 3])
        )
    }

    func colorSample(
        centeredAt point: AutomationVisualPixelPoint,
        radius: Int
    ) -> AutomationVisualPixelSample? {
        let clampedRadius = max(0, radius)
        let minX = Self.clamp(point.x - clampedRadius, lower: 0, upper: width - 1)
        let maxX = Self.clamp(point.x + clampedRadius, lower: 0, upper: width - 1)
        let minY = Self.clamp(point.y - clampedRadius, lower: 0, upper: height - 1)
        let maxY = Self.clamp(point.y + clampedRadius, lower: 0, upper: height - 1)
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var alpha = 0.0
        var samples = 0

        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = color(atX: x, y: y) else {
                    continue
                }
                red += color.red
                green += color.green
                blue += color.blue
                alpha += color.alpha
                samples += 1
            }
        }

        guard samples > 0 else {
            return nil
        }

        return AutomationVisualPixelSample(
            center: point,
            radius: clampedRadius,
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            sampleCount: samples,
            averageColor: AutomationVisualRGBAColor(
                red: red / Double(samples),
                green: green / Double(samples),
                blue: blue / Double(samples),
                alpha: alpha / Double(samples)
            )
        )
    }

    func changeScore(comparedTo baseline: AutomationVisualPixelBitmap) -> Double {
        regionDiffMetrics(comparedTo: baseline).changeScore
    }

    func regionDiffMetrics(comparedTo baseline: AutomationVisualPixelBitmap) -> AutomationVisualRegionDiffMetrics {
        let samplesX = Self.sampleCount(for: width)
        let samplesY = Self.sampleCount(for: height)
        var totalDelta = 0.0
        var maxDelta = 0.0
        var changedSamples = 0
        var samples = 0
        let baselineIsSameSize = baseline.width == width && baseline.height == height

        for sampleY in 0..<samplesY {
            let normalizedY = (Double(sampleY) + 0.5) / Double(samplesY)
            let currentY = Self.clamp(
                Int(normalizedY * Double(height)),
                lower: 0,
                upper: height - 1
            )
            let baselineY = baselineIsSameSize
                ? currentY
                : Self.clamp(
                    Int(normalizedY * Double(baseline.height)),
                    lower: 0,
                    upper: baseline.height - 1
                )

            for sampleX in 0..<samplesX {
                let normalizedX = (Double(sampleX) + 0.5) / Double(samplesX)
                let currentX = Self.clamp(
                    Int(normalizedX * Double(width)),
                    lower: 0,
                    upper: width - 1
                )
                let baselineX = baselineIsSameSize
                    ? currentX
                    : Self.clamp(
                        Int(normalizedX * Double(baseline.width)),
                        lower: 0,
                        upper: baseline.width - 1
                    )

                guard let currentColor = color(atX: currentX, y: currentY),
                      let baselineColor = baseline.color(atX: baselineX, y: baselineY) else {
                    continue
                }

                let delta = 1 - currentColor.similarity(to: baselineColor)
                totalDelta += delta
                maxDelta = max(maxDelta, delta)
                if delta >= Self.changedSampleThreshold {
                    changedSamples += 1
                }
                samples += 1
            }
        }

        guard samples > 0 else {
            return AutomationVisualRegionDiffMetrics(
                changeScore: 0,
                changedPixelRatio: 0,
                maxDelta: 0,
                sampleCount: 0
            )
        }

        return AutomationVisualRegionDiffMetrics(
            changeScore: totalDelta / Double(samples),
            changedPixelRatio: Double(changedSamples) / Double(samples),
            maxDelta: maxDelta,
            sampleCount: samples
        )
    }

    static func imageSimilarity(
        template: CGImage,
        runtime: CGImage,
        maximumSamplesPerAxis: Int = 32
    ) -> Double {
        guard let templateBitmap = AutomationVisualPixelBitmap(image: template),
              let runtimeBitmap = AutomationVisualPixelBitmap(image: runtime) else {
            return 0
        }
        return templateBitmap.scaledSimilarity(to: runtimeBitmap, maximumSamplesPerAxis: maximumSamplesPerAxis)
    }

    static func locate(
        template: CGImage,
        runtime: CGImage,
        threshold: Double,
        stride: Int,
        maximumSamplesPerAxis: Int = 32
    ) -> AutomationVisualImageLocationResult {
        guard let templateBitmap = AutomationVisualPixelBitmap(image: template),
              let runtimeBitmap = AutomationVisualPixelBitmap(image: runtime),
              templateBitmap.width <= runtimeBitmap.width,
              templateBitmap.height <= runtimeBitmap.height else {
            return AutomationVisualImageLocationResult(
                similarity: 0,
                threshold: threshold,
                matchedRect: nil
            )
        }

        let clampedStep = max(1, stride)
        let xPositions = scanPositions(
            lastOrigin: runtimeBitmap.width - templateBitmap.width,
            step: clampedStep
        )
        let yPositions = scanPositions(
            lastOrigin: runtimeBitmap.height - templateBitmap.height,
            step: clampedStep
        )
        var bestSimilarity = 0.0
        var bestRect: RectValue?

        for y in yPositions {
            for x in xPositions {
                let similarity = runtimeBitmap.windowSimilarity(
                    template: templateBitmap,
                    originX: x,
                    originY: y,
                    maximumSamplesPerAxis: maximumSamplesPerAxis
                )
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestRect = RectValue(
                        x: CGFloat(x),
                        y: CGFloat(y),
                        width: CGFloat(templateBitmap.width),
                        height: CGFloat(templateBitmap.height)
                    )
                }
            }
        }

        return AutomationVisualImageLocationResult(
            similarity: bestSimilarity,
            threshold: threshold,
            matchedRect: bestSimilarity >= threshold ? bestRect : nil
        )
    }

    private func scaledSimilarity(
        to other: AutomationVisualPixelBitmap,
        maximumSamplesPerAxis: Int
    ) -> Double {
        let samplesX = max(1, min(maximumSamplesPerAxis, width, other.width))
        let samplesY = max(1, min(maximumSamplesPerAxis, height, other.height))
        var totalSimilarity = 0.0
        var samples = 0

        for sampleY in 0..<samplesY {
            let currentY = scaledSampleCoordinate(index: sampleY, sampleCount: samplesY, sourceCount: height)
            let otherY = scaledSampleCoordinate(index: sampleY, sampleCount: samplesY, sourceCount: other.height)

            for sampleX in 0..<samplesX {
                let currentX = scaledSampleCoordinate(index: sampleX, sampleCount: samplesX, sourceCount: width)
                let otherX = scaledSampleCoordinate(index: sampleX, sampleCount: samplesX, sourceCount: other.width)
                guard let currentColor = color(atX: currentX, y: currentY),
                      let otherColor = other.color(atX: otherX, y: otherY) else {
                    continue
                }
                totalSimilarity += currentColor.similarity(to: otherColor)
                samples += 1
            }
        }

        guard samples > 0 else {
            return 0
        }
        return max(0, min(1, totalSimilarity / Double(samples)))
    }

    private func windowSimilarity(
        template: AutomationVisualPixelBitmap,
        originX: Int,
        originY: Int,
        maximumSamplesPerAxis: Int
    ) -> Double {
        guard originX >= 0,
              originY >= 0,
              originX + template.width <= width,
              originY + template.height <= height else {
            return 0
        }

        let samplesX = max(1, min(maximumSamplesPerAxis, template.width))
        let samplesY = max(1, min(maximumSamplesPerAxis, template.height))
        var totalSimilarity = 0.0
        var samples = 0

        for sampleY in 0..<samplesY {
            let templateY = template.scaledSampleCoordinate(
                index: sampleY,
                sampleCount: samplesY,
                sourceCount: template.height
            )
            let runtimeY = originY + templateY

            for sampleX in 0..<samplesX {
                let templateX = template.scaledSampleCoordinate(
                    index: sampleX,
                    sampleCount: samplesX,
                    sourceCount: template.width
                )
                let runtimeX = originX + templateX
                guard let templateColor = template.color(atX: templateX, y: templateY),
                      let runtimeColor = color(atX: runtimeX, y: runtimeY) else {
                    continue
                }
                totalSimilarity += templateColor.similarity(to: runtimeColor)
                samples += 1
            }
        }

        guard samples > 0 else {
            return 0
        }
        return max(0, min(1, totalSimilarity / Double(samples)))
    }

    private func scaledSampleCoordinate(index: Int, sampleCount: Int, sourceCount: Int) -> Int {
        guard sampleCount > 1 else {
            return Self.clamp(sourceCount / 2, lower: 0, upper: sourceCount - 1)
        }
        let ratio = Double(index) / Double(sampleCount - 1)
        return Self.clamp(Int((ratio * Double(sourceCount - 1)).rounded()), lower: 0, upper: sourceCount - 1)
    }

    private static func scanPositions(lastOrigin: Int, step: Int) -> [Int] {
        guard lastOrigin >= 0 else {
            return []
        }
        let clampedStep = max(1, step)
        var positions = stride(from: 0, through: lastOrigin, by: clampedStep).map { $0 }
        if positions.last != lastOrigin {
            positions.append(lastOrigin)
        }
        return positions
    }

    private static func sampleCount(for size: Int) -> Int {
        min(12, max(3, size / 16))
    }

    private static let changedSampleThreshold = 0.02

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}

private struct AutomationVisualPixelSample: Equatable, Sendable {
    var center: AutomationVisualPixelPoint
    var radius: Int
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var sampleCount: Int
    var averageColor: AutomationVisualRGBAColor

    var width: Int {
        max(0, maxX - minX + 1)
    }

    var height: Int {
        max(0, maxY - minY + 1)
    }
}

private struct AutomationVisualRegionDiffMetrics: Equatable, Sendable {
    var changeScore: Double
    var changedPixelRatio: Double
    var maxDelta: Double
    var sampleCount: Int

    init(
        changeScore: Double,
        changedPixelRatio: Double,
        maxDelta: Double,
        sampleCount: Int
    ) {
        self.changeScore = Self.clampUnit(changeScore)
        self.changedPixelRatio = Self.clampUnit(changedPixelRatio)
        self.maxDelta = Self.clampUnit(maxDelta)
        self.sampleCount = max(0, sampleCount)
    }

    private static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return max(0, min(1, value))
    }
}

private extension Double {
    var metricLabel: String {
        String(format: "%.2f", self)
    }
}

private struct AutomationVisualRGBAColor: Equatable, Sendable {
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

    var hexDescription: String {
        String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    func similarity(to other: AutomationVisualRGBAColor) -> Double {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        let distance = sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
        let maxDistance = sqrt(3 * 255.0 * 255.0)
        return max(0, min(1, 1 - distance / maxDistance))
    }
}

struct AutomationVisualPollingRequest: Sendable {
    var workflowID: UUID
    var taskID: UUID
    var condition: AutomationConditionSpec
    var context: AutomationOCRSearchRegionContext
    var scope: AutomationVisualObservationScope?
    var maxPolls: Int
    var pollingInterval: TimeInterval
    var sourceArtifactRef: String?
    var baselineArtifactRef: String?

    init(
        workflowID: UUID,
        taskID: UUID,
        condition: AutomationConditionSpec,
        context: AutomationOCRSearchRegionContext,
        scope: AutomationVisualObservationScope? = nil,
        maxPolls: Int = 3,
        pollingInterval: TimeInterval? = nil,
        sourceArtifactRef: String? = nil,
        baselineArtifactRef: String? = nil
    ) {
        self.workflowID = workflowID
        self.taskID = taskID
        self.condition = condition
        self.context = context
        self.scope = scope
        self.maxPolls = max(1, maxPolls)
        self.pollingInterval = max(0.05, pollingInterval ?? condition.pollingInterval)
        self.sourceArtifactRef = AutomationConditionDiagnosticArtifact.normalizedRelativePath(sourceArtifactRef)
        self.baselineArtifactRef = AutomationConditionDiagnosticArtifact.normalizedRelativePath(baselineArtifactRef)
    }
}

struct AutomationVisualPollingEvaluation: Sendable {
    var pollIndex: Int
    var routedFrame: AutomationVisualRoutedFrame
    var detectorResult: AutomationVisualDetectorResult
    var evaluatedAt: Date
}

enum AutomationVisualPollingStatus: String, Equatable, Sendable {
    case matched
    case exhausted
    case failed
}

struct AutomationVisualPollingSummary: Sendable {
    var status: AutomationVisualPollingStatus
    var evaluations: [AutomationVisualPollingEvaluation]
    var staleFrameCount: Int
    var lastError: AutomationVisualLiveFrameRouterError?

    var lastResult: AutomationVisualDetectorResult? {
        evaluations.last?.detectorResult
    }
}

actor AutomationVisualLatestFrameRouter {
    private var latestFrame: AutomationVisualImageFrame?

    func ingest(_ frame: AutomationVisualImageFrame) {
        guard let current = latestFrame else {
            latestFrame = frame
            return
        }

        if frame.sample.capturedAt >= current.sample.capturedAt {
            latestFrame = frame
        }
    }

    func latestSample() -> AutomationVisualFrameSample? {
        latestFrame?.sample
    }

    func routeLatest(
        workflowID: UUID,
        taskID: UUID,
        condition: AutomationConditionSpec,
        context: AutomationOCRSearchRegionContext,
        scope explicitScope: AutomationVisualObservationScope? = nil,
        requestedAt: Date,
        sourceArtifactRef: String? = nil,
        baselineArtifactRef: String? = nil
    ) throws -> AutomationVisualRoutedFrame {
        guard let latestFrame else {
            throw AutomationVisualLiveFrameRouterError.noLatestFrame
        }
        let scope = explicitScope ?? AutomationVisualObservationScope.inferred(
            for: condition,
            in: context
        )
        guard let scope,
              let request = AutomationVisualDetectorRequest(
                workflowID: workflowID,
                taskID: taskID,
                condition: condition,
                sample: latestFrame.sample,
                scope: scope,
                requestedAt: requestedAt,
                sourceArtifactRef: sourceArtifactRef,
                baselineArtifactRef: baselineArtifactRef
              ) else {
            throw AutomationVisualLiveFrameRouterError.unsupportedCondition
        }

        let route = AutomationVisualFrameRoute.resolve(request: request, in: context)
        if let unavailableReason = route.unavailableReason {
            throw AutomationVisualLiveFrameRouterError.routeUnavailable(unavailableReason)
        }
        guard let crop = AutomationVisualFrameCropper.crop(frame: latestFrame, route: route) else {
            throw AutomationVisualLiveFrameRouterError.cropUnavailable
        }
        return crop
    }
}

actor AutomationVisualPollingDispatcher {
    private let router: AutomationVisualLatestFrameRouter
    private let detector: AutomationVisualFrameDetectorClient
    private let now: @Sendable () -> Date
    private var lastProcessedSampleID: UUID?

    init(
        router: AutomationVisualLatestFrameRouter = AutomationVisualLatestFrameRouter(),
        detector: AutomationVisualFrameDetectorClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.router = router
        self.detector = detector
        self.now = now
    }

    func ingest(_ frame: AutomationVisualImageFrame) async {
        await router.ingest(frame)
    }

    func consume(_ frames: AsyncStream<AutomationVisualImageFrame>) async {
        for await frame in frames {
            await ingest(frame)
        }
    }

    func pollOnce(
        _ request: AutomationVisualPollingRequest,
        pollIndex: Int = 1
    ) async throws -> AutomationVisualPollingEvaluation {
        guard let latestSample = await router.latestSample() else {
            throw AutomationVisualLiveFrameRouterError.noLatestFrame
        }
        guard latestSample.id != lastProcessedSampleID else {
            throw AutomationVisualLiveFrameRouterError.noFreshFrame(latestSample.id)
        }

        let evaluatedAt = now()
        let routedFrame = try await router.routeLatest(
            workflowID: request.workflowID,
            taskID: request.taskID,
            condition: request.condition,
            context: request.context,
            scope: request.scope,
            requestedAt: evaluatedAt,
            sourceArtifactRef: request.sourceArtifactRef,
            baselineArtifactRef: request.baselineArtifactRef
        )
        lastProcessedSampleID = routedFrame.request.sample.id
        let detectorResult = await detector.evaluate(routedFrame)
        return AutomationVisualPollingEvaluation(
            pollIndex: max(1, pollIndex),
            routedFrame: routedFrame,
            detectorResult: detectorResult,
            evaluatedAt: evaluatedAt
        )
    }

    func pollUntilMatched(
        _ request: AutomationVisualPollingRequest,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { duration in
            guard duration > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    ) async -> AutomationVisualPollingSummary {
        var evaluations: [AutomationVisualPollingEvaluation] = []
        var staleFrameCount = 0
        var lastError: AutomationVisualLiveFrameRouterError?

        for pollIndex in 1...request.maxPolls {
            do {
                let evaluation = try await pollOnce(request, pollIndex: pollIndex)
                evaluations.append(evaluation)
                if evaluation.detectorResult.outcome == .conditionMatched {
                    return AutomationVisualPollingSummary(
                        status: .matched,
                        evaluations: evaluations,
                        staleFrameCount: staleFrameCount,
                        lastError: nil
                    )
                }
            } catch let error as AutomationVisualLiveFrameRouterError {
                switch error {
                case .noLatestFrame, .noFreshFrame:
                    staleFrameCount += 1
                    lastError = error
                case .unsupportedCondition, .routeUnavailable, .cropUnavailable:
                    return AutomationVisualPollingSummary(
                        status: .failed,
                        evaluations: evaluations,
                        staleFrameCount: staleFrameCount,
                        lastError: error
                    )
                }
            } catch {
                return AutomationVisualPollingSummary(
                    status: .failed,
                    evaluations: evaluations,
                    staleFrameCount: staleFrameCount,
                    lastError: nil
                )
            }

            if pollIndex < request.maxPolls {
                await sleep(request.pollingInterval)
            }
        }

        return AutomationVisualPollingSummary(
            status: .exhausted,
            evaluations: evaluations,
            staleFrameCount: staleFrameCount,
            lastError: lastError
        )
    }
}

enum AutomationVisualFrameCropper {
    static func crop(
        frame: AutomationVisualImageFrame,
        route: AutomationVisualFrameRoute
    ) -> AutomationVisualRoutedFrame? {
        guard route.isAvailable,
              let processingRegion = route.processingRegion else {
            return nil
        }

        let image = frame.image.image
        guard let pixelRect = pixelRect(
            for: processingRegion,
            sample: frame.sample,
            routeDisplayBounds: route.displayBounds,
            image: image
        ) else {
            return nil
        }
        guard let croppedImage = image.cropping(to: pixelRect.integral) else {
            return nil
        }

        return AutomationVisualRoutedFrame(
            request: route.request,
            route: route,
            croppedImage: AutomationVisualCGImage(croppedImage),
            cropRect: processingRegion,
            sourcePixelRect: RectValue(
                x: pixelRect.minX,
                y: pixelRect.minY,
                width: pixelRect.width,
                height: pixelRect.height
            ),
            isFullFrame: isFullFrame(pixelRect.integral, image: image)
        )
    }

    private static func pixelRect(
        for region: RectValue,
        sample: AutomationVisualFrameSample,
        routeDisplayBounds: RectValue,
        image: CGImage
    ) -> CGRect? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let sourceBounds = sourceBounds(
            sample: sample,
            routeDisplayBounds: routeDisplayBounds,
            image: image
        )
        guard sourceBounds.width > 0, sourceBounds.height > 0 else {
            return nil
        }

        let normalized = CGRect(
            x: (region.x - sourceBounds.x) / sourceBounds.width,
            y: (region.y - sourceBounds.y) / sourceBounds.height,
            width: region.width / sourceBounds.width,
            height: region.height / sourceBounds.height
        )
        let candidate = CGRect(
            x: normalized.minX * imageBounds.width,
            y: normalized.minY * imageBounds.height,
            width: normalized.width * imageBounds.width,
            height: normalized.height * imageBounds.height
        )
        let clipped = candidate.standardized.intersection(imageBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
            return nil
        }

        let minX = max(0, min(image.width, Int(floor(clipped.minX))))
        let minY = max(0, min(image.height, Int(floor(clipped.minY))))
        let maxX = max(0, min(image.width, Int(ceil(clipped.maxX))))
        let maxY = max(0, min(image.height, Int(ceil(clipped.maxY))))
        guard maxX > minX, maxY > minY else {
            return nil
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func sourceBounds(
        sample: AutomationVisualFrameSample,
        routeDisplayBounds: RectValue,
        image: CGImage
    ) -> RectValue {
        if let displayBounds = sample.displayBounds,
           displayBounds.width > 0,
           displayBounds.height > 0 {
            return displayBounds
        }

        if routeDisplayBounds.width > 0,
           routeDisplayBounds.height > 0 {
            return routeDisplayBounds
        }

        return RectValue(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
    }

    private static func isFullFrame(_ rect: CGRect, image: CGImage) -> Bool {
        Int(rect.minX) <= 0
            && Int(rect.minY) <= 0
            && Int(rect.width) >= image.width
            && Int(rect.height) >= image.height
    }
}

extension ScreenCaptureKitLiveFrame {
    func imageFrame(context: CIContext = CIContext()) -> AutomationVisualImageFrame? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return AutomationVisualImageFrame(sample: sample, image: cgImage)
    }
}
