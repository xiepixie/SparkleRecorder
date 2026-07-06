import Foundation

public struct AutomationOverviewProjection: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var workflows: [AutomationWorkflowProjection]
    public var timelineItems: [AutomationResourceTimelineItem]
    public var statusCounts: [AutomationStatusCount]

    public init(
        generatedAt: Date,
        workflows: [AutomationWorkflowProjection],
        timelineItems: [AutomationResourceTimelineItem],
        statusCounts: [AutomationStatusCount]
    ) {
        self.generatedAt = generatedAt
        self.workflows = workflows
        self.timelineItems = timelineItems
        self.statusCounts = statusCounts
    }
}

public struct AutomationMacroReviewSourcePresentation: Equatable, Sendable {
    public enum SourceKind: String, Equatable, Sendable {
        case savedMacro
        case manualBundle
    }

    public struct Badge: Equatable, Sendable {
        public var title: String
        public var value: String

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    public var sourceKind: SourceKind
    public var macroID: UUID?
    public var macroName: String?
    public var recordingReference: MacroSemanticRecordingReference?
    public var summary: String
    public var readinessBadges: [Badge]

    public init(
        sourceKind: SourceKind,
        macroID: UUID? = nil,
        macroName: String? = nil,
        recordingReference: MacroSemanticRecordingReference? = nil,
        summary: String,
        readinessBadges: [Badge]
    ) {
        self.sourceKind = sourceKind
        self.macroID = macroID
        self.macroName = macroName
        self.recordingReference = recordingReference
        self.summary = summary
        self.readinessBadges = readinessBadges
    }

    public static func make(
        run: AutomationTaskRun,
        workflow: AutomationWorkflow,
        macros: [SavedMacro]
    ) -> AutomationMacroReviewSourcePresentation {
        let macroID = run.macroID ?? workflow.tasks.first { $0.id == run.taskID }?.kind.macroID
        let macro = macroID.flatMap { macroID in
            macros.first { $0.id == macroID }
        }

        if let macro, let reference = macro.semanticRecording {
            return AutomationMacroReviewSourcePresentation(
                sourceKind: .savedMacro,
                macroID: macro.id,
                macroName: macro.name,
                recordingReference: reference,
                summary: "Open the semantic recording captured with \(macro.name). It includes \(reference.eventCount) timeline events; this run does not carry a separate semantic bundle yet.",
                readinessBadges: [
                    Badge(title: "Source", value: "Saved Macro"),
                    Badge(title: "Scope", value: "Macro-level"),
                    Badge(title: "Run", value: "Not bound")
                ] + reviewTargetBadges(for: run) + [
                    Badge(title: "Fallback", value: "Bundle Picker")
                ]
            )
        }

        return AutomationMacroReviewSourcePresentation(
            sourceKind: .manualBundle,
            macroID: macro?.id ?? macroID,
            macroName: macro?.name,
            recordingReference: nil,
            summary: "Open a semantic recording bundle for frame timeline, visual evidence, region selection, and review-only draft patch generation.",
            readinessBadges: [
                Badge(title: "Source", value: "Manual"),
                Badge(title: "Scope", value: "User-picked"),
                Badge(title: "Run", value: "Not bound")
            ] + reviewTargetBadges(for: run) + [
                Badge(title: "Fallback", value: "Bundle Picker")
            ]
        )
    }

    private static func reviewTargetBadges(for run: AutomationTaskRun) -> [Badge] {
        switch run.outcome {
        case .failed(let report):
            if let failedEventIndex = report?.failedEventIndex {
                return [
                    Badge(title: "Target", value: "Event #\(failedEventIndex + 1)"),
                    Badge(title: "Evidence", value: "Failure report")
                ]
            }
            return [
                Badge(title: "Target", value: "Failed run"),
                Badge(title: "Evidence", value: "Run outcome")
            ]
        case .timedOut:
            return [
                Badge(title: "Target", value: "Condition"),
                Badge(title: "Evidence", value: "Timeout")
            ]
        case .conditionNotMatched:
            return [
                Badge(title: "Target", value: "Condition"),
                Badge(title: "Evidence", value: "Else branch")
            ]
        case .succeeded, .cancelled, .resourceConflict, .permissionDenied,
             .conditionMatched, .missingMacro, .rejected, nil:
            return []
        }
    }

    public var canRevealLinkedBundle: Bool {
        recordingReference != nil
    }

    public func buttonTitle(isOpening: Bool) -> String {
        if isOpening {
            return "Opening"
        }
        return recordingReference == nil ? "Open Review" : "Open Linked Review"
    }
}
