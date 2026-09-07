import Foundation

/// One immutable Candidate transition in the reconstruction lineage. Coverage maps
/// source action IDs to candidate action IDs authored with the literal revision
/// `candidate`; the projector translates those IDs to `targetRevision` before
/// composing multiple generations.
public struct MacroReconstructionCandidateLineageStep: Equatable, Sendable {
    public var sourceRevision: String
    public var sourceEvents: [RecordedEvent]
    public var targetRevision: String
    public var targetEvents: [RecordedEvent]
    public var coverage: [MacroCandidateCoverage]

    public init(
        sourceRevision: String,
        sourceEvents: [RecordedEvent],
        targetRevision: String,
        targetEvents: [RecordedEvent],
        coverage: [MacroCandidateCoverage]
    ) {
        self.sourceRevision = sourceRevision
        self.sourceEvents = sourceEvents
        self.targetRevision = targetRevision
        self.targetEvents = targetEvents
        self.coverage = coverage
    }
}

public enum MacroReconstructionVideoAlignmentQuality: String, Codable, Equatable, Sendable {
    /// The target action is mechanically unchanged from the recorded source action.
    case exactSource
    /// Candidate coverage proves which recorded source action(s) demonstrate the
    /// target action, but the executable action itself changed.
    case coverageMapped
    /// No safe source-to-video mapping can be established for this action.
    case unavailable
}

public struct MacroReconstructionAlignedAction: Equatable, Sendable {
    public var action: MacroReconstructedAction
    public var sourceActionIDs: [String]
    public var sessionRange: RecordingTimeRange?
    public var videoSegmentID: String?
    public var videoRange: RecordingTimeRange?
    public var startFramePoint: PointValue?
    public var endFramePoint: PointValue?
    public var quality: MacroReconstructionVideoAlignmentQuality
    public var issues: [MacroReconstructionProjectionIssue]

    public init(
        action: MacroReconstructedAction,
        sourceActionIDs: [String] = [],
        sessionRange: RecordingTimeRange? = nil,
        videoSegmentID: String? = nil,
        videoRange: RecordingTimeRange? = nil,
        startFramePoint: PointValue? = nil,
        endFramePoint: PointValue? = nil,
        quality: MacroReconstructionVideoAlignmentQuality = .unavailable,
        issues: [MacroReconstructionProjectionIssue] = []
    ) {
        self.action = action
        self.sourceActionIDs = sourceActionIDs
        self.sessionRange = sessionRange
        self.videoSegmentID = videoSegmentID
        self.videoRange = videoRange
        self.startFramePoint = startFramePoint
        self.endFramePoint = endFramePoint
        self.quality = quality
        self.issues = issues
    }

    /// Compatibility projection for the existing video index. The action remains
    /// the current/target action; only verified source evidence supplies time and
    /// measured frame points.
    public var projectedAction: MacroReconstructionProjectedAction {
        MacroReconstructionProjectedAction(
            action: action,
            sessionRange: sessionRange,
            videoSegmentID: videoSegmentID,
            videoRange: videoRange,
            startFramePoint: startFramePoint,
            endFramePoint: endFramePoint,
            issues: issues
        )
    }
}

public enum MacroReconstructionPartialAlignmentError: Error, Equatable, Sendable {
    case evidenceRevisionMismatch
    case invalidLineage
    case noLineageToTarget
}

/// Composes immutable Candidate coverage back to the source revision that owns the
/// recording provenance. It never aligns by timestamps, labels, or array position
/// alone. Missing/unresolved/cross-segment mappings fail closed per action.
public enum MacroReconstructionPartialAlignmentProjector {
    private struct Contribution: Sendable {
        var row: MacroReconstructionProjectedAction
        var quality: MacroReconstructionVideoAlignmentQuality
    }

