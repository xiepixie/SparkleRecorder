import Foundation

public enum AutomationVisualFrameSourceKind: String, Codable, Equatable, Sendable {
    case screenCaptureKitStream
    case screenCaptureKitScreenshot
    case semanticRecordingFrame
    case fixture
}

public struct AutomationVisualFrameSample: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var source: AutomationVisualFrameSourceKind
    public var capturedAt: Date
    public var imageSize: RecordingImageSize
    public var displayScale: Double
    public var displayBounds: RectValue?
    public var contentRect: RectValue?
    public var artifactRef: String?
    public var provider: String

    public init(
        id: UUID = UUID(),
        source: AutomationVisualFrameSourceKind,
        capturedAt: Date,
        imageSize: RecordingImageSize,
        displayScale: Double = 1,
        displayBounds: RectValue? = nil,
        contentRect: RectValue? = nil,
        artifactRef: String? = nil,
        provider: String
    ) {
        self.id = id
        self.source = source
        self.capturedAt = capturedAt
        self.imageSize = imageSize
        self.displayScale = max(0, displayScale)
        self.displayBounds = displayBounds
        self.contentRect = contentRect
        self.artifactRef = AutomationConditionDiagnosticArtifact.normalizedRelativePath(artifactRef)
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum AutomationVisualObservationScopeKind: String, Codable, Equatable, Sendable {
    case selectedRegion
    case targetWindow
    case fullDisplay
}

public struct AutomationVisualObservationScope: Codable, Equatable, Sendable {
    public var kind: AutomationVisualObservationScopeKind
    public var region: RectValue?
    public var coordinateSpace: AutomationOCRSearchRegionSpace
    public var explicitlyChosen: Bool

    public init(
        kind: AutomationVisualObservationScopeKind,
        region: RectValue? = nil,
        coordinateSpace: AutomationOCRSearchRegionSpace = .automatic,
        explicitlyChosen: Bool = false
    ) {
        self.kind = kind
        self.region = region
        self.coordinateSpace = coordinateSpace
        self.explicitlyChosen = explicitlyChosen
    }

    public static func selectedRegion(
        _ region: RectValue,
        coordinateSpace: AutomationOCRSearchRegionSpace = .automatic
    ) -> AutomationVisualObservationScope {
        AutomationVisualObservationScope(
            kind: .selectedRegion,
            region: region,
            coordinateSpace: coordinateSpace,
            explicitlyChosen: true
        )
    }

    public static func targetWindow(explicitlyChosen: Bool = false) -> AutomationVisualObservationScope {
        AutomationVisualObservationScope(kind: .targetWindow, explicitlyChosen: explicitlyChosen)
    }

    public static func fullDisplay(explicitlyChosen: Bool) -> AutomationVisualObservationScope {
        AutomationVisualObservationScope(kind: .fullDisplay, explicitlyChosen: explicitlyChosen)
    }

    public static func inferred(
        for condition: AutomationConditionSpec,
        in context: AutomationOCRSearchRegionContext
    ) -> AutomationVisualObservationScope? {
        switch condition.kind {
        case .ocrText(let ocr):
            switch ocr.searchRegionResolution(in: context) {
            case .resolved(let region):
                return AutomationVisualObservationScope(
                    kind: .selectedRegion,
                    region: region,
                    coordinateSpace: .displayAbsolute,
                    explicitlyChosen: false
                )
            case .unrestricted:
                return windowBackedOrDisplayScope(in: context)
            case .unavailable:
                return AutomationVisualObservationScope(
                    kind: .selectedRegion,
                    region: ocr.searchRegion,
                    coordinateSpace: ocr.searchRegionSpace,
                    explicitlyChosen: false
                )
            }

        case .visual(let visual):
            switch visual.searchRegionResolution(in: context) {
            case .resolved(let region):
                return AutomationVisualObservationScope(
                    kind: .selectedRegion,
                    region: region,
                    coordinateSpace: .displayAbsolute,
                    explicitlyChosen: false
                )
            case .unrestricted:
                return windowBackedOrDisplayScope(in: context)
            case .unavailable:
                return AutomationVisualObservationScope(
                    kind: .selectedRegion,
                    region: visual.searchRegion,
                    coordinateSpace: visual.searchRegionSpace,
                    explicitlyChosen: false
                )
            }

        case .previousOutcome, .externalSignal, .manualApproval:
            return nil
        }
    }

    private static func windowBackedOrDisplayScope(
        in context: AutomationOCRSearchRegionContext
    ) -> AutomationVisualObservationScope {
        if context.contentFrame != nil || context.windowFrame != nil {
            return .targetWindow(explicitlyChosen: false)
        }
        return .fullDisplay(explicitlyChosen: false)
    }
}

public enum AutomationVisualFrameRouteUnavailableReason: String, Codable, Equatable, Sendable {
    case unsupportedCondition
    case missingSelectedRegion
    case selectedRegionOutsideDisplay
    case targetWindowUnavailable
    case fullDisplayUnavailable
}

public struct AutomationVisualFrameRoute: Codable, Equatable, Sendable {
    public var request: AutomationVisualDetectorRequest
    public var displayBounds: RectValue
    public var resolvedSearchRegion: RectValue?
    public var unavailableReason: AutomationVisualFrameRouteUnavailableReason?
    public var implicitFullDisplayFallback: Bool

    public init(
        request: AutomationVisualDetectorRequest,
        displayBounds: RectValue,
        resolvedSearchRegion: RectValue? = nil,
        unavailableReason: AutomationVisualFrameRouteUnavailableReason? = nil,
        implicitFullDisplayFallback: Bool = false
    ) {
        self.request = request
        self.displayBounds = displayBounds
        self.resolvedSearchRegion = resolvedSearchRegion
        self.unavailableReason = unavailableReason
        self.implicitFullDisplayFallback = implicitFullDisplayFallback
    }

    public var isAvailable: Bool {
        unavailableReason == nil
    }

    public var processingRegion: RectValue? {
        guard isAvailable else {
            return nil
        }
        return resolvedSearchRegion ?? displayBounds
    }

    public var isFullDisplaySearch: Bool {
        isAvailable && resolvedSearchRegion == nil
    }

    public static func resolve(
        request: AutomationVisualDetectorRequest,
        in context: AutomationOCRSearchRegionContext
    ) -> AutomationVisualFrameRoute {
        switch request.scope.kind {
        case .selectedRegion:
            guard let region = request.scope.region else {
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    unavailableReason: .missingSelectedRegion
                )
            }
            let condition = AutomationOCRCondition(
                text: "",
                searchRegion: region,
                searchRegionSpace: request.scope.coordinateSpace
            )
            switch condition.searchRegionResolution(in: context) {
            case .resolved(let resolvedRegion):
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    resolvedSearchRegion: resolvedRegion
                )
            case .unrestricted:
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    unavailableReason: .missingSelectedRegion
                )
            case .unavailable:
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    unavailableReason: .selectedRegionOutsideDisplay
                )
            }

        case .targetWindow:
            let region = context.contentFrame ?? context.windowFrame
            guard let region else {
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    unavailableReason: .targetWindowUnavailable
                )
            }
            guard let clipped = region.intersectionForVisualRoute(with: context.displayBounds) else {
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    unavailableReason: .targetWindowUnavailable
                )
            }
            return AutomationVisualFrameRoute(
                request: request,
                displayBounds: context.displayBounds,
                resolvedSearchRegion: clipped
            )

        case .fullDisplay:
            guard context.displayBounds.width > 0, context.displayBounds.height > 0 else {
                return AutomationVisualFrameRoute(
                    request: request,
                    displayBounds: context.displayBounds,
                    unavailableReason: .fullDisplayUnavailable
                )
            }
            return AutomationVisualFrameRoute(
                request: request,
                displayBounds: context.displayBounds,
                implicitFullDisplayFallback: !request.scope.explicitlyChosen
            )
        }
    }
}

