import Foundation

public enum MacroEditorRepeatUntilDraftReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelection
    case missingBody
    case multipleUntilConditions
    case missingUntilCondition
    case missingUntilText

    public var canCreate: Bool {
        self == .ready
    }
}

public struct MacroEditorRepeatUntilDraftRequest: Equatable, Sendable {
    public var sourceMacroName: String
    public var bodyMacroID: UUID
    public var bodyMacroName: String
    public var events: [RecordedEvent]
    public var groups: [ActionGroup]
    public var selectedGroupIDs: Set<UUID>
    public var maxAttempts: Int?
    public var timeoutSeconds: TimeInterval?
    public var pollingSeconds: TimeInterval?
    public var onFailure: String?

    public init(
        sourceMacroName: String,
        bodyMacroID: UUID,
        bodyMacroName: String,
        events: [RecordedEvent],
        groups: [ActionGroup],
        selectedGroupIDs: Set<UUID>,
        maxAttempts: Int? = 10,
        timeoutSeconds: TimeInterval? = 30,
        pollingSeconds: TimeInterval? = 1,
        onFailure: String? = AutomationWorkflowDraftLoopFailurePolicy.failRun
    ) {
        self.sourceMacroName = sourceMacroName
        self.bodyMacroID = bodyMacroID
        self.bodyMacroName = bodyMacroName
        self.events = events
        self.groups = groups
        self.selectedGroupIDs = selectedGroupIDs
        self.maxAttempts = maxAttempts
        self.timeoutSeconds = timeoutSeconds
        self.pollingSeconds = pollingSeconds
        self.onFailure = onFailure
    }
}

public struct MacroEditorRepeatUntilDraftPlan: Equatable, Sendable {
    public var readiness: MacroEditorRepeatUntilDraftReadiness
    public var bodyEventIndices: [Int]
    public var bodyEvents: [RecordedEvent]
    public var untilEventIndex: Int?
    public var untilCondition: AutomationWorkflowDraftCondition?
    public var untilRegion: AutomationWorkflowDraftVisualRegion?
    public var document: AutomationWorkflowDraftDocument?

    public init(
        readiness: MacroEditorRepeatUntilDraftReadiness,
        bodyEventIndices: [Int] = [],
        bodyEvents: [RecordedEvent] = [],
        untilEventIndex: Int? = nil,
        untilCondition: AutomationWorkflowDraftCondition? = nil,
        untilRegion: AutomationWorkflowDraftVisualRegion? = nil,
        document: AutomationWorkflowDraftDocument? = nil
    ) {
        self.readiness = readiness
        self.bodyEventIndices = bodyEventIndices
        self.bodyEvents = bodyEvents
        self.untilEventIndex = untilEventIndex
        self.untilCondition = untilCondition
        self.untilRegion = untilRegion
        self.document = document
    }
}

