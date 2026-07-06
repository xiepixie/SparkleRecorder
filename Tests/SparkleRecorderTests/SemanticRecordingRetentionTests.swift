import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Retention Tests")
struct SemanticRecordingRetentionTests {
    @Test("Expired policy prunes artifact refs and preserves metadata files")
    func expiredPolicyPrunesArtifactRefsAndPreservesMetadataFiles() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let policy = SemanticRecordingRetentionPolicy(maximumArtifactAge: 60)

        let plan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: policy,
            evaluatedAt: Date(timeIntervalSince1970: 1_120)
        )

        #expect(plan.recordingID == bundle.id)
        #expect(plan.disposition == .pruneArtifacts)
        #expect(plan.reason == .expired)
        #expect(plan.deletesArtifacts)
        #expect(!plan.deletesBundleDirectory)
        #expect(plan.metadataFilesToPreserve == SemanticRecordingRetentionPlanner.defaultMetadataFilesToPreserve)
        #expect(plan.artifactRefsToDelete.map(\.path) == [
            "frames/000001-start.png",
            "frames/000014-before-click.png",
            "frames/000016-after-click.png",
            "runs/run-001/condition-confirmation/diff.png",
            "runs/run-001/condition-confirmation/watched-region.png",
            "video/recording.mov",
            "visual-index/ocr/confirmation-region.png",
            "visual-index/templates/checkout-button.png"
        ])

        let encoded = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(SemanticRecordingRetentionPlan.self, from: encoded)
        #expect(decoded == plan)
    }

    @Test("Retention settings map UI choices into policy")
    func retentionSettingsMapUIChoicesIntoPolicy() {
        let pruneSettings = SemanticRecordingRetentionSettings(
            maximumArtifactAgeDays: 7,
            expiredDisposition: .pruneArtifacts
        )
        let keepSettings = SemanticRecordingRetentionSettings(
            maximumArtifactAgeDays: 0,
            expiredDisposition: .deleteBundle
        )
        let normalizedSettings = SemanticRecordingRetentionSettings(
            maximumArtifactAgeDays: 30,
            expiredDisposition: .retain
        )

        let prunePolicy = pruneSettings.policy()
        let keepPolicy = keepSettings.policy()
        let normalizedPolicy = normalizedSettings.policy()

        #expect(prunePolicy.maximumArtifactAge == TimeInterval(7 * 24 * 60 * 60))
        #expect(prunePolicy.expiredDisposition == .pruneArtifacts)
        #expect(keepPolicy.maximumArtifactAge == nil)
        #expect(keepPolicy.expiredDisposition == .deleteBundle)
        #expect(normalizedPolicy.maximumArtifactAge == TimeInterval(30 * 24 * 60 * 60))
        #expect(normalizedPolicy.expiredDisposition == .pruneArtifacts)
    }

    @Test("Scheduled cleanup planner skips disabled and recent runs")
    func scheduledCleanupPlannerSkipsDisabledAndRecentRuns() {
        let lastRunAt = Date(timeIntervalSince1970: 10_000)
        let now = Date(timeIntervalSince1970: 10_300)

        let disabled = SemanticRecordingScheduledRetentionCleanupPlanner.decision(
            settings: SemanticRecordingRetentionSettings(
                maximumArtifactAgeDays: 0,
                expiredDisposition: .pruneArtifacts
            ),
            lastRunAt: lastRunAt,
            evaluatedAt: now,
            minimumInterval: 600
        )
        let recent = SemanticRecordingScheduledRetentionCleanupPlanner.decision(
            settings: SemanticRecordingRetentionSettings(
                maximumArtifactAgeDays: 30,
                expiredDisposition: .pruneArtifacts
            ),
            lastRunAt: lastRunAt,
            evaluatedAt: now,
            minimumInterval: 600
        )

        #expect(disabled.action == .skipRetentionDisabled)
        #expect(!disabled.shouldRun)
        #expect(disabled.nextEligibleAt == nil)
        #expect(recent.action == .skipIntervalNotReached)
        #expect(!recent.shouldRun)
        #expect(recent.nextEligibleAt == Date(timeIntervalSince1970: 10_600))
    }

    @Test("Scheduled cleanup planner runs after interval")
    func scheduledCleanupPlannerRunsAfterInterval() throws {
        let lastRunAt = Date(timeIntervalSince1970: 10_000)
        let now = Date(timeIntervalSince1970: 10_601)
        let decision = SemanticRecordingScheduledRetentionCleanupPlanner.decision(
            settings: SemanticRecordingRetentionSettings(
                maximumArtifactAgeDays: 30,
                expiredDisposition: .deleteBundle
            ),
            lastRunAt: lastRunAt,
            evaluatedAt: now,
            minimumInterval: 600
        )

        #expect(decision.action == .previewAndApply)
        #expect(decision.shouldRun)
        #expect(decision.lastRunAt == lastRunAt)
        #expect(decision.nextEligibleAt == nil)
        #expect(decision.minimumInterval == 600)

        let encoded = try JSONEncoder().encode(decision)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingScheduledRetentionCleanupDecision.self,
            from: encoded
        )
        #expect(decoded == decision)
    }

    @Test("Cleanup preview filters retained plans and summarizes destructive work")
    func cleanupPreviewFiltersRetainedPlansAndSummarizesDestructiveWork() throws {
        let evaluatedAt = Date(timeIntervalSince1970: 10_000)
        var deleteBundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        deleteBundle.id = try #require(UUID(uuidString: "74000000-0000-0000-0000-00000000D001"))
        var pruneBundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        pruneBundle.id = try #require(UUID(uuidString: "74000000-0000-0000-0000-00000000D002"))
        var freshBundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 9_980)
        )
        freshBundle.id = try #require(UUID(uuidString: "74000000-0000-0000-0000-00000000D003"))

        let deletePlan = SemanticRecordingRetentionPlanner.plan(
            for: deleteBundle,
            policy: SemanticRecordingRetentionPolicy(
                maximumArtifactAge: 60,
                expiredDisposition: .deleteBundle
            ),
            evaluatedAt: evaluatedAt
        )
        let prunePlan = SemanticRecordingRetentionPlanner.plan(
            for: pruneBundle,
            policy: SemanticRecordingRetentionPolicy(
                maximumArtifactAge: 60,
                expiredDisposition: .pruneArtifacts
            ),
            evaluatedAt: evaluatedAt
        )
        let freshPlan = SemanticRecordingRetentionPlanner.plan(
            for: freshBundle,
            policy: SemanticRecordingRetentionPolicy(maximumArtifactAge: 60),
            evaluatedAt: evaluatedAt
        )

        let preview = SemanticRecordingRetentionCleanupPresenter.preview(
            plans: [freshPlan, prunePlan, deletePlan],
            scannedRecordingCount: 3,
            evaluatedAt: evaluatedAt
        )

        #expect(!preview.isEmpty)
        #expect(preview.evaluatedAt == evaluatedAt)
        #expect(preview.scannedRecordingCount == 3)
        #expect(preview.items.map(\.id) == [deleteBundle.id, pruneBundle.id])
        #expect(preview.plans == [deletePlan, prunePlan])
        #expect(preview.pruneCount == 1)
        #expect(preview.deleteBundleCount == 1)
        #expect(preview.artifactRefCount == deletePlan.artifactRefsToDelete.count + prunePlan.artifactRefsToDelete.count)
        #expect(preview.preservedMetadataFileCount == prunePlan.metadataFilesToPreserve.count)
        #expect(preview.confirmationRequired)
        #expect(preview.items.map(\.presentation.status) == [.deleteRequested, .pruneRecommended])

        let encoded = try JSONEncoder().encode(preview)
        let decoded = try JSONDecoder().decode(SemanticRecordingRetentionCleanupPreview.self, from: encoded)
        #expect(decoded == preview)
    }

    @Test("User requested deletion plans full bundle removal")
    func userRequestedDeletionPlansFullBundleRemoval() {
        let bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let policy = SemanticRecordingRetentionPolicy(
            maximumArtifactAge: 10_000,
            protectedRecordingIDs: [bundle.id]
        )

        let plan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: policy,
            evaluatedAt: Date(timeIntervalSince1970: 2_010),
            protectedReasons: ["favorite"],
            userRequestedDeletion: true
        )

        #expect(plan.disposition == .deleteBundle)
        #expect(plan.reason == .userRequestedDeletion)
        #expect(plan.deletesArtifacts)
        #expect(plan.deletesBundleDirectory)
        #expect(plan.protectedReasons.isEmpty)
        #expect(plan.metadataFilesToPreserve.isEmpty)
        #expect(plan.artifactRefsToDelete.contains {
            $0.path == "video/recording.mov"
        })
    }

    @Test("Retention artifact refs include redacted frame and video artifacts")
    func retentionArtifactRefsIncludeRedactedArtifacts() throws {
        var bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 2_500)
        )
        bundle.redactedFrames = [
            SemanticRecordingRenderedFrameRedaction(
                frameID: SemanticRecordingFixture.afterClickFrameID,
                sourceImageRef: try RecordingArtifactRef("frames/000016-after-click.png"),
                redactedImageRef: try RecordingArtifactRef("redacted/frames/after-click.png"),
                renderedMaskCount: 1,
                sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID]
            )
        ]
        bundle.redactedVideos = [
            SemanticRecordingRenderedVideoRedaction(
                videoSegmentID: SemanticRecordingFixture.videoSegmentID,
                sourceVideoRef: try RecordingArtifactRef("video/recording.mov"),
                redactedVideoRef: try RecordingArtifactRef("redacted/video/recording.mov"),
                renderedRangeCount: 1,
                sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID],
                reasons: [.passwordField]
            )
        ]

        let refs = SemanticRecordingRetentionPlanner.artifactRefs(in: bundle)

        #expect(refs.map(\.path).contains("redacted/frames/after-click.png"))
        #expect(refs.map(\.path).contains("redacted/video/recording.mov"))
    }

    @Test("Protected and fresh recordings are retained")
    func protectedAndFreshRecordingsAreRetained() {
        let bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let policy = SemanticRecordingRetentionPolicy(
            maximumArtifactAge: 60,
            protectedRecordingIDs: [bundle.id]
        )

        let protectedPlan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: policy,
            evaluatedAt: Date(timeIntervalSince1970: 3_120),
            protectedReasons: ["open review"]
        )
        let freshPlan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: SemanticRecordingRetentionPolicy(maximumArtifactAge: 60),
            evaluatedAt: Date(timeIntervalSince1970: 3_030)
        )

        #expect(protectedPlan.disposition == .retain)
        #expect(protectedPlan.reason == .protected)
        #expect(protectedPlan.protectedReasons == ["open review"])
        #expect(protectedPlan.artifactRefsToDelete.isEmpty)
        #expect(freshPlan.disposition == .retain)
        #expect(freshPlan.reason == .notExpired)
        #expect(freshPlan.age == 30)
    }

    @Test("Retention presentation asks before pruning expired artifacts")
    func retentionPresentationAsksBeforePruningExpiredArtifacts() {
        let bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 4_000)
        )
        let plan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: SemanticRecordingRetentionPolicy(maximumArtifactAge: 60),
            evaluatedAt: Date(timeIntervalSince1970: 4_120)
        )

        let presentation = SemanticRecordingRetentionPresenter.presentation(for: plan)

        #expect(presentation.recordingID == bundle.id)
        #expect(presentation.status == .pruneRecommended)
        #expect(presentation.confirmationRequired)
        #expect(presentation.title == "Delete expired semantic artifacts")
        #expect(presentation.summary.contains("preserving metadata"))
        #expect(presentation.artifactRefCount == plan.artifactRefsToDelete.count)
        #expect(presentation.preservedMetadataFileCount == plan.metadataFilesToPreserve.count)
        #expect(presentation.primaryAction == SemanticRecordingRetentionPresentationAction(
            kind: .pruneArtifacts,
            label: "Delete expired artifacts",
            isDestructive: true
        ))
        #expect(presentation.secondaryAction == SemanticRecordingRetentionPresentationAction(
            kind: .keepRecording,
            label: "Keep recording"
        ))
    }

    @Test("Retention presentation distinguishes full bundle deletion")
    func retentionPresentationDistinguishesFullBundleDeletion() {
        let bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 5_000)
        )
        let plan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: SemanticRecordingRetentionPolicy(maximumArtifactAge: 60),
            evaluatedAt: Date(timeIntervalSince1970: 5_010),
            userRequestedDeletion: true
        )

        let presentation = SemanticRecordingRetentionPresenter.presentation(for: plan)

        #expect(presentation.status == .deleteRequested)
        #expect(presentation.confirmationRequired)
        #expect(presentation.title == "Delete semantic recording bundle")
        #expect(presentation.summary.contains("Ordinary macro playback can remain available"))
        #expect(presentation.artifactRefCount == plan.artifactRefsToDelete.count)
        #expect(presentation.preservedMetadataFileCount == 0)
        #expect(presentation.primaryAction.kind == .deleteBundle)
        #expect(presentation.primaryAction.isDestructive)
        #expect(presentation.secondaryAction?.kind == .keepRecording)
    }

    @Test("Retention presentation explains protected recordings without destructive action")
    func retentionPresentationExplainsProtectedRecordings() {
        let bundle = SemanticRecordingFixture.checkoutBundle(
            createdAt: Date(timeIntervalSince1970: 6_000)
        )
        let plan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: SemanticRecordingRetentionPolicy(
                maximumArtifactAge: 60,
                protectedRecordingIDs: [bundle.id]
            ),
            evaluatedAt: Date(timeIntervalSince1970: 6_120),
            protectedReasons: ["open review", "favorite macro"]
        )

        let presentation = SemanticRecordingRetentionPresenter.presentation(for: plan)

        #expect(presentation.status == .retained)
        #expect(!presentation.confirmationRequired)
        #expect(presentation.title == "Semantic recording is protected")
        #expect(presentation.summary.contains("open review"))
        #expect(presentation.summary.contains("favorite macro"))
        #expect(presentation.protectedReasons == ["open review", "favorite macro"])
        #expect(!presentation.primaryAction.isDestructive)
        #expect(presentation.primaryAction.kind == .keepRecording)
        #expect(presentation.secondaryAction == nil)
    }
}