public enum AutomationVisualDetectorKind: String, Codable, Equatable, Sendable {
    case ocrText
    case featurePrintImage
    case regionDiff
    case pixelColor

    public static func kind(for condition: AutomationConditionKind) -> AutomationVisualDetectorKind? {
        switch condition {
        case .ocrText:
            return .ocrText
        case .visual(let visual):
            switch visual.type {
            case .imageAppeared, .imageDisappeared:
                return .featurePrintImage
            case .regionChanged:
                return .regionDiff
            case .pixelMatched:
                return .pixelColor
            }
        case .previousOutcome, .externalSignal, .manualApproval:
            return nil
        }
    }
}

public enum AutomationVisualDetectorComparison: String, Codable, Equatable, Sendable {
    case lessThanOrEqual
    case greaterThanOrEqual
}

public struct AutomationVisualDetectorScore: Codable, Equatable, Sendable {
    public var value: Double
    public var threshold: Double
    public var comparison: AutomationVisualDetectorComparison

    public init(
        value: Double,
        threshold: Double,
        comparison: AutomationVisualDetectorComparison
    ) {
        self.value = value.isFinite ? value : 0
        self.threshold = threshold.isFinite ? threshold : 0
        self.comparison = comparison
    }

    public var isMatched: Bool {
        switch comparison {
        case .lessThanOrEqual:
            return value <= threshold
        case .greaterThanOrEqual:
            return value >= threshold
        }
    }
}

