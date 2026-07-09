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
                title: NSLocalizedString("Record or insert an action", comment: ""),
                detail: NSLocalizedString("The editor is ready for the first macro action.", comment: ""),
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
                    format: NSLocalizedString("Text targets need review (%d)", comment: ""),
                    missingTextTargets.count
                ),
                detail: String(
                    format: NSLocalizedString("Text waits and text clicks need a target. Pending: %@", comment: ""),
                    indicesList
                ),
                systemImage: "text.viewfinder",
                actionTitle: NSLocalizedString("Pick First", comment: ""),
                action: .pickText([first.id])
            )
        )
    }

    if repeatUntilReadiness.canCreate {
        items.append(
            MacroEditorGuidanceItem(
                kind: .repeatUntilReady,
                priority: .next,
                title: NSLocalizedString("Repeat Until is ready", comment: ""),
                detail: NSLocalizedString("The selected body and text condition can become a bounded loop preview.", comment: ""),
                systemImage: "arrow.triangle.2.circlepath",
                actionTitle: NSLocalizedString("Preview", comment: ""),
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
                    title: NSLocalizedString("Behavior selection is ready", comment: ""),
                    detail: NSLocalizedString("The selected actions can be kept together as one reusable block.", comment: ""),
                    systemImage: "square.stack.3d.down.right",
                    actionTitle: NSLocalizedString("Create", comment: ""),
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
                    format: NSLocalizedString("Fixed clicks to check (%d)", comment: ""),
                    fixedCoordinateClicks.count
                ),
                detail: String(
                    format: NSLocalizedString("Coordinate clicks are less reliable than text clicks. Pending: %@", comment: ""),
                    indicesList
                ),
                systemImage: "cursorarrow.motionlines.click",
                actionTitle: NSLocalizedString("Bind First", comment: ""),
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
                    format: NSLocalizedString("Long waits to review (%d)", comment: ""),
                    longWaits.count
                ),
                detail: String(
                    format: NSLocalizedString("Long delays may be better as a Wait Text. Pending: %@", comment: ""),
                    indicesList
                ),
                systemImage: "hourglass.badge.exclamationmark",
                actionTitle: NSLocalizedString("Select First", comment: ""),
                action: .selectGroups([first.id])
            )
        )
    }

    if items.isEmpty {
        items.append(
            MacroEditorGuidanceItem(
                kind: .ready,
                priority: .done,
                title: NSLocalizedString("Ready to test", comment: ""),
                detail: NSLocalizedString("Text targets are set and no long waits or fixed clicks need immediate review.", comment: ""),
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
        return NSLocalizedString("No actions", comment: "")
    case .needsTargets:
        return NSLocalizedString("Needs targets", comment: "")
    case .reviewReliability:
        return NSLocalizedString("Review reliability", comment: "")
    case .ready:
        return NSLocalizedString("Ready to test", comment: "")
    }
}

func macroEditorHealthDetail(_ summary: MacroEditorHealthSummary) -> String {
    switch summary.state {
    case .empty:
        return NSLocalizedString("Record or insert the first action.", comment: "")
    case .needsTargets:
        return String(
            format: NSLocalizedString("Text targets need attention before reliable playback: %d.", comment: ""),
            summary.missingTextTargetCount
        )
    case .reviewReliability:
        return String(
            format: NSLocalizedString("%d fixed clicks and %d long waits may need cleanup.", comment: ""),
            summary.fixedCoordinateClickCount,
            summary.longWaitCount
        )
    case .ready:
        return NSLocalizedString("The macro is ready for a playback test.", comment: "")
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
