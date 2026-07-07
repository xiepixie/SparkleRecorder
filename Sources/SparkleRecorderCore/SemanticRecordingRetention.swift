import Foundation

public enum SemanticRecordingRetentionDisposition: String, Codable, Equatable, Hashable, Sendable {
    case retain
    case pruneArtifacts
    case deleteBundle
}

public enum SemanticRecordingRetentionReason: String, Codable, Equatable, Sendable {
    case notExpired
    case protected
    case expired
    case userRequestedDeletion
}

public struct SemanticRecordingRetentionPolicy: Codable, Equatable, Sendable {
    public var maximumArtifactAge: TimeInterval?
    public var expiredDisposition: SemanticRecordingRetentionDisposition
    public var protectedRecordingIDs: Set<UUID>
    public var metadataFilesToPreserveOnPrune: [String]

    public init(
        maximumArtifactAge: TimeInterval? = nil,
        expiredDisposition: SemanticRecordingRetentionDisposition = .pruneArtifacts,
        protectedRecordingIDs: Set<UUID> = [],
        metadataFilesToPreserveOnPrune: [String] = SemanticRecordingRetentionPlanner.defaultMetadataFilesToPreserve
    ) {
        self.maximumArtifactAge = maximumArtifactAge.map { max(0, $0) }
        self.expiredDisposition = expiredDisposition
        self.protectedRecordingIDs = protectedRecordingIDs
        self.metadataFilesToPreserveOnPrune = Self.normalizedMetadataFiles(metadataFilesToPreserveOnPrune)
    }

    private static func normalizedMetadataFiles(_ files: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for file in files {
            let trimmed = file.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        return normalized
    }
}

public struct SemanticRecordingRetentionSettings: Codable, Equatable, Sendable {
    public static let defaultMaximumArtifactAgeDays = 30

    public var maximumArtifactAgeDays: Int?
    public var expiredDisposition: SemanticRecordingRetentionDisposition

    public init(
        maximumArtifactAgeDays: Int? = Self.defaultMaximumArtifactAgeDays,
        expiredDisposition: SemanticRecordingRetentionDisposition = .pruneArtifacts
    ) {
        self.maximumArtifactAgeDays = Self.normalizedMaximumArtifactAgeDays(maximumArtifactAgeDays)
        self.expiredDisposition = expiredDisposition == .retain ? .pruneArtifacts : expiredDisposition
    }

    public func policy(
        protectedRecordingIDs: Set<UUID> = [],
        metadataFilesToPreserveOnPrune: [String] = SemanticRecordingRetentionPlanner.defaultMetadataFilesToPreserve
    ) -> SemanticRecordingRetentionPolicy {
        SemanticRecordingRetentionPolicy(
            maximumArtifactAge: maximumArtifactAgeDays.map { TimeInterval($0) * 24 * 60 * 60 },
            expiredDisposition: expiredDisposition,
            protectedRecordingIDs: protectedRecordingIDs,
            metadataFilesToPreserveOnPrune: metadataFilesToPreserveOnPrune
        )
    }

    private static func normalizedMaximumArtifactAgeDays(_ days: Int?) -> Int? {
        guard let days else {
            return nil
        }
        let clamped = max(0, days)
        return clamped == 0 ? nil : clamped
    }
}

public enum SemanticRecordingScheduledRetentionCleanupAction: String, Codable, Equatable, Sendable {
    case skipRetentionDisabled
    case skipIntervalNotReached
    case previewAndApply
}

public struct SemanticRecordingScheduledRetentionCleanupDecision: Codable, Equatable, Sendable {
    public var action: SemanticRecordingScheduledRetentionCleanupAction
    public var evaluatedAt: Date
    public var lastRunAt: Date?
    public var nextEligibleAt: Date?
    public var minimumInterval: TimeInterval