public struct AutomationVisualDetectorRequest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var condition: AutomationConditionSpec
    public var detectorKind: AutomationVisualDetectorKind
    public var sample: AutomationVisualFrameSample
    public var scope: AutomationVisualObservationScope
    public var requestedAt: Date
    public var sourceArtifactRef: String?
    public var baselineArtifactRef: String?

    public init?(
        id: UUID = UUID(),
        workflowID: UUID,
        taskID: UUID,
        condition: AutomationConditionSpec,
        sample: AutomationVisualFrameSample,
        scope: AutomationVisualObservationScope,
        requestedAt: Date,
        sourceArtifactRef: String? = nil,
        baselineArtifactRef: String? = nil
    ) {
        guard let detectorKind = AutomationVisualDetectorKind.kind(for: condition.kind) else {
            return nil
        }
        self.id = id
        self.workflowID = workflowID
        self.taskID = taskID
        self.condition = condition
        self.detectorKind = detectorKind
        self.sample = sample
        self.scope = scope
        self.requestedAt = requestedAt
        self.sourceArtifactRef = AutomationConditionDiagnosticArtifact.normalizedRelativePath(sourceArtifactRef)
        self.baselineArtifactRef = AutomationConditionDiagnosticArtifact.normalizedRelativePath(baselineArtifactRef)
    }
}

public struct AutomationVisualDetectorResult: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var detectorKind: AutomationVisualDetectorKind
    public var outcome: AutomationOutcome
    public var score: AutomationVisualDetectorScore?
    public var observedSummary: String
    public var sampleCount: Int
    public var runtimeArtifactRef: String?
    public var matchedRegion: RectValue?
    public var fields: [AutomationConditionDiagnosticField]
    public var evaluatedAt: Date

    public init(
        requestID: UUID,
        detectorKind: AutomationVisualDetectorKind,
        outcome: AutomationOutcome,
        score: AutomationVisualDetectorScore? = nil,
        observedSummary: String,
        sampleCount: Int = 1,
        runtimeArtifactRef: String? = nil,
        matchedRegion: RectValue? = nil,
        fields: [AutomationConditionDiagnosticField] = [],
        evaluatedAt: Date
    ) {
        self.requestID = requestID
        self.detectorKind = detectorKind
        self.outcome = outcome
        self.score = score
        self.observedSummary = observedSummary
        self.sampleCount = max(0, sampleCount)
        self.runtimeArtifactRef = AutomationConditionDiagnosticArtifact.normalizedRelativePath(runtimeArtifactRef)
        self.matchedRegion = matchedRegion
        self.fields = fields
        self.evaluatedAt = evaluatedAt
    }

    public init(
        requestID: UUID,
        detectorKind: AutomationVisualDetectorKind,
        score: AutomationVisualDetectorScore,
        observedSummary: String,
        sampleCount: Int = 1,
        runtimeArtifactRef: String? = nil,
        matchedRegion: RectValue? = nil,
        fields: [AutomationConditionDiagnosticField] = [],
        evaluatedAt: Date
    ) {
        self.init(
            requestID: requestID,
            detectorKind: detectorKind,
            outcome: score.isMatched ? .conditionMatched : .conditionNotMatched,
            score: score,
            observedSummary: observedSummary,
            sampleCount: sampleCount,
            runtimeArtifactRef: runtimeArtifactRef,
            matchedRegion: matchedRegion,
            fields: fields,
            evaluatedAt: evaluatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case requestID
        case detectorKind
        case outcome
        case score
        case observedSummary
        case sampleCount
        case runtimeArtifactRef
        case matchedRegion
        case fields
        case evaluatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requestID: try container.decode(UUID.self, forKey: .requestID),
            detectorKind: try container.decode(AutomationVisualDetectorKind.self, forKey: .detectorKind),
            outcome: try container.decode(AutomationOutcome.self, forKey: .outcome),
            score: try container.decodeIfPresent(AutomationVisualDetectorScore.self, forKey: .score),
            observedSummary: try container.decode(String.self, forKey: .observedSummary),
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 1,
            runtimeArtifactRef: try container.decodeIfPresent(String.self, forKey: .runtimeArtifactRef),
            matchedRegion: try container.decodeIfPresent(RectValue.self, forKey: .matchedRegion),
            fields: try container.decodeIfPresent(
                [AutomationConditionDiagnosticField].self,
                forKey: .fields
            ) ?? [],
            evaluatedAt: try container.decode(Date.self, forKey: .evaluatedAt)
        )
    }
}

