import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Visual Live Frame Router Tests")
struct AutomationVisualLiveFrameRouterTests {
    @Test("Latest frame router crops the newest selected region")
    func latestFrameRouterCropsNewestSelectedRegion() async throws {
        let router = AutomationVisualLatestFrameRouter()
        let workflowID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        let taskID = UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
        let firstSample = sample(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000011")!,
            capturedAt: 1,
            width: 100,
            height: 80
        )
        let secondSample = sample(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000012")!,
            capturedAt: 2,
            width: 100,
            height: 80
        )

        await router.ingest(AutomationVisualImageFrame(
            sample: firstSample,
            image: try makeImage(
                width: 100,
                height: 80,
                fill: .black,
                highlight: CGRect(x: 10, y: 20, width: 30, height: 20),
                highlightColor: .red
            )
        ))
        await router.ingest(AutomationVisualImageFrame(
            sample: secondSample,
            image: try makeImage(
                width: 100,
                height: 80,
                fill: .black,
                highlight: CGRect(x: 10, y: 20, width: 30, height: 20),
                highlightColor: .green
            )
        ))

        let condition = AutomationConditionSpec(
            name: "Ready text",
            kind: .ocrText(AutomationOCRCondition(
                text: "Ready",
                searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                searchRegionSpace: .displayAbsolute
            ))
        )
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)
        )

        let routed = try await router.routeLatest(
            workflowID: workflowID,
            taskID: taskID,
            condition: condition,
            context: context,
            requestedAt: Date(timeIntervalSince1970: 3)
        )

        #expect(routed.request.sample.id == secondSample.id)
        #expect(routed.route.resolvedSearchRegion == RectValue(x: 10, y: 20, width: 30, height: 20))
        #expect(routed.sourcePixelRect == RectValue(x: 10, y: 20, width: 30, height: 20))
        #expect(routed.croppedImage.image.width == 30)
        #expect(routed.croppedImage.image.height == 20)
        #expect(try pixelColor(in: routed.croppedImage.image, x: 15, y: 10).isClose(to: .green))
    }

    @Test("Live frame router maps target-window display coordinates to pixel crop")
    func liveFrameRouterMapsWindowCoordinatesToPixelCrop() async throws {
        let router = AutomationVisualLatestFrameRouter()
        let sample = AutomationVisualFrameSample(
            id: UUID(uuidString: "A2000000-0000-0000-0000-000000000001")!,
            source: .fixture,
            capturedAt: Date(timeIntervalSince1970: 10),
            imageSize: RecordingImageSize(width: 200, height: 100),
            displayScale: 2,
            displayBounds: RectValue(x: 0, y: 0, width: 100, height: 50),
            provider: "fixture"
        )
        await router.ingest(AutomationVisualImageFrame(
            sample: sample,
            image: try makeImage(
                width: 200,
                height: 100,
                fill: .black,
                highlight: CGRect(x: 20, y: 10, width: 40, height: 20),
                highlightColor: .blue
            )
        ))
        let condition = AutomationConditionSpec(
            name: "Wait for icon",
            kind: .visual(AutomationVisualCondition(type: .imageAppeared, imageRef: "assets/icon.png"))
        )
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 100, height: 50),
            windowFrame: RectValue(x: 10, y: 5, width: 20, height: 10)
        )

        let routed = try await router.routeLatest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: condition,
            context: context,
            requestedAt: Date(timeIntervalSince1970: 11)
        )

        #expect(routed.request.scope.kind == .targetWindow)
        #expect(routed.route.resolvedSearchRegion == RectValue(x: 10, y: 5, width: 20, height: 10))
        #expect(routed.sourcePixelRect == RectValue(x: 20, y: 10, width: 40, height: 20))
        #expect(routed.croppedImage.image.width == 40)
        #expect(routed.croppedImage.image.height == 20)
        #expect(try pixelColor(in: routed.croppedImage.image, x: 20, y: 10).isClose(to: .blue))
    }

    @Test("Live frame router reports missing frame and unavailable route")
    func liveFrameRouterReportsMissingFrameAndUnavailableRoute() async throws {
        let router = AutomationVisualLatestFrameRouter()
        let condition = AutomationConditionSpec(
            name: "Watch pixel",
            kind: .visual(AutomationVisualCondition(type: .pixelMatched, targetColorHex: "#00FF00"))
        )
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)
        )

        await #expect(throws: AutomationVisualLiveFrameRouterError.noLatestFrame) {
            _ = try await router.routeLatest(
                workflowID: UUID(),
                taskID: UUID(),
                condition: condition,
                context: context,
                requestedAt: Date(timeIntervalSince1970: 1)
            )
        }

        await router.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "A3000000-0000-0000-0000-000000000001")!,
                capturedAt: 2,
                width: 100,
                height: 80
            ),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))

        await #expect(throws: AutomationVisualLiveFrameRouterError.routeUnavailable(.selectedRegionOutsideDisplay)) {
            _ = try await router.routeLatest(
                workflowID: UUID(),
                taskID: UUID(),
                condition: condition,
                context: context,
                scope: .selectedRegion(RectValue(x: 500, y: 500, width: 20, height: 20)),
                requestedAt: Date(timeIntervalSince1970: 3)
            )
        }
    }

    @Test("Polling dispatcher skips stale frames")
    func pollingDispatcherSkipsStaleFrames() async throws {
        let sampleID = UUID(uuidString: "A4000000-0000-0000-0000-000000000001")!
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: AutomationVisualFrameDetectorClient { routedFrame in
                AutomationVisualDetectorResult(
                    requestID: routedFrame.request.id,
                    detectorKind: routedFrame.request.detectorKind,
                    outcome: .conditionNotMatched,
                    observedSummary: "Not ready",
                    evaluatedAt: Date(timeIntervalSince1970: 20)
                )
            },
            now: { Date(timeIntervalSince1970: 20) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: sampleID,
                capturedAt: 10,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))
        let request = AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Ready",
                kind: .ocrText(AutomationOCRCondition(text: "Ready"))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            maxPolls: 2,
            pollingInterval: 0.1
        )

        let first = try await dispatcher.pollOnce(request)
        #expect(first.routedFrame.request.sample.id == sampleID)

        await #expect(throws: AutomationVisualLiveFrameRouterError.noFreshFrame(sampleID)) {
            _ = try await dispatcher.pollOnce(request, pollIndex: 2)
        }
    }

    @Test("Polling dispatcher sleeps until a fresh frame matches")
    func pollingDispatcherSleepsUntilFreshFrameMatches() async throws {
        let redID = UUID(uuidString: "A5000000-0000-0000-0000-000000000001")!
        let greenID = UUID(uuidString: "A5000000-0000-0000-0000-000000000002")!
        let detectorLog = PollingDetectorLog()
        let sleepLog = PollingSleepLog()
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: AutomationVisualFrameDetectorClient { routedFrame in
                await detectorLog.record(routedFrame.request.sample.id)
                let matched = routedFrame.request.sample.id == greenID
                return AutomationVisualDetectorResult(
                    requestID: routedFrame.request.id,
                    detectorKind: routedFrame.request.detectorKind,
                    outcome: matched ? .conditionMatched : .conditionNotMatched,
                    observedSummary: matched ? "Matched fresh frame" : "Waiting",
                    evaluatedAt: Date(timeIntervalSince1970: matched ? 32 : 31)
                )
            },
            now: { Date(timeIntervalSince1970: 30) }
        )

        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(id: redID, capturedAt: 1, width: 100, height: 80),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))
        let greenFrame = AutomationVisualImageFrame(
            sample: sample(id: greenID, capturedAt: 2, width: 100, height: 80),
            image: try makeImage(width: 100, height: 80, fill: .green)
        )

        let request = AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Ready",
                kind: .visual(AutomationVisualCondition(type: .imageAppeared, imageRef: "assets/ready.png"))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 3,
            pollingInterval: 0.25
        )

        let summary = await dispatcher.pollUntilMatched(request) { interval in
            await sleepLog.record(interval)
            await dispatcher.ingest(greenFrame)
        }

        #expect(summary.status == .matched)
        #expect(summary.evaluations.map(\.routedFrame.request.sample.id) == [redID, greenID])
        #expect(summary.staleFrameCount == 0)
        #expect(await detectorLog.ids == [redID, greenID])
        #expect(await sleepLog.intervals == [0.25])
    }

    @Test("Polling dispatcher exhausts without reprocessing stale frame")
    func pollingDispatcherExhaustsWithoutReprocessingStaleFrame() async throws {
        let frameID = UUID(uuidString: "A6000000-0000-0000-0000-000000000001")!
        let detectorLog = PollingDetectorLog()
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: AutomationVisualFrameDetectorClient { routedFrame in
                await detectorLog.record(routedFrame.request.sample.id)
                return AutomationVisualDetectorResult(
                    requestID: routedFrame.request.id,
                    detectorKind: routedFrame.request.detectorKind,
                    outcome: .conditionNotMatched,
                    observedSummary: "Still waiting",
                    evaluatedAt: Date(timeIntervalSince1970: 40)
                )
            },
            now: { Date(timeIntervalSince1970: 40) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(id: frameID, capturedAt: 1, width: 100, height: 80),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))
        let request = AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Ready",
                kind: .ocrText(AutomationOCRCondition(text: "Ready"))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 3,
            pollingInterval: 0.1
        )

        let summary = await dispatcher.pollUntilMatched(request) { _ in }

        #expect(summary.status == .exhausted)
        #expect(summary.evaluations.count == 1)
        #expect(summary.staleFrameCount == 2)
        #expect(summary.lastError == .noFreshFrame(frameID))
        #expect(await detectorLog.ids == [frameID])
    }

    @Test("OCR detector matches routed crop text and maps normalized text bounds")
    func ocrDetectorMatchesRoutedCropTextAndMapsBounds() async throws {
        let frameID = UUID(uuidString: "A7000000-0000-0000-0000-000000000001")!
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .ocrText(
                textDetector: AutomationVisualTextDetectorClient { routedFrame in
                    #expect(routedFrame.croppedImage.image.width == 30)
                    #expect(routedFrame.croppedImage.image.height == 20)
                    return [
                        TextDetection(
                            text: "Ready now",
                            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3),
                            confidence: 0.92
                        )
                    ]
                },
                now: { Date(timeIntervalSince1970: 50) }
            ),
            now: { Date(timeIntervalSince1970: 50) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(id: frameID, capturedAt: 1, width: 100, height: 80),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))

        let request = AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Ready text",
                kind: .ocrText(AutomationOCRCondition(
                    text: "ready",
                    matchMode: .contains,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        )

        let summary = await dispatcher.pollUntilMatched(request)

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.detectorKind == .ocrText)
        #expect(result.observedSummary == "Matched text: Ready now")
        #expect(result.matchedRegion == RectValue(x: 13, y: 24, width: 12, height: 6))
    }

    @Test("OCR detector respects exact text match mode")
    func ocrDetectorRespectsExactTextMatchMode() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .ocrText(
                textDetector: AutomationVisualTextDetectorClient { _ in
                    [
                        TextDetection(
                            text: "Ready now",
                            boundingBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                            confidence: 0.95
                        )
                    ]
                },
                now: { Date(timeIntervalSince1970: 60) }
            ),
            now: { Date(timeIntervalSince1970: 60) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "A8000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Exact ready",
                kind: .ocrText(AutomationOCRCondition(text: "Ready", matchMode: .exact))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            maxPolls: 1
        ))

        #expect(summary.status == .exhausted)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionNotMatched)
        #expect(result.observedSummary == "Detected text: Ready now")
        #expect(result.matchedRegion == nil)
    }

    @Test("OCR detector rejects non-OCR routed conditions")
    func ocrDetectorRejectsNonOCRRoutedConditions() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .ocrText(
                textDetector: AutomationVisualTextDetectorClient { _ in [] },
                now: { Date(timeIntervalSince1970: 70) }
            ),
            now: { Date(timeIntervalSince1970: 70) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "A9000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let evaluation = try await dispatcher.pollOnce(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Pixel",
                kind: .visual(AutomationVisualCondition(type: .pixelMatched, targetColorHex: "#00FF00"))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            scope: .fullDisplay(explicitlyChosen: true)
        ))

        #expect(evaluation.detectorResult.outcome == .rejected(reason: "OCR detector received a non-OCR condition"))
        #expect(evaluation.detectorResult.observedSummary == "Unsupported routed condition for OCR detector")
    }

    @Test("Feature-print detector matches image appeared over routed crop")
    func featurePrintDetectorMatchesImageAppearedOverRoutedCrop() async throws {
        let template = AutomationVisualCGImage(try makeImage(width: 12, height: 12, fill: .green))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { routedFrame, reference in
                    #expect(reference == "ready_template")
                    #expect(routedFrame.croppedImage.image.width == 30)
                    #expect(routedFrame.croppedImage.image.height == 20)
                    return template.image
                },
                featurePrint: AutomationVisualFeaturePrintClient { _, runtime in
                    #expect(runtime.width == 30)
                    #expect(runtime.height == 20)
                    return 12.5
                },
                now: { Date(timeIntervalSince1970: 80) }
            ),
            now: { Date(timeIntervalSince1970: 80) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AA000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for icon",
                kind: .visual(AutomationVisualCondition(
                    type: .imageAppeared,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    imageRef: "ready_template"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.detectorKind == .featurePrintImage)
        #expect(result.score == AutomationVisualDetectorScore(
            value: 12.5,
            threshold: 15,
            comparison: .lessThanOrEqual
        ))
        #expect(result.observedSummary == "Image ready_template distance 12.50 <= 15.00")
        #expect(result.matchedRegion == RectValue(x: 10, y: 20, width: 30, height: 20))
    }

    @Test("Feature-print detector can require deterministic verifier match")
    func featurePrintDetectorCanRequireDeterministicVerifierMatch() async throws {
        let template = AutomationVisualCGImage(try makeImage(width: 12, height: 12, fill: .green))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { _, _ in template.image },
                featurePrint: AutomationVisualFeaturePrintClient { _, _ in 12.5 },
                verifier: .pixelSimilarity(threshold: 0.90),
                now: { Date(timeIntervalSince1970: 82) }
            ),
            now: { Date(timeIntervalSince1970: 82) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AA100000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for verified icon",
                kind: .visual(AutomationVisualCondition(
                    type: .imageAppeared,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    imageRef: "ready_template"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .exhausted)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionNotMatched)
        #expect(result.observedSummary == "Image ready_template distance 12.50 <= 15.00 verified 0.42 < 0.90")
        #expect(result.matchedRegion == nil)
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: "ready_template"),
            AutomationConditionDiagnosticField(id: "distance", title: "Feature distance", value: "12.50"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Feature threshold", value: "15.00"),
            AutomationConditionDiagnosticField(id: "verifierSimilarity", title: "Verifier similarity", value: "0.42"),
            AutomationConditionDiagnosticField(id: "verifierThreshold", title: "Verifier threshold", value: "0.90")
        ])
    }

    @Test("Feature-print detector matches when verifier also accepts")
    func featurePrintDetectorMatchesWhenVerifierAlsoAccepts() async throws {
        let template = AutomationVisualCGImage(try makeImage(width: 12, height: 12, fill: .green))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { _, _ in template.image },
                featurePrint: AutomationVisualFeaturePrintClient { _, _ in 12.5 },
                verifier: .pixelSimilarity(threshold: 0.90),
                now: { Date(timeIntervalSince1970: 84) }
            ),
            now: { Date(timeIntervalSince1970: 84) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AA200000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(width: 100, height: 80, fill: .green)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for verified icon",
                kind: .visual(AutomationVisualCondition(
                    type: .imageAppeared,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    imageRef: "ready_template"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.observedSummary == "Image ready_template distance 12.50 <= 15.00 verified 1.00 >= 0.90")
        #expect(result.matchedRegion == RectValue(x: 10, y: 20, width: 30, height: 20))
    }

    @Test("Feature-print detector locates template inside routed crop")
    func featurePrintDetectorLocatesTemplateInsideRoutedCrop() async throws {
        let template = AutomationVisualCGImage(try makeImage(width: 6, height: 6, fill: .green))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { _, reference in
                    #expect(reference == "ready_template")
                    return template.image
                },
                featurePrint: AutomationVisualFeaturePrintClient { _, _ in 16 },
                locator: .pixelSimilarity(threshold: 0.99, stride: 1),
                now: { Date(timeIntervalSince1970: 86) }
            ),
            now: { Date(timeIntervalSince1970: 86) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AA300000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(
                width: 100,
                height: 80,
                fill: .black,
                highlight: CGRect(x: 28, y: 27, width: 6, height: 6),
                highlightColor: .green
            )
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for icon inside selection",
                kind: .visual(AutomationVisualCondition(
                    type: .imageAppeared,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    imageRef: "ready_template"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.score == AutomationVisualDetectorScore(
            value: 1,
            threshold: 0.99,
            comparison: .greaterThanOrEqual
        ))
        #expect(result.observedSummary == "Image ready_template distance 16.00 > 15.00 located 1.00 >= 0.99")
        #expect(result.matchedRegion == RectValue(x: 28, y: 27, width: 6, height: 6))
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: "ready_template"),
            AutomationConditionDiagnosticField(id: "distance", title: "Feature distance", value: "16.00"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Feature threshold", value: "15.00"),
            AutomationConditionDiagnosticField(id: "locatorSimilarity", title: "Locator similarity", value: "1.00"),
            AutomationConditionDiagnosticField(id: "locatorThreshold", title: "Locator threshold", value: "0.99"),
            AutomationConditionDiagnosticField(id: "locatorX", title: "Locator x", value: "18.00"),
            AutomationConditionDiagnosticField(id: "locatorY", title: "Locator y", value: "7.00"),
            AutomationConditionDiagnosticField(id: "locatorWidth", title: "Locator width", value: "6.00"),
            AutomationConditionDiagnosticField(id: "locatorHeight", title: "Locator height", value: "6.00")
        ])
    }

    @Test("Feature-print detector treats unlocated template as disappeared")
    func featurePrintDetectorTreatsUnlocatedTemplateAsDisappeared() async throws {
        let template = AutomationVisualCGImage(try makeImage(width: 6, height: 6, fill: .green))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { _, reference in
                    #expect(reference == "spinner_template")
                    return template.image
                },
                featurePrint: AutomationVisualFeaturePrintClient { _, _ in 12.5 },
                locator: .pixelSimilarity(threshold: 0.99, stride: 1),
                now: { Date(timeIntervalSince1970: 88) }
            ),
            now: { Date(timeIntervalSince1970: 88) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AA400000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(width: 100, height: 80, fill: .black)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for spinner gone inside selection",
                kind: .visual(AutomationVisualCondition(
                    type: .imageDisappeared,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    imageRef: "spinner_template"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        let score = try #require(result.score)
        #expect(score.value > 0.42)
        #expect(score.value < 0.43)
        #expect(score.threshold == 0.99)
        #expect(score.comparison == .greaterThanOrEqual)
        #expect(result.observedSummary == "Image spinner_template absent distance 12.50 <= 15.00 located 0.42 < 0.99")
        #expect(result.matchedRegion == nil)
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "imageRef", title: "Image", value: "spinner_template"),
            AutomationConditionDiagnosticField(id: "distance", title: "Feature distance", value: "12.50"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Feature threshold", value: "15.00"),
            AutomationConditionDiagnosticField(id: "locatorSimilarity", title: "Locator similarity", value: "0.42"),
            AutomationConditionDiagnosticField(id: "locatorThreshold", title: "Locator threshold", value: "0.99")
        ])
    }

    @Test("Feature-print detector treats absent image as disappeared match")
    func featurePrintDetectorTreatsAbsentImageAsDisappearedMatch() async throws {
        let template = AutomationVisualCGImage(try makeImage(width: 8, height: 8, fill: .blue))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { _, reference in
                    #expect(reference == "spinner_template")
                    return template.image
                },
                featurePrint: AutomationVisualFeaturePrintClient { _, _ in 16 },
                now: { Date(timeIntervalSince1970: 90) }
            ),
            now: { Date(timeIntervalSince1970: 90) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AB000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for spinner gone",
                kind: .visual(AutomationVisualCondition(
                    type: .imageDisappeared,
                    imageRef: "spinner_template"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.score == AutomationVisualDetectorScore(
            value: 16,
            threshold: 15,
            comparison: .lessThanOrEqual
        ))
        #expect(result.observedSummary == "Image spinner_template absent distance 16.00 > 15.00")
        #expect(result.matchedRegion == nil)
    }

    @Test("Feature-print detector rejects missing image reference")
    func featurePrintDetectorRejectsMissingImageReference() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .featurePrintImage(
                imageProvider: { _, _ in nil },
                featurePrint: AutomationVisualFeaturePrintClient { _, _ in 0 },
                now: { Date(timeIntervalSince1970: 100) }
            ),
            now: { Date(timeIntervalSince1970: 100) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AC000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let evaluation = try await dispatcher.pollOnce(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for icon",
                kind: .visual(AutomationVisualCondition(type: .imageAppeared))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            scope: .fullDisplay(explicitlyChosen: true)
        ))

        #expect(evaluation.detectorResult.outcome == .rejected(
            reason: "Feature-print detector missing image reference"
        ))
        #expect(evaluation.detectorResult.observedSummary == "No image reference configured for feature-print detector")
    }

    @Test("Pixel detector matches normalized point inside routed selected region")
    func pixelDetectorMatchesNormalizedPointInsideRoutedSelectedRegion() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .pixelColor(now: { Date(timeIntervalSince1970: 110) }),
            now: { Date(timeIntervalSince1970: 110) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AD000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(
                width: 100,
                height: 80,
                fill: .black,
                highlight: CGRect(x: 10, y: 20, width: 30, height: 20),
                highlightColor: .green
            )
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for green status",
                kind: .visual(AutomationVisualCondition(
                    type: .pixelMatched,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    pixel: AutomationGraphPoint(x: 0.5, y: 0.5),
                    targetColorHex: "#00FF00"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.detectorKind == .pixelColor)
        #expect(result.score == AutomationVisualDetectorScore(
            value: 1,
            threshold: 0.95,
            comparison: .greaterThanOrEqual
        ))
        #expect(result.observedSummary == "Pixel similarity 1.00 (#00FF00 avg vs #00FF00, samples 9)")
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "sampledColor", title: "Sampled color", value: "#00FF00"),
            AutomationConditionDiagnosticField(id: "targetColor", title: "Target color", value: "#00FF00"),
            AutomationConditionDiagnosticField(id: "similarity", title: "Similarity", value: "1.00"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: "0.95"),
            AutomationConditionDiagnosticField(id: "sampleRadius", title: "Sample radius", value: "1"),
            AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "9")
        ])
        #expect(result.matchedRegion == RectValue(x: 24, y: 29, width: 3, height: 3))
    }

    @Test("Pixel detector samples selected-region center when no explicit point is set")
    func pixelDetectorSamplesSelectedRegionCenterWhenNoExplicitPointIsSet() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .pixelColor(now: { Date(timeIntervalSince1970: 120) }),
            now: { Date(timeIntervalSince1970: 120) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AE000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(
                width: 80,
                height: 60,
                fill: .black,
                highlight: CGRect(x: 20, y: 10, width: 20, height: 20),
                highlightColor: .blue
            )
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for blue center",
                kind: .visual(AutomationVisualCondition(
                    type: .pixelMatched,
                    searchRegion: RectValue(x: 20, y: 10, width: 20, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    targetColorHex: "#0000FF"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.matchedRegion == RectValue(x: 29, y: 19, width: 3, height: 3))
    }

    @Test("Pixel detector tolerates single-pixel noise with small radius sampling")
    func pixelDetectorToleratesSinglePixelNoiseWithSmallRadiusSampling() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .pixelColor(now: { Date(timeIntervalSince1970: 125) }),
            now: { Date(timeIntervalSince1970: 125) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AE500000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 30,
                height: 30
            ),
            image: try makeNoisyPixelImage()
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for noisy green status",
                kind: .visual(AutomationVisualCondition(
                    type: .pixelMatched,
                    searchRegion: RectValue(x: 0, y: 0, width: 30, height: 30),
                    searchRegionSpace: .displayAbsolute,
                    pixel: AutomationGraphPoint(x: 0.5, y: 0.5),
                    targetColorHex: "#00FF00",
                    threshold: 0.93
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 30, height: 30)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        let score = try #require(result.score)
        #expect(score.value > 0.93)
        #expect(score.value < 0.94)
        #expect(result.observedSummary == "Pixel similarity 0.94 (#00E200 avg vs #00FF00, samples 9)")
        #expect(result.matchedRegion == RectValue(x: 14, y: 14, width: 3, height: 3))
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "sampledColor", title: "Sampled color", value: "#00E200"),
            AutomationConditionDiagnosticField(id: "targetColor", title: "Target color", value: "#00FF00"),
            AutomationConditionDiagnosticField(id: "similarity", title: "Similarity", value: "0.94"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: "0.93"),
            AutomationConditionDiagnosticField(id: "sampleRadius", title: "Sample radius", value: "1"),
            AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "9")
        ])
    }

    @Test("Pixel detector honors configured zero-radius sampling")
    func pixelDetectorHonorsConfiguredZeroRadiusSampling() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .pixelColor(now: { Date(timeIntervalSince1970: 126) }),
            now: { Date(timeIntervalSince1970: 126) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AE500000-0000-0000-0000-000000000002")!,
                capturedAt: 1,
                width: 30,
                height: 30
            ),
            image: try makeNoisyPixelImage()
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for exact noisy center",
                kind: .visual(AutomationVisualCondition(
                    type: .pixelMatched,
                    searchRegion: RectValue(x: 0, y: 0, width: 30, height: 30),
                    searchRegionSpace: .displayAbsolute,
                    pixel: AutomationGraphPoint(x: 0.5, y: 0.5),
                    targetColorHex: "#00FF00",
                    pixelSampleRadius: 0,
                    threshold: 0.93
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 30, height: 30)),
            maxPolls: 1
        ))

        #expect(summary.status == .exhausted)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionNotMatched)
        #expect(result.observedSummary == "Pixel similarity 0.42 (#000000 avg vs #00FF00, samples 1)")
        #expect(result.matchedRegion == nil)
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "sampledColor", title: "Sampled color", value: "#000000"),
            AutomationConditionDiagnosticField(id: "targetColor", title: "Target color", value: "#00FF00"),
            AutomationConditionDiagnosticField(id: "similarity", title: "Similarity", value: "0.42"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: "0.93"),
            AutomationConditionDiagnosticField(id: "sampleRadius", title: "Sample radius", value: "0"),
            AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "1")
        ])
    }

    @Test("Pixel detector rejects missing target color")
    func pixelDetectorRejectsMissingTargetColor() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .pixelColor(now: { Date(timeIntervalSince1970: 130) }),
            now: { Date(timeIntervalSince1970: 130) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "AF000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let evaluation = try await dispatcher.pollOnce(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for color",
                kind: .visual(AutomationVisualCondition(
                    type: .pixelMatched,
                    pixel: AutomationGraphPoint(x: 0.5, y: 0.5)
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            scope: .fullDisplay(explicitlyChosen: true)
        ))

        #expect(evaluation.detectorResult.outcome == .rejected(reason: "Pixel detector missing target color"))
        #expect(evaluation.detectorResult.observedSummary == "No target color configured for pixel detector")
    }

    @Test("Region diff detector matches changed routed crop against baseline")
    func regionDiffDetectorMatchesChangedRoutedCropAgainstBaseline() async throws {
        let baseline = AutomationVisualCGImage(try makeImage(width: 30, height: 20, fill: .black))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .regionDiff(
                baselineProvider: { routedFrame, reference in
                    #expect(reference == "status_baseline")
                    #expect(routedFrame.croppedImage.image.width == 30)
                    #expect(routedFrame.croppedImage.image.height == 20)
                    return baseline.image
                },
                now: { Date(timeIntervalSince1970: 140) }
            ),
            now: { Date(timeIntervalSince1970: 140) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 100,
                height: 80
            ),
            image: try makeImage(
                width: 100,
                height: 80,
                fill: .black,
                highlight: CGRect(x: 10, y: 20, width: 30, height: 20),
                highlightColor: .green
            )
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for status change",
                kind: .visual(AutomationVisualCondition(
                    type: .regionChanged,
                    searchRegion: RectValue(x: 10, y: 20, width: 30, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    baselineRef: "status_baseline"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 100, height: 80)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionMatched)
        #expect(result.detectorKind == .regionDiff)
        let score = try #require(result.score)
        #expect(abs(score.value - 0.5773502691896258) < 0.000_001)
        #expect(score.threshold == 0.08)
        #expect(score.comparison == .greaterThanOrEqual)
        #expect(result.observedSummary == "Region change 0.58 (changed 1.00, max 0.58, samples 9)")
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "baselineRef", title: "Baseline", value: "status_baseline"),
            AutomationConditionDiagnosticField(id: "changeScore", title: "Change score", value: "0.58"),
            AutomationConditionDiagnosticField(id: "changedRatio", title: "Changed ratio", value: "1.00"),
            AutomationConditionDiagnosticField(id: "maxDelta", title: "Max delta", value: "0.58"),
            AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "9"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: "0.08")
        ])
        #expect(result.matchedRegion == RectValue(x: 10, y: 20, width: 30, height: 20))
    }

    @Test("Region diff detector does not match unchanged routed crop")
    func regionDiffDetectorDoesNotMatchUnchangedRoutedCrop() async throws {
        let baseline = AutomationVisualCGImage(try makeImage(width: 20, height: 20, fill: .black))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .regionDiff(
                baselineProvider: { _, _ in baseline.image },
                now: { Date(timeIntervalSince1970: 150) }
            ),
            now: { Date(timeIntervalSince1970: 150) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for status change",
                kind: .visual(AutomationVisualCondition(
                    type: .regionChanged,
                    searchRegion: RectValue(x: 20, y: 10, width: 20, height: 20),
                    searchRegionSpace: .displayAbsolute,
                    baselineRef: "status_baseline"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            maxPolls: 1
        ))

        #expect(summary.status == .exhausted)
        let result = try #require(summary.lastResult)
        #expect(result.outcome == .conditionNotMatched)
        #expect(result.score == AutomationVisualDetectorScore(
            value: 0,
            threshold: 0.08,
            comparison: .greaterThanOrEqual
        ))
        #expect(result.observedSummary == "Region change 0.00 (changed 0.00, max 0.00, samples 9)")
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "baselineRef", title: "Baseline", value: "status_baseline"),
            AutomationConditionDiagnosticField(id: "changeScore", title: "Change score", value: "0.00"),
            AutomationConditionDiagnosticField(id: "changedRatio", title: "Changed ratio", value: "0.00"),
            AutomationConditionDiagnosticField(id: "maxDelta", title: "Max delta", value: "0.00"),
            AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "9"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: "0.08")
        ])
        #expect(result.matchedRegion == nil)
    }

    @Test("Region diff detector reports partial changed ratio")
    func regionDiffDetectorReportsPartialChangedRatio() async throws {
        let baseline = AutomationVisualCGImage(try makeImage(width: 64, height: 64, fill: .black))
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .regionDiff(
                baselineProvider: { _, _ in baseline.image },
                now: { Date(timeIntervalSince1970: 155) }
            ),
            now: { Date(timeIntervalSince1970: 155) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "B1500000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 64,
                height: 64
            ),
            image: try makeImage(
                width: 64,
                height: 64,
                fill: .black,
                highlight: CGRect(x: 0, y: 0, width: 64, height: 32),
                highlightColor: .green
            )
        ))

        let summary = await dispatcher.pollUntilMatched(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for partial region change",
                kind: .visual(AutomationVisualCondition(
                    type: .regionChanged,
                    searchRegion: RectValue(x: 0, y: 0, width: 64, height: 64),
                    searchRegionSpace: .displayAbsolute,
                    baselineRef: "status_baseline"
                ))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 64, height: 64)),
            maxPolls: 1
        ))

        #expect(summary.status == .matched)
        let result = try #require(summary.lastResult)
        let score = try #require(result.score)
        #expect(abs(score.value - 0.2886751345948129) < 0.000_001)
        #expect(result.observedSummary == "Region change 0.29 (changed 0.50, max 0.58, samples 16)")
        #expect(result.fields == [
            AutomationConditionDiagnosticField(id: "baselineRef", title: "Baseline", value: "status_baseline"),
            AutomationConditionDiagnosticField(id: "changeScore", title: "Change score", value: "0.29"),
            AutomationConditionDiagnosticField(id: "changedRatio", title: "Changed ratio", value: "0.50"),
            AutomationConditionDiagnosticField(id: "maxDelta", title: "Max delta", value: "0.58"),
            AutomationConditionDiagnosticField(id: "sampleCount", title: "Samples", value: "16"),
            AutomationConditionDiagnosticField(id: "threshold", title: "Threshold", value: "0.08")
        ])
    }

    @Test("Region diff detector rejects missing baseline reference")
    func regionDiffDetectorRejectsMissingBaselineReference() async throws {
        let dispatcher = AutomationVisualPollingDispatcher(
            detector: .regionDiff(now: { Date(timeIntervalSince1970: 160) }),
            now: { Date(timeIntervalSince1970: 160) }
        )
        await dispatcher.ingest(AutomationVisualImageFrame(
            sample: sample(
                id: UUID(uuidString: "B2000000-0000-0000-0000-000000000001")!,
                capturedAt: 1,
                width: 80,
                height: 60
            ),
            image: try makeImage(width: 80, height: 60, fill: .black)
        ))

        let evaluation = try await dispatcher.pollOnce(AutomationVisualPollingRequest(
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Wait for change",
                kind: .visual(AutomationVisualCondition(type: .regionChanged))
            ),
            context: AutomationOCRSearchRegionContext(displayBounds: RectValue(x: 0, y: 0, width: 80, height: 60)),
            scope: .fullDisplay(explicitlyChosen: true)
        ))

        #expect(evaluation.detectorResult.outcome == .rejected(
            reason: "Region-diff detector missing baseline reference"
        ))
        #expect(evaluation.detectorResult.observedSummary == "No baseline reference configured for region-diff detector")
    }

    private func sample(
        id: UUID,
        capturedAt: TimeInterval,
        width: Int,
        height: Int
    ) -> AutomationVisualFrameSample {
        AutomationVisualFrameSample(
            id: id,
            source: .fixture,
            capturedAt: Date(timeIntervalSince1970: capturedAt),
            imageSize: RecordingImageSize(width: width, height: height),
            displayBounds: RectValue(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
            provider: "fixture"
        )
    }

    private func makeImage(
        width: Int,
        height: Int,
        fill: TestRGBA,
        highlight: CGRect? = nil,
        highlightColor: TestRGBA? = nil
    ) throws -> CGImage {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let color = highlight?.contains(point) == true ? (highlightColor ?? fill) : fill
                let offset = (y * width + x) * 4
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                bytes[offset + 3] = color.alpha
            }
        }
        var image: CGImage?

        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
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
                return
            }
            image = context.makeImage()
        }

        return try #require(image)
    }

    private func makeNoisyPixelImage() throws -> CGImage {
        let width = 30
        let height = 30
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let isSampleRegion = x >= 14 && x <= 16 && y >= 14 && y <= 16
                let isNoisyCenter = x == 15 && y == 15
                let color: TestRGBA = isSampleRegion && !isNoisyCenter ? .green : .black
                let offset = (y * width + x) * 4
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                bytes[offset + 3] = color.alpha
            }
        }
        var image: CGImage?

        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
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
                return
            }
            image = context.makeImage()
        }

        return try #require(image)
    }

    private func pixelColor(in image: CGImage, x: Int, y: Int) throws -> TestRGBA {
        let bytesPerRow = image.width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(didDraw)
        let offset = (y * image.width + x) * 4
        return TestRGBA(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }
}

