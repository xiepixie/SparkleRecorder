import Foundation
import CoreGraphics

public enum ActionGroupKind: String, Codable, Sendable {
    case click
    case doubleClick
    case longPress
    case drag
    case scroll
    case keyPress
    case keyHold
    case keyRepeat
    case shortcut
    case modifierHold
    case textInput
    case wait
    case mouseMove
    case waitForText
    case waitForTextGone
    case verifyText
    case repeatedClick
    case multiPointClick
    case sequence
}

public struct EventGroupingOptions: Codable, Equatable, Sendable {
    public var clickMoveTolerance: CGFloat = 5
    public var dragDistanceThreshold: CGFloat = 8
    public var longPressThreshold: TimeInterval = 0.35
    public var keyHoldThreshold: TimeInterval = 0.35
    public var scrollBurstGap: TimeInterval = 0.18
    public var scrollPositionTolerance: CGFloat = 40
    public var scrollSegmentGap: TimeInterval = 0.55
    public var scrollSegmentPositionTolerance: CGFloat = 180
    public var waitThreshold: TimeInterval = 0.200
    public var maxGestureDuration: TimeInterval = 30.0
    /// Maximum direct gap between clicks to merge them into a multi-click (double/triple).
    /// A derived wait row always breaks click merging, even when the gap is shorter than this value.
    public var clickMergeGap: TimeInterval = 0.45
    /// Maximum distance between click positions to allow merging
    public var clickMergeDistance: CGFloat = 20
    /// Maximum gap between distinct click targets to present them as one near-simultaneous action.
    public var multiPointClickGap: TimeInterval = 0.12
    /// Disable all gesture/action grouping and return raw events
    public var disableGrouping: Bool = false
    
    public init() {}
}

public struct ActionGroup: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ActionGroupKind
    public var eventIndices: [Int]

    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var duration: TimeInterval { endTime - startTime }

    public var startPoint: CGPoint?
    public var endPoint: CGPoint?
    public var path: [CGPoint]

    public var keyCode: UInt16?
    public var keyFlags: UInt64?
    public var unicodeString: String?
    public var mouseButton: Int64?

    public var scrollDeltaX: Int32?
    public var scrollDeltaY: Int32?
    public var scrollPayload: ScrollPayload?

    public var summary: String
    /// Number of clicks (1 = single, 2 = double, 3 = triple, etc.)
    public var clickCount: Int
    
    // Phase 8 properties
    public var textAnchor: TextAnchor?
    public var textTimeout: TimeInterval?
    public var verifyMustExist: Bool?
    public var textTargetReadiness: TextTargetReadiness
    public var behaviorGroupID: BehaviorGroupID?
    public var behaviorGroupName: String?
    public var containedActionCount: Int?
    
    public init(
        id: UUID = UUID(),
        kind: ActionGroupKind,
        eventIndices: [Int],
        startTime: TimeInterval,
        endTime: TimeInterval,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        path: [CGPoint] = [],
        keyCode: UInt16? = nil,
        keyFlags: UInt64? = nil,
        unicodeString: String? = nil,
        mouseButton: Int64? = nil,
        scrollDeltaX: Int32? = nil,
        scrollDeltaY: Int32? = nil,
        scrollPayload: ScrollPayload? = nil,
        summary: String,
        clickCount: Int = 1,
        textAnchor: TextAnchor? = nil,
        textTimeout: TimeInterval? = nil,
        verifyMustExist: Bool? = nil,
        textTargetReadiness: TextTargetReadiness = .notTextTarget,
        behaviorGroupID: BehaviorGroupID? = nil,
        behaviorGroupName: String? = nil,
        containedActionCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.eventIndices = eventIndices
        self.startTime = startTime
        self.endTime = endTime
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.path = path
        self.keyCode = keyCode
        self.keyFlags = keyFlags
        self.unicodeString = unicodeString
        self.mouseButton = mouseButton
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.scrollPayload = scrollPayload
        self.summary = summary
        self.clickCount = clickCount
        self.textAnchor = textAnchor
        self.textTimeout = textTimeout
        self.verifyMustExist = verifyMustExist
        self.textTargetReadiness = textTargetReadiness
        self.behaviorGroupID = behaviorGroupID
        self.behaviorGroupName = behaviorGroupName
        self.containedActionCount = containedActionCount
    }
}

public struct EventGrouper: Sendable {
    public let options: EventGroupingOptions

    public init(options: EventGroupingOptions = EventGroupingOptions()) {
        self.options = options
    }