    public init(
        action: SemanticRecordingScheduledRetentionCleanupAction,
        evaluatedAt: Date,
        lastRunAt: Date? = nil,
        nextEligibleAt: Date? = nil,
        minimumInterval: TimeInterval
    ) {
        self.action = action
        self.evaluatedAt = evaluatedAt
        self.lastRunAt = lastRunAt
        self.nextEligibleAt = nextEligibleAt
        self.minimumInterval = max(0, minimumInterval)
    }

    public var shouldRun: Bool {
        action == .previewAndApply
    }
}

public enum SemanticRecordingScheduledRetentionCleanupPlanner {
    public static let defaultMinimumInterval: TimeInterval = 24 * 60 * 60

    public static func decision(
        settings: SemanticRecordingRetentionSettings,
        lastRunAt: Date?,
        evaluatedAt: Date = Date(),
        minimumInterval: TimeInterval = Self.defaultMinimumInterval
    ) -> SemanticRecordingScheduledRetentionCleanupDecision {
        let interval = max(0, minimumInterval)
        guard settings.maximumArtifactAgeDays != nil else {
            return SemanticRecordingScheduledRetentionCleanupDecision(
                action: .skipRetentionDisabled,
                evaluatedAt: evaluatedAt,
                lastRunAt: lastRunAt,
                minimumInterval: interval
            )
        }

        if let lastRunAt {
            let nextEligibleAt = lastRunAt.addingTimeInterval(interval)
            if evaluatedAt < nextEligibleAt {
                return SemanticRecordingScheduledRetentionCleanupDecision(
                    action: .skipIntervalNotReached,
                    evaluatedAt: evaluatedAt,
                    lastRunAt: lastRunAt,
                    nextEligibleAt: nextEligibleAt,
                    minimumInterval: interval
                )
            }
        }

        return SemanticRecordingScheduledRetentionCleanupDecision(
            action: .previewAndApply,
            evaluatedAt: evaluatedAt,
            lastRunAt: lastRunAt,
            minimumInterval: interval
        )
    }
}

public struct SemanticRecordingRetentionPlan: Codable, Equatable, Sendable {
    public var recordingID: UUID
    public var disposition: SemanticRecordingRetentionDisposition
    public var reason: SemanticRecordingRetentionReason
    public var createdAt: Date
    public var evaluatedAt: Date
    public var age: TimeInterval
    public var protectedReasons: [String]
    public var artifactRefsToDelete: [RecordingArtifactRef]
    public var metadataFilesToPreserve: [String]

    public init(
        recordingID: UUID,
        disposition: SemanticRecordingRetentionDisposition,
        reason: SemanticRecordingRetentionReason,
        createdAt: Date,
        evaluatedAt: Date,
        age: TimeInterval,
        protectedReasons: [String] = [],
        artifactRefsToDelete: [RecordingArtifactRef] = [],
        metadataFilesToPreserve: [String] = []
    ) {
        self.recordingID = recordingID
        self.disposition = disposition
        self.reason = reason
        self.createdAt = createdAt
        self.evaluatedAt = evaluatedAt
        self.age = max(0, age)
        self.protectedReasons = protectedReasons
        self.artifactRefsToDelete = artifactRefsToDelete
        self.metadataFilesToPreserve = metadataFilesToPreserve
    }

    public var deletesArtifacts: Bool {
        disposition == .pruneArtifacts || disposition == .deleteBundle
    }

    public var deletesBundleDirectory: Bool {
        disposition == .deleteBundle
    }
}

public enum SemanticRecordingRetentionPresentationStatus: String, Codable, Equatable, Sendable {
    case retained
    case pruneRecommended
    case deleteRequested
}

public enum SemanticRecordingRetentionPresentationActionKind: String, Codable, Equatable, Sendable {
    case keepRecording
    case pruneArtifacts
    case deleteBundle
}

public struct SemanticRecordingRetentionPresentationAction: Codable, Equatable, Sendable {
    public var kind: SemanticRecordingRetentionPresentationActionKind
    public var label: String
    public var isDestructive: Bool

