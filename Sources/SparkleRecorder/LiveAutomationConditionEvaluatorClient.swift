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
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        externalSignal: AutomationExternalSignalClient,
        manualApproval: AutomationManualApprovalClient,
        searchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.externalSignal = externalSignal
        self.manualApproval = manualApproval
        self.searchRegionContext = searchRegionContext
        self.now = now
        self.sleep = sleep
    }

    func evaluate(_ request: AutomationConditionEvaluationRequest) async -> AutomationOutcome {
        switch request.condition.kind {
        case .ocrText(let condition):
            return await evaluateOCR(condition, request: request)
        case .previousOutcome(let predicate):
            return request.previousOutcomes.contains(where: predicate.matches)
                ? .conditionMatched
                : .conditionNotMatched
        case .externalSignal(let signalName):
            return await externalSignal.isActive(signalName)
                ? .conditionMatched
                : .conditionNotMatched
        case .manualApproval:
            return await manualApproval.requestApproval(request)
                ? .conditionMatched
                : .conditionNotMatched
        }
    }

    private func evaluateOCR(
        _ condition: AutomationOCRCondition,
        request: AutomationConditionEvaluationRequest
    ) async -> AutomationOutcome {
        let spec = request.condition
        let deadline = spec.timeout.map { now().addingTimeInterval($0) }

        while true {
            switch await scanScreen(condition, request: request) {
            case .matched:
                return .conditionMatched
            case .notMatched:
                break
            case .failed(let outcome):
                return outcome
            }

            guard let deadline, now() < deadline else {
                return .conditionNotMatched
            }

            await sleep(spec.pollingInterval)
        }
    }

    private func scanScreen(
        _ condition: AutomationOCRCondition,
        request: AutomationConditionEvaluationRequest
    ) async -> OCRScanResult {
        do {
            let image = try await ScreenCaptureService.shared.captureDisplay()
            let detections = try await visionDetector.detectText(in: image)
            let displayBounds = RectValue(
                x: 0,
                y: 0,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
            let regionContext = await searchRegionContext(request, displayBounds)
            let matched = detections.contains { detection in
                detectionIntersectsSearchRegion(
                    detection,
                    image: image,
                    condition: condition,
                    regionContext: regionContext
                ) && matches(candidate: detection.text, target: condition.text, mode: condition.matchMode)
            }
            return matched ? .matched : .notMatched
        } catch {
            return .failed(await outcome(for: error))
        }
    }

    private func detectionIntersectsSearchRegion(
        _ detection: TextDetection,
        image: CGImage,
        condition: AutomationOCRCondition,
        regionContext: AutomationOCRSearchRegionContext
    ) -> Bool {
        switch condition.searchRegionResolution(in: regionContext) {
        case .unrestricted:
            return true
        case .unavailable:
            return false
        case .resolved(let searchRegion):
            let imageSize = CGSize(width: image.width, height: image.height)
            let detectionRect = CGRect(
                x: detection.boundingBox.minX * imageSize.width,
                y: detection.boundingBox.minY * imageSize.height,
                width: detection.boundingBox.width * imageSize.width,
                height: detection.boundingBox.height * imageSize.height
            )
            let searchRect = CGRect(
                x: searchRegion.x,
                y: searchRegion.y,
                width: searchRegion.width,
                height: searchRegion.height
            )
            return detectionRect.intersects(searchRect)
        }
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
        case matched
        case notMatched
        case failed(AutomationOutcome)
    }
}

extension AutomationConditionEvaluatorClient {
    static func live(
        externalSignal: AutomationExternalSignalClient = .inactive,
        manualApproval: AutomationManualApprovalClient = .rejecting,
        searchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext = { _, displayBounds in
            AutomationOCRSearchRegionContext(displayBounds: displayBounds)
        },
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { duration in
            guard duration > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    ) -> AutomationConditionEvaluatorClient {
        let evaluator = LiveAutomationConditionEvaluator(
            externalSignal: externalSignal,
            manualApproval: manualApproval,
            searchRegionContext: searchRegionContext,
            now: now,
            sleep: sleep
        )
        return AutomationConditionEvaluatorClient { request in
            await evaluator.evaluate(request)
        }
    }
}
