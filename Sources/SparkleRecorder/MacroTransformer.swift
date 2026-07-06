import AppKit
import Foundation
import CoreGraphics
import SparkleRecorderCore

extension Array where Element == RecordedEvent {
    public mutating func sortByTimePreservingOrder() {
        self = enumerated()
            .sorted { left, right in
                if left.element.time == right.element.time {
                    return left.offset < right.offset
                }
                return left.element.time < right.element.time
            }
            .map(\.element)
    }

    public mutating func deleteEvents(at indices: IndexSet) {
        let sorted = indices.sorted(by: >)
        for i in sorted where self.indices.contains(i) {
            self.remove(at: i)
        }

    }

    /// Returns the event's index after the time-ordered re-sort so callers can
    /// keep their selection pointing at the edited event.
    @discardableResult
    public mutating func updateEvent(at index: Int, with new: RecordedEvent) -> Int? {
        guard self.indices.contains(index) else { return nil }
        self[index] = new
        self.sortByTimePreservingOrder()

        return self.firstIndex(of: new)
    }

    private mutating func updateLocalCoordinates(for event: inout RecordedEvent, surfaces: [String: PlaybackSurface], resolvedContentFrames: [String: CGRect]? = nil) {
        guard let sId = event.surfaceId, let surface = surfaces[sId] else { return }
        let frame = surface.recordedFrame
        
        let lx = event.x - frame.x
        let ly = event.y - frame.y
        
        let contentFrame: CGRect
        if let frames = resolvedContentFrames, let cf = frames[sId] {
            contentFrame = cf
        } else if let rectContentFrame = surface.recordedContentFrame {
            contentFrame = CGRect(x: rectContentFrame.x, y: rectContentFrame.y, width: rectContentFrame.width, height: rectContentFrame.height)
        } else {
            let bid = surface.bundleIdentifier
            let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
            let resolved = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: frame)
            contentFrame = resolved.frame
        }
        
        // Old coordinate fallback
        event.windowLocalX = lx
        let tbHeight = contentFrame.minY - frame.y
        event.windowLocalY = ly - tbHeight
        
        event.windowNormalizedX = frame.width > 0 ? lx / frame.width : 0
        let clientHeight = Swift.max(1.0, frame.height - tbHeight)
        event.windowNormalizedY = ly >= tbHeight ? (ly - tbHeight) / clientHeight : 0
        