    public init(
        kind: SemanticRecordingRetentionPresentationActionKind,
        label: String,
        isDestructive: Bool = false
    ) {
        self.kind = kind
        self.label = label
        self.isDestructive = isDestructive
    }
}

public struct SemanticRecordingRetentionPresentation: Codable, Equatable, Sendable {
    public var recordingID: UUID
    public var status: SemanticRecordingRetentionPresentationStatus
    public var title: String
    public var summary: String
    public var artifactRefCount: Int
    public var preservedMetadataFileCount: Int
    public var protectedReasons: [String]
    public var confirmationRequired: Bool
    public var primaryAction: SemanticRecordingRetentionPresentationAction
    public var secondaryAction: SemanticRecordingRetentionPresentationAction?

    public init(
        recordingID: UUID,
        status: SemanticRecordingRetentionPresentationStatus,
        title: String,
        summary: String,
        artifactRefCount: Int,
        preservedMetadataFileCount: Int,
        protectedReasons: [String] = [],
        confirmationRequired: Bool,
        primaryAction: SemanticRecordingRetentionPresentationAction,
        secondaryAction: SemanticRecordingRetentionPresentationAction? = nil
    ) {
        self.recordingID = recordingID
        self.status = status
        self.title = title
        self.summary = summary
        self.artifactRefCount = max(0, artifactRefCount)
        self.preservedMetadataFileCount = max(0, preservedMetadataFileCount)
        self.protectedReasons = protectedReasons
        self.confirmationRequired = confirmationRequired
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

public enum SemanticRecordingRetentionPresenter {
    public static func presentation(
        for plan: SemanticRecordingRetentionPlan
    ) -> SemanticRecordingRetentionPresentation {
        switch plan.disposition {
        case .retain:
            return retainedPresentation(for: plan)
        case .pruneArtifacts:
            return prunePresentation(for: plan)
        case .deleteBundle:
            return deletePresentation(for: plan)
        }
    }

    private static func retainedPresentation(
        for plan: SemanticRecordingRetentionPlan
    ) -> SemanticRecordingRetentionPresentation {
        SemanticRecordingRetentionPresentation(
            recordingID: plan.recordingID,
            status: .retained,
            title: retainedTitle(for: plan),
            summary: retainedSummary(for: plan),
            artifactRefCount: plan.artifactRefsToDelete.count,
            preservedMetadataFileCount: plan.metadataFilesToPreserve.count,
            protectedReasons: plan.protectedReasons,
            confirmationRequired: false,
            primaryAction: keepAction
        )
    }

    private static func prunePresentation(
        for plan: SemanticRecordingRetentionPlan
    ) -> SemanticRecordingRetentionPresentation {
        SemanticRecordingRetentionPresentation(
            recordingID: plan.recordingID,
            status: .pruneRecommended,
            title: "Delete expired semantic artifacts",
            summary: "This removes video, keyframe and visual evidence files while preserving metadata needed to explain the recording history.",
            artifactRefCount: plan.artifactRefsToDelete.count,
            preservedMetadataFileCount: plan.metadataFilesToPreserve.count,
            confirmationRequired: true,
            primaryAction: SemanticRecordingRetentionPresentationAction(
                kind: .pruneArtifacts,
                label: "Delete expired artifacts",
                isDestructive: true
            ),
            secondaryAction: keepAction
        )
    }

    private static func deletePresentation(
        for plan: SemanticRecordingRetentionPlan
    ) -> SemanticRecordingRetentionPresentation {
        SemanticRecordingRetentionPresentation(
            recordingID: plan.recordingID,
            status: .deleteRequested,
            title: "Delete semantic recording bundle",
            summary: "This removes the semantic video, keyframes, OCR and bundle metadata. Ordinary macro playback can remain available through the saved playable events.",
            artifactRefCount: plan.artifactRefsToDelete.count,
            preservedMetadataFileCount: 0,
            confirmationRequired: true,
            primaryAction: SemanticRecordingRetentionPresentationAction(
                kind: .deleteBundle,
                label: "Delete bundle",
                isDestructive: true
            ),
            secondaryAction: keepAction
        )
    }

    private static var keepAction: SemanticRecordingRetentionPresentationAction {
        SemanticRecordingRetentionPresentationAction(
            kind: .keepRecording,
            label: "Keep recording"
        )
    }

    private static func retainedTitle(
        for plan: SemanticRecordingRetentionPlan
    ) -> String {
        switch plan.reason {
        case .protected:
            return "Semantic recording is protected"
        case .notExpired:
            return "Semantic recording is still fresh"
        case .expired:
            return "Semantic recording is retained"
        case .userRequestedDeletion:
            return "Semantic recording is retained"
        }
    }

    private static func retainedSummary(
        for plan: SemanticRecordingRetentionPlan
    ) -> String {
        switch plan.reason {
        case .protected:
            return plan.protectedReasons.isEmpty
                ? "No artifacts will be deleted because this recording is protected."
                : "No artifacts will be deleted because this recording is protected: \(plan.protectedReasons.joined(separator: ", "))."
        case .notExpired:
            return "No artifacts will be deleted because the recording has not reached the retention threshold."
        case .expired:
            return "No artifacts will be deleted by the current retention policy."
        case .userRequestedDeletion:
            return "No artifacts will be deleted."
        }
    }
}

public struct SemanticRecordingRetentionCleanupItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { plan.recordingID }
    public var plan: SemanticRecordingRetentionPlan
    public var presentation: SemanticRecordingRetentionPresentation

    public init(
        plan: SemanticRecordingRetentionPlan,
        presentation: SemanticRecordingRetentionPresentation
    ) {
        self.plan = plan
        self.presentation = presentation
    }
}

public struct SemanticRecordingRetentionCleanupPreview: Codable, Equatable, Sendable {
    public var evaluatedAt: Date
    public var scannedRecordingCount: Int
    public var items: [SemanticRecordingRetentionCleanupItem]

