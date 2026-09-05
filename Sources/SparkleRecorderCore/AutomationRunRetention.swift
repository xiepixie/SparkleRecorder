import Foundation

public struct AutomationRunRetentionSettings: Codable, Equatable, Sendable {
    public static let defaultSuccessEvidenceAgeDays = 30
    public static let defaultAttentionEvidenceAgeDays = 90
    public static let defaultMetadataAgeDays = 365
    public static let defaultMaximumMetadataRunCount = 10_000

    public var successEvidenceAgeDays: Int?
    public var attentionEvidenceAgeDays: Int?
    public var metadataAgeDays: Int?
    public var maximumMetadataRunCount: Int?

    public init(
        successEvidenceAgeDays: Int? = Self.defaultSuccessEvidenceAgeDays,
        attentionEvidenceAgeDays: Int? = Self.defaultAttentionEvidenceAgeDays,
        metadataAgeDays: Int? = Self.defaultMetadataAgeDays,
        maximumMetadataRunCount: Int? = Self.defaultMaximumMetadataRunCount
    ) {
        self.successEvidenceAgeDays = Self.normalizedDays(successEvidenceAgeDays)
        self.attentionEvidenceAgeDays = Self.normalizedDays(attentionEvidenceAgeDays)
        self.metadataAgeDays = Self.normalizedDays(metadataAgeDays)
        self.maximumMetadataRunCount = Self.normalizedCount(maximumMetadataRunCount)
    }

    private static func normalizedDays(_ days: Int?) -> Int? {
        guard let days else { return nil }
        let clamped = max(0, days)
        return clamped == 0 ? nil : clamped
    }

    private static func normalizedCount(_ count: Int?) -> Int? {
        guard let count else { return nil }
        let clamped = max(0, count)
        return clamped == 0 ? nil : clamped
    }
}

public struct AutomationRunScheduledRetentionCleanupDecision: Equatable, Sendable {
    public var evaluatedAt: Date
    public var nextEligibleAt: Date?

    public init(evaluatedAt: Date, nextEligibleAt: Date?) {
        self.evaluatedAt = evaluatedAt
        self.nextEligibleAt = nextEligibleAt
    }

    public var shouldRun: Bool {
        guard let nextEligibleAt else { return true }
        return evaluatedAt >= nextEligibleAt
    }
}

public enum AutomationRunScheduledRetentionCleanupPlanner {
    public static func decision(
        lastRunAt: Date?,
        evaluatedAt: Date,
        minimumInterval: TimeInterval = 24 * 60 * 60
    ) -> AutomationRunScheduledRetentionCleanupDecision {
        let nextEligibleAt = lastRunAt?.addingTimeInterval(max(0, minimumInterval))
        return AutomationRunScheduledRetentionCleanupDecision(
            evaluatedAt: evaluatedAt,
            nextEligibleAt: nextEligibleAt
        )
    }
}

public enum AutomationRunRetentionProtection: String, Codable, Equatable, Hashable, Sendable {
    case active
    case latestWorkflowExecution
    case latestWorkflowFailure
    case latestMacroEvidence
}

public enum AutomationRunArtifactKind: String, Codable, Equatable, Hashable, Sendable {
    case macroRunEvidence
    case conditionEvidence
}

public enum AutomationRunManualDeletionScope: String, Equatable, Sendable {
    case screenshots
    case evidence
    case history
}

public enum AutomationRunManualDeletionValidationError: Error, Equatable, Sendable {
    case missingRuns([UUID])
    case activeRuns([UUID])
}

public enum AutomationRunManualDeletionPlanner {
    public static func validatedRuns(
        runs: [AutomationTaskRun],
        runIDs: Set<UUID>
    ) throws -> [AutomationTaskRun] {
        let selected = runs.filter { runIDs.contains($0.id) }
        let foundIDs = Set(selected.map(\.id))
        let missing = runIDs.subtracting(foundIDs).sorted { $0.uuidString < $1.uuidString }
        guard missing.isEmpty else {
            throw AutomationRunManualDeletionValidationError.missingRuns(missing)
        }
        let active = selected.filter { !$0.isTerminal }.map(\.id).sorted { $0.uuidString < $1.uuidString }
        guard active.isEmpty else {
            throw AutomationRunManualDeletionValidationError.activeRuns(active)
        }
        return selected
    }

    public static func plan(
        runs: [AutomationTaskRun],
        runIDs: Set<UUID>,
        scope: AutomationRunManualDeletionScope,
        evaluatedAt: Date = Date()
    ) throws -> AutomationRunRetentionPlan {
        precondition(scope != .screenshots, "Screenshot deletion does not use a retention plan")
        let selected = try validatedRuns(runs: runs, runIDs: runIDs)
        let items = selected.map { run in
            var artifactKinds: Set<AutomationRunArtifactKind> = []
            if run.evidenceID != nil || run.artifactRetention?.originalEvidenceID != nil {
                artifactKinds.insert(.macroRunEvidence)
            }
            if run.conditionEvidence?.artifacts.isEmpty == false {
                artifactKinds.insert(.conditionEvidence)
            }
            return AutomationRunRetentionPlanItem(
                runID: run.id,
                workflowID: run.workflowID,
                macroID: run.macroID,
                evidenceID: run.evidenceID ?? run.artifactRetention?.originalEvidenceID,
                activityAt: run.completedAt ?? run.actualStartTime ?? run.createdAt,
                artifactKinds: artifactKinds,
                deleteMetadata: scope == .history
            )
        }
        return AutomationRunRetentionPlan(
            evaluatedAt: evaluatedAt,
            scannedRunCount: runs.count,
            items: items,
            protectedRunReasons: [:]
        )
    }

