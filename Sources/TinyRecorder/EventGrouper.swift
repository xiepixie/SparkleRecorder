import Foundation
import CoreGraphics

public enum ActionGroupKind: String, Codable {
    case click
    case doubleClick
    case longPress
    case drag
    case scroll
    case keyPress
    case keyHold
    case wait
    case mouseMove
}

public struct EventGroupingOptions: Codable, Equatable {
    public var clickMoveTolerance: CGFloat = 5
    public var dragDistanceThreshold: CGFloat = 8
    public var longPressThreshold: TimeInterval = 0.35
    public var keyHoldThreshold: TimeInterval = 0.35
    public var scrollBurstGap: TimeInterval = 0.18
    public var scrollPositionTolerance: CGFloat = 40
    public var waitThreshold: TimeInterval = 0.200
    public var maxGestureDuration: TimeInterval = 30.0
    /// Maximum gap between consecutive clicks to merge them into a multi-click (double/triple)
    public var clickMergeGap: TimeInterval = 0.45
    /// Maximum distance between click positions to allow merging
    public var clickMergeDistance: CGFloat = 20
    /// Disable all gesture/action grouping and return raw events
    public var disableGrouping: Bool = false
    
    public init() {}
}

public struct ActionGroup: Identifiable, Equatable {
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

    public var scrollDeltaX: Int32?
    public var scrollDeltaY: Int32?

    public var summary: String
    /// Number of clicks (1 = single, 2 = double, 3 = triple, etc.)
    public var clickCount: Int
    
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
        scrollDeltaX: Int32? = nil,
        scrollDeltaY: Int32? = nil,
        summary: String,
        clickCount: Int = 1
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
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.summary = summary
        self.clickCount = clickCount
    }
}

public struct EventGrouper {
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
                }
                
                // Construct a simple raw event name
                let name: String
                if ev.kind.isKey {
                    let nameStr = keyName(ev.keyCode) ?? "Key \(ev.keyCode)"
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
                    summary: name
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
            return groups
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
            
            // 1. Mouse Drag, LongPress or Click Gesture (Strict state machine)
            if ev.kind == .leftMouseDown || ev.kind == .rightMouseDown || ev.kind == .otherMouseDown {
                let startIdx = i
                var lastIdx = i
                var dragPoints: [CGPoint] = [CGPoint(x: ev.x, y: ev.y)]
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
                    
                    if next.kind == dragKind {
                        dragPoints.append(CGPoint(x: next.x, y: next.y))
                        lastIdx = j
                        j += 1
                    } else if next.kind == upKind {
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
                
                if distance > options.dragDistanceThreshold {
                    kind = .drag
                    summary = String(format: NSLocalizedString("Drag from (%d, %d) to (%d, %d)", comment: ""), Int(startEv.x), Int(startEv.y), Int(endEv.x), Int(endEv.y))
                } else if duration >= options.longPressThreshold {
                    kind = .longPress
                    let btnName = ev.kind == .leftMouseDown ? NSLocalizedString("Left", comment: "") : (ev.kind == .rightMouseDown ? NSLocalizedString("Right", comment: "") : NSLocalizedString("Other", comment: ""))
                    summary = String(format: NSLocalizedString("Long Press (%@) at (%d, %d)", comment: ""), btnName, Int(startEv.x), Int(startEv.y))
                } else {
                    kind = .click
                    summary = String(format: NSLocalizedString("Click at (%d, %d)", comment: ""), Int(startEv.x), Int(startEv.y))
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
                    summary: summary
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
                    summary: String(format: NSLocalizedString("Scroll (dy: %d, dx: %d)", comment: ""), totalDY, totalDX)
                ))
                
                i = j
                continue
            }
            
            // 3. Key Press (KeyDown + KeyUp pair)
            if ev.kind == .keyDown {
                let startIdx = i
                var lastIdx = i
                
                var j = i + 1
                while j < events.count {
                    let next = events[j]
                    if next.time - ev.time > options.maxGestureDuration {
                        break
                    }
                    if next.kind == .keyUp && next.keyCode == ev.keyCode {
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
                let name = keyName(ev.keyCode) ?? "Code \(ev.keyCode)"
                let duration = endEv.time - startEv.time
                
                let kind: ActionGroupKind = duration >= options.keyHoldThreshold ? .keyHold : .keyPress
                let formatStr = kind == .keyHold 
                    ? NSLocalizedString("Hold key: %@ (%.2fs)", comment: "")
                    : NSLocalizedString("Press key: %@", comment: "")
                let summary = kind == .keyHold
                    ? String(format: formatStr, name, duration)
                    : String(format: formatStr, name)
                
                groups.append(ActionGroup(
                    id: deterministicUUID(from: "key-\(kind.rawValue)-\(startEv.time)-\(endEv.time)-\(indices.first ?? 0)-\(indices.last ?? 0)-\(ev.keyCode)"),
                    kind: kind,
                    eventIndices: indices,
                    startTime: startEv.time,
                    endTime: endEv.time,
                    keyCode: ev.keyCode,
                    keyFlags: ev.flags,
                    summary: summary
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
                name = String(format: NSLocalizedString("Key Release: %@", comment: ""), keyName(ev.keyCode) ?? "Code \(ev.keyCode)")
                kind = .keyPress
            } else if ev.kind == .mouseMoved {
                name = String(format: NSLocalizedString("Move to (%d, %d)", comment: ""), Int(ev.x), Int(ev.y))
                kind = .mouseMove
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
                summary: name
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
        groups = mergeConsecutiveClicks(groups, events: events)
        
        return groups
    }
    
    private func mergeConsecutiveClicks(_ groups: [ActionGroup], events: [RecordedEvent]) -> [ActionGroup] {
        var result: [ActionGroup] = []
        var i = 0
        while i < groups.count {
            let g = groups[i]
            if g.kind == .click {
                var merged = g
                var count = 1
                var j = i + 1
                // Look ahead: skip wait groups and merge subsequent clicks
                while j < groups.count {
                    let next = groups[j]
                    if next.kind == .wait {
                        // Check if the wait is short enough to still merge
                        if next.duration <= options.clickMergeGap {
                            j += 1
                            continue
                        } else {
                            break
                        }
                    }
                    if next.kind == .click, let sp1 = merged.startPoint, let sp2 = next.startPoint {
                        let dist = hypot(sp2.x - sp1.x, sp2.y - sp1.y)
                        let gap = next.startTime - merged.endTime
                        
                        let isOSMultiClick = next.eventIndices.contains { idx in
                            events.indices.contains(idx) && events[idx].clickCount > 1
                        }
                        
                        if isOSMultiClick && dist <= options.clickMergeDistance && gap <= options.clickMergeGap {
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
                    merged.kind = .doubleClick
                    merged.clickCount = count
                    let clickName: String
                    switch count {
                    case 2: clickName = NSLocalizedString("Double Click", comment: "")
                    case 3: clickName = NSLocalizedString("Triple Click", comment: "")
                    default: clickName = String(format: NSLocalizedString("%d× Click", comment: ""), count)
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
        }
    }
}