    public init(
        evaluatedAt: Date,
        scannedRecordingCount: Int,
        items: [SemanticRecordingRetentionCleanupItem]
    ) {
        self.evaluatedAt = evaluatedAt
        self.scannedRecordingCount = max(0, scannedRecordingCount)
        self.items = items
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public var pruneCount: Int {
        items.filter { $0.plan.disposition == .pruneArtifacts }.count
    }

    public var deleteBundleCount: Int {
        items.filter { $0.plan.disposition == .deleteBundle }.count
    }

    public var artifactRefCount: Int {
        items.reduce(0) { $0 + $1.presentation.artifactRefCount }
    }

    public var preservedMetadataFileCount: Int {
        items.reduce(0) { $0 + $1.presentation.preservedMetadataFileCount }
    }

    public var confirmationRequired: Bool {
        items.contains { $0.presentation.confirmationRequired }
    }

    public var plans: [SemanticRecordingRetentionPlan] {
        items.map(\.plan)
    }
}

public enum SemanticRecordingRetentionCleanupPresenter {
    public static func preview(
        plans: [SemanticRecordingRetentionPlan],
        scannedRecordingCount: Int,
        evaluatedAt: Date
    ) -> SemanticRecordingRetentionCleanupPreview {
        let items = plans
            .filter(\.deletesArtifacts)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.recordingID.uuidString < rhs.recordingID.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map { plan in
                SemanticRecordingRetentionCleanupItem(
                    plan: plan,
                    presentation: SemanticRecordingRetentionPresenter.presentation(for: plan)
                )
            }

        return SemanticRecordingRetentionCleanupPreview(
            evaluatedAt: evaluatedAt,
            scannedRecordingCount: scannedRecordingCount,
            items: items
        )
    }
}

public enum SemanticRecordingRetentionPlanner {
    public static let defaultMetadataFilesToPreserve: [String] = [
        SemanticRecordingSchema.manifestFileName,
        SemanticRecordingSchema.privateTimelineFileName,
        SemanticRecordingSchema.aiSafeEventsFileName,
        SemanticRecordingSchema.suppressionsFileName,
        "video/segments.json",
        "frames/index.jsonl",
        "ocr/observations.jsonl"
    ]