        // New content coordinate model
        let cLocalX = event.x - contentFrame.minX
        let cLocalY = event.y - contentFrame.minY
        event.contentLocalX = cLocalX
        event.contentLocalY = cLocalY
        event.contentNormalizedX = contentFrame.width > 0 ? cLocalX / contentFrame.width : 0
        event.contentNormalizedY = contentFrame.height > 0 ? cLocalY / contentFrame.height : 0
    }
    
    private mutating func resolveContentFrames(for indices: [Int], surfaces: [String: PlaybackSurface]) -> [String: CGRect] {
        var contentFrames: [String: CGRect] = [:]
        for idx in indices where self.indices.contains(idx) {
            if let sId = self[idx].surfaceId, contentFrames[sId] == nil, let surface = surfaces[sId] {
                if let rectContentFrame = surface.recordedContentFrame {
                    contentFrames[sId] = CGRect(x: rectContentFrame.x, y: rectContentFrame.y, width: rectContentFrame.width, height: rectContentFrame.height)
                } else {
                    let bid = surface.bundleIdentifier
                    let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                    contentFrames[sId] = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: surface.recordedFrame).frame
                }
            }
        }
        return contentFrames
    }

    /// Shift coordinates of events at indices by dx/dy.
    public mutating func translateEvents(at indices: [Int], dx: CGFloat, dy: CGFloat, surfaces: [String: PlaybackSurface] = [:]) {
        var newEvents = self
        let contentFrames = resolveContentFrames(for: indices, surfaces: surfaces)
        for idx in indices where newEvents.indices.contains(idx) {
            newEvents[idx].x += dx
            newEvents[idx].y += dy
            updateLocalCoordinates(for: &newEvents[idx], surfaces: surfaces, resolvedContentFrames: contentFrames)
        }
        self = newEvents
    }

    /// Shift coordinates of mouse events at indices using linear interpolation between startDelta and endDelta.
    public mutating func translateEventsLinear(at indices: [Int], startDelta: CGPoint, endDelta: CGPoint, surfaces: [String: PlaybackSurface] = [:]) {
        let n = indices.count
        var newEvents = self
        let contentFrames = resolveContentFrames(for: indices, surfaces: surfaces)
        for (t, idx) in indices.enumerated() {
            guard newEvents.indices.contains(idx) else { continue }
            if newEvents[idx].kind.isMouse {
                let factor = n > 1 ? Double(t) / Double(n - 1) : 1.0
                let dx = startDelta.x + (endDelta.x - startDelta.x) * factor
                let dy = startDelta.y + (endDelta.y - startDelta.y) * factor
                newEvents[idx].x += dx
                newEvents[idx].y += dy
                updateLocalCoordinates(for: &newEvents[idx], surfaces: surfaces, resolvedContentFrames: contentFrames)
            }
        }
        self = newEvents
    }

    /// Adjusts the end point of a path at the given indices, mapping all intermediate points
    /// conformally (preserving relative scale, rotation, and curves) based on a pivot (start point).
    public mutating func conformPath(at indices: [Int], startPoint: CGPoint, oldEndPoint: CGPoint, newEndPoint: CGPoint, surfaces: [String: PlaybackSurface] = [:]) {
        conformPath(
            at: indices,
            oldStartPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newStartPoint: startPoint,
            newEndPoint: newEndPoint,
            surfaces: surfaces
        )
    }
    
    /// Remaps a path between new start/end handles while preserving the user's
    /// relative curve shape as much as possible.
    public mutating func conformPath(at indices: [Int], oldStartPoint: CGPoint, oldEndPoint: CGPoint, newStartPoint: CGPoint, newEndPoint: CGPoint, surfaces: [String: PlaybackSurface] = [:]) {
        let mainVector = CGPoint(x: oldEndPoint.x - oldStartPoint.x, y: oldEndPoint.y - oldStartPoint.y)
        let newVector = CGPoint(x: newEndPoint.x - newStartPoint.x, y: newEndPoint.y - newStartPoint.y)
        
        let oldLen2 = mainVector.x * mainVector.x + mainVector.y * mainVector.y
        guard oldLen2 > 0.001 else {
            let dx = newStartPoint.x - oldStartPoint.x
            let dy = newStartPoint.y - oldStartPoint.y
            translateEvents(at: indices, dx: dx, dy: dy, surfaces: surfaces)
            return
        }
        
        let mainVectorPerp = CGPoint(x: -mainVector.y, y: mainVector.x)
        let newVectorPerp = CGPoint(x: -newVector.y, y: newVector.x)
        
        var newEvents = self
        let contentFrames = resolveContentFrames(for: indices, surfaces: surfaces)
        for idx in indices where newEvents.indices.contains(idx) {
            guard newEvents[idx].kind.isMouse else { continue }
            let pt = CGPoint(x: newEvents[idx].x, y: newEvents[idx].y)
            
            let dx = pt.x - oldStartPoint.x
            let dy = pt.y - oldStartPoint.y
            
            let u = (dx * mainVector.x + dy * mainVector.y) / oldLen2
            let v = (dx * mainVectorPerp.x + dy * mainVectorPerp.y) / oldLen2
            
            newEvents[idx].x = newStartPoint.x + u * newVector.x + v * newVectorPerp.x
            newEvents[idx].y = newStartPoint.y + u * newVector.y + v * newVectorPerp.y
            updateLocalCoordinates(for: &newEvents[idx], surfaces: surfaces, resolvedContentFrames: contentFrames)
        }
        self = newEvents
    }

    /// Update key codes of events at indices.
    public mutating func updateKeyCodes(at indices: [Int], with keyCode: UInt16) {
        var newEvents = self
        for idx in indices where newEvents.indices.contains(idx) {
            newEvents[idx].keyCode = keyCode
        }
        self = newEvents
    }

    /// Update key codes and flags of events at indices.
    public mutating func updateKeyStroke(at indices: [Int], keyCode: UInt16, flags: UInt64) {
        var newEvents = self
        for idx in indices where newEvents.indices.contains(idx) {
            newEvents[idx].keyCode = keyCode
            newEvents[idx].flags = flags
        }
        self = newEvents
    }

    /// Update coordinate strategy and optional OCR text of events at indices.
    public mutating func updateCoordinateStrategy(at indices: [Int], strategy: CoordinateStrategy, textAnchor: TextAnchor? = nil, fallbackPolicy: LocatorFallbackPolicy? = nil, textTimeout: TimeInterval? = nil) {
        var newEvents = self
        for idx in indices {
            guard idx >= 0 && idx < newEvents.count else { continue }
            newEvents[idx].coordinateStrategy = strategy
            if let t = textAnchor {
                newEvents[idx].textAnchor = strategy == .locatorOnly
                    ? TextTargetAnchorFactory.clickableAnchor(t, fallbackEvent: newEvents[idx])
                    : t
            }
            if let fallbackPolicy {
                newEvents[idx].locatorFallbackPolicy = fallbackPolicy
            }
            if let textTimeout {
                newEvents[idx].textTimeout = textTimeout
            }
            if strategy == .locatorOnly {
                newEvents[idx].coordinateBinding = .targetWindow
            }
        }
        self = newEvents
    }
    
    /// Update OCR semantic action fields of events at indices.
    public mutating func updateSemanticAction(at indices: [Int], textAnchor: TextAnchor?, timeout: TimeInterval?, verifyMustExist: Bool?, fallbackPolicy: LocatorFallbackPolicy? = nil) {
        var newEvents = self
        for idx in indices {
            guard idx >= 0 && idx < newEvents.count else { continue }
            if let t = textAnchor { newEvents[idx].textAnchor = t }
            if let to = timeout { newEvents[idx].textTimeout = to }
            if let v = verifyMustExist { newEvents[idx].verifyMustExist = v }
            if let fallbackPolicy { newEvents[idx].locatorFallbackPolicy = fallbackPolicy }
        }
        self = newEvents
    }
    
    /// Update surface ID of events at indices.
    public mutating func updateSurfaceId(at indices: [Int], surfaceId: String) {
        var newEvents = self
        for idx in indices {
            guard idx >= 0 && idx < newEvents.count else { continue }
            newEvents[idx].surfaceId = surfaceId
        }
        self = newEvents
    }
    
    public mutating func bindBehavior(at indices: [Int], id: BehaviorGroupID = BehaviorGroupID(), name: String) {
        var newEvents = self
        for idx in indices {
            guard newEvents.indices.contains(idx) else { continue }
            newEvents[idx].behaviorGroupID = id
            newEvents[idx].behaviorGroupName = name
        }
        self = newEvents
    }
    
    public mutating func unbindBehavior(at indices: [Int]) {
        var newEvents = self
        for idx in indices {
            guard newEvents.indices.contains(idx) else { continue }
            newEvents[idx].behaviorGroupID = nil
            newEvents[idx].behaviorGroupName = nil
        }
        self = newEvents
    }

    /// Scale timestamps of specific event indices relative to a base time.
    public mutating func scaleTime(of indices: IndexSet, by factor: Double, relativeTo baseTime: TimeInterval) {
        let f = Swift.max(0.01, factor)
        for i in indices where self.indices.contains(i) {
            self[i].time = baseTime + (self[i].time - baseTime) * f
        }
        self.sortByTimePreservingOrder()

    }


    /// Stretch (>1) or compress (<1) the timestamps of every event.
    public mutating func scaleTime(by factor: Double) {
        let f = Swift.max(0.01, factor)
        for i in self.indices {
            self[i].time *= f
        }

    }

    /// Add or subtract a constant from the timestamps of selected events.
    public mutating func shiftTime(of indices: IndexSet, by delta: TimeInterval) {
        for i in indices where self.indices.contains(i) {
            self[i].time = Swift.max(0, self[i].time + delta)
        }
        self.sortByTimePreservingOrder()

    }

    public mutating func applyActionGroupDeletionPlan(_ plan: ActionGroupDeletionPlan) {
        for shift in plan.eventTimeShifts {
            for index in shift.eventIndices where self.indices.contains(index) {
                self[index].time = Swift.max(0, self[index].time + shift.delta)
            }
        }
        if !plan.eventIndices.isEmpty {
            deleteEvents(at: IndexSet(plan.eventIndices))
        }
        if !plan.eventTimeShifts.isEmpty {
            sortByTimePreservingOrder()
        }
    }

    public mutating func applyTextClickConversionPlan(_ plan: ActionGroupTextClickConversionPlan) {
        guard let sourceEventIndex = plan.sourceEventIndex,
              self.indices.contains(sourceEventIndex),
              !plan.insertedEvents.isEmpty else {
            return
        }

        for shift in plan.eventTimeShifts {
            for index in shift.eventIndices where self.indices.contains(index) {
                self[index].time = Swift.max(0, self[index].time + shift.delta)
            }
        }

        self.remove(at: sourceEventIndex)
        let insertionIndex = Swift.max(0, Swift.min(sourceEventIndex, self.count))
        self.insert(contentsOf: plan.insertedEvents, at: insertionIndex)
        self.sortByTimePreservingOrder()
    }

    public mutating func applyPassiveWaitDuplicationPlan(_ plan: ActionGroupPassiveWaitDuplicationPlan) {
        guard !plan.eventTimeShifts.isEmpty else { return }

        for shift in plan.eventTimeShifts {
            for index in shift.eventIndices where self.indices.contains(index) {
                self[index].time = Swift.max(0, self[index].time + shift.delta)
            }
        }
        self.sortByTimePreservingOrder()
    }

    /// Drop everything before `index` and rebase remaining timestamps to start at 0.
    public mutating func trimBefore(index: Int) {
        guard self.indices.contains(index), index > 0 else { return }
        let cutoff = self[index].time
        self.removeFirst(index)
        for i in self.indices {
            self[i].time = Swift.max(0, self[i].time - cutoff)
        }

    }

    /// Drop everything after `index`.
    public mutating func trimAfter(index: Int) {
        guard self.indices.contains(index), index < self.count - 1 else { return }
        self.removeSubrange((index + 1)..<self.count)
        // Snap liveDuration to last kept event (discard trailing wait after trimmed region)

    }

    /// Insert a wait of `milliseconds` at `index` (shifting subsequent events forward in time).
    /// `index == 0` adds the wait at the very start. `index == self.count` extends the end.
    public mutating func insertWait(at index: Int, milliseconds: Double) {
        let delta = Swift.max(0, milliseconds / 1000.0)
        guard delta > 0, !self.isEmpty else { return }
        let clamped = Swift.max(0, Swift.min(index, self.count))
        for i in clamped..<self.count {
            self[i].time += delta
        }

    }

    public mutating func updateClickType(at indices: [Int], to clickCount: Int64) {
        for idx in indices {
            guard self.indices.contains(idx) else { continue }
            self[idx].clickCount = clickCount
        }
    }

    public mutating func insertClick(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let down = RecordedEvent(kind: .leftMouseDown, time: t, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .leftMouseUp, time: t + 0.1, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(contentsOf: [down, up], at: clamped)
        self.sortByTimePreservingOrder()

    }
    
    public mutating func insertDoubleClick(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let down = RecordedEvent(kind: .leftMouseDown, time: t, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 2, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .leftMouseUp, time: t + 0.1, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 2, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(contentsOf: [down, up], at: clamped)
        self.sortByTimePreservingOrder()
    }

    public mutating func insertMultiPointClick(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let points = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 150, y: 100),
            CGPoint(x: 200, y: 100)
        ]
        let inserted = makeRapidClickEvents(points: points, startingAt: t)
        let duration = (inserted.last?.time ?? t) - t + 0.04
        for i in clamped..<self.count { self[i].time += duration }
        self.insert(contentsOf: inserted, at: clamped)
        self.sortByTimePreservingOrder()
    }
    
    @discardableResult
    public mutating func insertTextClick(
        at index: Int,
        textAnchor: TextAnchor = TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)),
        textTimeout: TimeInterval = 10.0,
        fallbackPolicy: LocatorFallbackPolicy = .fail,
        surfaceId: String? = nil
    ) -> Range<Int> {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let inserted = TextClickEventFactory.makeEvents(
            startTime: t,
            textAnchor: textAnchor,
            timeout: textTimeout,
            fallbackPolicy: fallbackPolicy,
            surfaceId: surfaceId
        )
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(contentsOf: inserted, at: clamped)
        self.sortByTimePreservingOrder()
        return clamped..<(clamped + inserted.count)
    }
    
    public mutating func insertDrag(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let down = RecordedEvent(kind: .leftMouseDown, time: t, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let drag = RecordedEvent(kind: .leftMouseDragged, time: t + 0.2, x: 200, y: 200, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .leftMouseUp, time: t + 0.4, x: 200, y: 200, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<self.count { self[i].time += 0.5 }
        self.insert(contentsOf: [down, drag, up], at: clamped)
        self.sortByTimePreservingOrder()

    }
    
    public mutating func insertScroll(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let scroll = RecordedEvent(kind: .scrollWheel, time: t, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 10, scrollDeltaX: 0, scrollPayload: ScrollPayload(deltaX: 0, deltaY: 10, phase: 0, isContinuous: false))
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(scroll, at: clamped)
        self.sortByTimePreservingOrder()
    }

    public mutating func appendMultiPointClick(at indices: [Int], point: CGPoint) {
        let sorted = indices.sorted()
        guard let lastIndex = sorted.last, self.indices.contains(lastIndex) else { return }
        let insertIndex = Swift.min(lastIndex + 1, self.count)
        let startTime = self[lastIndex].time + 0.04
        let inserted = makeRapidClickEvents(points: [point], startingAt: startTime)
        let duration = (inserted.last?.time ?? startTime) - startTime + 0.04
        for i in insertIndex..<self.count { self[i].time += duration }
        self.insert(contentsOf: inserted, at: insertIndex)
        self.sortByTimePreservingOrder()
    }

    public mutating func translateMultiPointClickPoint(at indices: [Int], pointIndex: Int, dx: CGFloat, dy: CGFloat, surfaces: [String: PlaybackSurface] = [:]) {
        let validIndices = indices.sorted().filter { self.indices.contains($0) }
        let downIndices = validIndices.filter { isMouseDownKind(self[$0].kind) }
        guard downIndices.indices.contains(pointIndex) else { return }

        let downIndex = downIndices[pointIndex]
        var targetIndices = [downIndex]
        if let downPosition = validIndices.firstIndex(of: downIndex),
           let expectedUpKind = mouseUpKind(for: self[downIndex].kind) {
            for idx in validIndices.dropFirst(downPosition + 1) where self.indices.contains(idx) {
                if self[idx].kind == expectedUpKind && self[idx].mouseButton == self[downIndex].mouseButton {
                    targetIndices.append(idx)
                    break
                }
                if isMouseDownKind(self[idx].kind) {
                    break
                }
            }
        }

        translateEvents(at: targetIndices, dx: dx, dy: dy, surfaces: surfaces)
    }

    public mutating func removeLastMultiPointClick(at indices: [Int]) {
        let sorted = indices.sorted()
        guard sorted.count > 2 else { return }
        let removable = [Int](sorted.suffix(2))
        deleteEvents(at: IndexSet(removable))
    }

    private func makeRapidClickEvents(points: [CGPoint], startingAt startTime: TimeInterval) -> [RecordedEvent] {
        points.enumerated().flatMap { offset, point in
            let downTime = startTime + Double(offset) * 0.04
            let upTime = downTime + 0.018
            let down = RecordedEvent(kind: .leftMouseDown, time: downTime, x: point.x, y: point.y, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
            let up = RecordedEvent(kind: .leftMouseUp, time: upTime, x: point.x, y: point.y, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
            return [down, up]
        }
    }

    private func isMouseDownKind(_ kind: RecordedEvent.Kind) -> Bool {
        switch kind {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private func mouseUpKind(for kind: RecordedEvent.Kind) -> RecordedEvent.Kind? {
        switch kind {
        case .leftMouseDown:
            return .leftMouseUp
        case .rightMouseDown:
            return .rightMouseUp
        case .otherMouseDown:
            return .otherMouseUp
        default:
            return nil
        }
    }
    
    public mutating func insertKeystroke(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        // default to space bar (49)
        let down = RecordedEvent(kind: .keyDown, time: t, x: 0, y: 0, keyCode: 49, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .keyUp, time: t + 0.1, x: 0, y: 0, keyCode: 49, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(contentsOf: [down, up], at: clamped)
        self.sortByTimePreservingOrder()

    }
    
    public mutating func insertWaitForText(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let ev = RecordedEvent(kind: .waitForText, time: t, x: 0, y: 0, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0, textAnchor: TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)), textTimeout: 10.0, verifyMustExist: true)
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(ev, at: clamped)
        self.sortByTimePreservingOrder()

    }

    public mutating func insertWaitForTextGone(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let ev = RecordedEvent(kind: .waitForText, time: t, x: 0, y: 0, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0, textAnchor: TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)), textTimeout: 10.0, verifyMustExist: false)
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(ev, at: clamped)
        self.sortByTimePreservingOrder()
    }
    
    public mutating func insertVerifyText(at index: Int) {
        let t = self.isEmpty ? 0 : (index > 0 && index <= self.count ? self[index - 1].time + 0.1 : self.last!.time + 0.1)
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let ev = RecordedEvent(kind: .verifyText, time: t, x: 0, y: 0, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0, textAnchor: TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)), verifyMustExist: true)
        for i in clamped..<self.count { self[i].time += 0.2 }
        self.insert(ev, at: clamped)
        self.sortByTimePreservingOrder()

    }

    @discardableResult
    public mutating func insertRevealAndClickTextFlow(
        at index: Int,
        preDelay: TimeInterval
    ) -> Range<Int> {
        let clamped = Swift.max(0, Swift.min(index, self.count))
        let previousTime = clamped > 0 ? self[clamped - 1].time : 0
        let revealDownTime = previousTime + Swift.max(0, preDelay)
        let anchor = TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0))
        let revealDown = RecordedEvent(kind: .leftMouseDown, time: revealDownTime, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let revealUp = RecordedEvent(kind: .leftMouseUp, time: revealDownTime + 0.08, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let waitText = RecordedEvent(kind: .waitForText, time: revealDownTime + 0.18, x: 0, y: 0, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0, textAnchor: anchor, textTimeout: 10.0, verifyMustExist: true)
        var textClick = TextClickEventFactory.makeEvents(
            startTime: revealDownTime + 0.30,
            textAnchor: anchor
        )
        if textClick.indices.contains(1) {
            textClick[1].time = revealDownTime + 0.38
        }
        let inserted = [revealDown, revealUp, waitText] + textClick
        let shift = (inserted.last?.time ?? revealDownTime) - previousTime + 0.08
        for i in clamped..<self.count { self[i].time += shift }
        self.insert(contentsOf: inserted, at: clamped)
        self.sortByTimePreservingOrder()
        return clamped..<(clamped + inserted.count)
    }

    public mutating func reorderGroup(sourceEventIndices: [Int], beforeEventIndex: Int?) {
        guard !self.isEmpty else { return }
        let sortedSource = sourceEventIndices.sorted()
        guard !sortedSource.isEmpty else { return }
        
        let groups = EventGrouper().group(self, liveDuration: self.last?.time ?? 0)
        let nonWaitGroups = groups.filter { $0.kind != .wait }
        let n = nonWaitGroups.count
        guard n > 0 else { return }
        
        var movingIndices: [Int] = []
        for (idx, g) in nonWaitGroups.enumerated() {
            if g.eventIndices.contains(where: { sortedSource.contains($0) }) {
                movingIndices.append(idx)
            }
        }
        guard !movingIndices.isEmpty else { return }
        
        let targetIdx: Int
        if let beforeIdx = beforeEventIndex {
            targetIdx = nonWaitGroups.firstIndex(where: { $0.eventIndices.contains(beforeIdx) }) ?? n
        } else {
            targetIdx = n
        }
        
        let start_delay = nonWaitGroups[0].startTime
        var intervals = [TimeInterval](repeating: 0, count: n - 1)
        for i in 0..<n-1 {
            intervals[i] = Swift.max(0, nonWaitGroups[i+1].startTime - nonWaitGroups[i].endTime)
        }
        let end_delay = Swift.max(0, (self.last?.time ?? 0) - nonWaitGroups.last!.endTime)
        
        var newOrder: [Int] = (0..<n).map { $0 }
        let movingSet = Set(movingIndices)
        newOrder.removeAll { movingSet.contains($0) }
        
        let adjTargetIdx = targetIdx - movingIndices.filter { $0 < targetIdx }.count
        let clampedTarget = Swift.max(0, Swift.min(adjTargetIdx, newOrder.count))
        newOrder.insert(contentsOf: movingIndices, at: clampedTarget)
        
        var newTimes = [Int: TimeInterval]()
        var current_time = start_delay
        
        for idx in newOrder {
            let g = nonWaitGroups[idx]
            let g_startTime = g.startTime
            let g_endTime = g.endTime
            let g_duration = g_endTime - g_startTime
            
            for evIdx in g.eventIndices {
                let offset = self[evIdx].time - g_startTime
                newTimes[evIdx] = current_time + offset
            }
            
            let post_wait = (idx == n - 1) ? end_delay : intervals[idx]
            current_time = current_time + g_duration + post_wait
        }
        
        for (evIdx, t) in newTimes {
            self[evIdx].time = t
        }
        
        self.sortByTimePreservingOrder()
    }

    /// Duplicate a group of events. The copies are placed right after the originals
    /// and subsequent events are shifted forward in time.
    public mutating func duplicateEvents(at indices: [Int]) {
        let sorted = indices.sorted()
        guard !sorted.isEmpty else { return }

        let sourceEvents = sorted.map { self[$0] }
        let srcBaseTime = sourceEvents[0].time
        let srcDuration = (sourceEvents.last!.time - srcBaseTime) + 0.1

        // Shift all events after the source group forward
        let afterIdx = (sorted.last! + 1)
        for i in afterIdx..<self.count { self[i].time += srcDuration }

        // Create copies with shifted timestamps
        var copies: [RecordedEvent] = []
        for ev in sourceEvents {
            var copy = ev
            copy.time += srcDuration
            copies.append(copy)
        }

        self.insert(contentsOf: copies, at: afterIdx)

    }
}