    public static func project(
        evidenceRows: [MacroReconstructionProjectedAction],
        evidenceSourceEvents: [RecordedEvent],
        evidenceSourceRevision: String,
        targetEvents: [RecordedEvent],
        targetRevision: String,
        lineage: [MacroReconstructionCandidateLineageStep]
    ) throws -> [MacroReconstructionAlignedAction] {
        let targetActions = try MacroActionReconstructor.reconstruct(
            events: targetEvents,
            sourceRevision: targetRevision
        )
        let evidenceIDs = Set(evidenceRows.map(\.action.id))
        let evidenceActions = try MacroActionReconstructor.reconstruct(
            events: evidenceSourceEvents,
            sourceRevision: evidenceSourceRevision
        )

        // Direct source playback requires no lineage. Verify action identity instead
        // of trusting equal counts or times.
        if targetRevision == evidenceSourceRevision, Set(targetActions.map(\.id)) == evidenceIDs {
            let rowsByID = Dictionary(uniqueKeysWithValues: evidenceRows.map { ($0.action.id, $0) })
            return targetActions.map { action in
                guard let row = rowsByID[action.id] else {
                    return MacroReconstructionAlignedAction(action: action, issues: [.videoUnavailable])
                }
                return aligned(action: action, contributions: [Contribution(row: row, quality: .exactSource)])
            }
        }

        guard Set(evidenceActions.map(\.id)).isSubset(of: evidenceIDs) else {
            throw MacroReconstructionPartialAlignmentError.evidenceRevisionMismatch
        }

        let path = try lineagePath(
            from: evidenceSourceRevision,
            targetEvents: targetEvents,
            targetRevision: targetRevision,
            lineage: lineage
        )

        var contributions = Dictionary(
            uniqueKeysWithValues: evidenceRows.map { row in
                (row.action.id, [Contribution(row: row, quality: .exactSource)])
            }
        )
        var terminalEvents: [RecordedEvent] = evidenceSourceEvents
        var terminalRevision = evidenceSourceRevision

        for step in path {
            guard step.sourceRevision == terminalRevision,
                  canonical(step.sourceEvents) == canonical(terminalEvents) else {
                throw MacroReconstructionPartialAlignmentError.invalidLineage
            }
            let sourceActions = try MacroActionReconstructor.reconstruct(
                events: step.sourceEvents,
                sourceRevision: step.sourceRevision
            )
            let sourceByID = Dictionary(uniqueKeysWithValues: sourceActions.map { ($0.id, $0) })
            let literalTargets = try MacroActionReconstructor.reconstruct(
                events: step.targetEvents,
                sourceRevision: "candidate"
            )
            let actualTargets = try MacroActionReconstructor.reconstruct(
                events: step.targetEvents,
                sourceRevision: step.targetRevision
            )
            guard let literalToActual = structuralActionMap(from: literalTargets, to: actualTargets) else {
                throw MacroReconstructionPartialAlignmentError.invalidLineage
            }
            let literalByID = Dictionary(uniqueKeysWithValues: literalTargets.map { ($0.id, $0) })
            var next: [String: [Contribution]] = [:]

            for item in step.coverage {
                guard item.disposition != .removedAsNoise,
                      item.disposition != .unresolved,
                      let incoming = contributions[item.sourceActionID],
                      let sourceAction = sourceByID[item.sourceActionID] else { continue }
                for candidateID in item.candidateActionIDs {
                    guard let actualID = literalToActual[candidateID],
                          let targetAction = literalByID[candidateID] else {
                        throw MacroReconstructionPartialAlignmentError.invalidLineage
                    }
                    let exactTransition = item.disposition == .preserved
                        && item.candidateActionIDs.count == 1
                        && actionsAreMechanicallyEqual(
                            sourceAction: sourceAction,
                            sourceEvents: step.sourceEvents,
                            targetAction: targetAction,
                            targetEvents: step.targetEvents
                        )
                    let mapped = incoming.map { contribution in
                        Contribution(
                            row: contribution.row,
                            quality: exactTransition && contribution.quality == .exactSource
                                ? .exactSource
                                : .coverageMapped
                        )
                    }
                    next[actualID, default: []].append(contentsOf: mapped)
                }
            }
            contributions = next
            terminalEvents = step.targetEvents
            terminalRevision = step.targetRevision
        }

        // A later app-owned execution-setting edit can change MacroCandidateIdentity
        // without changing the action array. Translate the terminal action IDs to the
        // current revision only when the event content is mechanically identical.
        if terminalRevision != targetRevision {
            guard canonical(terminalEvents) == canonical(targetEvents) else {
                throw MacroReconstructionPartialAlignmentError.noLineageToTarget
            }
            let terminalActions = try MacroActionReconstructor.reconstruct(
                events: terminalEvents,
                sourceRevision: terminalRevision
            )
            guard let terminalToTarget = structuralActionMap(from: terminalActions, to: targetActions) else {
                throw MacroReconstructionPartialAlignmentError.invalidLineage
            }
            contributions = Dictionary(uniqueKeysWithValues: contributions.compactMap { key, value in
                guard let targetID = terminalToTarget[key] else { return nil }
                return (targetID, value)
            })
        }

        return targetActions.map { action in
            aligned(action: action, contributions: contributions[action.id] ?? [])
        }
    }