    public static func markScreenshotsDeleted(
        runs: [AutomationTaskRun],
        runIDs: Set<UUID>
    ) throws -> [AutomationTaskRun] {
        _ = try validatedRuns(runs: runs, runIDs: runIDs)
        return runs.map { run in
            guard runIDs.contains(run.id) else { return run }
            var copy = run
            if var persistence = copy.evidencePersistence {
                persistence.screenshot = .unavailable
                copy.evidencePersistence = persistence
            }
            return copy
        }
    }
}

public struct AutomationRunRetentionPlanItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { runID }

    public var runID: UUID
    public var workflowID: UUID
    public var macroID: UUID?
    public var evidenceID: UUID?
    public var activityAt: Date
    public var artifactKinds: Set<AutomationRunArtifactKind>
    public var deleteMetadata: Bool

    public init(
        runID: UUID,
        workflowID: UUID,
        macroID: UUID?,
        evidenceID: UUID?,
        activityAt: Date,
        artifactKinds: Set<AutomationRunArtifactKind>,
        deleteMetadata: Bool
    ) {
        self.runID = runID
        self.workflowID = workflowID
        self.macroID = macroID
        self.evidenceID = evidenceID
        self.activityAt = activityAt
        self.artifactKinds = artifactKinds
        self.deleteMetadata = deleteMetadata
    }
}

public struct AutomationRunRetentionPlan: Codable, Equatable, Sendable {
    public var evaluatedAt: Date
    public var scannedRunCount: Int
    public var items: [AutomationRunRetentionPlanItem]
    public var protectedRunReasons: [UUID: Set<AutomationRunRetentionProtection>]

    public init(
        evaluatedAt: Date,
        scannedRunCount: Int,
        items: [AutomationRunRetentionPlanItem],
        protectedRunReasons: [UUID: Set<AutomationRunRetentionProtection>]
    ) {
        self.evaluatedAt = evaluatedAt
        self.scannedRunCount = max(0, scannedRunCount)
        self.items = items
        self.protectedRunReasons = protectedRunReasons
    }

    public var artifactRunCount: Int {
        items.count { !$0.artifactKinds.isEmpty }
    }

    public var metadataRunCount: Int {
        items.count(where: \.deleteMetadata)
    }
}

public enum AutomationRunRetentionPlanner {
    public static func plan(
        runs: [AutomationTaskRun],
        settings: AutomationRunRetentionSettings = AutomationRunRetentionSettings(),
        evaluatedAt: Date = Date()
    ) -> AutomationRunRetentionPlan {
        let protected = protectedRunReasons(runs: runs)
        let metadataOverflowRunIDs = metadataOverflowRunIDs(
            runs: runs,
            protectedRunReasons: protected,
            maximumRunCount: settings.maximumMetadataRunCount
        )
        let items = runs.compactMap { run -> AutomationRunRetentionPlanItem? in
            let isPendingDeletion = run.artifactRetention?.status == .pendingDeletion
            if isPendingDeletion {
                guard protected[run.id]?.contains(.active) != true else { return nil }
            } else {
                guard protected[run.id] == nil else { return nil }
            }
            let activityAt = activityDate(run)
            let age = max(0, evaluatedAt.timeIntervalSince(activityAt))
            let attention = needsAttention(run)
            let evidenceDays = attention
                ? settings.attentionEvidenceAgeDays
                : settings.successEvidenceAgeDays
            let evidenceExpired = isPendingDeletion || isExpired(
                age: age,
                days: evidenceDays
            )
            let metadataExpired = run.isTerminal && (
                isExpired(age: age, days: settings.metadataAgeDays)
                    || metadataOverflowRunIDs.contains(run.id)
            )

            var artifactKinds: Set<AutomationRunArtifactKind> = []
            if evidenceExpired,
               run.evidenceID != nil || run.artifactRetention?.originalEvidenceID != nil {
                artifactKinds.insert(.macroRunEvidence)
            }
            if evidenceExpired,
               run.conditionEvidence?.artifacts.isEmpty == false {
                artifactKinds.insert(.conditionEvidence)
            }
            guard !artifactKinds.isEmpty || metadataExpired else { return nil }

            return AutomationRunRetentionPlanItem(
                runID: run.id,
                workflowID: run.workflowID,
                macroID: run.macroID,
                evidenceID: run.evidenceID ?? run.artifactRetention?.originalEvidenceID,
                activityAt: activityAt,
                artifactKinds: artifactKinds,
                deleteMetadata: metadataExpired
            )
        }
        .sorted { left, right in
            if left.activityAt != right.activityAt { return left.activityAt < right.activityAt }
            return left.runID.uuidString < right.runID.uuidString
        }

        return AutomationRunRetentionPlan(
            evaluatedAt: evaluatedAt,
            scannedRunCount: runs.count,
            items: items,
            protectedRunReasons: protected
        )
    }