private struct TestRGBA: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8 = 255

    static let black = TestRGBA(red: 0, green: 0, blue: 0)
    static let red = TestRGBA(red: 255, green: 0, blue: 0)
    static let green = TestRGBA(red: 0, green: 255, blue: 0)
    static let blue = TestRGBA(red: 0, green: 0, blue: 255)

    var cgColor: CGColor {
        CGColor(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: CGFloat(alpha) / 255.0
        )
    }

    func isClose(to other: TestRGBA, tolerance: UInt8 = 2) -> Bool {
        abs(Int(red) - Int(other.red)) <= Int(tolerance)
            && abs(Int(green) - Int(other.green)) <= Int(tolerance)
            && abs(Int(blue) - Int(other.blue)) <= Int(tolerance)
            && abs(Int(alpha) - Int(other.alpha)) <= Int(tolerance)
    }
}

private actor PollingDetectorLog {
    private var recordedIDs: [UUID] = []

    var ids: [UUID] {
        recordedIDs
    }

    func record(_ id: UUID) {
        recordedIDs.append(id)
    }
}

private actor PollingSleepLog {
    private var recordedIntervals: [TimeInterval] = []

    var intervals: [TimeInterval] {
        recordedIntervals
    }

    func record(_ interval: TimeInterval) {
        recordedIntervals.append(interval)
    }
}