    private static func lineagePath(
        from sourceRevision: String,
        targetEvents: [RecordedEvent],
        targetRevision: String,
        lineage: [MacroReconstructionCandidateLineageStep]
    ) throws -> [MacroReconstructionCandidateLineageStep] {
        struct State {
            var revision: String
            var path: [Int]
        }
        var queue = [State(revision: sourceRevision, path: [])]
        var visited: Set<String> = [sourceRevision]
        var fallbackPath: [Int]?
        var cursor = 0
        while cursor < queue.count {
            let state = queue[cursor]
            cursor += 1
            for (index, step) in lineage.enumerated() where step.sourceRevision == state.revision {
                guard !state.path.contains(index) else { continue }
                let nextPath = state.path + [index]
                if step.targetRevision == targetRevision {
                    return nextPath.map { lineage[$0] }
                }
                if fallbackPath == nil, canonical(step.targetEvents) == canonical(targetEvents) {
                    fallbackPath = nextPath
                }
                if visited.insert(step.targetRevision).inserted {
                    queue.append(State(revision: step.targetRevision, path: nextPath))
                }
            }
        }
        if let fallbackPath {
            return fallbackPath.map { lineage[$0] }
        }
        throw MacroReconstructionPartialAlignmentError.noLineageToTarget
    }

    private static func structuralActionMap(
        from lhs: [MacroReconstructedAction],
        to rhs: [MacroReconstructedAction]
    ) -> [String: String]? {
        guard lhs.count == rhs.count else { return nil }
        var result: [String: String] = [:]
        for (left, right) in zip(lhs, rhs) {
            guard left.kind == right.kind,
                  left.sourceEventIndices == right.sourceEventIndices,
                  left.startTime.bitPattern == right.startTime.bitPattern,
                  left.endTime.bitPattern == right.endTime.bitPattern,
                  left.surfaceID == right.surfaceID,
                  left.startPoint == right.startPoint,
                  left.endPoint == right.endPoint else { return nil }
            result[left.id] = right.id
        }
        return result
    }

    private static func actionsAreMechanicallyEqual(
        sourceAction: MacroReconstructedAction,
        sourceEvents: [RecordedEvent],
        targetAction: MacroReconstructedAction,
        targetEvents: [RecordedEvent]
    ) -> Bool {
        guard sourceAction.kind == targetAction.kind,
              sourceAction.startTime.bitPattern == targetAction.startTime.bitPattern,
              sourceAction.endTime.bitPattern == targetAction.endTime.bitPattern else { return false }
        if sourceAction.sourceEventIndices.isEmpty || targetAction.sourceEventIndices.isEmpty {
            return sourceAction.sourceEventIndices.isEmpty
                && targetAction.sourceEventIndices.isEmpty
                && sourceAction.surfaceID == targetAction.surfaceID
                && sourceAction.startPoint == targetAction.startPoint
                && sourceAction.endPoint == targetAction.endPoint
        }
        let sourceSlice = sourceAction.sourceEventIndices.compactMap { sourceEvents.indices.contains($0) ? canonical(sourceEvents[$0]) : nil }
        let targetSlice = targetAction.sourceEventIndices.compactMap { targetEvents.indices.contains($0) ? canonical(targetEvents[$0]) : nil }
        return sourceSlice.count == sourceAction.sourceEventIndices.count
            && targetSlice.count == targetAction.sourceEventIndices.count
            && sourceSlice == targetSlice
    }

