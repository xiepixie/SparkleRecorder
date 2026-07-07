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

    public struct DecisionRow: Equatable, Sendable {
        public enum Tone: String, Equatable, Sendable {
            case ready
            case needsInput
            case reviewOnly
        }

        public var title: String
        public var value: String
        public var detail: String
        public var tone: Tone

        public init(
            title: String,
            value: String,
            detail: String,
            tone: Tone
        ) {
            self.title = title
            self.value = value
            self.detail = detail
            self.tone = tone
        }
    }

    public var sourceKind: SourceKind
    public var macroID: UUID?
    public var macroName: String?
    public var recordingReference: MacroSemanticRecordingReference?
    public var summary: String
    public var readinessBadges: [Badge]
    public var decisionRows: [DecisionRow]

    public init(
        sourceKind: SourceKind,
        macroID: UUID? = nil,
        macroName: String? = nil,
        recordingReference: MacroSemanticRecordingReference? = nil,
        summary: String,
        readinessBadges: [Badge],
        decisionRows: [DecisionRow]
    ) {
        self.sourceKind = sourceKind
        self.macroID = macroID
        self.macroName = macroName
        self.recordingReference = recordingReference
        self.summary = summary
        self.readinessBadges = readinessBadges
        self.decisionRows = decisionRows
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
                ],
                decisionRows: [
                    DecisionRow(
                        title: "Next step",
                        value: "Open linked review",
                        detail: "Uses the semantic recording attached to the saved macro and preselects the closest event or condition evidence when the run outcome provides a target.",
                        tone: .ready
                    ),
                    DecisionRow(
                        title: "Evidence binding",
                        value: "Macro-level",
                        detail: "This run does not yet carry a per-run semantic bundle, so review evidence is useful for repair but not accepted as live run proof.",
                        tone: .needsInput
                    ),
                    DecisionRow(
                        title: "Mutation boundary",
                        value: "Review only",
                        detail: "Opening Macro Review never mutates the workflow; reviewed changes still need Draft Preview and confirmed import.",
                        tone: .reviewOnly
                    )
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
            ],
            decisionRows: [
                DecisionRow(
                    title: "Next step",
                    value: "Choose bundle",
                    detail: "No semantic recording link was found for this macro or run; choose a bundle before reviewing frames, OCR, or visual evidence.",
                    tone: .needsInput
                ),
                DecisionRow(
                    title: "Evidence binding",
                    value: "Manual selection",
                    detail: "The selected bundle is not proven to belong to this run, so use it for local review until S2 provides a saved-macro-linked live bundle.",
                    tone: .needsInput
                ),
                DecisionRow(
                    title: "Mutation boundary",
                    value: "Review only",
                    detail: "Opening Macro Review never mutates the workflow; reviewed changes still need Draft Preview and confirmed import.",
                    tone: .reviewOnly
                )
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