    public static func markPending(
        runs: [AutomationTaskRun],
        plan: AutomationRunRetentionPlan
    ) -> [AutomationTaskRun] {
        let itemsByRunID = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.runID, $0) })
        return runs.map { run in
            guard let item = itemsByRunID[run.id], !item.artifactKinds.isEmpty else {
                return run
            }
            var copy = run
            copy.artifactRetention = AutomationRunArtifactRetention(
                status: .pendingDeletion,
                requestedAt: plan.evaluatedAt,
                originalEvidenceID: item.evidenceID
            )
            return copy
        }
    }

    public static func markApplied(
        runs: [AutomationTaskRun],
        plan: AutomationRunRetentionPlan,
        deletedRelativePathsByRunID: [UUID: [String]]
    ) -> [AutomationTaskRun] {
        let itemsByRunID = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.runID, $0) })
        return runs.compactMap { run in
            guard let item = itemsByRunID[run.id] else { return run }
            if item.deleteMetadata { return nil }

            var copy = run
            guard !item.artifactKinds.isEmpty else { return copy }
            copy.artifactRetention = AutomationRunArtifactRetention(
                status: .pruned,
                requestedAt: copy.artifactRetention?.requestedAt ?? plan.evaluatedAt,
                completedAt: plan.evaluatedAt,
                originalEvidenceID: item.evidenceID,
                deletedRelativePaths: deletedRelativePathsByRunID[run.id] ?? []
            )
            copy.evidenceID = nil
            if var conditionEvidence = copy.conditionEvidence {
                conditionEvidence.artifacts = []
                copy.conditionEvidence = conditionEvidence
            }
            return copy
        }
    }

    private static func protectedRunReasons(
        runs: [AutomationTaskRun]
    ) -> [UUID: Set<AutomationRunRetentionProtection>] {
        var result: [UUID: Set<AutomationRunRetentionProtection>] = [:]
        for run in runs where !run.isTerminal {
            result[run.id, default: []].insert(.active)
        }

        let runsByWorkflow = Dictionary(grouping: runs, by: \.workflowID)
        for workflowRuns in runsByWorkflow.values {
            if let latestRun = workflowRuns.max(by: activityAscending) {
                let latestExecutionID = latestRun.executionID
                for run in workflowRuns where run.executionID == latestExecutionID {
                    result[run.id, default: []].insert(.latestWorkflowExecution)
                }
            }
            if let latestFailure = workflowRuns.filter(needsAttention).max(by: activityAscending) {
                result[latestFailure.id, default: []].insert(.latestWorkflowFailure)
            }
        }

        let evidenceRunsByMacro = Dictionary(grouping: runs.filter { $0.macroID != nil && $0.evidenceID != nil }) {
            $0.macroID!
        }
        for macroRuns in evidenceRunsByMacro.values {
            if let latestEvidence = macroRuns.max(by: activityAscending) {
                result[latestEvidence.id, default: []].insert(.latestMacroEvidence)
            }
        }
        return result
    }

    private static func metadataOverflowRunIDs(
        runs: [AutomationTaskRun],
        protectedRunReasons: [UUID: Set<AutomationRunRetentionProtection>],
        maximumRunCount: Int?
    ) -> Set<UUID> {
        guard let maximumRunCount else { return [] }
        let overflowCount = max(0, runs.count - maximumRunCount)
        guard overflowCount > 0 else { return [] }

        let removableRuns = runs
            .filter { $0.isTerminal && protectedRunReasons[$0.id] == nil }
            .sorted { left, right in
                let leftActivity = activityDate(left)
                let rightActivity = activityDate(right)
                if leftActivity != rightActivity { return leftActivity < rightActivity }
                return left.id.uuidString < right.id.uuidString
            }
        return Set(removableRuns.prefix(overflowCount).map(\.id))
    }

    private static func activityAscending(_ left: AutomationTaskRun, _ right: AutomationTaskRun) -> Bool {
        activityDate(left) < activityDate(right)
    }

    private static func activityDate(_ run: AutomationTaskRun) -> Date {
        run.completedAt ?? run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    private static func needsAttention(_ run: AutomationTaskRun) -> Bool {
        if run.interruption != nil { return true }
        switch run.outcome {
        case .failed, .timedOut, .resourceConflict, .permissionDenied, .missingMacro, .rejected:
            return true
        case .succeeded, .cancelled, .conditionMatched, .conditionNotMatched, nil:
            return false
        }
    }

    private static func isExpired(age: TimeInterval, days: Int?) -> Bool {
        guard let days else { return false }
        return age >= TimeInterval(days) * 24 * 60 * 60
    }
}