public enum AutomationRepeatUntilFailurePolicy: String, Codable, Equatable, Sendable {
    case failRun
    case continueWorkflow
    case requireManualApproval
}

public struct AutomationRepeatUntilLoopPolicy: Codable, Equatable, Sendable {
    public static let defaultMaxAttempts = 3
    public static let maxSupportedAttempts = 1_000

    public var bodyTaskIDs: [UUID]
    public var conditionTaskID: UUID?
    public var condition: AutomationConditionSpec
    public var maxAttempts: Int
    public var timeout: TimeInterval?
    public var pollingInterval: TimeInterval
    public var cooldown: TimeInterval
    public var failurePolicy: AutomationRepeatUntilFailurePolicy

    public init(
        bodyTaskIDs: [UUID],
        conditionTaskID: UUID? = nil,
        condition: AutomationConditionSpec,
        maxAttempts: Int = Self.defaultMaxAttempts,
        timeout: TimeInterval? = nil,
        pollingInterval: TimeInterval? = nil,
        cooldown: TimeInterval = 0,
        failurePolicy: AutomationRepeatUntilFailurePolicy = .failRun
    ) {
        var seenBodyTaskIDs = Set<UUID>()
        self.bodyTaskIDs = bodyTaskIDs.filter { seenBodyTaskIDs.insert($0).inserted }
        self.conditionTaskID = conditionTaskID
        self.condition = condition
        self.maxAttempts = min(max(maxAttempts, 1), Self.maxSupportedAttempts)
        self.timeout = timeout.map { max(0, $0) }
        self.pollingInterval = max(0.05, pollingInterval ?? condition.pollingInterval)
        self.cooldown = max(0, cooldown)
        self.failurePolicy = failurePolicy
    }
}

public enum AutomationRepeatUntilStopReason: String, Codable, Equatable, Sendable {
    case matched
    case maxAttempts
    case timeout
}

public enum AutomationRepeatUntilLoopStatus: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case waitingForManualApproval
}

public struct AutomationRepeatUntilAttemptEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var attemptIndex: Int
    public var startedAt: Date
    public var bodyCompletedAt: Date?
    public var evaluatedAt: Date
    public var outcome: AutomationOutcome
    public var detectorResult: AutomationVisualDetectorResult?
    public var conditionEvidence: AutomationConditionEvaluationEvidence?

    public init(
        id: UUID = UUID(),
        attemptIndex: Int,
        startedAt: Date,
        bodyCompletedAt: Date? = nil,
        evaluatedAt: Date,
        outcome: AutomationOutcome,
        detectorResult: AutomationVisualDetectorResult? = nil,
        conditionEvidence: AutomationConditionEvaluationEvidence? = nil
    ) {
        self.id = id
        self.attemptIndex = max(1, attemptIndex)
        self.startedAt = startedAt
        self.bodyCompletedAt = bodyCompletedAt
        self.evaluatedAt = evaluatedAt
        self.outcome = outcome
        self.detectorResult = detectorResult
        self.conditionEvidence = conditionEvidence
    }

    public var matched: Bool {
        outcome == .conditionMatched
    }
}