public enum MacroEditorRepeatUntilDraftBuilder {
    public static func plan(
        request: MacroEditorRepeatUntilDraftRequest
    ) -> MacroEditorRepeatUntilDraftPlan {
        let selectedGroups = request.groups.filter { request.selectedGroupIDs.contains($0.id) }
        guard !selectedGroups.isEmpty else {
            return MacroEditorRepeatUntilDraftPlan(readiness: .noSelection)
        }

        let untilGroups = selectedGroups.filter(isTextUntilGroup)
        guard untilGroups.count <= 1 else {
            return MacroEditorRepeatUntilDraftPlan(readiness: .multipleUntilConditions)
        }
        guard let untilGroup = untilGroups.first,
              let untilEventIndex = untilGroup.eventIndices.first(where: { request.events.indices.contains($0) }) else {
            return MacroEditorRepeatUntilDraftPlan(readiness: .missingUntilCondition)
        }

        let bodyEventIndices = selectedGroups
            .filter { $0.id != untilGroup.id }
            .flatMap(\.eventIndices)
            .filter { request.events.indices.contains($0) }
            .sorted()
        guard !bodyEventIndices.isEmpty else {
            return MacroEditorRepeatUntilDraftPlan(
                readiness: .missingBody,
                untilEventIndex: untilEventIndex
            )
        }

        let untilEvent = request.events[untilEventIndex]
        guard let text = untilEvent.textAnchor?.text.trimmedForMacroEditorRepeatUntil.nilIfEmptyForMacroEditorRepeatUntil else {
            return MacroEditorRepeatUntilDraftPlan(
                readiness: .missingUntilText,
                bodyEventIndices: bodyEventIndices,
                bodyEvents: normalizedBodyEvents(from: bodyEventIndices, events: request.events),
                untilEventIndex: untilEventIndex
            )
        }

        let regionKey = "editor_\(shortKey(request.bodyMacroID))_until_region"
        let untilRegion = visualRegion(for: untilEvent, key: regionKey)
        let untilCondition = AutomationWorkflowDraftCondition(
            type: "ocrText",
            text: text,
            matchMode: untilEvent.textAnchor?.matchMode ?? .contains,
            regionRef: untilRegion?.key,
            requireVisible: requireVisible(for: untilGroup, event: untilEvent)
        )
        let bodyEvents = normalizedBodyEvents(from: bodyEventIndices, events: request.events)
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "\(request.sourceMacroName) Repeat Until",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "repeat_until_\(shortKey(request.bodyMacroID))",
                        type: "loop",
                        name: "Repeat \(request.bodyMacroName)",
                        loop: AutomationWorkflowDraftLoop(
                            count: 1,
                            tasks: [
                                AutomationWorkflowDraftTask(
                                    key: "do_\(shortKey(request.bodyMacroID))",
                                    type: "macro",
                                    name: request.bodyMacroName,
                                    macroRef: AutomationWorkflowDraftMacroRef(
                                        id: request.bodyMacroID,
                                        name: request.bodyMacroName
                                    )
                                )
                            ],
                            kind: AutomationWorkflowDraftLoopKind.repeatUntil,
                            until: untilCondition,
                            maxAttempts: request.maxAttempts,
                            timeoutSeconds: request.timeoutSeconds,
                            pollingSeconds: request.pollingSeconds,
                            onFailure: request.onFailure
                        )
                    )
                ]
            ),
            visualAssets: untilRegion.map {
                AutomationWorkflowDraftVisualAssets(regions: [$0])
            }
        )

        return MacroEditorRepeatUntilDraftPlan(
            readiness: .ready,
            bodyEventIndices: bodyEventIndices,
            bodyEvents: bodyEvents,
            untilEventIndex: untilEventIndex,
            untilCondition: untilCondition,
            untilRegion: untilRegion,
            document: document
        )
    }

    public static func readiness(
        events: [RecordedEvent],
        groups: [ActionGroup],
        selectedGroupIDs: Set<UUID>
    ) -> MacroEditorRepeatUntilDraftReadiness {
        plan(request: MacroEditorRepeatUntilDraftRequest(
            sourceMacroName: "Macro",
            bodyMacroID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            bodyMacroName: "Selected Behavior",
            events: events,
            groups: groups,
            selectedGroupIDs: selectedGroupIDs
        )).readiness
    }

    private static func isTextUntilGroup(_ group: ActionGroup) -> Bool {
        switch group.kind {
        case .waitForText, .waitForTextGone, .verifyText:
            return true
        default:
            return false
        }
    }

    private static func requireVisible(for group: ActionGroup, event: RecordedEvent) -> Bool {
        switch group.kind {
        case .waitForTextGone:
            return false
        case .verifyText:
            return event.verifyMustExist ?? true
        default:
            return true
        }
    }

    private static func normalizedBodyEvents(
        from indices: [Int],
        events: [RecordedEvent]
    ) -> [RecordedEvent] {
        let selected = indices.compactMap { events.indices.contains($0) ? events[$0] : nil }
        guard let firstTime = selected.map(\.time).min() else {
            return []
        }
        return selected.map { event in
            var copy = event
            copy.time = max(0, event.time - firstTime)
            copy.behaviorGroupID = nil
            copy.behaviorGroupName = nil
            return copy
        }
    }

    private static func visualRegion(
        for event: RecordedEvent,
        key: String
    ) -> AutomationWorkflowDraftVisualRegion? {
        guard let anchor = event.textAnchor else {
            return nil
        }
        if let region = anchor.searchContentNormalizedRegion,
           region.width > 0,
           region.height > 0 {
            return AutomationWorkflowDraftVisualRegion(
                key: key,
                label: anchor.text,
                bounds: region,
                space: .contentNormalized
            )
        }
        if let region = anchor.searchRegion,
           region.width > 0,
           region.height > 0 {
            return AutomationWorkflowDraftVisualRegion(
                key: key,
                label: anchor.text,
                bounds: region,
                space: .displayAbsolute
            )
        }
        if let region = anchor.observedContentNormalizedFrame,
           region.width > 0,
           region.height > 0 {
            return AutomationWorkflowDraftVisualRegion(
                key: key,
                label: anchor.text,
                bounds: region,
                space: .contentNormalized
            )
        }
        guard anchor.observedFrame.width > 0, anchor.observedFrame.height > 0 else {
            return nil
        }
        return AutomationWorkflowDraftVisualRegion(
            key: key,
            label: anchor.text,
            bounds: anchor.observedFrame,
            space: .displayAbsolute
        )
    }

    private static func shortKey(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }
}

private extension String {
    var trimmedForMacroEditorRepeatUntil: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForMacroEditorRepeatUntil: String? {
        isEmpty ? nil : self
    }
}