    public static func plan(
        for bundle: SemanticRecordingBundle,
        policy: SemanticRecordingRetentionPolicy,
        evaluatedAt: Date,
        protectedReasons: [String] = [],
        userRequestedDeletion: Bool = false
    ) -> SemanticRecordingRetentionPlan {
        let age = max(0, evaluatedAt.timeIntervalSince(bundle.createdAt))
        let artifacts = artifactRefs(in: bundle)

        if userRequestedDeletion {
            return SemanticRecordingRetentionPlan(
                recordingID: bundle.id,
                disposition: .deleteBundle,
                reason: .userRequestedDeletion,
                createdAt: bundle.createdAt,
                evaluatedAt: evaluatedAt,
                age: age,
                artifactRefsToDelete: artifacts
            )
        }

        let normalizedProtectedReasons = protectedReasons
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if policy.protectedRecordingIDs.contains(bundle.id) || !normalizedProtectedReasons.isEmpty {
            return SemanticRecordingRetentionPlan(
                recordingID: bundle.id,
                disposition: .retain,
                reason: .protected,
                createdAt: bundle.createdAt,
                evaluatedAt: evaluatedAt,
                age: age,
                protectedReasons: normalizedProtectedReasons
            )
        }

        guard let maximumArtifactAge = policy.maximumArtifactAge,
              age >= maximumArtifactAge else {
            return SemanticRecordingRetentionPlan(
                recordingID: bundle.id,
                disposition: .retain,
                reason: .notExpired,
                createdAt: bundle.createdAt,
                evaluatedAt: evaluatedAt,
                age: age
            )
        }

        return SemanticRecordingRetentionPlan(
            recordingID: bundle.id,
            disposition: policy.expiredDisposition,
            reason: .expired,
            createdAt: bundle.createdAt,
            evaluatedAt: evaluatedAt,
            age: age,
            artifactRefsToDelete: policy.expiredDisposition == .retain ? [] : artifacts,
            metadataFilesToPreserve: policy.expiredDisposition == .pruneArtifacts
                ? policy.metadataFilesToPreserveOnPrune
                : []
        )
    }

    public static func artifactRefs(
        in bundle: SemanticRecordingBundle
    ) -> [RecordingArtifactRef] {
        var refs: [RecordingArtifactRef] = []
        refs.append(contentsOf: bundle.videoSegments.map(\.artifactRef))
        refs.append(contentsOf: bundle.frames.map(\.imageRef))
        refs.append(contentsOf: bundle.visualObservations.compactMap(\.artifactRef))
        refs.append(contentsOf: bundle.sourcePreviews.compactMap(\.artifactRef))
        refs.append(contentsOf: bundle.runtimeSamples.map(\.artifactRef))
        refs.append(contentsOf: bundle.previewComparisons.compactMap(\.diffArtifactRef))
        refs.append(contentsOf: bundle.suppressions.compactMap(\.redactedArtifactRef))
        refs.append(contentsOf: bundle.redactedFrames.map(\.redactedImageRef))
        refs.append(contentsOf: bundle.redactedVideos.map(\.redactedVideoRef))

        var seen = Set<String>()
        return refs
            .sorted { $0.path < $1.path }
            .filter { ref in
                if seen.contains(ref.path) {
                    return false
                }
                seen.insert(ref.path)
                return true
            }
    }
}