public struct AutomationRepeatUntilLoopState: Codable, Equatable, Sendable {
    public var policy: AutomationRepeatUntilLoopPolicy
    public var startedAt: Date
    public var status: AutomationRepeatUntilLoopStatus
    public var attempts: [AutomationRepeatUntilAttemptEvidence]
    public var stopReason: AutomationRepeatUntilStopReason?
    public var terminalOutcome: AutomationOutcome?
    public var completedAt: Date?

    public init(
        policy: AutomationRepeatUntilLoopPolicy,
        startedAt: Date,
        status: AutomationRepeatUntilLoopStatus = .running,
        attempts: [AutomationRepeatUntilAttemptEvidence] = [],
        stopReason: AutomationRepeatUntilStopReason? = nil,
        terminalOutcome: AutomationOutcome? = nil,
        completedAt: Date? = nil
    ) {
        self.policy = policy
        self.startedAt = startedAt
        self.status = status
        self.attempts = attempts.sorted { $0.attemptIndex < $1.attemptIndex }
        self.stopReason = stopReason
        self.terminalOutcome = terminalOutcome
        self.completedAt = completedAt
    }

    public var nextAttemptIndex: Int? {
        status == .running ? attempts.count + 1 : nil
    }

    public func appendingAttempt(
        _ attempt: AutomationRepeatUntilAttemptEvidence
    ) -> AutomationRepeatUntilLoopState {
        guard status == .running else {
            return self
        }

        var next = self
        next.attempts.append(attempt)
        next.attempts.sort { $0.attemptIndex < $1.attemptIndex }

        if attempt.matched {
            next.finish(
                status: .completed,
                outcome: .conditionMatched,
                stopReason: .matched,
                at: attempt.evaluatedAt
            )
            return next
        }

        if timedOut(at: attempt.evaluatedAt) {
            next.applyFailurePolicy(stopReason: .timeout, at: attempt.evaluatedAt)
            return next
        }

        if next.attempts.count >= policy.maxAttempts {
            next.applyFailurePolicy(stopReason: .maxAttempts, at: attempt.evaluatedAt)
            return next
        }

        return next
    }

    private func timedOut(at date: Date) -> Bool {
        guard let timeout = policy.timeout else {
            return false
        }
        return date.timeIntervalSince(startedAt) >= timeout
    }

    private mutating func applyFailurePolicy(
        stopReason: AutomationRepeatUntilStopReason,
        at date: Date
    ) {
        switch policy.failurePolicy {
        case .failRun:
            finish(status: .failed, outcome: .failed(report: nil), stopReason: stopReason, at: date)
        case .continueWorkflow:
            finish(status: .completed, outcome: .conditionNotMatched, stopReason: stopReason, at: date)
        case .requireManualApproval:
            status = .waitingForManualApproval
            self.stopReason = stopReason
            terminalOutcome = nil
            completedAt = nil
        }
    }

    private mutating func finish(
        status: AutomationRepeatUntilLoopStatus,
        outcome: AutomationOutcome,
        stopReason: AutomationRepeatUntilStopReason,
        at date: Date
    ) {
        self.status = status
        terminalOutcome = outcome
        self.stopReason = stopReason
        completedAt = date
    }
}

private extension RectValue {
    var visualRouteMaxX: CGFloat {
        x + width
    }

    var visualRouteMaxY: CGFloat {
        y + height
    }

    func intersectionForVisualRoute(with frame: RectValue) -> RectValue? {
        let left = max(x, frame.x)
        let top = max(y, frame.y)
        let right = min(visualRouteMaxX, frame.visualRouteMaxX)
        let bottom = min(visualRouteMaxY, frame.visualRouteMaxY)
        guard right > left, bottom > top else {
            return nil
        }
        return RectValue(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }
}
