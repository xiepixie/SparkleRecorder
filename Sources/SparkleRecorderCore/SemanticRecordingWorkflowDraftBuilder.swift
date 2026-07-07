import Foundation

public struct SemanticRecordingWorkflowDraftBuildOptions: Equatable, Sendable {
    public var workflowName: String?
    public var maxTasks: Int
    public var includeCandidateFallback: Bool

    public init(
        workflowName: String? = nil,
        maxTasks: Int = 6,
        includeCandidateFallback: Bool = true
    ) {
        self.workflowName = workflowName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyForSemanticDraft
        self.maxTasks = max(0, maxTasks)
        self.includeCandidateFallback = includeCandidateFallback
    }
}

public enum SemanticRecordingWorkflowDraftSource: String, Codable, Equatable, Sendable {
    case suggestion
    case conditionCandidate
}

public struct SemanticRecordingWorkflowDraftItem: Codable, Equatable, Sendable {
    public var source: SemanticRecordingWorkflowDraftSource
    public var suggestionID: UUID?
    public var candidateID: String?
    public var frameID: UUID?
    public var eventID: UUID?
    public var taskKey: String?
    public var conditionType: String?
    public var action: SemanticRecordingReviewActionSemantics?

    public init(
        source: SemanticRecordingWorkflowDraftSource,
        suggestionID: UUID? = nil,
        candidateID: String? = nil,
        frameID: UUID? = nil,
        eventID: UUID? = nil,
        taskKey: String? = nil,
        conditionType: String? = nil,
        action: SemanticRecordingReviewActionSemantics? = nil
    ) {
        self.source = source
        self.suggestionID = suggestionID
        self.candidateID = candidateID
        self.frameID = frameID
        self.eventID = eventID
        self.taskKey = taskKey
        self.conditionType = conditionType
        self.action = action
    }
}

public struct SemanticRecordingWorkflowDraftSkippedItem: Codable, Equatable, Sendable {
    public var source: SemanticRecordingWorkflowDraftSource
    public var suggestionID: UUID?
    public var candidateID: String?
    public var reason: String

    public init(
        source: SemanticRecordingWorkflowDraftSource,
        suggestionID: UUID? = nil,
        candidateID: String? = nil,
        reason: String
    ) {
        self.source = source
        self.suggestionID = suggestionID
        self.candidateID = candidateID
        self.reason = reason
    }
}

public struct SemanticRecordingWorkflowDraftBuildResult: Codable, Equatable, Sendable {
    public var document: AutomationWorkflowDraftDocument
    public var validation: AutomationWorkflowDraftValidationResult
    public var suggestionCount: Int
    public var candidateCount: Int
    public var appliedItems: [SemanticRecordingWorkflowDraftItem]
    public var skippedItems: [SemanticRecordingWorkflowDraftSkippedItem]

    public init(
        document: AutomationWorkflowDraftDocument,
        validation: AutomationWorkflowDraftValidationResult,
        suggestionCount: Int,
        candidateCount: Int,
        appliedItems: [SemanticRecordingWorkflowDraftItem],
        skippedItems: [SemanticRecordingWorkflowDraftSkippedItem]
    ) {
        self.document = document
        self.validation = validation
        self.suggestionCount = suggestionCount
        self.candidateCount = candidateCount
        self.appliedItems = appliedItems
        self.skippedItems = skippedItems
    }

    public var generatedTaskCount: Int {
        document.workflow.tasks.count
    }

    public var isValid: Bool {
        validation.isValid
    }
}

