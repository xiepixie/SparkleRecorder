import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Visual Repeat Until Tests")
struct AutomationVisualRepeatUntilTests {
    @Test("Detector kind follows condition intent")
    func detectorKindFollowsConditionIntent() {
        #expect(AutomationVisualDetectorKind.kind(for: .ocrText(AutomationOCRCondition(text: "Ready"))) == .ocrText)
        #expect(AutomationVisualDetectorKind.kind(for: .visual(AutomationVisualCondition(type: .imageAppeared))) == .featurePrintImage)
        #expect(AutomationVisualDetectorKind.kind(for: .visual(AutomationVisualCondition(type: .imageDisappeared))) == .featurePrintImage)
        #expect(AutomationVisualDetectorKind.kind(for: .visual(AutomationVisualCondition(type: .regionChanged))) == .regionDiff)
        #expect(AutomationVisualDetectorKind.kind(for: .visual(AutomationVisualCondition(type: .pixelMatched))) == .pixelColor)
        #expect(AutomationVisualDetectorKind.kind(for: .manualApproval) == nil)
    }

    @Test("Feature print distance score preserves detector-native threshold")
    func featurePrintDistancePreservesNativeThreshold() {
        let score = AutomationVisualDetectorScore(
            value: 12.5,
            threshold: 15,
            comparison: .lessThanOrEqual
        )
        let miss = AutomationVisualDetectorScore(
            value: 16,
            threshold: 15,
            comparison: .lessThanOrEqual
        )

        #expect(score.isMatched)
        #expect(score.threshold == 15)
        #expect(!miss.isMatched)
    }

    @Test("Region diff score can use greater-than threshold")
    func regionDiffScoreUsesGreaterThanThreshold() {
        let changed = AutomationVisualDetectorScore(
            value: 0.42,
            threshold: 0.2,
            comparison: .greaterThanOrEqual
        )
        let unchanged = AutomationVisualDetectorScore(
            value: 0.05,
            threshold: 0.2,
            comparison: .greaterThanOrEqual
        )

        #expect(changed.isMatched)
        #expect(!unchanged.isMatched)
    }

    @Test("Detector result fields round trip and legacy payloads decode")
    func detectorResultFieldsRoundTripAndLegacyDecode() throws {
        let result = AutomationVisualDetectorResult(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000151")!,
            detectorKind: .regionDiff,
            outcome: .conditionMatched,
            score: AutomationVisualDetectorScore(
                value: 0.42,
                threshold: 0.2,
                comparison: .greaterThanOrEqual
            ),
            observedSummary: "Region change 0.42",
            sampleCount: 2,
            runtimeArtifactRef: "frames/runtime.png",
            matchedRegion: RectValue(x: 1, y: 2, width: 3, height: 4),
            fields: [
                AutomationConditionDiagnosticField(id: "changeScore", title: "Change score", value: "0.42"),
                AutomationConditionDiagnosticField(id: "changedRatio", title: "Changed ratio", value: "0.75")
            ],
            evaluatedAt: Date(timeIntervalSince1970: 42)
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(AutomationVisualDetectorResult.self, from: encoded)
        #expect(decoded == result)

        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "fields")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(AutomationVisualDetectorResult.self, from: legacyData)

        #expect(legacy.fields == [])
        #expect(legacy.observedSummary == result.observedSummary)
        #expect(legacy.score == result.score)
    }

    @Test("Detector request records explicit visual scope and safe refs")
    func detectorRequestRecordsScopeAndSafeRefs() throws {
        let workflowID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let taskID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let condition = AutomationConditionSpec(
            name: "Wait for icon",
            kind: .visual(AutomationVisualCondition(type: .imageAppeared, imageRef: "icons/done.png"))
        )
        let sample = AutomationVisualFrameSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            source: .screenCaptureKitStream,
            capturedAt: Date(timeIntervalSince1970: 20),
            imageSize: RecordingImageSize(width: 1_280, height: 720),
            displayScale: 2,
            artifactRef: "/unsafe.png",
            provider: "SCStreamOutput"
        )
        let scope = AutomationVisualObservationScope.selectedRegion(
            RectValue(x: 10, y: 20, width: 120, height: 80),
            coordinateSpace: .windowLocal
        )