    private static func canonical(_ events: [RecordedEvent]) -> [RecordedEvent] {
        events.map(canonical)
    }

    private static func canonical(_ event: RecordedEvent) -> RecordedEvent {
        var copy = event
        copy.behaviorGroupID = nil
        copy.behaviorGroupName = nil
        return copy
    }

    private static func aligned(
        action: MacroReconstructedAction,
        contributions: [Contribution]
    ) -> MacroReconstructionAlignedAction {
        guard !contributions.isEmpty else {
            return MacroReconstructionAlignedAction(
                action: action,
                quality: .unavailable,
                issues: [.videoUnavailable]
            )
        }
        let ordered = contributions.sorted {
            let lhs = $0.row.videoRange?.startTime ?? $0.row.action.startTime
            let rhs = $1.row.videoRange?.startTime ?? $1.row.action.startTime
            if lhs != rhs { return lhs < rhs }
            return $0.row.action.id < $1.row.action.id
        }
        var seen = Set<String>()
        let sourceIDs = ordered.compactMap { item -> String? in
            guard seen.insert(item.row.action.id).inserted else { return nil }
            return item.row.action.id
        }
        let validVideo = ordered.compactMap { item -> (Contribution, String, RecordingTimeRange)? in
            guard let segment = item.row.videoSegmentID,
                  let range = item.row.videoRange,
                  range.startTime.isFinite,
                  range.duration.isFinite,
                  range.duration >= 0 else { return nil }
            return (item, segment, range)
        }
        let segments = Set(validVideo.map { $0.1 })
        if segments.count > 1 {
            return MacroReconstructionAlignedAction(
                action: action,
                sourceActionIDs: sourceIDs,
                quality: .unavailable,
                issues: uniqueIssues(ordered.flatMap { $0.row.issues } + [.crossesVideoSegments])
            )
        }
        guard let segment = segments.first, !validVideo.isEmpty else {
            return MacroReconstructionAlignedAction(
                action: action,
                sourceActionIDs: sourceIDs,
                quality: .unavailable,
                issues: uniqueIssues(ordered.flatMap { $0.row.issues } + [.videoUnavailable])
            )
        }
        let videoRange: RecordingTimeRange
        if validVideo.count == 1 {
            videoRange = validVideo[0].2
        } else {
            let videoStart = validVideo.map { $0.2.startTime }.min()!
            let videoEnd = validVideo.map { $0.2.startTime + $0.2.duration }.max()!
            videoRange = RecordingTimeRange(startTime: videoStart, duration: max(0, videoEnd - videoStart))
        }
        let sessionRanges = ordered.compactMap(\.row.sessionRange)
        let sessionRange: RecordingTimeRange?
        if sessionRanges.count == 1 {
            sessionRange = sessionRanges[0]
        } else if let start = sessionRanges.map(\.startTime).min(),
                  let end = sessionRanges.map({ $0.startTime + $0.duration }).max() {
            sessionRange = RecordingTimeRange(startTime: start, duration: max(0, end - start))
        } else {
            sessionRange = nil
        }
        let first = validVideo.min { $0.2.startTime < $1.2.startTime }?.0.row
        let last = validVideo.max { ($0.2.startTime + $0.2.duration) < ($1.2.startTime + $1.2.duration) }?.0.row
        let quality: MacroReconstructionVideoAlignmentQuality = ordered.allSatisfy { $0.quality == .exactSource }
            ? .exactSource
            : .coverageMapped
        return MacroReconstructionAlignedAction(
            action: action,
            sourceActionIDs: sourceIDs,
            sessionRange: sessionRange,
            videoSegmentID: segment,
            videoRange: videoRange,
            startFramePoint: first?.startFramePoint,
            endFramePoint: last?.endFramePoint,
            quality: quality,
            issues: uniqueIssues(ordered.flatMap { $0.row.issues }.filter { $0 != .videoUnavailable })
        )
    }

    private static func uniqueIssues(_ issues: [MacroReconstructionProjectionIssue]) -> [MacroReconstructionProjectionIssue] {
        var seen = Set<MacroReconstructionProjectionIssue>()
        return issues.filter { seen.insert($0).inserted }
    }
}