public enum SemanticRecordingWorkflowDraftBuilder {
    public static func build(
        bundle: SemanticRecordingBundle,
        suggestions: [RecordingSuggestion],
        options: SemanticRecordingWorkflowDraftBuildOptions = SemanticRecordingWorkflowDraftBuildOptions()
    ) -> SemanticRecordingWorkflowDraftBuildResult {
        var document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: options.workflowName ?? defaultWorkflowName(for: bundle)
            )
        )
        var appliedItems: [SemanticRecordingWorkflowDraftItem] = []
        var skippedItems: [SemanticRecordingWorkflowDraftSkippedItem] = []
        let sortedSuggestions = suggestions.sorted(by: suggestionSort)

        for suggestion in sortedSuggestions where appliedItems.count < options.maxTasks {
            let projection = SemanticRecordingReviewProjection(bundle: bundle, suggestions: [suggestion])
            guard let suggestionRow = projection.suggestionRows.first,
                  let match = SemanticRecordingReviewSuggestionPatchResolver.makeRequest(
                      suggestion: suggestionRow,
                      bundle: bundle
                  ) else {
                skippedItems.append(SemanticRecordingWorkflowDraftSkippedItem(
                    source: .suggestion,
                    suggestionID: suggestion.id,
                    reason: "No review condition candidate matched the suggestion evidence."
                ))
                continue
            }
            apply(
                source: .suggestion,
                suggestionID: suggestion.id,
                candidateID: match.candidate.id,
                frameID: match.frameID,
                eventID: match.eventID,
                bundle: bundle,
                request: match.request,
                document: &document,
                appliedItems: &appliedItems,
                skippedItems: &skippedItems
            )
        }

        let candidates = conditionCandidateInputs(bundle: bundle)
        if appliedItems.isEmpty, options.includeCandidateFallback {
            for input in candidates where appliedItems.count < options.maxTasks {
                apply(
                    source: .conditionCandidate,
                    suggestionID: nil,
                    candidateID: input.candidate.id,
                    frameID: input.frameID,
                    eventID: input.eventID,
                    bundle: bundle,
                    request: SemanticRecordingReviewDraftPatchRequest(candidate: input.candidate),
                    document: &document,
                    appliedItems: &appliedItems,
                    skippedItems: &skippedItems
                )
            }
        }

        let validation = AutomationWorkflowDraftValidator.validate(document)
        return SemanticRecordingWorkflowDraftBuildResult(
            document: document,
            validation: validation,
            suggestionCount: suggestions.count,
            candidateCount: candidates.count,
            appliedItems: appliedItems,
            skippedItems: skippedItems
        )
    }

    private static func apply(
        source: SemanticRecordingWorkflowDraftSource,
        suggestionID: UUID?,
        candidateID: String,
        frameID: UUID?,
        eventID: UUID?,
        bundle: SemanticRecordingBundle,
        request: SemanticRecordingReviewDraftPatchRequest,
        document: inout AutomationWorkflowDraftDocument,
        appliedItems: inout [SemanticRecordingWorkflowDraftItem],
        skippedItems: inout [SemanticRecordingWorkflowDraftSkippedItem]
    ) {
        do {
            let patchResult = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
                bundle: bundle,
                request: request
            )
            let editResult = try AutomationWorkflowDraftPatchApplier.apply(
                patchResult.patch,
                to: document
            )
            document = editResult.document
            let action = SemanticRecordingReviewActionSemantics.previewDraft(patchResult)
            appliedItems.append(SemanticRecordingWorkflowDraftItem(
                source: source,
                suggestionID: suggestionID,
                candidateID: candidateID,
                frameID: frameID,
                eventID: eventID,
                taskKey: patchResult.taskKey,
                conditionType: patchResult.condition.type,
                action: action
            ))
        } catch {
            skippedItems.append(SemanticRecordingWorkflowDraftSkippedItem(
                source: source,
                suggestionID: suggestionID,
                candidateID: candidateID,
                reason: String(describing: error)
            ))
        }
    }

    private struct ConditionCandidateInput {
        var frameID: UUID
        var eventID: UUID?
        var candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    }

    private static func conditionCandidateInputs(
        bundle: SemanticRecordingBundle
    ) -> [ConditionCandidateInput] {
        bundle.frames
            .sorted(by: frameSort)
            .flatMap { frame -> [ConditionCandidateInput] in
                let projection = SemanticRecordingReviewProjection(
                    bundle: bundle,
                    selectedEventID: frame.relatedEventIDs.first,
                    selectedFrameID: frame.id
                )
                guard let selectedFrame = projection.selectedFrame else {
                    return []
                }
                return selectedFrame.conditionCandidates
                    .filter { $0.kind != .pixelMatched }
                    .sorted(by: conditionCandidateSort)
                    .prefix(1)
                    .map { candidate in
                        ConditionCandidateInput(
                            frameID: frame.id,
                            eventID: frame.relatedEventIDs.first,
                            candidate: candidate
                        )
                    }
            }
    }

    private static func defaultWorkflowName(for bundle: SemanticRecordingBundle) -> String {
        if let summary = bundle.semanticEvents.first(where: { $0.kind == .summary })?.title,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(summary) Draft"
        }
        if let windowTitle = bundle.captureTarget?.windowTitle,
           !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(windowTitle) Draft"
        }
        return "Recording \(String(bundle.id.uuidString.prefix(8)).lowercased()) Draft"
    }

    private static func suggestionSort(_ left: RecordingSuggestion, _ right: RecordingSuggestion) -> Bool {
        if left.confidence == right.confidence {
            if left.title == right.title {
                return left.id.uuidString < right.id.uuidString
            }
            return left.title < right.title
        }
        return left.confidence > right.confidence
    }

    private static func frameSort(_ left: RecordingFrameReference, _ right: RecordingFrameReference) -> Bool {
        if left.recordingTime == right.recordingTime {
            return left.id.uuidString < right.id.uuidString
        }
        return left.recordingTime < right.recordingTime
    }

    private static func conditionCandidateSort(
        _ left: SemanticRecordingReviewProjection.ConditionCandidateRow,
        _ right: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) -> Bool {
        let leftPriority = conditionCandidatePriority(left.kind)
        let rightPriority = conditionCandidatePriority(right.kind)
        if leftPriority == rightPriority {
            return left.id < right.id
        }
        return leftPriority < rightPriority
    }

    private static func conditionCandidatePriority(
        _ kind: SemanticRecordingReviewProjection.ConditionCandidateKind
    ) -> Int {
        switch kind {
        case .ocrWait:
            return 0
        case .imageAppeared:
            return 1
        case .regionChanged:
            return 2
        case .imageDisappeared:
            return 3
        case .pixelMatched:
            return 4
        }
    }
}

private extension String {
    var nilIfEmptyForSemanticDraft: String? {
        isEmpty ? nil : self
    }
}
