import Foundation
import SparkleRecorderCore

enum MacroEditorHealthState: String, Codable, Equatable, Sendable {
    case empty
    case needsTargets
    case reviewReliability
    case ready
}

struct MacroEditorHealthSummary: Equatable, Sendable {
    var actionCount: Int
    var recordedActionCount: Int
    var textTargetCount: Int
    var missingTextTargetCount: Int
    var fixedCoordinateClickCount: Int
    var longWaitCount: Int
    var behaviorCount: Int

    var state: MacroEditorHealthState {
        guard actionCount > 0 else { return .empty }
        if missingTextTargetCount > 0 { return .needsTargets }
        if fixedCoordinateClickCount > 0 || longWaitCount > 0 { return .reviewReliability }
        return .ready
    }
}

enum MacroEditorGuidancePriority: Int, Codable, Equatable, Comparable, Sendable {
    case blocking = 0
    case next = 1
    case improve = 2
    case done = 3

    static func < (lhs: MacroEditorGuidancePriority, rhs: MacroEditorGuidancePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MacroEditorGuidanceKind: String, Codable, Equatable, Sendable {
    case empty
    case missingTextTarget
    case repeatUntilReady
    case behaviorReady
    case fixedCoordinateClicks
    case longWaits
    case ready
}

enum MacroEditorGuidanceAction: Equatable, Sendable {
    case none
    case selectGroups([UUID])
    case pickText([UUID])
    case createBehavior
    case createRepeatUntil
}

struct MacroEditorGuidanceItem: Identifiable, Equatable, Sendable {
    var kind: MacroEditorGuidanceKind
    var priority: MacroEditorGuidancePriority
    var title: String
    var detail: String
    var systemImage: String
    var actionTitle: String?
    var action: MacroEditorGuidanceAction

    var id: String { kind.rawValue }
}

func macroEditorHealthSummary(
    for groups: [ActionGroup],
    events: [RecordedEvent],
    longWaitThreshold: TimeInterval = 2.0
) -> MacroEditorHealthSummary {
    let actionGroups = groups.filter { $0.kind != .mouseMove }
    let textTargetGroups = actionGroups.filter {
        ActionGroupProjection.isTextTargetGroup(
            $0,
            events: events,
            includesCoordinateClickCandidates: false
        )
    }
    let missingTargets = textTargetGroups.filter {
        ActionGroupProjection.textTargetReadiness(
            for: $0,
            events: events,
            includesCoordinateClickCandidates: false
        ).needsUserTarget
    }
    let fixedCoordinateClicks = actionGroups.filter {
        macroEditorGuidanceIsFixedCoordinateClick($0, events: events)
    }
    let longWaits = actionGroups.filter {
        $0.kind == .wait && $0.duration >= longWaitThreshold
    }
    let behaviorIDs = Set(actionGroups.compactMap(\.behaviorGroupID))

    return MacroEditorHealthSummary(
        actionCount: actionGroups.count,
        recordedActionCount: actionGroups.filter { !$0.eventIndices.isEmpty }.count,
        textTargetCount: textTargetGroups.count,
        missingTextTargetCount: missingTargets.count,
        fixedCoordinateClickCount: fixedCoordinateClicks.count,
        longWaitCount: longWaits.count,
        behaviorCount: behaviorIDs.count
    )
}

func macroEditorGuidanceItems(
    for groups: [ActionGroup],
    events: [RecordedEvent],
    selectedGroupIDs: Set<UUID>,
    repeatUntilReadiness: MacroEditorRepeatUntilDraftReadiness,
    longWaitThreshold: TimeInterval = 2.0
) -> [MacroEditorGuidanceItem] {
    let actionGroups = groups.filter { $0.kind != .mouseMove }
    let summary = macroEditorHealthSummary(
        for: actionGroups,
        events: events,
        longWaitThreshold: longWaitThreshold
    )

    guard summary.actionCount > 0 else {
        return [
            MacroEditorGuidanceItem(
                kind: .empty,
                priority: .next,
                title: String(localized: "Record or insert an action", table: "Recording"),
                detail: String(localized: "The editor is ready for the first macro action.", table: "EditorUX"),
                systemImage: "record.circle",
                actionTitle: nil,
                action: .none
            )
        ]
    }

    var items: [MacroEditorGuidanceItem] = []
    let missingTextTargets = actionGroups.filter {
        ActionGroupProjection.textTargetReadiness(
            for: $0,
            events: events,
            includesCoordinateClickCandidates: false
        ).needsUserTarget
    }
    if let first = missingTextTargets.first {
        let indices = missingTextTargets.compactMap { tg in groups.firstIndex(where: { $0.id == tg.id }).map { "**#\($0 + 1)**" } }
        let indicesList = indices.joined(separator: ", ")
        items.append(
            MacroEditorGuidanceItem(
                kind: .missingTextTarget,
                priority: .blocking,
                title: String(
                    format: String(localized: "Text targets need review (%d)", table: "EditorUX"),
                    missingTextTargets.count
                ),
                detail: String(
                    format: String(localized: "Text waits and text clicks need a target. Pending: %@", table: "EditorUX"),
                    indicesList
                ),
                systemImage: "text.viewfinder",
                actionTitle: String(localized: "Pick First", table: "Common"),
                action: .pickText([first.id])
            )
        )
    }

    if repeatUntilReadiness.canCreate {
        items.append(
            MacroEditorGuidanceItem(
                kind: .repeatUntilReady,
                priority: .next,
                title: String(localized: "Repeat Until is ready", table: "Common"),
                detail: String(localized: "The selected body and text condition can become a bounded loop preview.", table: "Automation"),
                systemImage: "arrow.triangle.2.circlepath",
                actionTitle: String(localized: "Preview", table: "Common"),
                action: .createRepeatUntil
            )
        )
    } else {
        let snapshot = ActionGroupProjection.selectionSnapshot(
            groups: actionGroups,
            selectedGroupIDs: selectedGroupIDs,
            events: events
        )
        if snapshot.canBindBehavior {
            items.append(
                MacroEditorGuidanceItem(
                    kind: .behaviorReady,
                    priority: .next,
                    title: String(localized: "Behavior selection is ready", table: "Common"),
                    detail: String(localized: "The selected actions can be kept together as one reusable block.", table: "EditorUX"),
                    systemImage: "square.stack.3d.down.right",
                    actionTitle: String(localized: "Create", table: "Common"),
                    action: .createBehavior
                )
            )
        }
    }

    let fixedCoordinateClicks = actionGroups.filter {
        macroEditorGuidanceIsFixedCoordinateClick($0, events: events)
    }
    if let first = fixedCoordinateClicks.first {
        let indices = fixedCoordinateClicks.compactMap { tg in groups.firstIndex(where: { $0.id == tg.id }).map { "**#\($0 + 1)**" } }
        let indicesList = indices.joined(separator: ", ")
        items.append(
            MacroEditorGuidanceItem(
                kind: .fixedCoordinateClicks,
                priority: .improve,
                title: String(
                    format: String(localized: "Fixed clicks to check (%d)", table: "EditorUX"),
                    fixedCoordinateClicks.count
                ),
                detail: String(
                    format: String(localized: "Coordinate clicks are less reliable than text clicks. Pending: %@", table: "EditorUX"),
                    indicesList
                ),
                systemImage: "cursorarrow.motionlines.click",
                actionTitle: String(localized: "Bind First", table: "Common"),
                action: .pickText([first.id])
            )
        )
    }

    let longWaits = actionGroups.filter { $0.kind == .wait && $0.duration >= longWaitThreshold }
    if let first = longWaits.first {
        let indices = longWaits.compactMap { tg in groups.firstIndex(where: { $0.id == tg.id }).map { "**#\($0 + 1)**" } }
        let indicesList = indices.joined(separator: ", ")
        items.append(
            MacroEditorGuidanceItem(
                kind: .longWaits,
                priority: .improve,
                title: String(
                    format: String(localized: "Long waits to review (%d)", table: "EditorUX"),
                    longWaits.count
                ),
                detail: String(
                    format: String(localized: "Long delays may be better as a Wait Text. Pending: %@", table: "EditorUX"),
                    indicesList
                ),
                systemImage: "hourglass.badge.exclamationmark",
                actionTitle: String(localized: "Select First", table: "Common"),
                action: .selectGroups([first.id])
            )
        )
    }

    if items.isEmpty {
        items.append(
            MacroEditorGuidanceItem(
                kind: .ready,
                priority: .done,
                title: String(localized: "Ready to test", table: "Common"),
                detail: String(localized: "Text targets are set and no long waits or fixed clicks need immediate review.", table: "EditorUX"),
                systemImage: "checkmark.seal",
                actionTitle: nil,
                action: .none
            )
        )
    }

    return items.sorted {
        if $0.priority != $1.priority {
            return $0.priority < $1.priority
        }
        return $0.kind.rawValue < $1.kind.rawValue
    }
}

func macroEditorHealthTitle(_ summary: MacroEditorHealthSummary) -> String {
    switch summary.state {
    case .empty:
        return String(localized: "No actions", table: "EditorUX")
    case .needsTargets:
        return String(localized: "Needs targets", table: "Common")
    case .reviewReliability:
        return String(localized: "Review reliability", table: "Common")
    case .ready:
        return String(localized: "Ready to test", table: "Common")
    }
}

func macroEditorHealthDetail(_ summary: MacroEditorHealthSummary) -> String {
    switch summary.state {
    case .empty:
        return String(localized: "Record or insert the first action.", table: "Recording")
    case .needsTargets:
        return String(
            format: String(localized: "Text targets need attention before reliable playback: %d.", table: "EditorUX"),
            summary.missingTextTargetCount
        )
    case .reviewReliability:
        return String(
            format: String(localized: "%d fixed clicks and %d long waits may need cleanup.", table: "EditorUX"),
            summary.fixedCoordinateClickCount,
            summary.longWaitCount
        )
    case .ready:
        return String(localized: "The macro is ready for a playback test.", table: "EditorUX")
    }
}

func macroEditorGuidanceIsFixedCoordinateClick(
    _ group: ActionGroup,
    events: [RecordedEvent]
) -> Bool {
    guard group.kind.isClickFamily, group.kind != .multiPointClick else {
        return false
    }
    let readiness = ActionGroupProjection.textTargetReadiness(
        for: group,
        events: events,
        includesCoordinateClickCandidates: true
    )
    return readiness == .missingAnchor
}
