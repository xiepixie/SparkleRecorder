import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Projection Tests")
struct SemanticRecordingReviewProjectionTests {
    @Test("Checkout fixture opens a review timeline with before and after frames")
    func checkoutFixtureOpensReviewTimelineWithBeforeAndAfterFrames() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        )

        #expect(projection.recordingID == SemanticRecordingFixture.recordingID)
        #expect(projection.title == "Checkout flow")
        #expect(projection.hasVideo)
        #expect(projection.summary.frameCount == 3)
        #expect(projection.summary.eventCount == 3)
        #expect(projection.summary.observationCount == 2)
        #expect(projection.frameStrip.map(\.id) == [
            SemanticRecordingFixture.startFrameID,
            SemanticRecordingFixture.beforeClickFrameID,
            SemanticRecordingFixture.afterClickFrameID
        ])

        let clickRow = try #require(
            projection.timelineRows.first { $0.id == SemanticRecordingFixture.clickEventID }
        )
        #expect(clickRow.primaryFrameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(clickRow.beforeFrameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(clickRow.afterFrameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(clickRow.evidenceFrameIDs.contains(SemanticRecordingFixture.beforeClickFrameID))
        #expect(clickRow.evidenceFrameIDs.contains(SemanticRecordingFixture.afterClickFrameID))
        #expect(clickRow.sourcePreviewCount == 2)
        #expect(clickRow.suggestionCount == 1)

        #expect(projection.selectedEvent?.id == SemanticRecordingFixture.clickEventID)
        #expect(projection.selectedFrame?.id == SemanticRecordingFixture.beforeClickFrameID)
        #expect(projection.selectedFrame?.sourcePreviews.map(\.id) == [
            SemanticRecordingFixture.sourceTemplateRefID
        ])
        #expect(projection.selectedFrame?.conditionCandidates.map(\.kind) == [
            .imageAppeared,
            .imageDisappeared
        ])
    }

    @Test("Selected wait frame exposes OCR overlay and source runtime comparison")
    func selectedWaitFrameExposesOCROverlayAndSourceRuntimeComparison() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: SemanticRecordingFixture.checkoutSuggestions(bundle: bundle),
            selectedEventID: SemanticRecordingFixture.waitEventID
        )

        let selectedFrame = try #require(projection.selectedFrame)
        #expect(selectedFrame.id == SemanticRecordingFixture.afterClickFrameID)
        #expect(selectedFrame.imageRefPath == "frames/000016-after-click.png")
        #expect(selectedFrame.overlays.map(\.id) == [SemanticRecordingFixture.ocrObservationID])
        #expect(selectedFrame.overlays.first?.title == "Order confirmed")
        #expect(selectedFrame.sourcePreviews.map(\.id) == [SemanticRecordingFixture.sourceOCRRefID])
        #expect(selectedFrame.conditionCandidates.map(\.kind) == [.ocrWait])
        #expect(selectedFrame.conditionCandidates.first?.artifactPath == "visual-index/ocr/confirmation-region.png")

        let comparison = try #require(selectedFrame.comparisonRows.first)
        #expect(comparison.id == SemanticRecordingFixture.comparisonID)
        #expect(comparison.sourcePreviewRefID == SemanticRecordingFixture.sourceOCRRefID)
        #expect(comparison.runtimeSampleRefID == SemanticRecordingFixture.runtimeSampleID)
        #expect(comparison.sourceArtifactPath == "visual-index/ocr/confirmation-region.png")
        #expect(comparison.runtimeArtifactPath == "runs/run-001/condition-confirmation/watched-region.png")
        #expect(comparison.diffArtifactPath == "runs/run-001/condition-confirmation/diff.png")
        #expect(comparison.outcome == .matched)
        #expect(comparison.score == 0.96)
        #expect(comparison.threshold == 0.90)
    }

    @Test("Review projection prefers redacted frame refs while preserving source frame refs")
    func reviewProjectionPrefersRedactedFrameRefs() throws {
        var bundle = SemanticRecordingFixture.checkoutBundle()
        bundle.redactedFrames = [
            SemanticRecordingRenderedFrameRedaction(
                frameID: SemanticRecordingFixture.afterClickFrameID,
                sourceImageRef: try RecordingArtifactRef("frames/000016-after-click.png"),
                redactedImageRef: try RecordingArtifactRef("redacted/frames/after-click.png"),
                renderedMaskCount: 1,
                sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID]
            )
        ]

        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )

        let selectedFrame = try #require(projection.selectedFrame)
        #expect(selectedFrame.id == SemanticRecordingFixture.afterClickFrameID)
        #expect(selectedFrame.imageRefPath == "redacted/frames/after-click.png")
        #expect(selectedFrame.sourceImageRefPath == "frames/000016-after-click.png")
        #expect(selectedFrame.redactedImageRefPath == "redacted/frames/after-click.png")
        #expect(selectedFrame.isRedacted)

        let stripItem = try #require(
            projection.frameStrip.first { $0.id == SemanticRecordingFixture.afterClickFrameID }
        )
        #expect(stripItem.imageRefPath == "redacted/frames/after-click.png")
        #expect(stripItem.sourceImageRefPath == "frames/000016-after-click.png")
        #expect(stripItem.redactedImageRefPath == "redacted/frames/after-click.png")
        #expect(stripItem.isRedacted)
    }

    @Test("Suggestions remain review-only and cite evidence")
    func suggestionsRemainReviewOnlyAndCiteEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: SemanticRecordingFixture.checkoutSuggestions(bundle: bundle),
            selectedEventID: SemanticRecordingFixture.waitEventID
        )

        let suggestion = try #require(projection.suggestionRows.first)
        #expect(suggestion.kind == .conditionCandidate)
        #expect(suggestion.confidence == 0.86)
        #expect(suggestion.risk?.contains("user review") == true)
        #expect(suggestion.mutationPolicy == "Review required; no workflow mutation until accepted.")

        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(evidence.eventIDs == [
            SemanticRecordingFixture.clickEventID,
            SemanticRecordingFixture.waitEventID
        ])
        #expect(evidence.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(evidence.artifactPath == "visual-index/ocr/confirmation-region.png")
    }

    @Test("OCR condition candidate creates a draft patch for an existing task")
    func ocrConditionCandidateCreatesDraftPatchForExistingTask() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )
        let candidate = try #require(projection.selectedFrame?.conditionCandidates.first)
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                targetTaskKey: "wait_confirmation"
            )
        )

        #expect(result.patch.ops.map(\.op) == ["upsertVisualRegion", "setCondition"])
        #expect(result.taskKey == "wait_confirmation")
        #expect(result.appliesToExistingTask)
        #expect(result.condition.type == "ocrText")
        #expect(result.condition.text == "Order confirmed")
        #expect(result.condition.matchMode == .contains)
        #expect(result.condition.regionRef == "sr_00000001_order_confirmed_0000000e_region")
        #expect(result.region?.bounds == RectValue(x: 700, y: 210, width: 260, height: 42))
        #expect(result.region?.space == .windowLocal)

        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Checkout",
            tasks: [
                AutomationWorkflowDraftTask(key: "wait_confirmation", type: "delay", delaySeconds: 1)
            ]
        ))
        let patched = try AutomationWorkflowDraftPatchApplier.apply(result.patch, to: document)
        let task = try #require(patched.document.workflow.tasks.first)
        let region = try #require(result.region)

        #expect(patched.validation.isValid)
        #expect(patched.changedTaskKeys == ["wait_confirmation"])
        #expect(task.type == "condition")
        #expect(task.condition == result.condition)
        #expect(task.timeoutSeconds == 15)
        #expect(task.pollingSeconds == 0.25)
        #expect(patched.document.visualAssets?.regions == [region])
    }

    @Test("Image template candidate creates a visual asset backed condition task")
    func imageTemplateCandidateCreatesVisualAssetBackedConditionTask() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .imageAppeared }
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                newTaskKey: "wait_checkout_button",
                threshold: 0.88
            )
        )

        #expect(result.patch.ops.map(\.op) == ["upsertVisualRegion", "upsertVisualImage", "addTask"])
        #expect(result.condition.type == "imageAppeared")
        #expect(result.condition.imageRef == "sr_00000001_checkout_button_0000000f_template")
        #expect(result.condition.threshold == 0.88)
        #expect(result.imageAsset?.path == "visual-index/templates/checkout-button.png")
        #expect(result.imageAsset?.sha256 == "fixture-template-digest")
        #expect(result.imageAsset?.sourceFrameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(result.imageAsset?.sourceArtifactPath == "frames/000014-before-click.png")
        #expect(result.imageAsset?.sourceBounds == RectValue(x: 880, y: 620, width: 180, height: 48))
        #expect(result.imageAsset?.sourceBoundsSpace == .windowLocal)
        #expect(result.assetExtractions.isEmpty)

        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(name: "Checkout"))
        let patched = try AutomationWorkflowDraftPatchApplier.apply(result.patch, to: document)
        let task = try #require(patched.document.workflow.tasks.first)
        let region = try #require(result.region)
        let imageAsset = try #require(result.imageAsset)

        #expect(patched.validation.isValid)
        #expect(task.key == "wait_checkout_button")
        #expect(task.type == "condition")
        #expect(task.condition == result.condition)
        #expect(patched.document.visualAssets?.regions == [region])
        #expect(patched.document.visualAssets?.images == [imageAsset])
    }

    @Test("Review visual assets materialize into package local patch paths")
    func reviewVisualAssetsMaterializeIntoPackageLocalPatchPaths() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .imageAppeared }
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(candidate: candidate)
        )
        let templateData = Data("template-data".utf8)
        var writtenAssets: [String: Data] = [:]

        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: result.patch,
            readArtifact: { sourcePath in
                #expect(sourcePath == "visual-index/templates/checkout-button.png")
                return templateData
            },
            writeAsset: { data, destinationPath in
                writtenAssets[destinationPath] = data
            }
        )

        let imageOperation = try #require(
            materialized.patch.ops.first { $0.op == "upsertVisualImage" }
        )
        let imageAsset = try #require(imageOperation.visualImage)
        let copiedAsset = try #require(materialized.copiedAssets.first)
        let expectedPath = "assets/images/sr_00000001_checkout_button_0000000f_template.png"
        let expectedDigest = "20dc26ad587152ac3f284bd839b19944cb945d680f3220334697b5aa0f455f13"

        #expect(materialized.copiedAssets.count == 1)
        #expect(copiedAsset.kind == .image)
        #expect(copiedAsset.sourcePath == "visual-index/templates/checkout-button.png")
        #expect(copiedAsset.destinationPath == expectedPath)
        #expect(copiedAsset.sha256 == expectedDigest)
        #expect(imageAsset.path == expectedPath)
        #expect(imageAsset.sha256 == expectedDigest)
        #expect(writtenAssets[expectedPath] == templateData)
    }

    @Test("Manual image region selection materializes from the selected frame crop")
    func manualImageRegionSelectionMaterializesFromSelectedFrameCrop() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .imageAppeared }
        )
        let selection = SemanticRecordingFrameRegionSelection(
            frameID: SemanticRecordingFixture.beforeClickFrameID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: RecordingBounds(
                rect: RecordingRect(x: 20, y: 30, width: 80, height: 50),
                coordinateSpace: .framePixels
            ),
            imageSize: RecordingImageSize(width: 1_440, height: 900),
            label: "Manual button crop",
            candidateKind: .imageAppeared,
            sourcePreviewRefID: candidate.sourcePreviewRefID,
            observationID: candidate.observationID,
            artifactPath: candidate.artifactPath
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                regionSelection: selection
            )
        )
        let extraction = try #require(result.assetExtractions.first)
        let frameData = Data("frame-image".utf8)
        let croppedData = Data("cropped-template".utf8)
        var preparedExtraction: SemanticRecordingReviewAssetExtraction?
        var writtenAssets: [String: Data] = [:]

        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: result.patch,
            assetExtractions: result.assetExtractions,
            readArtifact: { sourcePath in
                #expect(sourcePath == "frames/000014-before-click.png")
                return frameData
            },
            prepareAssetData: { data, extraction in
                #expect(data == frameData)
                preparedExtraction = extraction
                return croppedData
            },
            writeAsset: { data, destinationPath in
                writtenAssets[destinationPath] = data
            }
        )

        let imageOperation = try #require(
            materialized.patch.ops.first { $0.op == "upsertVisualImage" }
        )
        let imageAsset = try #require(imageOperation.visualImage)
        let expectedPath = "assets/images/sr_00000001_checkout_button_0000000f_template.png"
        let expectedDigest = "758ae8687d52e2f871be2752f1b9c7ba97f9a3651a7f3be8768d0ee96ca4293f"

        #expect(result.imageAsset?.sourceBounds == RectValue(x: 20, y: 30, width: 80, height: 50))
        #expect(result.imageAsset?.sourceBoundsSpace == .displayAbsolute)
        #expect(extraction.kind == .image)
        #expect(extraction.sourceFrameImagePath == "frames/000014-before-click.png")
        #expect(extraction.bounds == selection.bounds)
        #expect(preparedExtraction == extraction)
        #expect(imageAsset.path == expectedPath)
        #expect(imageAsset.sha256 == expectedDigest)
        #expect(writtenAssets[expectedPath] == croppedData)
    }

    @Test("Manual frame region selection can override candidate bounds")
    func manualFrameRegionSelectionCanOverrideCandidateBounds() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )
        let candidate = try #require(projection.selectedFrame?.conditionCandidates.first)
        let selection = SemanticRecordingFrameRegionSelection(
            frameID: SemanticRecordingFixture.afterClickFrameID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: RecordingBounds(
                rect: RecordingRect(x: 10, y: 20, width: 100, height: 40),
                coordinateSpace: .displayPixels
            ),
            imageSize: RecordingImageSize(width: 1_440, height: 900),
            label: "Custom confirmation area",
            candidateKind: .ocrWait,
            sourcePreviewRefID: SemanticRecordingFixture.sourceOCRRefID
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                newTaskKey: "wait_custom_confirmation",
                regionSelection: selection,
                text: "Ready"
            )
        )

        #expect(result.patch.ops.map(\.op) == ["upsertVisualRegion", "addTask"])
        #expect(result.condition.text == "Ready")
        #expect(result.region?.bounds == RectValue(x: 10, y: 20, width: 100, height: 40))
        #expect(result.region?.space == .displayAbsolute)
        #expect(result.region?.label == "Custom confirmation area")
    }

    @Test("Pixel condition candidate can use user-picked color without metadata")
    func pixelConditionCandidateCanUseUserPickedColorWithoutMetadata() throws {
        let pixelSourceID = UUID(uuidString: "74000000-0000-0000-0000-000000000020")!
        let pixelObservationID = UUID(uuidString: "74000000-0000-0000-0000-000000000021")!
        let pixelBounds = RecordingBounds(
            rect: RecordingRect(x: 1_024, y: 246, width: 1, height: 1),
            coordinateSpace: .windowPixels
        )
        var bundle = SemanticRecordingFixture.checkoutBundle()
        bundle.sourcePreviews.append(RecordingSourcePreviewReference(
            id: pixelSourceID,
            kind: .pixelSample,
            recordingID: bundle.id,
            frameID: SemanticRecordingFixture.afterClickFrameID,
            eventID: SemanticRecordingFixture.waitEventID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: pixelBounds,
            imageSize: RecordingImageSize(width: 1, height: 1),
            createdAt: bundle.createdAt,
            recordingTime: 2.45,
            label: "Ready status pixel"
        ))
        bundle.visualObservations.append(RecordingVisualObservation(
            id: pixelObservationID,
            kind: .pixelSample,
            recordingTime: 2.45,
            frameID: SemanticRecordingFixture.afterClickFrameID,
            sourcePreviewRefID: pixelSourceID,
            bounds: pixelBounds,
            confidence: 0.94,
            score: 0.94,
            provider: "SparkleRecorder.fixture",
            providerVersion: "0.1",
            labels: ["readyStatus"],
            createdAt: bundle.createdAt
        ))

        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .pixelMatched }
        )

        #expect(throws: SemanticRecordingReviewDraftPatchError.missingPixelColor(candidate.id)) {
            try SemanticRecordingReviewDraftPatchBuilder.makePatch(
                bundle: bundle,
                request: SemanticRecordingReviewDraftPatchRequest(candidate: candidate)
            )
        }

        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                threshold: 0.93,
                pixelColorHex: "#2BC66A"
            )
        )

        #expect(result.patch.ops.map { $0.op } == ["upsertVisualRegion", "addTask"])
        #expect(result.condition.type == "pixelMatched")
        #expect(result.condition.colorHex == "#2BC66A")
        #expect(result.condition.threshold == 0.93)
        #expect(result.condition.regionRef == "sr_00000001_ready_status_pixel_00000020_region")
        #expect(result.region?.bounds == RectValue(x: 1_024, y: 246, width: 1, height: 1))
        #expect(result.region?.space == .windowLocal)

        let patched = try AutomationWorkflowDraftPatchApplier.apply(
            result.patch,
            to: AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(name: "Checkout"))
        )
        let task = try #require(patched.document.workflow.tasks.first)
        let region = try #require(result.region)
        let regions = try #require(patched.document.visualAssets?.regions)

        #expect(patched.validation.isValid)
        #expect(task.type == "condition")
        #expect(task.condition == result.condition)
        #expect(regions == [region])
    }

    @Test("Run target selects exact failed recorded event when available")
    func runTargetSelectsExactFailedRecordedEventWhenAvailable() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let run = AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            outcome: .failed(report: RunReport(
                runID: UUID(),
                startTime: bundle.createdAt,
                duration: 4,
                isSuccess: false,
                failedEventIndex: 4,
                errorMessage: "Click target moved"
            ))
        )

        let target = SemanticRecordingReviewRunTarget.make(run: run, bundle: bundle)

        #expect(target.selectedEventID == SemanticRecordingFixture.clickEventID)
        #expect(target.selectedFrameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(target.reason == .failedRecordedEventIndex(4))
    }

    @Test("Run target falls back to nearest recorded event when failed index is not present")
    func runTargetFallsBackToNearestRecordedEventWhenFailedIndexIsNotPresent() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let run = AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            outcome: .failed(report: RunReport(
                runID: UUID(),
                startTime: bundle.createdAt,
                duration: 4,
                isSuccess: false,
                failedEventIndex: 2,
                errorMessage: "Fixture macro report used an older event index"
            ))
        )

        let target = SemanticRecordingReviewRunTarget.make(run: run, bundle: bundle)

        #expect(target.selectedEventID == SemanticRecordingFixture.clickEventID)
        #expect(target.selectedFrameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(target.reason == .nearestRecordedEventIndex(requested: 2, matched: 4))
    }

    @Test("Run target sends timeout outcomes to condition candidate evidence")
    func runTargetSendsTimeoutOutcomesToConditionCandidateEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let run = AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            outcome: .timedOut(deadline: nil)
        )

        let target = SemanticRecordingReviewRunTarget.make(run: run, bundle: bundle)

        #expect(target.selectedEventID == SemanticRecordingFixture.waitEventID)
        #expect(target.selectedFrameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(target.reason == SemanticRecordingReviewRunTarget.Reason.conditionCandidate)
    }

    @Test("Run target presentation explains failed event targeting")
    func runTargetPresentationExplainsFailedEventTargeting() {
        let presentation = SemanticRecordingReviewRunTargetPresentation.make(
            target: SemanticRecordingReviewRunTarget(
                selectedEventID: nil,
                selectedFrameID: nil,
                reason: .failedRecordedEventIndex(2)
            )
        )

        #expect(presentation.title == "Review starts at failed event")
        #expect(presentation.detail == "Run Detail opened the recorded event reported by playback failure evidence.")
        #expect(presentation.badges == [
            .init(title: "Target", value: "Event #3"),
            .init(title: "Evidence", value: "Failure report")
        ])
    }

    @Test("Run target presentation explains nearest event fallback")
    func runTargetPresentationExplainsNearestEventFallback() {
        let presentation = SemanticRecordingReviewRunTargetPresentation.make(
            target: SemanticRecordingReviewRunTarget(
                selectedEventID: nil,
                selectedFrameID: nil,
                reason: .nearestRecordedEventIndex(requested: 8, matched: 2)
            )
        )

        #expect(presentation.title == "Review starts near failed event")
        #expect(presentation.detail.contains("not present in this bundle"))
        #expect(presentation.badges == [
            .init(title: "Requested", value: "Event #9"),
            .init(title: "Matched", value: "Event #3"),
            .init(title: "Evidence", value: "Nearest event")
        ])
    }

    @Test("Run target presentation explains condition targeting")
    func runTargetPresentationExplainsConditionTargeting() {
        let presentation = SemanticRecordingReviewRunTargetPresentation.make(
            target: SemanticRecordingReviewRunTarget(
                selectedEventID: nil,
                selectedFrameID: nil,
                reason: .conditionCandidate
            )
        )

        #expect(presentation.title == "Review starts at condition evidence")
        #expect(presentation.badges == [
            .init(title: "Target", value: "Condition"),
            .init(title: "Evidence", value: "Run outcome")
        ])
    }

    @Test("Run target evidence is codable provenance, not a mutation action")
    func runTargetEvidenceIsCodableProvenanceNotMutationAction() throws {
        let target = SemanticRecordingReviewRunTarget(
            selectedEventID: SemanticRecordingFixture.clickEventID,
            selectedFrameID: SemanticRecordingFixture.beforeClickFrameID,
            reason: .failedRecordedEventIndex(4)
        )
        let evidence = SemanticRecordingReviewRunTargetEvidence.make(target: target)
        let presentation = SemanticRecordingReviewRunTargetPresentation.make(target: target)

        #expect(evidence.provenanceName.rawValue == "semanticReview.runTarget")
        #expect(evidence.title == presentation.title)
        #expect(evidence.detail == presentation.detail)
        #expect(evidence.reason == .failedRecordedEventIndex)
        #expect(evidence.selectedEventID == SemanticRecordingFixture.clickEventID)
        #expect(evidence.selectedFrameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(evidence.requestedRecordedEventIndex == 4)
        #expect(evidence.matchedRecordedEventIndex == 4)
        #expect(evidence.boundary == .provenanceOnly)
        #expect(!evidence.createsDraftPatch)
        #expect(!evidence.mutatesWorkflow)
        #expect(evidence.rows.contains {
            $0.kind == .provenance && $0.value == "semanticReview.runTarget"
        })
        #expect(evidence.rows.contains {
            $0.kind == .boundary && $0.value == "provenanceOnly"
        })
        #expect(evidence.rows.contains {
            $0.kind == .effect && $0.value == "No workflow mutation"
        })

        let encoded = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingReviewRunTargetEvidence.self,
            from: encoded
        )

        #expect(decoded == evidence)
    }

    @Test("Run target evidence preserves nearest fallback indexes")
    func runTargetEvidencePreservesNearestFallbackIndexes() {
        let evidence = SemanticRecordingReviewRunTargetEvidence.make(
            target: SemanticRecordingReviewRunTarget(
                selectedEventID: SemanticRecordingFixture.clickEventID,
                selectedFrameID: SemanticRecordingFixture.beforeClickFrameID,
                reason: .nearestRecordedEventIndex(requested: 8, matched: 4)
            )
        )

        #expect(evidence.reason == .nearestRecordedEventIndex)
        #expect(evidence.requestedRecordedEventIndex == 8)
        #expect(evidence.matchedRecordedEventIndex == 4)
        #expect(evidence.rows.contains {
            $0.kind == .requestedEventIndex && $0.value == "Event #9"
        })
        #expect(evidence.rows.contains {
            $0.kind == .matchedEventIndex && $0.value == "Event #5"
        })
    }
}
