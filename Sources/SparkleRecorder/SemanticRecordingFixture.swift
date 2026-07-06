import Foundation

public enum SemanticRecordingFixture {
    public static let recordingID = fixedUUID("74000000-0000-0000-0000-000000000001")
    public static let videoSegmentID = fixedUUID("74000000-0000-0000-0000-000000000002")
    public static let startFrameID = fixedUUID("74000000-0000-0000-0000-000000000003")
    public static let beforeClickFrameID = fixedUUID("74000000-0000-0000-0000-000000000004")
    public static let afterClickFrameID = fixedUUID("74000000-0000-0000-0000-000000000005")
    public static let openEventID = fixedUUID("74000000-0000-0000-0000-000000000006")
    public static let clickEventID = fixedUUID("74000000-0000-0000-0000-000000000007")
    public static let waitEventID = fixedUUID("74000000-0000-0000-0000-000000000008")
    public static let summaryEventID = fixedUUID("74000000-0000-0000-0000-000000000009")
    public static let clickSemanticEventID = fixedUUID("74000000-0000-0000-0000-00000000000a")
    public static let conditionSemanticEventID = fixedUUID("74000000-0000-0000-0000-00000000000b")
    public static let ocrObservationID = fixedUUID("74000000-0000-0000-0000-00000000000c")
    public static let templateObservationID = fixedUUID("74000000-0000-0000-0000-00000000000d")
    public static let sourceOCRRefID = fixedUUID("74000000-0000-0000-0000-00000000000e")
    public static let sourceTemplateRefID = fixedUUID("74000000-0000-0000-0000-00000000000f")
    public static let runtimeSampleID = fixedUUID("74000000-0000-0000-0000-000000000010")
    public static let comparisonID = fixedUUID("74000000-0000-0000-0000-000000000011")
    public static let suppressionID = fixedUUID("74000000-0000-0000-0000-000000000012")
    public static let queryResultID = fixedUUID("74000000-0000-0000-0000-000000000013")
    public static let suggestionID = fixedUUID("74000000-0000-0000-0000-000000000014")
    public static let runID = fixedUUID("74000000-0000-0000-0000-000000000015")
    public static let taskID = fixedUUID("74000000-0000-0000-0000-000000000016")
    public static let conditionID = fixedUUID("74000000-0000-0000-0000-000000000017")

    public static let surfaceID = "checkout-window"

