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
}