        let request = try #require(AutomationVisualDetectorRequest(
            workflowID: workflowID,
            taskID: taskID,
            condition: condition,
            sample: sample,
            scope: scope,
            requestedAt: Date(timeIntervalSince1970: 21),
            sourceArtifactRef: "visual-index/templates/done.png",
            baselineArtifactRef: "../unsafe.png"
        ))

        #expect(request.detectorKind == .featurePrintImage)
        #expect(request.scope.kind == .selectedRegion)
        #expect(request.scope.explicitlyChosen)
        #expect(request.scope.region == RectValue(x: 10, y: 20, width: 120, height: 80))
        #expect(request.sourceArtifactRef == "visual-index/templates/done.png")
        #expect(request.baselineArtifactRef == nil)
        #expect(request.sample.artifactRef == nil)
    }

    @Test("Frame route keeps user selected OCR region scoped")
    func frameRouteKeepsSelectedOCRRegionScoped() throws {
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 1_200, height: 800),
            windowFrame: RectValue(x: 100, y: 80, width: 600, height: 420),
            contentFrame: RectValue(x: 100, y: 120, width: 600, height: 380)
        )
        let condition = AutomationConditionSpec(
            name: "Wait for Ready",
            kind: .ocrText(AutomationOCRCondition(
                text: "Ready",
                searchRegion: RectValue(x: 0.25, y: 0.5, width: 0.25, height: 0.25),
                searchRegionSpace: .windowNormalized
            ))
        )
        let scope = try #require(AutomationVisualObservationScope.inferred(for: condition, in: context))
        let request = try #require(AutomationVisualDetectorRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            sample: sample(),
            scope: scope,
            requestedAt: Date(timeIntervalSince1970: 11)
        ))

        let route = AutomationVisualFrameRoute.resolve(request: request, in: context)

        #expect(route.isAvailable)
        #expect(route.request.detectorKind == .ocrText)
        #expect(route.request.scope.kind == .selectedRegion)
        #expect(!route.request.scope.explicitlyChosen)
        #expect(route.resolvedSearchRegion == RectValue(x: 250, y: 290, width: 150, height: 105))
        #expect(route.processingRegion == route.resolvedSearchRegion)
        #expect(!route.implicitFullDisplayFallback)
    }

    @Test("Frame route defaults to target window before full display")
    func frameRouteDefaultsToTargetWindowBeforeFullDisplay() throws {
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 1_440, height: 900),
            windowFrame: RectValue(x: 100, y: 80, width: 700, height: 500),
            contentFrame: RectValue(x: 100, y: 120, width: 700, height: 460)
        )
        let condition = AutomationConditionSpec(
            name: "Wait for icon",
            kind: .visual(AutomationVisualCondition(type: .imageAppeared, imageRef: "assets/icons/done.png"))
        )
        let scope = try #require(AutomationVisualObservationScope.inferred(for: condition, in: context))
        let request = try #require(AutomationVisualDetectorRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            sample: sample(),
            scope: scope,
            requestedAt: Date(timeIntervalSince1970: 12)
        ))

        let route = AutomationVisualFrameRoute.resolve(request: request, in: context)

        #expect(scope.kind == .targetWindow)
        #expect(route.isAvailable)
        #expect(route.resolvedSearchRegion == RectValue(x: 100, y: 120, width: 700, height: 460))
        #expect(!route.isFullDisplaySearch)
        #expect(!route.implicitFullDisplayFallback)
    }

    @Test("Frame route marks implicit full display fallback")
    func frameRouteMarksImplicitFullDisplayFallback() throws {
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 1_024, height: 768)
        )
        let condition = AutomationConditionSpec(
            name: "Wait for icon",
            kind: .visual(AutomationVisualCondition(type: .imageDisappeared, imageRef: "assets/icons/spinner.png"))
        )
        let scope = try #require(AutomationVisualObservationScope.inferred(for: condition, in: context))
        let request = try #require(AutomationVisualDetectorRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            sample: sample(),
            scope: scope,
            requestedAt: Date(timeIntervalSince1970: 13)
        ))

        let route = AutomationVisualFrameRoute.resolve(request: request, in: context)

        #expect(scope.kind == .fullDisplay)
        #expect(!scope.explicitlyChosen)
        #expect(route.isAvailable)
        #expect(route.processingRegion == context.displayBounds)
        #expect(route.isFullDisplaySearch)
        #expect(route.implicitFullDisplayFallback)
    }

    @Test("Frame route rejects unavailable selected region")
    func frameRouteRejectsUnavailableSelectedRegion() throws {
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 640, height: 480)
        )
        let condition = AutomationConditionSpec(
            name: "Watch pixel",
            kind: .visual(AutomationVisualCondition(type: .pixelMatched, targetColorHex: "#00FF00"))
        )
        let request = try #require(AutomationVisualDetectorRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            sample: sample(),
            scope: .selectedRegion(RectValue(x: 1_000, y: 1_000, width: 80, height: 80)),
            requestedAt: Date(timeIntervalSince1970: 14)
        ))

        let route = AutomationVisualFrameRoute.resolve(request: request, in: context)

        #expect(!route.isAvailable)
        #expect(route.processingRegion == nil)
        #expect(route.unavailableReason == .selectedRegionOutsideDisplay)
    }

    @Test("Loop policy clamps attempts and polling while preserving body order")
    func loopPolicyClampsAttemptsAndPolling() {
        let firstTask = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondTask = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let policy = AutomationRepeatUntilLoopPolicy(
            bodyTaskIDs: [firstTask, secondTask, firstTask],
            condition: AutomationConditionSpec(
                name: "Wait for done",
                kind: .ocrText(AutomationOCRCondition(text: "Done")),
                pollingInterval: 0.01
            ),
            maxAttempts: 0,
            timeout: -4,
            pollingInterval: 0.01,
            cooldown: -2
        )

        #expect(policy.bodyTaskIDs == [firstTask, secondTask])
        #expect(policy.maxAttempts == 1)
        #expect(policy.timeout == 0)
        #expect(policy.pollingInterval == 0.05)
        #expect(policy.cooldown == 0)
    }

    @Test("Repeat until completes when condition matches")
    func repeatUntilCompletesWhenConditionMatches() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let policy = repeatPolicy(maxAttempts: 3)
        let attempt = AutomationRepeatUntilAttemptEvidence(
            attemptIndex: 1,
            startedAt: startedAt,
            bodyCompletedAt: Date(timeIntervalSince1970: 101),
            evaluatedAt: Date(timeIntervalSince1970: 102),
            outcome: .conditionMatched
        )

        let state = AutomationRepeatUntilLoopState(policy: policy, startedAt: startedAt)
            .appendingAttempt(attempt)

        #expect(state.status == .completed)
        #expect(state.stopReason == .matched)
        #expect(state.terminalOutcome == .conditionMatched)
        #expect(state.completedAt == Date(timeIntervalSince1970: 102))
        #expect(state.nextAttemptIndex == nil)
    }

    @Test("Repeat until fails after max attempts")
    func repeatUntilFailsAfterMaxAttempts() {
        let startedAt = Date(timeIntervalSince1970: 200)
        let policy = repeatPolicy(maxAttempts: 2)

        let first = AutomationRepeatUntilLoopState(policy: policy, startedAt: startedAt)
            .appendingAttempt(notMatchedAttempt(1, startedAt: startedAt, evaluatedAt: 201))

        #expect(first.status == .running)
        #expect(first.nextAttemptIndex == 2)

        let second = first.appendingAttempt(notMatchedAttempt(2, startedAt: Date(timeIntervalSince1970: 202), evaluatedAt: 203))

        #expect(second.status == .failed)
        #expect(second.stopReason == .maxAttempts)
        #expect(second.terminalOutcome == .failed(report: nil))
        #expect(second.completedAt == Date(timeIntervalSince1970: 203))
    }

    @Test("Repeat until can continue workflow after timeout")
    func repeatUntilCanContinueAfterTimeout() {
        let startedAt = Date(timeIntervalSince1970: 300)
        let policy = repeatPolicy(
            maxAttempts: 5,
            timeout: 2,
            failurePolicy: .continueWorkflow
        )

        let state = AutomationRepeatUntilLoopState(policy: policy, startedAt: startedAt)
            .appendingAttempt(notMatchedAttempt(1, startedAt: startedAt, evaluatedAt: 303))

        #expect(state.status == .completed)
        #expect(state.stopReason == .timeout)
        #expect(state.terminalOutcome == .conditionNotMatched)
    }

    @Test("Repeat until can require manual approval after exhaustion")
    func repeatUntilCanRequireManualApprovalAfterExhaustion() {
        let startedAt = Date(timeIntervalSince1970: 400)
        let policy = repeatPolicy(
            maxAttempts: 1,
            failurePolicy: .requireManualApproval
        )

        let state = AutomationRepeatUntilLoopState(policy: policy, startedAt: startedAt)
            .appendingAttempt(notMatchedAttempt(1, startedAt: startedAt, evaluatedAt: 401))

        #expect(state.status == .waitingForManualApproval)
        #expect(state.stopReason == .maxAttempts)
        #expect(state.terminalOutcome == nil)
        #expect(state.completedAt == nil)
    }

    private func repeatPolicy(
        maxAttempts: Int,
        timeout: TimeInterval? = nil,
        failurePolicy: AutomationRepeatUntilFailurePolicy = .failRun
    ) -> AutomationRepeatUntilLoopPolicy {
        AutomationRepeatUntilLoopPolicy(
            bodyTaskIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000301")!],
            condition: AutomationConditionSpec(
                name: "Wait for done",
                kind: .ocrText(AutomationOCRCondition(text: "Done")),
                pollingInterval: 0.25
            ),
            maxAttempts: maxAttempts,
            timeout: timeout,
            failurePolicy: failurePolicy
        )
    }

    private func notMatchedAttempt(
        _ index: Int,
        startedAt: Date,
        evaluatedAt: TimeInterval
    ) -> AutomationRepeatUntilAttemptEvidence {
        AutomationRepeatUntilAttemptEvidence(
            attemptIndex: index,
            startedAt: startedAt,
            bodyCompletedAt: Date(timeIntervalSince1970: evaluatedAt - 0.25),
            evaluatedAt: Date(timeIntervalSince1970: evaluatedAt),
            outcome: .conditionNotMatched
        )
    }

    private func sample() -> AutomationVisualFrameSample {
        AutomationVisualFrameSample(
            source: .fixture,
            capturedAt: Date(timeIntervalSince1970: 10),
            imageSize: RecordingImageSize(width: 1_200, height: 800),
            provider: "fixture"
        )
    }
}
