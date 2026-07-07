import Foundation
import SparkleRecorderCore
import Testing

@Suite("Semantic Recording CLI Payload Tests")
struct SemanticRecordingCLITests {
    @Test("Recording show envelope summarizes fixture bundle with safe refs")
    func recordingShowEnvelopeSummarizesFixtureBundle() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload>
            .semanticRecordingShow(
                command: "recording.show",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout"
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.schema == AutomationCLIResultSchema.current)
        #expect(envelope.command == "recording.show")
        #expect(envelope.warnings.map(\.code) == ["fixtureMode"])
        #expect(payload.requestedRecordingID == "checkout-demo")
        #expect(payload.recordingID == SemanticRecordingFixture.recordingID)
        #expect(payload.fixtureMode)
        #expect(payload.fixture == "checkout")
        #expect(payload.captureTarget?.appName == "Checkout Demo")
        #expect(payload.captureTarget?.surfaceID == SemanticRecordingFixture.surfaceID)
        #expect(payload.videoAvailable)
        #expect(payload.keyframesAvailable)
        #expect(payload.videoSegmentCount == 1)
        #expect(payload.frameCount == 3)
        #expect(payload.aiSafeEventCount == 3)
        #expect(payload.ocrObservationCount == 1)
        #expect(payload.suppressionSummary.totalSuppressedCount == 1)
        #expect(payload.artifactAvailability.videoRefs.map(\.path) == ["video/recording.mov"])
        #expect(payload.artifactAvailability.redactedVideoRefs.isEmpty)
        #expect(payload.artifactAvailability.frameRefs.map(\.path).contains("frames/000016-after-click.png"))
        #expect(envelope.nextActions.contains { $0.command.contains("recording frames checkout-demo --fixture checkout --json") })
    }

    @Test("Recording explain envelope summarizes semantic events and local evidence")
    func recordingExplainEnvelopeSummarizesSemanticEventsAndLocalEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIExplainPayload>
            .semanticRecordingExplain(
                command: "recording.explain",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout"
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.command == "recording.explain")
        #expect(envelope.warnings.map(\.code) == ["fixtureMode"])
        #expect(payload.fixtureMode)
        #expect(payload.summary.aiSafeEventCount == 3)
        #expect(payload.keyPointCount == 3)
        #expect(payload.visualEvidenceCount == 2)
        #expect(payload.mutationPolicy.contains("read-only evidence"))

        let summaryPoint = try #require(
            payload.keyPoints.first { $0.kind == .summary }
        )
        #expect(summaryPoint.evidence.first?.frameID == SemanticRecordingFixture.startFrameID)
        #expect(summaryPoint.evidence.first?.artifactRef?.path == "frames/000001-start.png")
        #expect(summaryPoint.evidence.first?.observationIDs.isEmpty == true)

        let conditionPoint = try #require(
            payload.keyPoints.first { $0.kind == .conditionCandidate }
        )
        #expect(conditionPoint.id == SemanticRecordingFixture.conditionSemanticEventID)
        #expect(conditionPoint.title == "Wait for confirmation text")
        #expect(conditionPoint.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(conditionPoint.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(conditionPoint.evidence.first?.artifactRef?.path == "visual-index/ocr/confirmation-region.png")
        #expect(conditionPoint.evidence.first?.eventIDs == [
            SemanticRecordingFixture.waitEventID,
            SemanticRecordingFixture.clickEventID
        ])

        let ocrEvidence = try #require(
            payload.visualEvidence.first { $0.kind == .ocrText }
        )
        #expect(ocrEvidence.text == "Order confirmed")
        #expect(ocrEvidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(ocrEvidence.artifactRef?.path == "visual-index/ocr/confirmation-region.png")
        #expect(payload.evidenceNotes.contains { $0.contains("Suppressed evidence is present") })
        #expect(envelope.nextActions.contains {
            $0.command.contains("workflow draft from-recording checkout-demo --fixture checkout --json")
        })
    }

    @Test("Recording frames envelope returns frame ids, event ids, timing and artifact refs")
    func recordingFramesEnvelopeReturnsEvidenceRefs() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
            .semanticRecordingFrames(
                command: "recording.frames",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout"
            )

        let payload = try #require(envelope.data)
        #expect(payload.count == 3)
        #expect(payload.frames.map(\.id) == [
            SemanticRecordingFixture.startFrameID,
            SemanticRecordingFixture.beforeClickFrameID,
            SemanticRecordingFixture.afterClickFrameID
        ])

        let afterClick = try #require(
            payload.frames.first { $0.id == SemanticRecordingFixture.afterClickFrameID }
        )
        #expect(afterClick.recordingTime == 2.45)
        #expect(afterClick.videoTime == 2.45)
        #expect(afterClick.surfaceID == SemanticRecordingFixture.surfaceID)
        #expect(afterClick.relatedEventIDs == [
            SemanticRecordingFixture.clickEventID,
            SemanticRecordingFixture.waitEventID
        ])
        #expect(afterClick.imageRef.path == "frames/000016-after-click.png")
        #expect(afterClick.effectiveImageRef.path == "frames/000016-after-click.png")
        #expect(afterClick.redactedImageRef == nil)
        #expect(afterClick.observationIDs == [SemanticRecordingFixture.ocrObservationID])
    }

    @Test("Recording frame payload exposes redacted refs as effective refs without losing source refs")
    func recordingFramePayloadExposesRedactedRefs() throws {
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

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
            .semanticRecordingFrames(
                command: "recording.frames",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout"
            )

        let payload = try #require(envelope.data)
        let afterClick = try #require(
            payload.frames.first { $0.id == SemanticRecordingFixture.afterClickFrameID }
        )
        #expect(afterClick.imageRef.path == "frames/000016-after-click.png")
        #expect(afterClick.effectiveImageRef.path == "redacted/frames/after-click.png")
        #expect(afterClick.redactedImageRef?.path == "redacted/frames/after-click.png")
    }

    @Test("Recording frame show envelope reuses frame payload for one cited frame")
    func recordingFrameShowEnvelopeReturnsOneFrame() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let frame = try #require(
            bundle.frames.first { $0.id == SemanticRecordingFixture.beforeClickFrameID }
        )

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
            .semanticRecordingFrameShow(
                command: "recording.frame.show",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                frame: frame,
                fixture: "checkout"
            )

        let payload = try #require(envelope.data)
        #expect(envelope.command == "recording.frame.show")
        #expect(payload.count == 1)
        #expect(payload.frames.map(\.id) == [SemanticRecordingFixture.beforeClickFrameID])
        #expect(payload.frames.first?.imageRef.path == "frames/000014-before-click.png")
        #expect(envelope.nextActions.first?.command.contains("--time 2.1") == true)
    }

    @Test("Recording events-near envelope narrows timeline and related frames")
    func recordingEventsNearEnvelopeReturnsNearbyEventsAndFrames() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIEventsNearPayload>
            .semanticRecordingEventsNear(
                command: "recording.eventsNear",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout",
                time: 2.4,
                window: 0.25
            )

        let payload = try #require(envelope.data)
        #expect(payload.query.time == 2.4)
        #expect(payload.query.window == 0.25)
        #expect(payload.events.map(\.id) == [SemanticRecordingFixture.clickEventID])
        #expect(payload.events.first?.relatedFrameIDs == [
            SemanticRecordingFixture.beforeClickFrameID,
            SemanticRecordingFixture.afterClickFrameID
        ])
        #expect(payload.frames.map(\.id) == [
            SemanticRecordingFixture.beforeClickFrameID,
            SemanticRecordingFixture.afterClickFrameID
        ])
        #expect(payload.frames.map(\.imageRef.path) == [
            "frames/000014-before-click.png",
            "frames/000016-after-click.png"
        ])
    }

    @Test("Recording OCR search envelope returns deterministic observation evidence")
    func recordingOCRSearchEnvelopeReturnsObservationEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIOCRSearchPayload>
            .semanticRecordingOCRSearch(
                command: "recording.ocr.search",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout",
                text: "order",
                matchMode: .contains,
                queryResults: []
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.command == "recording.ocr.search")
        #expect(envelope.warnings.map(\.code) == ["fixtureMode"])
        #expect(payload.availability == .deterministicFixture)
        #expect(payload.query.text == "order")
        #expect(payload.query.matchMode == .contains)
        #expect(payload.unavailableReason == nil)
        #expect(payload.count == 1)

        let result = try #require(payload.results.first)
        #expect(result.observationID == SemanticRecordingFixture.ocrObservationID)
        #expect(result.queryResultIDs == [SemanticRecordingFixture.queryResultID])
        #expect(result.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(result.text == "Order confirmed")
        #expect(result.confidence == 0.97)
        #expect(result.score == 0.97)
        #expect(result.provider == "Vision.fixture")
        #expect(result.artifactRef?.path == "visual-index/ocr/confirmation-region.png")
        #expect(result.bounds?.rect.x == 700)
        #expect(result.bounds?.coordinateSpace == .windowPixels)

        let evidence = try #require(result.evidence.first)
        #expect(evidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(evidence.eventIDs == [SemanticRecordingFixture.waitEventID])
        #expect(evidence.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(evidence.artifactRef?.path == "frames/000016-after-click.png")
        #expect(envelope.nextActions.contains { $0.command.contains("recording suggest conditions checkout-demo --fixture checkout --json") })
    }

    @Test("Recording OCR search marks stored bundle reads as persisted search")
    func recordingOCRSearchMarksPersistedBundleSearch() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIOCRSearchPayload>
            .semanticRecordingOCRSearch(
                command: "recording.ocr.search",
                requestedRecordingID: bundle.id.uuidString,
                bundle: bundle,
                text: "order",
                matchMode: .contains
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.warnings.isEmpty)
        #expect(payload.fixtureMode == false)
        #expect(payload.availability == .persistedBundle)
        #expect(payload.unavailableReason == nil)
        #expect(payload.query.text == "order")
        #expect(payload.count == 1)
        #expect(payload.results.first?.observationID == SemanticRecordingFixture.ocrObservationID)
        #expect(payload.results.first?.queryResultIDs.isEmpty == true)
        #expect(payload.results.first?.evidence.first?.summary == "OCR observation matched the search text.")
    }

    @Test("Recording visual search envelope returns observation evidence")
    func recordingVisualSearchEnvelopeReturnsObservationEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIVisualSearchPayload>
            .semanticRecordingVisualSearch(
                command: "recording.visual.search",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout",
                kind: .imageTemplateCandidate,
                label: "button"
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.command == "recording.visual.search")
        #expect(envelope.warnings.map(\.code) == ["fixtureMode"])
        #expect(payload.query.kind == .imageTemplateCandidate)
        #expect(payload.query.label == "button")
        #expect(payload.count == 1)

        let result = try #require(payload.results.first)
        #expect(result.observationID == SemanticRecordingFixture.templateObservationID)
        #expect(result.kind == .imageTemplateCandidate)
        #expect(result.frameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(result.score == 0.91)
        #expect(result.labels == ["button", "primaryAction"])
        #expect(result.artifactRef?.path == "visual-index/templates/checkout-button.png")
        #expect(result.bounds?.rect.width == 180)

        let evidence = try #require(result.evidence.first)
        #expect(evidence.frameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(evidence.observationIDs == [SemanticRecordingFixture.templateObservationID])
        #expect(evidence.artifactRef?.path == "visual-index/templates/checkout-button.png")
        #expect(envelope.nextActions.contains { $0.command.contains("recording events-near checkout-demo") })
    }

    @Test("Recording asset extraction envelope returns draft-compatible visual asset refs")
    func recordingAssetExtractionEnvelopeReturnsDraftCompatibleVisualAssetRefs() throws {
        let sourceRef = try RecordingArtifactRef("frames/000014-before-click.png")
        let bounds = RecordingBounds(
            rect: RecordingRect(x: 20, y: 30, width: 80, height: 50),
            coordinateSpace: .framePixels
        )
        let query = SemanticRecordingCLIAssetExtractionQuery(
            frameID: SemanticRecordingFixture.beforeClickFrameID,
            region: bounds,
            kind: .imageTemplate,
            name: "Checkout Button",
            assetKey: "sr_74000000_checkout_button_template"
        )
        let materialized = SemanticRecordingReviewMaterializedAsset(
            kind: .image,
            key: query.assetKey,
            sourcePath: sourceRef.path,
            destinationPath: "assets/images/sr_74000000_checkout_button_template.png",
            sha256: "abc123"
        )
        let visualAsset = AutomationWorkflowDraftVisualImageAsset(
            key: query.assetKey,
            label: query.name,
            path: materialized.destinationPath,
            sha256: materialized.sha256,
            sourceFrameID: query.frameID,
            sourceSurfaceID: SemanticRecordingFixture.surfaceID,
            sourceArtifactPath: sourceRef.path,
            sourceBounds: RectValue(x: 20, y: 30, width: 80, height: 50),
            sourceBoundsSpace: .displayAbsolute
        )
        let evidence = [
            RecordingEvidenceReference(
                frameID: query.frameID,
                eventIDs: [SemanticRecordingFixture.clickEventID],
                artifactRef: sourceRef,
                bounds: bounds,
                summary: "Frame region was extracted as a draft-compatible visual asset."
            )
        ]
        let payload = SemanticRecordingCLIAssetExtractionPayload(
            requestedRecordingID: "checkout-demo",
            recordingID: SemanticRecordingFixture.recordingID,
            fixture: "checkout",
            query: query,
            sourceArtifactRef: sourceRef,
            outputRoot: "/tmp/draft-package",
            materializedAsset: materialized,
            visualAsset: visualAsset,
            evidence: evidence
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIAssetExtractionPayload>
            .semanticRecordingAssetExtraction(command: "recording.asset.extract", payload: payload)

        let data = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.command == "recording.asset.extract")
        #expect(envelope.warnings.map(\.code) == ["fixtureMode"])
        #expect(data.fixtureMode)
        #expect(data.query.kind == .imageTemplate)
        #expect(data.materializedAsset == materialized)
        #expect(data.visualAsset == visualAsset)
        #expect(data.visualAssets.images == [visualAsset])
        #expect(data.visualAssets.baselines.isEmpty)
        #expect(data.evidence == evidence)
        #expect(envelope.nextActions.contains { $0.command.contains("visualAssets.images") })
    }

    @Test("Recording baseline extraction payload routes asset into draft baselines")
    func recordingBaselineExtractionPayloadRoutesAssetIntoDraftBaselines() throws {
        let sourceRef = try RecordingArtifactRef("frames/000016-after-click.png")
        let bounds = RecordingBounds(
            rect: RecordingRect(x: 0, y: 0, width: 120, height: 80),
            coordinateSpace: .framePixels
        )
        let query = SemanticRecordingCLIAssetExtractionQuery(
            frameID: SemanticRecordingFixture.afterClickFrameID,
            region: bounds,
            kind: .baseline,
            name: "Confirmation Region",
            assetKey: "sr_74000000_confirmation_region_baseline"
        )
        let materialized = SemanticRecordingReviewMaterializedAsset(
            kind: .baseline,
            key: query.assetKey,
            sourcePath: sourceRef.path,
            destinationPath: "assets/baselines/sr_74000000_confirmation_region_baseline.png",
            sha256: "def456"
        )
        let visualAsset = AutomationWorkflowDraftVisualImageAsset(
            key: query.assetKey,
            label: query.name,
            path: materialized.destinationPath,
            sha256: materialized.sha256
        )
        let payload = SemanticRecordingCLIAssetExtractionPayload(
            requestedRecordingID: "checkout-demo",
            recordingID: SemanticRecordingFixture.recordingID,
            query: query,
            sourceArtifactRef: sourceRef,
            outputRoot: "/tmp/draft-package",
            materializedAsset: materialized,
            visualAsset: visualAsset,
            evidence: []
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIAssetExtractionPayload>
            .semanticRecordingAssetExtraction(command: "recording.asset.baseline", payload: payload)

        let data = try #require(envelope.data)
        #expect(data.fixtureMode == false)
        #expect(data.visualAssets.images.isEmpty)
        #expect(data.visualAssets.baselines == [visualAsset])
        #expect(envelope.nextActions.contains { $0.command.contains("visualAssets.baselines") })
    }

    @Test("Recording suggestion envelope is review-only and cites evidence")
    func recordingSuggestionEnvelopeIsReviewOnlyAndEvidenceBacked() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>
            .semanticRecordingSuggestions(
                command: "recording.suggest.conditions",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout",
                category: .conditions,
                suggestions: SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.command == "recording.suggest.conditions")
        #expect(payload.category == .conditions)
        #expect(payload.availability == .deterministicFixture)
        #expect(payload.query.allowedKinds == [.conditionCandidate])
        #expect(payload.unavailableReason == nil)
        #expect(payload.count == 1)

        let suggestion = try #require(payload.suggestions.first)
        #expect(suggestion.id == SemanticRecordingFixture.suggestionID)
        #expect(suggestion.kind == .conditionCandidate)
        #expect(suggestion.title == "Replace fixed wait with OCR confirmation")
        #expect(suggestion.confidence == 0.86)
        #expect(suggestion.risk?.contains("user review") == true)
        #expect(suggestion.fallback.contains("original playable macro wait"))
        #expect(suggestion.mutationPolicy == "Review required; no workflow or macro mutation until accepted.")

        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(evidence.eventIDs == [
            SemanticRecordingFixture.clickEventID,
            SemanticRecordingFixture.waitEventID
        ])
        #expect(evidence.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(evidence.artifactRef?.path == "visual-index/ocr/confirmation-region.png")

        #expect(suggestion.reviewActions.map(\.actionName) == [
            .acceptSuggestion,
            .rejectSuggestion,
            .clearDecision
        ])
        let acceptAction = try #require(suggestion.reviewActions.first)
        #expect(acceptAction.mutationBoundary == .draftPreviewRequired)
        #expect(acceptAction.createsDraftPatch)
        #expect(!acceptAction.mutatesWorkflow)
        #expect(acceptAction.evidence.suggestionID == SemanticRecordingFixture.suggestionID)
        #expect(acceptAction.evidence.frameID == evidence.frameID)
        #expect(acceptAction.evidence.eventIDs == evidence.eventIDs)
        #expect(acceptAction.evidence.observationIDs == evidence.observationIDs)
        #expect(acceptAction.evidence.artifactPath == evidence.artifactRef?.path)
        #expect(suggestion.reviewActionPresentations.map(\.actionName) == [
            .acceptSuggestion,
            .rejectSuggestion,
            .clearDecision
        ])
        let acceptPresentation = try #require(suggestion.reviewActionPresentations.first)
        let acceptRows = Dictionary(uniqueKeysWithValues: acceptPresentation.rows.map { ($0.kind, $0) })
        #expect(acceptRows[.mutationBoundary]?.value == "Draft Preview required")
        #expect(acceptRows[.mutationEffect]?.value == "Creates reviewed draft patch")
        #expect(acceptRows[.suggestion]?.value == "00000014")
        #expect(acceptRows[.frame]?.value == "00000005")
        #expect(acceptRows[.observations]?.value == "0000000c")
        #expect(acceptRows[.artifact]?.value == evidence.artifactRef?.path)
        #expect(envelope.nextActions.contains { $0.reason.contains("non-destructive evidence proposals") })
    }

    @Test("Recording suggestion envelope exposes persisted stored query contract")
    func recordingSuggestionEnvelopeExposesPersistedStoredQueryContract() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestionResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: nil,
            query: .kinds([.conditionCandidate])
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>
            .semanticRecordingSuggestions(
                command: "recording.suggest.conditions",
                requestedRecordingID: bundle.id.uuidString,
                bundle: bundle,
                category: .conditions,
                suggestionResult: suggestionResult
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(payload.fixtureMode == false)
        #expect(payload.availability == .persistedBundle)
        #expect(payload.query.allowedKinds == [.conditionCandidate])
        #expect(payload.unavailableReason == nil)
        #expect(payload.count == 2)
        #expect(payload.suggestions.map(\.kind) == [.conditionCandidate, .conditionCandidate])
        #expect(payload.suggestions.contains {
            $0.title == "Create OCR wait for \"Order confirmed\"" &&
                $0.evidence.contains { $0.observationIDs == [SemanticRecordingFixture.ocrObservationID] }
        })
        #expect(payload.suggestions.contains {
            $0.title == "Create image condition for button" &&
                $0.evidence.contains { $0.observationIDs == [SemanticRecordingFixture.templateObservationID] }
        })
        #expect(envelope.warnings.isEmpty)
    }

    @Test("Recording suggestion envelope surfaces artifact file status")
    func recordingSuggestionEnvelopeSurfacesArtifactFileStatus() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let ocrArtifact = try #require(
            bundle.visualObservations.first { $0.id == SemanticRecordingFixture.ocrObservationID }?.artifactRef
        )
        let suggestionResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: nil,
            query: .kinds([.conditionCandidate])
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>
            .semanticRecordingSuggestions(
                command: "recording.suggest.conditions",
                requestedRecordingID: bundle.id.uuidString,
                bundle: bundle,
                category: .conditions,
                suggestionResult: suggestionResult,
                artifactFiles: SemanticRecordingCLIArtifactFileSummary(evidence: [
                    SemanticRecordingCLIArtifactFileEvidence(
                        kind: .visualObservation,
                        ref: ocrArtifact,
                        status: .missing
                    )
                ])
            )

        let payload = try #require(envelope.data)
        #expect(payload.artifactFiles?.checkedCount == 1)
        #expect(payload.artifactFiles?.missingCount == 1)
        #expect(payload.artifactFiles?.evidence.first?.kind == .visualObservation)
        #expect(payload.artifactFiles?.evidence.first?.ref == ocrArtifact)
        #expect(envelope.warnings.map(\.code).contains("recordingArtifactsDegraded"))
        #expect(envelope.warnings.first { $0.code == "recordingArtifactsDegraded" }?.message.contains("before accepting suggestions") == true)
    }

    @Test("Recording suggestions without evidence stay low confidence")
    func recordingSuggestionWithoutEvidenceStaysLowConfidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestion = RecordingSuggestion(
            recordingID: bundle.id,
            kind: .conditionCandidate,
            title: "Infer a confirmation wait",
            summary: "A suggestion without frame, event or observation evidence must stay guarded.",
            confidence: 0.92,
            evidence: []
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>
            .semanticRecordingSuggestions(
                command: "recording.suggest.conditions",
                requestedRecordingID: "checkout-demo",
                bundle: bundle,
                fixture: "checkout",
                category: .conditions,
                suggestions: [suggestion]
            )

        let payload = try #require(envelope.data)
        let summary = try #require(payload.suggestions.first)
        #expect(summary.confidence == 0.49)
        #expect(summary.evidence.isEmpty)
        #expect(summary.risk?.contains("Missing recording evidence refs") == true)
        #expect(summary.mutationPolicy == "Review required; no workflow or macro mutation until accepted.")
        #expect(summary.reviewActions.first?.evidence.frameID == nil)
        #expect(summary.reviewActions.first?.evidence.observationIDs.isEmpty == true)
    }

    @Test("Workflow draft from recording builds a review-only draft from fixture suggestions")
    func workflowDraftFromRecordingBuildsReviewOnlyDraftFromFixtureSuggestions() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let result = SemanticRecordingWorkflowDraftBuilder.build(
            bundle: bundle,
            suggestions: SemanticRecordingFixture.checkoutSuggestions(bundle: bundle),
            options: SemanticRecordingWorkflowDraftBuildOptions(
                workflowName: "Checkout Generated",
                maxTasks: 2
            )
        )

        #expect(result.isValid)
        #expect(result.document.workflow.name == "Checkout Generated")
        #expect(result.document.workflow.tasks.map(\.key) == ["wait_order_confirmed_0000000e"])
        #expect(result.document.workflow.dependencies.isEmpty)
        #expect(result.suggestionCount == 1)
        #expect(result.appliedItems.map(\.source) == [.suggestion])
        #expect(result.appliedItems.first?.suggestionID == SemanticRecordingFixture.suggestionID)
        #expect(result.appliedItems.first?.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(result.appliedItems.first?.conditionType == "ocrText")

        let task = try #require(result.document.workflow.tasks.first)
        #expect(task.type == "condition")
        #expect(task.name == "Wait for Order confirmed")
        #expect(task.condition?.text == "Order confirmed")
        #expect(task.condition?.regionRef == "sr_00000001_order_confirmed_0000000e_region")
        #expect(result.document.visualAssets?.regions.first?.key == task.condition?.regionRef)
        #expect(result.validation.issues.contains { $0.code == .missingTimeoutBranch })
    }

    @Test("Workflow draft from recording envelope cites fixture and draft validation evidence")
    func workflowDraftFromRecordingEnvelopeCitesFixtureAndValidationEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let result = SemanticRecordingWorkflowDraftBuilder.build(
            bundle: bundle,
            suggestions: SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        )
        let payload = AutomationWorkflowDraftFromRecordingPayload(
            requestedRecordingID: "checkout-demo",
            recordingID: bundle.id,
            fixture: "checkout",
            wrotePath: "/tmp/checkout-draft.json",
            result: result
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftFromRecordingPayload>
            .workflowDraftFromRecording(command: "workflow draft from-recording", payload: payload)

        let data = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(data.fixtureMode)
        #expect(data.result.generatedTaskCount == 1)
        #expect(data.result.document.workflow.tasks.first?.condition?.type == "ocrText")
        #expect(envelope.warnings.contains { $0.code == "fixtureMode" })
        #expect(envelope.warnings.contains { $0.code == AutomationWorkflowDraftIssueCode.missingTimeoutBranch.rawValue })
        #expect(envelope.nextActions.contains { $0.command.contains("workflow draft validate /tmp/checkout-draft.json") })
        #expect(envelope.nextActions.contains { $0.command.contains("recording frames checkout-demo --fixture checkout --json") })
    }

    @Test("Recording list envelope exposes fixture catalog entry")
    func recordingListEnvelopeExposesFixtureCatalogEntry() throws {
        let entry = SemanticRecordingCLICatalogEntry(
            recordingID: SemanticRecordingFixture.recordingID,
            source: .fixture,
            fixture: "checkout"
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
            .semanticRecordingList(
                command: "recording.list",
                recordings: [entry],
                fixture: "checkout"
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(envelope.command == "recording.list")
        #expect(envelope.warnings.map(\.code) == ["fixtureMode"])
        #expect(payload.fixtureMode)
        #expect(payload.count == 1)
        #expect(payload.recordings.first?.recordingID == SemanticRecordingFixture.recordingID)
        #expect(payload.recordings.first?.source == .fixture)
        #expect(envelope.nextActions.first?.command.contains("--fixture checkout --json") == true)
    }

    @Test("Stored recording source option propagates without fixture warning")
    func storedRecordingSourceOptionPropagatesWithoutFixtureWarning() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let sourceOption = " --recordings-root '/tmp/Sparkle Recorder'"
        let listEntry = SemanticRecordingCLICatalogEntry(
            recordingID: bundle.id,
            source: .storedBundle,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let listEnvelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
            .semanticRecordingList(
                command: "recording.list",
                recordings: [listEntry],
                recordingsRoot: "/tmp/Sparkle Recorder",
                sourceOption: sourceOption
            )
        let showEnvelope = AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload>
            .semanticRecordingShow(
                command: "recording.show",
                requestedRecordingID: bundle.id.uuidString,
                bundle: bundle,
                sourceOption: sourceOption
            )
        let explainEnvelope = AutomationCLIResultEnvelope<SemanticRecordingCLIExplainPayload>
            .semanticRecordingExplain(
                command: "recording.explain",
                requestedRecordingID: bundle.id.uuidString,
                bundle: bundle,
                sourceOption: sourceOption
            )

        let listPayload = try #require(listEnvelope.data)
        let showPayload = try #require(showEnvelope.data)
        let explainPayload = try #require(explainEnvelope.data)
        #expect(!listPayload.fixtureMode)
        #expect(!showPayload.fixtureMode)
        #expect(!explainPayload.fixtureMode)
        #expect(listEnvelope.warnings.isEmpty)
        #expect(showEnvelope.warnings.isEmpty)
        #expect(explainEnvelope.warnings.isEmpty)
        #expect(listEnvelope.nextActions.first?.command.contains(sourceOption) == true)
        #expect(showEnvelope.nextActions.contains { $0.command.contains(sourceOption) })
        #expect(explainEnvelope.nextActions.contains { $0.command.contains(sourceOption) })
    }

    @Test("Default stored recording source omits explicit root from next actions")
    func defaultStoredRecordingSourceOmitsExplicitRootFromNextActions() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let defaultRoot = "/Users/example/Library/Application Support/SparkleRecorder/SemanticRecordings"
        let listEntry = SemanticRecordingCLICatalogEntry(
            recordingID: bundle.id,
            source: .storedBundle,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )
        let listEnvelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
            .semanticRecordingList(
                command: "recording.list",
                recordings: [listEntry],
                recordingsRoot: defaultRoot
            )
        let showEnvelope = AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload>
            .semanticRecordingShow(
                command: "recording.show",
                requestedRecordingID: bundle.id.uuidString,
                bundle: bundle
            )

        let listPayload = try #require(listEnvelope.data)
        let showPayload = try #require(showEnvelope.data)
        #expect(!listPayload.fixtureMode)
        #expect(!showPayload.fixtureMode)
        #expect(listPayload.recordingsRoot == defaultRoot)
        #expect(listEnvelope.warnings.isEmpty)
        #expect(showEnvelope.warnings.isEmpty)
        #expect(listEnvelope.nextActions.first?.command.contains("--recordings-root") == false)
        #expect(showEnvelope.nextActions.allSatisfy { !$0.command.contains("--recordings-root") })
        #expect(listEnvelope.nextActions.first?.command.contains("recording show \(bundle.id.uuidString) --json") == true)
    }

    @Test("Recording readiness envelope exposes sidecar diagnostics and readiness warnings")
    func recordingReadinessEnvelopeExposesDiagnosticsAndWarnings() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        var diagnostics = SemanticRecordingBundleSidecarLoadDiagnostics(
            loadedKinds: [.videoSegments, .frames]
        )
        diagnostics.recordFailed(
            .visualObservations,
            relativePath: "ocr/observations.jsonl",
            message: "Could not decode sidecar."
        )
        let loadResult = SemanticRecordingBundleLoadResult(
            manifest: bundle,
            sidecarDiagnostics: diagnostics
        )
        let readiness = SemanticRecordingBundleReadiness.evaluate(
            loadResult.bundle,
            policy: SemanticRecordingBundleReadinessPolicy(
                capturePolicy: bundle.capturePolicy,
                requiresOCRObservations: true,
                requiresWindowOrAXObservations: true
            )
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIReadinessPayload>
            .semanticRecordingReadiness(
                command: "recording.readiness",
                requestedRecordingID: bundle.id.uuidString,
                loadResult: loadResult,
                readiness: readiness,
                bundleDirectory: "/tmp/SemanticRecordings/\(bundle.id.uuidString)",
                followUps: ["Inspect ocr/observations.jsonl."],
                artifactFiles: SemanticRecordingCLIArtifactFileSummary(evidence: [
                    SemanticRecordingCLIArtifactFileEvidence(
                        kind: .video,
                        ref: try RecordingArtifactRef("video/recording.mov"),
                        status: .present,
                        byteCount: 128
                    ),
                    SemanticRecordingCLIArtifactFileEvidence(
                        kind: .frame,
                        ref: try RecordingArtifactRef("frames/missing.png"),
                        status: .missing
                    )
                ])
            )

        let payload = try #require(envelope.data)
        #expect(envelope.ok)
        #expect(payload.status == .notReady)
        #expect(payload.issueCount == readiness.issues.count)
        #expect(payload.blockingIssueCount == readiness.blockingIssueCount)
        #expect(payload.degradedIssueCount == readiness.degradedIssueCount)
        #expect(payload.load.sidecarDiagnostics.failedIssues.map(\.kind) == [.visualObservations])
        #expect(payload.followUps == ["Inspect ocr/observations.jsonl."])
        #expect(payload.artifactAvailability.videoRefs == bundle.videoSegments.map(\.artifactRef))
        #expect(payload.artifactFiles?.checkedCount == 2)
        #expect(payload.artifactFiles?.presentCount == 1)
        #expect(payload.artifactFiles?.missingCount == 1)
        #expect(payload.artifactFiles?.videoPresentCount == 1)
        #expect(envelope.warnings.map(\.code).contains("recordingReadinessNotReady"))
        #expect(envelope.warnings.map(\.code).contains("recordingSidecarsDegraded"))
        #expect(envelope.warnings.map(\.code).contains("recordingArtifactsDegraded"))
        #expect(envelope.nextActions.first?.command.contains("--recordings-root") == false)
    }

    @Test("Recording macro links envelope audits saved macro semantic bundle references")
    func recordingMacroLinksEnvelopeAuditsSavedMacroSemanticBundleReferences() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let linkedMacro = SavedMacro(
            id: UUID(uuidString: "31000000-0000-0000-0000-000000000001")!,
            name: "Linked checkout",
            events: [
                .make(.leftMouseDown, time: 0.1, x: 10, y: 20),
                .make(.leftMouseUp, time: 0.2, x: 10, y: 20)
            ],
            semanticRecording: MacroSemanticRecordingReference(
                recordingID: bundle.id,
                bundleRelativePath: "SemanticRecordings/\(bundle.id.uuidString)",
                manifestRelativePath: "SemanticRecordings/\(bundle.id.uuidString)/manifest.json",
                eventCount: 2
            )
        )
        let unlinkedMacro = SavedMacro(
            id: UUID(uuidString: "31000000-0000-0000-0000-000000000002")!,
            name: "Unlinked",
            events: []
        )
        let readiness = SemanticRecordingBundleReadiness.evaluate(
            bundle,
            policy: SemanticRecordingBundleReadinessPolicy(
                capturePolicy: bundle.capturePolicy,
                requiresOCRObservations: true,
                requiresWindowOrAXObservations: true
            )
        )
        let linkedEntry = SemanticRecordingCLIMacroLinkEntry(
            macro: linkedMacro,
            bundleDirectory: "/tmp/SemanticRecordings/\(bundle.id.uuidString)",
            loadResult: SemanticRecordingBundleLoadResult(manifest: bundle),
            readiness: readiness,
            artifactFiles: SemanticRecordingCLIArtifactFileSummary(evidence: [
                SemanticRecordingCLIArtifactFileEvidence(
                    kind: .video,
                    ref: try RecordingArtifactRef("video/recording.mov"),
                    status: .empty,
                    byteCount: 0
                )
            ])
        )
        let unlinkedEntry = SemanticRecordingCLIMacroLinkEntry(
            macro: unlinkedMacro,
            status: .unlinked
        )
        let payload = SemanticRecordingCLIMacroLinksPayload(
            macrosRoot: "/tmp/Macros",
            recordingsRoot: "/tmp/SemanticRecordings",
            totalMacroCount: 2,
            requiresOCRObservations: true,
            requiresWindowOrAXObservations: true,
            links: [linkedEntry, unlinkedEntry]
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIMacroLinksPayload>
            .semanticRecordingMacroLinks(
                command: "recording.macroLinks",
                payload: payload,
                recordingsRootSourceOption: " --recordings-root /tmp/SemanticRecordings"
            )

        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<SemanticRecordingCLIMacroLinksPayload>.self,
            from: try JSONEncoder().encode(envelope)
        )
        let decodedPayload = try #require(decoded.data)
        #expect(decodedPayload.totalMacroCount == 2)
        #expect(decodedPayload.linkedMacroCount == 1)
        #expect(decodedPayload.unlinkedCount == 1)
        #expect(decodedPayload.notReadyCount == 1)
        #expect(decodedPayload.links.first?.recordingID == bundle.id)
        #expect(decodedPayload.links.first?.artifactAvailability?.videoRefs == bundle.videoSegments.map(\.artifactRef))
        #expect(decodedPayload.links.first?.artifactFiles?.emptyCount == 1)
        #expect(decoded.warnings.map(\.code).contains("macroSemanticRecordingNotReady"))
        #expect(decoded.warnings.map(\.code).contains("macroSemanticRecordingArtifactsDegraded"))
        #expect(decoded.nextActions.first?.command.contains("recording readiness \(bundle.id.uuidString) --recordings-root /tmp/SemanticRecordings --json") == true)
    }
}