    public static func checkoutBundle(
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> SemanticRecordingBundle {
        let captureTarget = RecordingCaptureTarget(
            kind: .window,
            surfaceID: surfaceID,
            displayID: 1,
            windowID: 42,
            appBundleIdentifier: "com.example.Checkout",
            appName: "Checkout Demo",
            windowTitle: "Checkout"
        )
        let frameSize = RecordingImageSize(width: 1_440, height: 900)
        let checkoutButtonBounds = RecordingBounds(
            rect: RecordingRect(x: 880, y: 620, width: 180, height: 48),
            coordinateSpace: .windowPixels
        )
        let confirmationTextBounds = RecordingBounds(
            rect: RecordingRect(x: 700, y: 210, width: 260, height: 42),
            coordinateSpace: .windowPixels
        )

        let videoSegment = RecordingVideoSegment(
            id: videoSegmentID,
            artifactRef: artifactRef("video/recording.mov"),
            startTime: 0,
            duration: 7.5,
            target: captureTarget,
            fileType: "mov",
            codec: "SCRecordingOutput",
            frameSize: frameSize
        )

        let frames = [
            RecordingFrameReference(
                id: startFrameID,
                recordingTime: 0.2,
                videoSegmentID: videoSegmentID,
                videoTime: 0.2,
                imageRef: artifactRef("frames/000001-start.png"),
                imageSize: frameSize,
                source: .recordingStart,
                surfaceID: surfaceID,
                displayScale: 2.0,
                relatedEventIDs: [openEventID]
            ),
            RecordingFrameReference(
                id: beforeClickFrameID,
                recordingTime: 2.1,
                videoSegmentID: videoSegmentID,
                videoTime: 2.1,
                imageRef: artifactRef("frames/000014-before-click.png"),
                imageSize: frameSize,
                source: .mouseDown,
                surfaceID: surfaceID,
                windowBounds: checkoutButtonBounds,
                displayScale: 2.0,
                relatedEventIDs: [clickEventID]
            ),
            RecordingFrameReference(
                id: afterClickFrameID,
                recordingTime: 2.45,
                videoSegmentID: videoSegmentID,
                videoTime: 2.45,
                imageRef: artifactRef("frames/000016-after-click.png"),
                imageSize: frameSize,
                source: .mouseUp,
                surfaceID: surfaceID,
                windowBounds: confirmationTextBounds,
                displayScale: 2.0,
                relatedEventIDs: [clickEventID, waitEventID]
            )
        ]

        let timelineEvents = [
            RecordingTimelineEvent(
                id: openEventID,
                recordingTime: 0.2,
                kind: .focusChange,
                frameID: startFrameID,
                videoSegmentID: videoSegmentID,
                surfaceID: surfaceID,
                summary: "Checkout window became active"
            ),
            RecordingTimelineEvent(
                id: clickEventID,
                recordingTime: 2.3,
                kind: .recordedEvent,
                frameID: beforeClickFrameID,
                videoSegmentID: videoSegmentID,
                recordedEventIndex: 4,
                surfaceID: surfaceID,
                summary: "Clicked the checkout button"
            ),
            RecordingTimelineEvent(
                id: waitEventID,
                recordingTime: 3.1,
                kind: .waitEnd,
                frameID: afterClickFrameID,
                videoSegmentID: videoSegmentID,
                surfaceID: surfaceID,
                summary: "Confirmation text appeared",
                relatedEventIDs: [clickEventID]
            )
        ]

        let sourcePreviews = [
            RecordingSourcePreviewReference(
                id: sourceTemplateRefID,
                kind: .imageTemplate,
                recordingID: recordingID,
                frameID: beforeClickFrameID,
                eventID: clickEventID,
                surfaceID: surfaceID,
                artifactRef: artifactRef("visual-index/templates/checkout-button.png"),
                bounds: checkoutButtonBounds,
                imageSize: RecordingImageSize(width: 180, height: 48),
                createdAt: createdAt,
                recordingTime: 2.1,
                contentDigest: RecordingContentDigest(algorithm: "sha256", value: "fixture-template-digest"),
                label: "Checkout button"
            ),
            RecordingSourcePreviewReference(
                id: sourceOCRRefID,
                kind: .ocrRegion,
                recordingID: recordingID,
                frameID: afterClickFrameID,
                eventID: waitEventID,
                surfaceID: surfaceID,
                artifactRef: artifactRef("visual-index/ocr/confirmation-region.png"),
                bounds: confirmationTextBounds,
                imageSize: RecordingImageSize(width: 260, height: 42),
                createdAt: createdAt,
                recordingTime: 2.45,
                contentDigest: RecordingContentDigest(algorithm: "sha256", value: "fixture-ocr-region-digest"),
                label: "Confirmation text"
            )
        ]

        let visualObservations = [
            RecordingVisualObservation(
                id: templateObservationID,
                kind: .imageTemplateCandidate,
                recordingTime: 2.1,
                frameID: beforeClickFrameID,
                sourcePreviewRefID: sourceTemplateRefID,
                artifactRef: artifactRef("visual-index/templates/checkout-button.png"),
                bounds: checkoutButtonBounds,
                confidence: 0.92,
                score: 0.91,
                provider: "SparkleRecorder.fixture",
                providerVersion: "0.1",
                labels: ["button", "primaryAction"],
                createdAt: createdAt
            ),
            RecordingVisualObservation(
                id: ocrObservationID,
                kind: .ocrText,
                recordingTime: 2.45,
                frameID: afterClickFrameID,
                sourcePreviewRefID: sourceOCRRefID,
                artifactRef: artifactRef("visual-index/ocr/confirmation-region.png"),
                bounds: confirmationTextBounds,
                text: "Order confirmed",
                confidence: 0.97,
                provider: "Vision.fixture",
                providerVersion: "0.1",
                labels: ["confirmation"],
                createdAt: createdAt
            )
        ]

        let semanticEvents = [
            RecordingSemanticEvent(
                id: summaryEventID,
                recordingTime: 0.2,
                kind: .summary,
                frameID: startFrameID,
                title: "Checkout flow",
                summary: "Open the checkout window, click Checkout, and wait for confirmation.",
                evidenceFrameIDs: [startFrameID, beforeClickFrameID, afterClickFrameID],
                observationIDs: [templateObservationID, ocrObservationID]
            ),
            RecordingSemanticEvent(
                id: clickSemanticEventID,
                recordingTime: 2.3,
                kind: .click,
                frameID: beforeClickFrameID,
                timelineEventID: clickEventID,
                title: "Click Checkout",
                summary: "The user clicked the primary checkout button.",
                evidenceFrameIDs: [beforeClickFrameID, afterClickFrameID],
                observationIDs: [templateObservationID],
                risk: "Coordinate click should become an image or AX locator before reuse."
            ),
            RecordingSemanticEvent(
                id: conditionSemanticEventID,
                recordingTime: 3.1,
                kind: .conditionCandidate,
                frameID: afterClickFrameID,
                timelineEventID: waitEventID,
                title: "Wait for confirmation text",
                summary: "The wait can become an OCR condition for 'Order confirmed'.",
                evidenceFrameIDs: [afterClickFrameID],
                observationIDs: [ocrObservationID]
            )
        ]

        let runtimeSample = RecordingRuntimeSampleReference(
            id: runtimeSampleID,
            kind: .watchedRegionCrop,
            runID: runID,
            taskID: taskID,
            conditionID: conditionID,
            artifactRef: artifactRef("runs/run-001/condition-confirmation/watched-region.png"),
            capturedAt: createdAt.addingTimeInterval(90),
            bounds: confirmationTextBounds,
            imageSize: RecordingImageSize(width: 260, height: 42),
            contentDigest: RecordingContentDigest(algorithm: "sha256", value: "fixture-runtime-sample-digest")
        )

        let comparison = RecordingPreviewComparison(
            id: comparisonID,
            sourcePreviewRefID: sourceOCRRefID,
            runtimeSampleRefID: runtimeSampleID,
            outcome: .matched,
            score: 0.96,
            threshold: 0.90,
            matcher: RecordingMatcherDescriptor(
                kind: "ocr-text-exact",
                version: "0.1",
                provider: "SparkleRecorder.fixture"
            ),
            diffArtifactRef: artifactRef("runs/run-001/condition-confirmation/diff.png"),
            reason: "Runtime OCR matched the recorded confirmation text.",
            comparedAt: createdAt.addingTimeInterval(91)
        )

        let suppression = RecordingSuppressionRecord(
            id: suppressionID,
            reason: .passwordField,
            recordingTime: 1.2,
            timeRange: RecordingTimeRange(startTime: 1.1, duration: 0.4),
            target: captureTarget,
            frameID: startFrameID,
            eventID: openEventID,
            count: 1,
            detail: "A credential field was visible before the checkout click.",
            createdAt: createdAt
        )

        return SemanticRecordingBundle(
            id: recordingID,
            createdAt: createdAt,
            capturePolicy: RecordingCapturePolicy(mode: .videoAndKeyframes),
            captureTarget: captureTarget,
            videoSegments: [videoSegment],
            frames: frames,
            timelineEvents: timelineEvents,
            semanticEvents: semanticEvents,
            visualObservations: visualObservations,
            sourcePreviews: sourcePreviews,
            runtimeSamples: [runtimeSample],
            previewComparisons: [comparison],
            suppressions: [suppression]
        )
    }

    public static func checkoutQueryResults(
        bundle: SemanticRecordingBundle = checkoutBundle()
    ) -> [RecordingQueryResult] {
        [
            RecordingQueryResult(
                id: queryResultID,
                recordingID: bundle.id,
                kind: .ocrText,
                title: "Order confirmed",
                summary: "Confirmation text was observed after the checkout click.",
                score: 0.97,
                evidence: [
                    RecordingEvidenceReference(
                        frameID: afterClickFrameID,
                        eventIDs: [waitEventID],
                        observationIDs: [ocrObservationID],
                        artifactRef: artifactRef("frames/000016-after-click.png"),
                        bounds: RecordingBounds(
                            rect: RecordingRect(x: 700, y: 210, width: 260, height: 42),
                            coordinateSpace: .windowPixels
                        ),
                        summary: "OCR region contains 'Order confirmed'."
                    )
                ]
            )
        ]
    }

    public static func checkoutSuggestions(
        bundle: SemanticRecordingBundle = checkoutBundle()
    ) -> [RecordingSuggestion] {
        [
            RecordingSuggestion(
                id: suggestionID,
                recordingID: bundle.id,
                kind: .conditionCandidate,
                title: "Replace fixed wait with OCR confirmation",
                summary: "Use the recorded confirmation region as an OCR wait instead of replaying a fixed delay.",
                confidence: 0.86,
                risk: "Requires live Vision OCR and user review before importing into a workflow.",
                evidence: [
                    RecordingEvidenceReference(
                        frameID: afterClickFrameID,
                        eventIDs: [clickEventID, waitEventID],
                        observationIDs: [ocrObservationID],
                        artifactRef: artifactRef("visual-index/ocr/confirmation-region.png"),
                        bounds: RecordingBounds(
                            rect: RecordingRect(x: 700, y: 210, width: 260, height: 42),
                            coordinateSpace: .windowPixels
                        ),
                        summary: "Recorded text appeared after the checkout click."
                    )
                ]
            )
        ]
    }

    private static func artifactRef(_ path: String) -> RecordingArtifactRef {
        do {
            return try RecordingArtifactRef(path)
        } catch {
            preconditionFailure("Invalid semantic recording fixture artifact ref: \(path)")
        }
    }

    private static func fixedUUID(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid semantic recording fixture UUID: \(value)")
        }
        return uuid
    }
}