    public func group(_ events: [RecordedEvent], liveDuration: TimeInterval? = nil) -> [ActionGroup] {
        guard !events.isEmpty else { return [] }
        
        if options.disableGrouping {
            var groups: [ActionGroup] = []
            for (i, ev) in events.enumerated() {
                if i > 0 {
                    let prevEv = events[i-1]
                    let gap = ev.time - prevEv.time
                    if gap > options.waitThreshold {
                        groups.append(ActionGroup(
                            id: deterministicUUID(from: "wait-\(prevEv.time)-\(ev.time)"),
                            kind: .wait,
                            eventIndices: [],
                            startTime: prevEv.time,
                            endTime: ev.time,
                            summary: String(format: NSLocalizedString("Wait %.2fs", comment: ""), gap)
                        ))
                    }
                }
                
                let kind: ActionGroupKind
                switch ev.kind {
                case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
                    kind = .click
                case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                    kind = .drag
                case .mouseMoved:
                    kind = .mouseMove
                case .scrollWheel:
                    kind = .scroll
                case .keyDown, .keyUp:
                    kind = .keyPress
                case .flagsChanged:
                    kind = .keyPress
                case .waitForText:
                    kind = ev.verifyMustExist == false ? .waitForTextGone : .waitForText
                case .verifyText:
                    kind = .verifyText
                }
                
                // Construct a simple raw event name
                let name: String
                if ev.kind.isKey {
                    let nameStr = ev.unicodeString ?? keyName(ev.keyCode) ?? "Key \(ev.keyCode)"
                    let keyLabel = ev.kind == .keyDown ? NSLocalizedString("Key Down", comment: "") : (ev.kind == .keyUp ? NSLocalizedString("Key Up", comment: "") : NSLocalizedString("Modifier", comment: ""))
                    name = "\(keyLabel) (\(nameStr))"
                } else {
                    name = localizedEventKindName(ev.kind)
                }
                
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "raw-\(ev.kind.rawValue)-\(ev.time)-\(i)"),
                    kind: kind,
                    eventIndices: [i],
                    startTime: ev.time,
                    endTime: ev.time,
                    startPoint: ev.kind.isMouse ? CGPoint(x: ev.x, y: ev.y) : nil,
                    keyCode: ev.kind.isKey ? ev.keyCode : nil,
                    keyFlags: ev.kind.isKey ? ev.flags : nil,
                    unicodeString: ev.kind.isKey ? ev.unicodeString : nil,
                    mouseButton: ev.kind.isMouse ? ev.mouseButton : nil,
                    scrollPayload: ev.scrollPayload,
                    summary: name,
                    textAnchor: ev.textAnchor,
                    textTimeout: ev.textTimeout,
                    verifyMustExist: ev.verifyMustExist
                ))
            }
            
            if let live = liveDuration, !groups.isEmpty {
                let lastEv = events.last!
                let gap = live - lastEv.time
                if gap > options.waitThreshold {
                    groups.append(ActionGroup(
                        id: deterministicUUID(from: "wait-\(lastEv.time)-\(live)"),
                        kind: .wait,
                        eventIndices: [],
                        startTime: lastEv.time,
                        endTime: live,
                        summary: String(format: NSLocalizedString("Wait %.2fs", comment: ""), gap)
                    ))
                }
            }
            return mergeBehaviorGroups(groups, events: events)
        }
        
        var groups: [ActionGroup] = []
        
        var i = 0
        while i < events.count {
            // Check for gap (Wait group)
            if !groups.isEmpty {
                let prevGroup = groups.last!
                let gap = events[i].time - prevGroup.endTime
                if gap > options.waitThreshold {
                    groups.append(ActionGroup(
                        id: deterministicUUID(from: "wait-\(prevGroup.endTime)-\(events[i].time)"),
                        kind: .wait,
                        eventIndices: [],
                        startTime: prevGroup.endTime,
                        endTime: events[i].time,
                        summary: String(format: NSLocalizedString("Wait %.2fs", comment: ""), gap)
                    ))
                }
            }
            
            let ev = events[i]
            
            // 0. Modifier-led Shortcut or Modifier Hold
            if ev.kind == .flagsChanged {
                if let grouped = groupModifierGesture(events, startingAt: i) {
                    groups.append(grouped.group)
                    i = grouped.nextIndex
                    continue
                }
            }
            
            // 1. Mouse Drag, LongPress or Click Gesture (Strict state machine)
            if ev.kind == .leftMouseDown || ev.kind == .rightMouseDown || ev.kind == .otherMouseDown {
                let startIdx = i
                var lastIdx = i
                var dragPoints: [CGPoint] = [CGPoint(x: ev.x, y: ev.y)]
                var sawDraggedEvent = false
                let dragKind: RecordedEvent.Kind
                let upKind: RecordedEvent.Kind
                if ev.kind == .leftMouseDown {
                    dragKind = .leftMouseDragged
                    upKind = .leftMouseUp
                } else if ev.kind == .rightMouseDown {
                    dragKind = .rightMouseDragged
                    upKind = .rightMouseUp
                } else {
                    dragKind = .otherMouseDragged
                    upKind = .otherMouseUp
                }
                
                var j = i + 1
                while j < events.count {
                    let next = events[j]
                    
                    if next.time - ev.time > options.maxGestureDuration {
                        break
                    }
                    
                    if next.kind == dragKind && next.mouseButton == ev.mouseButton {
                        sawDraggedEvent = true
                        dragPoints.append(CGPoint(x: next.x, y: next.y))
                        lastIdx = j
                        j += 1
                    } else if next.kind == upKind && next.mouseButton == ev.mouseButton {
                        dragPoints.append(CGPoint(x: next.x, y: next.y))
                        lastIdx = j
                        j += 1
                        break
                    } else {
                        break
                    }
                }
                
                let indices = Array(startIdx...lastIdx)
                let startEv = events[startIdx]
                let endEv = events[lastIdx]
                let distance = dragPoints.count > 1 ? hypot(dragPoints.last!.x - dragPoints.first!.x, dragPoints.last!.y - dragPoints.first!.y) : 0
                let duration = endEv.time - startEv.time
                
                let kind: ActionGroupKind
                let summary: String
                
                if sawDraggedEvent && distance > options.clickMoveTolerance {
                    kind = .drag
                    summary = String(format: NSLocalizedString("Drag from (%d, %d) to (%d, %d)", comment: ""), Int(startEv.x), Int(startEv.y), Int(endEv.x), Int(endEv.y))
                } else if distance > options.dragDistanceThreshold {
                    kind = .drag
                    summary = String(format: NSLocalizedString("Drag from (%d, %d) to (%d, %d)", comment: ""), Int(startEv.x), Int(startEv.y), Int(endEv.x), Int(endEv.y))
                } else if duration >= options.longPressThreshold {
                    kind = .longPress
                    let btnName = mouseButtonName(kind: ev.kind, button: ev.mouseButton)
                    summary = String(format: NSLocalizedString("Long Press (%@) at (%d, %d)", comment: ""), btnName, Int(startEv.x), Int(startEv.y))
                } else {
                    kind = .click
                    let btnName = mouseButtonName(kind: ev.kind, button: ev.mouseButton)
                    if startEv.coordinateStrategy == .locatorOnly || startEv.textAnchor != nil {
                        let text = startEv.textAnchor?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        summary = text.isEmpty
                            ? NSLocalizedString("Click text (needs text)", comment: "")
                            : String(format: NSLocalizedString("Click text: %@", comment: ""), text)
                    } else {
                        summary = String(format: NSLocalizedString("%@ Click at (%d, %d)", comment: ""), btnName, Int(startEv.x), Int(startEv.y))
                    }
                }
                
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "mouse-\(kind.rawValue)-\(startEv.time)-\(endEv.time)-\(indices.first ?? 0)-\(indices.last ?? 0)"),
                    kind: kind,
                    eventIndices: indices,
                    startTime: startEv.time,
                    endTime: endEv.time,
                    startPoint: CGPoint(x: startEv.x, y: startEv.y),
                    endPoint: CGPoint(x: endEv.x, y: endEv.y),
                    path: dragPoints,
                    mouseButton: ev.mouseButton,
                    summary: summary,
                    clickCount: max(1, Int(startEv.clickCount)),
                    textAnchor: startEv.textAnchor,
                    textTimeout: startEv.textTimeout,
                    verifyMustExist: startEv.verifyMustExist,
                    textTargetReadiness: (startEv.coordinateStrategy == .locatorOnly || startEv.textAnchor != nil)
                        ? textTargetReadiness(for: startEv.textAnchor)
                        : .notTextTarget
                ))
                
                i = j
                continue
            }
            
            // 2. Scroll Burst
            if ev.kind == .scrollWheel {
                let startIdx = i
                var lastIdx = i
                var totalDX: Int32 = ev.scrollDeltaX
                var totalDY: Int32 = ev.scrollDeltaY
                
                var j = i + 1
                while j < events.count {
                    let next = events[j]
                    guard next.kind == .scrollWheel else { break }
                    guard (next.time - events[lastIdx].time) <= options.scrollBurstGap else { break }
                    guard hypot(next.x - ev.x, next.y - ev.y) <= options.scrollPositionTolerance else { break }
                    
                    let verticalCompatible = (ev.scrollDeltaY == 0 && next.scrollDeltaY == 0) || (ev.scrollDeltaY > 0 && next.scrollDeltaY > 0) || (ev.scrollDeltaY < 0 && next.scrollDeltaY < 0)
                    let horizontalCompatible = (ev.scrollDeltaX == 0 && next.scrollDeltaX == 0) || (ev.scrollDeltaX > 0 && next.scrollDeltaX > 0) || (ev.scrollDeltaX < 0 && next.scrollDeltaX < 0)
                    guard verticalCompatible && horizontalCompatible else { break }
                    
                    totalDX += next.scrollDeltaX
                    totalDY += next.scrollDeltaY
                    lastIdx = j
                    j += 1
                }
                
                let indices = Array(startIdx...lastIdx)
                let startEv = events[startIdx]
                let endEv = events[lastIdx]
                
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "scroll-\(startEv.time)-\(endEv.time)-\(indices.first ?? 0)-\(indices.last ?? 0)-\(totalDX)-\(totalDY)"),
                    kind: .scroll,
                    eventIndices: indices,
                    startTime: startEv.time,
                    endTime: endEv.time,
                    startPoint: CGPoint(x: startEv.x, y: startEv.y),
                    scrollDeltaX: totalDX,
                    scrollDeltaY: totalDY,
                    scrollPayload: aggregateScrollPayload(Array(events[startIdx...lastIdx])),
                    summary: String(format: NSLocalizedString("Scroll (dy: %d, dx: %d)", comment: ""), totalDY, totalDX)
                ))
                
                i = j
                continue
            }
            
            // 3. Key Press (KeyDown + KeyUp pair)
            if ev.kind == .keyDown {
                if hasShortcutModifier(ev.flags) {
                    if let grouped = groupShortcutFromKeyDown(events, startingAt: i) {
                        groups.append(grouped.group)
                        i = grouped.nextIndex
                        continue
                    }
                }
                
                let startIdx = i
                var lastIdx = i
                var repeatCount = 0
                
                var j = i + 1
                while j < events.count {
                    let next = events[j]
                    if next.time - ev.time > options.maxGestureDuration {
                        break
                    }
                    if next.kind == .keyDown && next.keyCode == ev.keyCode {
                        repeatCount += 1
                        lastIdx = j
                        j += 1
                    } else if next.kind == .keyUp && next.keyCode == ev.keyCode {
                        lastIdx = j
                        j += 1
                        break
                    } else if next.kind == .flagsChanged || (next.kind == .keyDown && next.keyCode != ev.keyCode) || (next.kind == .keyUp && next.keyCode != ev.keyCode) {
                        lastIdx = j
                        j += 1
                    } else {
                        break
                    }
                }
                
                let indices = Array(startIdx...lastIdx)
                let startEv = events[startIdx]
                let endEv = events[lastIdx]
                let name = startEv.unicodeString ?? keyName(ev.keyCode) ?? "Code \(ev.keyCode)"
                let duration = endEv.time - startEv.time
                
                let kind: ActionGroupKind
                let summary: String
                if repeatCount > 0 {
                    kind = .keyRepeat
                    summary = String(format: NSLocalizedString("Repeat key: %@ (%d repeats)", comment: ""), name, repeatCount)
                } else if duration >= options.keyHoldThreshold {
                    kind = .keyHold
                    summary = String(format: NSLocalizedString("Hold key: %@ (%.2fs)", comment: ""), name, duration)
                } else {
                    kind = .keyPress
                    summary = String(format: NSLocalizedString("Press key: %@", comment: ""), name)
                }
                
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "key-\(kind.rawValue)-\(startEv.time)-\(endEv.time)-\(indices.first ?? 0)-\(indices.last ?? 0)-\(ev.keyCode)"),
                    kind: kind,
                    eventIndices: indices,
                    startTime: startEv.time,
                    endTime: endEv.time,
                    keyCode: ev.keyCode,
                    keyFlags: ev.flags,
                    unicodeString: startEv.unicodeString,
                    summary: summary
                ))
                
                i = j
                continue
            }
            
            // 3.5. Mouse Move Burst (consecutive mouse moves)
            if ev.kind == .mouseMoved {
                let startIdx = i
                var lastIdx = i
                var movePoints: [CGPoint] = [CGPoint(x: ev.x, y: ev.y)]
                
                var j = i + 1
                while j < events.count {
                    let next = events[j]
                    guard next.kind == .mouseMoved else { break }
                    guard (next.time - events[lastIdx].time) <= options.scrollBurstGap else { break }
                    
                    movePoints.append(CGPoint(x: next.x, y: next.y))
                    lastIdx = j
                    j += 1
                }
                
                let indices = Array(startIdx...lastIdx)
                let startEv = events[startIdx]
                let endEv = events[lastIdx]
                
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "mousemove-\(startEv.time)-\(endEv.time)-\(indices.first ?? 0)-\(indices.last ?? 0)"),
                    kind: .mouseMove,
                    eventIndices: indices,
                    startTime: startEv.time,
                    endTime: endEv.time,
                    startPoint: CGPoint(x: startEv.x, y: startEv.y),
                    endPoint: CGPoint(x: endEv.x, y: endEv.y),
                    path: movePoints,
                    summary: String(format: NSLocalizedString("Move to (%d, %d)", comment: ""), Int(endEv.x), Int(endEv.y))
                ))
                
                i = j
                continue
            }
            
            // 4. Default Fallback
            let name: String
            let kind: ActionGroupKind
            if ev.kind == .flagsChanged {
                name = String(format: NSLocalizedString("Modifiers changed: 0x%02X", comment: ""), ev.flags)
                kind = .keyPress
            } else if ev.kind == .keyUp {
                let nameStr = ev.unicodeString ?? keyName(ev.keyCode) ?? "Code \(ev.keyCode)"
                name = String(format: NSLocalizedString("Key Release: %@", comment: ""), nameStr)
                kind = .keyPress
            } else if ev.kind == .mouseMoved {
                name = String(format: NSLocalizedString("Move to (%d, %d)", comment: ""), Int(ev.x), Int(ev.y))
                kind = .mouseMove
            } else if ev.kind == .waitForText {
                let mustExist = ev.verifyMustExist ?? true
                if let text = ev.textAnchor?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    name = mustExist
                        ? String(format: NSLocalizedString("Wait Text: %@", comment: ""), text)
                        : String(format: NSLocalizedString("Wait Text Gone: %@", comment: ""), text)
                } else {
                    name = mustExist
                        ? NSLocalizedString("Wait Text (needs text)", comment: "")
                        : NSLocalizedString("Wait Text Gone (needs text)", comment: "")
                }
                kind = mustExist ? .waitForText : .waitForTextGone
            } else if ev.kind == .verifyText {
                let mustExist = ev.verifyMustExist ?? true
                if let text = ev.textAnchor?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    name = String(format: NSLocalizedString("Verify Text: %@ (%@)", comment: ""), text, mustExist ? NSLocalizedString("Exists", comment: "") : NSLocalizedString("Not Exists", comment: ""))
                } else {
                    name = NSLocalizedString("Verify Text (needs text)", comment: "")
                }
                kind = .verifyText
            } else {
                name = "\(ev.kind)"
                kind = ev.kind.isMouse ? .click : .keyPress
            }
            
            groups.append(ActionGroup(
                id: deterministicUUID(from: "fallback-\(kind.rawValue)-\(ev.time)-\(i)"),
                kind: kind,
                eventIndices: [i],
                startTime: ev.time,
                endTime: ev.time,
                    startPoint: ev.kind.isMouse ? CGPoint(x: ev.x, y: ev.y) : nil,
                    keyCode: ev.kind.isKey ? ev.keyCode : nil,
                    keyFlags: ev.kind.isKey ? ev.flags : nil,
                    unicodeString: ev.kind.isKey ? ev.unicodeString : nil,
                    mouseButton: ev.kind.isMouse ? ev.mouseButton : nil,
                    summary: name,
                    textAnchor: ev.textAnchor,
                    textTimeout: ev.textTimeout,
                    verifyMustExist: ev.verifyMustExist,
                    textTargetReadiness: (kind == .waitForText || kind == .waitForTextGone || kind == .verifyText)
                        ? textTargetReadiness(for: ev.textAnchor)
                        : .notTextTarget
            ))
            
            i += 1
        }
        
        if let live = liveDuration, !groups.isEmpty {
            let lastGroup = groups.last!
            let gap = live - lastGroup.endTime
            if gap > options.waitThreshold {
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "wait-\(lastGroup.endTime)-\(live)"),
                    kind: .wait,
                    eventIndices: [],
                    startTime: lastGroup.endTime,
                    endTime: live,
                    summary: String(format: NSLocalizedString("Wait %.2fs", comment: ""), gap)
                ))
            }
        }
        
        // Post-process: merge consecutive clicks into multi-clicks
        groups = mergeScrollSegments(groups, events: events)
        groups = mergeConsecutiveClicks(groups, events: events)
        groups = mergeRapidMultiPointClicks(groups)
        groups = mergeTextInputGroups(groups)
        groups = mergeBehaviorGroups(groups, events: events)
        
        return groups
    }

    private func textTargetReadiness(for anchor: TextAnchor?) -> TextTargetReadiness {
        guard let anchor else { return .missingAnchor }
        return ActionGroupProjection.textAnchorIsReady(anchor) ? .ready : .missingText
    }

    private func mergeScrollSegments(_ groups: [ActionGroup], events: [RecordedEvent]) -> [ActionGroup] {
        var result: [ActionGroup] = []
        var i = 0

        while i < groups.count {
            let first = groups[i]
            guard first.kind == .scroll else {
                result.append(first)
                i += 1
                continue
            }

            var scrollGroups = [first]
            var j = i + 1
            while j < groups.count {
                let candidateIndex: Int
                if groups[j].kind == .scroll {
                    candidateIndex = j
                } else if groups[j].kind == .wait,
                          groups[j].duration <= options.scrollSegmentGap,
                          groups.indices.contains(j + 1),
                          groups[j + 1].kind == .scroll {
                    candidateIndex = j + 1
                } else {
                    break
                }

                let next = groups[candidateIndex]
                guard canMergeScrollSegment(scrollGroups[0], scrollGroups.last!, next, events: events) else {
                    break
                }

                scrollGroups.append(next)
                j = candidateIndex + 1
            }

            guard scrollGroups.count > 1 else {
                result.append(first)
                i += 1
                continue
            }

            result.append(makeMergedScrollSegment(from: scrollGroups, events: events))
            i = j
        }

        return result
    }

    private func canMergeScrollSegment(_ first: ActionGroup, _ previous: ActionGroup, _ next: ActionGroup, events: [RecordedEvent]) -> Bool {
        guard next.startTime - previous.endTime <= options.scrollSegmentGap else { return false }
        guard behaviorGroupID(for: first, events: events) == behaviorGroupID(for: next, events: events) else { return false }

        if let firstPoint = first.startPoint, let nextPoint = next.startPoint {
            guard hypot(nextPoint.x - firstPoint.x, nextPoint.y - firstPoint.y) <= options.scrollSegmentPositionTolerance else {
                return false
            }
        }

        guard let firstDirection = dominantScrollDirection(first),
              let nextDirection = dominantScrollDirection(next) else {
            return true
        }
        return firstDirection == nextDirection
    }

    private func makeMergedScrollSegment(from scrollGroups: [ActionGroup], events: [RecordedEvent]) -> ActionGroup {
        let eventIndices = scrollGroups.flatMap(\.eventIndices).sorted()
        let totalDX = scrollGroups.reduce(Int32(0)) { $0 + ($1.scrollDeltaX ?? 0) }
        let totalDY = scrollGroups.reduce(Int32(0)) { $0 + ($1.scrollDeltaY ?? 0) }
        let first = scrollGroups.first!
        let last = scrollGroups.last!
        let payloadEvents = eventIndices.compactMap { events.indices.contains($0) ? events[$0] : nil }

        return ActionGroup(
            id: deterministicUUID(from: "scrollsegment-\(first.startTime)-\(last.endTime)-\(eventIndices.first ?? 0)-\(eventIndices.last ?? 0)-\(totalDX)-\(totalDY)"),
            kind: .scroll,
            eventIndices: eventIndices,
            startTime: first.startTime,
            endTime: last.endTime,
            startPoint: first.startPoint,
            endPoint: last.startPoint ?? first.startPoint,
            path: scrollGroups.compactMap(\.startPoint),
            scrollDeltaX: totalDX,
            scrollDeltaY: totalDY,
            scrollPayload: aggregateScrollPayload(payloadEvents),
            summary: String(format: NSLocalizedString("Scroll Segment (dy: %d, dx: %d)", comment: ""), totalDY, totalDX)
        )
    }

    private func dominantScrollDirection(_ group: ActionGroup) -> (axis: Int, sign: Int)? {
        let dx = Int(group.scrollDeltaX ?? 0)
        let dy = Int(group.scrollDeltaY ?? 0)
        if abs(dy) >= abs(dx), dy != 0 {
            return (axis: 1, sign: dy > 0 ? 1 : -1)
        }
        if dx != 0 {
            return (axis: 2, sign: dx > 0 ? 1 : -1)
        }
        return nil
    }
    
    private func mergeBehaviorGroups(_ groups: [ActionGroup], events: [RecordedEvent]) -> [ActionGroup] {
        var result: [ActionGroup] = []
        var i = 0
        
        while i < groups.count {
            let group = groups[i]
            guard let behaviorID = behaviorGroupID(for: group, events: events) else {
                result.append(group)
                i += 1
                continue
            }
            
            var mergedGroups: [ActionGroup] = [group]
            var j = i + 1
            while j < groups.count {
                let next = groups[j]
                if next.kind == .wait,
                   j + 1 < groups.count,
                   behaviorGroupID(for: groups[j + 1], events: events) == behaviorID {
                    mergedGroups.append(next)
                    j += 1
                    continue
                }
                
                if behaviorGroupID(for: next, events: events) == behaviorID {
                    mergedGroups.append(next)
                    j += 1
                    continue
                }
                
                break
            }
            
            if mergedGroups.count == 1 {
                var single = group
                single.behaviorGroupID = behaviorID
                single.behaviorGroupName = behaviorGroupName(for: group, events: events)
                result.append(single)
                i += 1
                continue
            }
            
            let nonWaitCount = mergedGroups.filter { $0.kind != .wait }.count
            let eventIndices = mergedGroups.flatMap(\.eventIndices)
            let first = mergedGroups.first!
            let last = mergedGroups.last!
            let name = behaviorGroupName(for: group, events: events) ?? NSLocalizedString("Behavior", comment: "")
            
            result.append(ActionGroup(
                id: behaviorID.rawValue,
                kind: .sequence,
                eventIndices: eventIndices,
                startTime: first.startTime,
                endTime: last.endTime,
                startPoint: first.startPoint,
                endPoint: last.endPoint ?? mergedGroups.reversed().compactMap(\.endPoint).first,
                path: mergedGroups.flatMap(\.path),
                keyCode: first.keyCode,
                keyFlags: first.keyFlags,
                unicodeString: nil,
                mouseButton: first.mouseButton,
                scrollDeltaX: nil,
                scrollDeltaY: nil,
                scrollPayload: nil,
                summary: String(format: NSLocalizedString("%@ (%d actions)", comment: ""), name, nonWaitCount),
                clickCount: 1,
                textAnchor: nil,
                textTimeout: nil,
                verifyMustExist: nil,
                behaviorGroupID: behaviorID,
                behaviorGroupName: name,
                containedActionCount: nonWaitCount
            ))
            
            i = j
        }
        
        return result
    }
    
    private func behaviorGroupID(for group: ActionGroup, events: [RecordedEvent]) -> BehaviorGroupID? {
        guard !group.eventIndices.isEmpty else { return nil }
        var found: BehaviorGroupID?
        for idx in group.eventIndices {
            guard events.indices.contains(idx), let id = events[idx].behaviorGroupID else { return nil }
            if let existing = found, existing != id { return nil }
            found = id
        }
        return found
    }
    
    private func behaviorGroupName(for group: ActionGroup, events: [RecordedEvent]) -> String? {
        for idx in group.eventIndices where events.indices.contains(idx) {
            if let name = events[idx].behaviorGroupName, !name.isEmpty {
                return name
            }
        }
        return nil
    }
    
    private func mergeConsecutiveClicks(_ groups: [ActionGroup], events: [RecordedEvent]) -> [ActionGroup] {
        var result: [ActionGroup] = []
        var i = 0
        while i < groups.count {
            let g = groups[i]
            if isMergeableCoordinateClick(g) {
                var merged = g
                var count = max(1, g.clickCount)
                var j = i + 1
                // Look ahead and merge directly adjacent clicks. A visible wait
                // row is a user-meaningful pause and must not be consumed into
                // a double/triple click.
                while j < groups.count {
                    let next = groups[j]
                    if isMergeableCoordinateClick(next), let sp1 = merged.startPoint, let sp2 = next.startPoint {
                        guard merged.mouseButton == next.mouseButton else { break }
                        let dist = hypot(sp2.x - sp1.x, sp2.y - sp1.y)
                        let gap = next.startTime - merged.endTime
                        
                        let isOSMultiClick = next.eventIndices.contains { idx in
                            events.indices.contains(idx) && events[idx].clickCount > 1
                        }
                        
                        if (isOSMultiClick || gap <= options.clickMergeGap) && dist <= options.clickMergeDistance {
                            count += 1
                            merged.eventIndices += next.eventIndices
                            merged.endTime = next.endTime
                            merged.endPoint = next.endPoint
                            j += 1
                            continue
                        }
                    }
                    break
                }
                if count > 1 {
                    merged.kind = count > 3 ? .repeatedClick : .doubleClick
                    merged.clickCount = count
                    let clickName: String
                    switch count {
                    case 2: clickName = NSLocalizedString("Double Click", comment: "")
                    case 3: clickName = NSLocalizedString("Triple Click", comment: "")
                    default: clickName = String(format: NSLocalizedString("Repeated Click (%d)", comment: ""), count)
                    }
                    if let sp = merged.startPoint {
                        merged.summary = String(format: "%@ (%d, %d)", clickName, Int(sp.x), Int(sp.y))
                    } else {
                        merged.summary = clickName
                    }
                    merged.id = deterministicUUID(from: "multiclick-\(merged.startTime)-\(merged.endTime)-\(count)")
                }
                result.append(merged)
                // Skip any small waits that were consumed between clicks
                i = j
            } else {
                result.append(g)
                i += 1
            }
        }
        return result
    }
    
    private func mergeTextInputGroups(_ groups: [ActionGroup]) -> [ActionGroup] {
        var result: [ActionGroup] = []
        var i = 0
        while i < groups.count {
            let g = groups[i]
            guard g.kind == .keyPress,
                  let text = g.unicodeString,
                  isTextInputCandidate(text, flags: g.keyFlags ?? 0) else {
                result.append(g)
                i += 1
                continue
            }
            
            var merged = g
            var typed = text
            var j = i + 1
            while j < groups.count {
                let next = groups[j]
                guard next.kind == .keyPress,
                      next.startTime - merged.endTime <= options.clickMergeGap,
                      let nextText = next.unicodeString,
                      isTextInputCandidate(nextText, flags: next.keyFlags ?? 0) else {
                    break
                }
                typed += nextText
                merged.eventIndices += next.eventIndices
                merged.endTime = next.endTime
                j += 1
            }
            
            if j > i + 1 {
                merged.kind = .textInput
                merged.unicodeString = typed
                merged.summary = String(format: NSLocalizedString("Type %@", comment: ""), typed)
                merged.id = deterministicUUID(from: "textinput-\(merged.startTime)-\(merged.endTime)-\(typed)")
            }
            result.append(merged)
            i = j
        }
        return result
    }

    private func mergeRapidMultiPointClicks(_ groups: [ActionGroup]) -> [ActionGroup] {
        var result: [ActionGroup] = []
        var i = 0
        while i < groups.count {
            let first = groups[i]
            guard isMergeableCoordinateClick(first), first.startPoint != nil else {
                result.append(first)
                i += 1
                continue
            }

            var mergedGroups = [first]
            var j = i + 1
            while j < groups.count {
                let next = groups[j]
                guard isMergeableCoordinateClick(next),
                      next.startPoint != nil,
                      next.startTime - mergedGroups.last!.endTime <= options.multiPointClickGap else {
                    break
                }
                mergedGroups.append(next)
                j += 1
            }

            guard mergedGroups.count >= 2 else {
                result.append(first)
                i += 1
                continue
            }

            let points = mergedGroups.compactMap(\.startPoint)
            let eventIndices = mergedGroups.flatMap(\.eventIndices)
            let firstGroup = mergedGroups.first!
            let lastGroup = mergedGroups.last!
            result.append(ActionGroup(
                id: deterministicUUID(from: "multipoint-\(firstGroup.startTime)-\(lastGroup.endTime)-\(points.count)-\(eventIndices.first ?? 0)-\(eventIndices.last ?? 0)"),
                kind: .multiPointClick,
                eventIndices: eventIndices,
                startTime: firstGroup.startTime,
                endTime: lastGroup.endTime,
                startPoint: points.first,
                endPoint: points.last,
                path: points,
                mouseButton: firstGroup.mouseButton,
                summary: String(format: NSLocalizedString("Multi Click (%d points)", comment: ""), points.count),
                clickCount: points.count
            ))
            i = j
        }
        return result
    }

    private func isMergeableCoordinateClick(_ group: ActionGroup) -> Bool {
        group.kind == .click &&
        group.textAnchor == nil &&
        group.textTargetReadiness == .notTextTarget
    }
    
    private func aggregateScrollPayload(_ events: [RecordedEvent]) -> ScrollPayload? {
        let payloads = events.compactMap(\.scrollPayload)
        guard let first = payloads.first else { return nil }
        let totalPointX = payloads.reduce(CGFloat(0)) { $0 + $1.deltaX }
        let totalPointY = payloads.reduce(CGFloat(0)) { $0 + $1.deltaY }
        let totalLineX = payloads.reduce(Int32(0)) { $0 + ($1.lineDeltaX ?? 0) }
        let totalLineY = payloads.reduce(Int32(0)) { $0 + ($1.lineDeltaY ?? 0) }
        let totalFixedX = payloads.reduce(Double(0)) { $0 + ($1.fixedDeltaX ?? 0) }
        let totalFixedY = payloads.reduce(Double(0)) { $0 + ($1.fixedDeltaY ?? 0) }
        return ScrollPayload(
            deltaX: totalPointX,
            deltaY: totalPointY,
            lineDeltaX: totalLineX,
            lineDeltaY: totalLineY,
            phase: first.phase,
            momentumPhase: payloads.last(where: { $0.momentumPhase != nil })?.momentumPhase,
            fixedDeltaX: totalFixedX == 0 ? nil : totalFixedX,
            fixedDeltaY: totalFixedY == 0 ? nil : totalFixedY,
            isContinuous: payloads.contains(where: { $0.isContinuous })
        )
    }
    
    private func groupModifierGesture(_ events: [RecordedEvent], startingAt index: Int) -> (group: ActionGroup, nextIndex: Int)? {
        let start = events[index]
        guard hasShortcutModifier(start.flags) else { return nil }
        
        var keyDownIndex: Int?
        var j = index + 1
        while j < events.count, events[j].time - start.time <= options.maxGestureDuration {
            let next = events[j]
            if next.kind == .keyDown {
                keyDownIndex = j
                break
            }
            if next.kind.isMouse || next.kind == .scrollWheel { break }
            if next.kind == .flagsChanged && !hasShortcutModifier(next.flags) {
                let indices = Array(index...j)
                return (
                    ActionGroup(
                        id: deterministicUUID(from: "modifierhold-\(start.time)-\(next.time)-\(start.flags)"),
                        kind: .modifierHold,
                        eventIndices: indices,
                        startTime: start.time,
                        endTime: next.time,
                        keyCode: start.keyCode,
                        keyFlags: start.flags,
                        summary: String(format: NSLocalizedString("Hold modifier: %@", comment: ""), modifierName(start.flags))
                    ),
                    j + 1
                )
            }
            j += 1
        }
        
        guard let keyIdx = keyDownIndex else { return nil }
        return makeShortcutGroup(events, startIndex: index, keyDownIndex: keyIdx)
    }
    
    private func groupShortcutFromKeyDown(_ events: [RecordedEvent], startingAt index: Int) -> (group: ActionGroup, nextIndex: Int)? {
        makeShortcutGroup(events, startIndex: index, keyDownIndex: index)
    }
    
    private func makeShortcutGroup(_ events: [RecordedEvent], startIndex: Int, keyDownIndex: Int) -> (group: ActionGroup, nextIndex: Int)? {
        let keyDown = events[keyDownIndex]
        guard keyDown.kind == .keyDown, hasShortcutModifier(keyDown.flags) else { return nil }
        
        var lastIdx = keyDownIndex
        var j = keyDownIndex + 1
        while j < events.count, events[j].time - events[startIndex].time <= options.maxGestureDuration {
            let next = events[j]
            lastIdx = j
            if next.kind == .keyUp && next.keyCode == keyDown.keyCode {
                j += 1
                if j < events.count, events[j].kind == .flagsChanged {
                    lastIdx = j
                    j += 1
                }
                break
            }
            if next.kind.isMouse || next.kind == .scrollWheel { break }
            j += 1
        }
        
        let indices = Array(startIndex...lastIdx)
        let end = events[lastIdx]
        let label = shortcutLabel(keyCode: keyDown.keyCode, flags: keyDown.flags)
        return (
            ActionGroup(
                id: deterministicUUID(from: "shortcut-\(events[startIndex].time)-\(end.time)-\(keyDown.keyCode)-\(keyDown.flags)"),
                kind: .shortcut,
                eventIndices: indices,
                startTime: events[startIndex].time,
                endTime: end.time,
                keyCode: keyDown.keyCode,
                keyFlags: keyDown.flags,
                unicodeString: keyDown.unicodeString,
                summary: String(format: NSLocalizedString("Shortcut %@", comment: ""), label)
            ),
            max(j, lastIdx + 1)
        )
    }
    
    private func hasShortcutModifier(_ flags: UInt64) -> Bool {
        flags & (ModFlag.command | ModFlag.option | ModFlag.control | ModFlag.shift) != 0
    }
    
    private func isTextInputCandidate(_ text: String, flags: UInt64) -> Bool {
        guard !text.isEmpty else { return false }
        guard flags & (ModFlag.command | ModFlag.option | ModFlag.control) == 0 else { return false }
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    
    private func shortcutLabel(keyCode: UInt16, flags: UInt64) -> String {
        "\(modifierName(flags))\(keyName(keyCode) ?? "Key \(keyCode)")"
    }
    
    private func modifierName(_ flags: UInt64) -> String {
        var parts: [String] = []
        if flags & ModFlag.control != 0 { parts.append("Ctrl+") }
        if flags & ModFlag.option != 0 { parts.append("Opt+") }
        if flags & ModFlag.shift != 0 { parts.append("Shift+") }
        if flags & ModFlag.command != 0 { parts.append("Cmd+") }
        return parts.joined()
    }
    
    private func mouseButtonName(kind: RecordedEvent.Kind, button: Int64) -> String {
        switch kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return NSLocalizedString("Left", comment: "")
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return NSLocalizedString("Right", comment: "")
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            if button == 2 { return NSLocalizedString("Middle", comment: "") }
            return String(format: NSLocalizedString("Mouse Button %d", comment: ""), Int(button))
        default:
            return NSLocalizedString("Mouse", comment: "")
        }
    }
    
    private func keyName(_ code: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12", 122: "F1", 120: "F2",
            99: "F3", 118: "F4",
            55: "⌘", 56: "⇧", 58: "⌥", 59: "⌃",
        ]
        return map[code]
    }
    
    private func deterministicUUID(from string: String) -> UUID {
        var hashBytes = [UInt8](repeating: 0, count: 16)
        var h = UInt64(5381)
        for byte in string.utf8 {
            h = ((h << 5) &+ h) &+ UInt64(byte)
        }
        for i in 0..<8 {
            hashBytes[i] = UInt8((h >> (i * 8)) & 0xFF)
        }
        var h2 = UInt64(5381)
        for byte in string.utf8.reversed() {
            h2 = ((h2 << 5) &+ h2) &+ UInt64(byte)
        }
        for i in 0..<8 {
            hashBytes[8 + i] = UInt8((h2 >> (i * 8)) & 0xFF)
        }
        hashBytes[6] = (hashBytes[6] & 0x0F) | 0x40
        hashBytes[8] = (hashBytes[8] & 0x3F) | 0x80
        
        let tuple = (
            hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
            hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
            hashBytes[8], hashBytes[9], hashBytes[10], hashBytes[11],
            hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
        )
        return UUID(uuid: tuple)
    }
    
    private func localizedEventKindName(_ k: RecordedEvent.Kind) -> String {
        switch k {
        case .leftMouseDown:     return NSLocalizedString("Left Click ↓", comment: "")
        case .leftMouseUp:       return NSLocalizedString("Left Click ↑", comment: "")
        case .rightMouseDown:    return NSLocalizedString("Right Click ↓", comment: "")
        case .rightMouseUp:      return NSLocalizedString("Right Click ↑", comment: "")
        case .mouseMoved:        return NSLocalizedString("Mouse Move", comment: "")
        case .leftMouseDragged:  return NSLocalizedString("Left Drag", comment: "")
        case .rightMouseDragged: return NSLocalizedString("Right Drag", comment: "")
        case .otherMouseDown:    return NSLocalizedString("Other Click ↓", comment: "")
        case .otherMouseUp:      return NSLocalizedString("Other Click ↑", comment: "")
        case .otherMouseDragged: return NSLocalizedString("Other Drag", comment: "")
        case .keyDown:           return NSLocalizedString("Key Down", comment: "")
        case .keyUp:             return NSLocalizedString("Key Up", comment: "")
        case .flagsChanged:      return NSLocalizedString("Modifier", comment: "")
        case .scrollWheel:       return NSLocalizedString("Scroll", comment: "")
        case .waitForText:       return NSLocalizedString("Wait Text", comment: "")
        case .verifyText:        return NSLocalizedString("Verify Text", comment: "")
        }
    }
}
