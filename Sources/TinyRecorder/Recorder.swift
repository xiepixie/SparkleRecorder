import Cocoa
import CoreGraphics
import Combine
import TinyRecorderCore

/// Captures live mouse + keyboard events into an in-memory macro using a CGEventTap.
final class Recorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var events: [RecordedEvent] = []
    @Published private(set) var liveDuration: TimeInterval = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var startTime: CFAbsoluteTime = 0
    private var displayTimer: Timer?
    /// Captured events accumulate here (on the main run loop, where the tap
    /// callback fires) and flush into the @Published array at 10 Hz. Per-event
    /// @Published mutations caused a SwiftUI re-render per input event, which
    /// could starve the tap into timeout during fast input.
    private var pending: [RecordedEvent] = []

    /// Key codes the recorder must NOT capture (our own hotkeys).
    var ignoredKeyCodes: Set<UInt16> = []

    var eventCount: Int { events.count }

    deinit {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        displayTimer?.invalidate()
    }

    /// Replace the in-memory event list (used when opening a saved macro).
    func loadEvents(_ new: [RecordedEvent]) {
        events = new
        liveDuration = new.last?.time ?? 0
    }

    // MARK: - Editing

    func deleteEvents(at indices: IndexSet) {
        let sorted = indices.sorted(by: >)
        for i in sorted where events.indices.contains(i) {
            events.remove(at: i)
        }
        liveDuration = events.last?.time ?? 0
    }

    /// Returns the event's index after the time-ordered re-sort so callers can
    /// keep their selection pointing at the edited event.
    @discardableResult
    func updateEvent(at index: Int, with new: RecordedEvent) -> Int? {
        guard events.indices.contains(index) else { return nil }
        events[index] = new
        events.sort { $0.time < $1.time }
        liveDuration = events.last?.time ?? 0
        return events.firstIndex(of: new)
    }

    /// Shift coordinates of events at indices by dx/dy.
    func translateEvents(at indices: [Int], dx: CGFloat, dy: CGFloat) {
        for idx in indices where events.indices.contains(idx) {
            events[idx].x += dx
            events[idx].y += dy
        }
        events = events // Trigger SwiftUI refresh
    }

    /// Shift coordinates of mouse events at indices using linear interpolation between startDelta and endDelta.
    func translateEventsLinear(at indices: [Int], startDelta: CGPoint, endDelta: CGPoint) {
        let n = indices.count
        for (t, idx) in indices.enumerated() {
            guard events.indices.contains(idx) else { continue }
            if events[idx].kind.isMouse {
                let factor = n > 1 ? Double(t) / Double(n - 1) : 1.0
                let dx = startDelta.x + (endDelta.x - startDelta.x) * factor
                let dy = startDelta.y + (endDelta.y - startDelta.y) * factor
                events[idx].x += dx
                events[idx].y += dy
            }
        }
        events = events // Trigger SwiftUI refresh
    }

    /// Adjusts the end point of a path at the given indices, mapping all intermediate points
    /// conformally (preserving relative scale, rotation, and curves) based on a pivot (start point).
    func conformPath(at indices: [Int], startPoint: CGPoint, oldEndPoint: CGPoint, newEndPoint: CGPoint) {
        let mainVector = CGPoint(x: oldEndPoint.x - startPoint.x, y: oldEndPoint.y - startPoint.y)
        let newVector = CGPoint(x: newEndPoint.x - startPoint.x, y: newEndPoint.y - startPoint.y)
        
        let oldLen2 = mainVector.x * mainVector.x + mainVector.y * mainVector.y
        guard oldLen2 > 0.001 else {
            let dx = newEndPoint.x - oldEndPoint.x
            let dy = newEndPoint.y - oldEndPoint.y
            translateEventsLinear(at: indices, startDelta: .zero, endDelta: CGPoint(x: dx, y: dy))
            return
        }
        
        let mainVectorPerp = CGPoint(x: -mainVector.y, y: mainVector.x)
        let newVectorPerp = CGPoint(x: -newVector.y, y: newVector.x)
        
        for idx in indices where events.indices.contains(idx) {
            guard events[idx].kind.isMouse else { continue }
            let pt = CGPoint(x: events[idx].x, y: events[idx].y)
            
            let dx = pt.x - startPoint.x
            let dy = pt.y - startPoint.y
            
            let u = (dx * mainVector.x + dy * mainVector.y) / oldLen2
            let v = (dx * mainVectorPerp.x + dy * mainVectorPerp.y) / oldLen2
            
            events[idx].x = startPoint.x + u * newVector.x + v * newVectorPerp.x
            events[idx].y = startPoint.y + u * newVector.y + v * newVectorPerp.y
        }
        events = events // Trigger SwiftUI refresh
    }

    /// Update key codes of events at indices.
    func updateKeyCodes(at indices: [Int], with keyCode: UInt16) {
        for idx in indices where events.indices.contains(idx) {
            events[idx].keyCode = keyCode
        }
        events = events // Trigger SwiftUI refresh
    }

    /// Update key codes and flags of events at indices.
    func updateKeyStroke(at indices: [Int], keyCode: UInt16, flags: UInt64) {
        for idx in indices where events.indices.contains(idx) {
            events[idx].keyCode = keyCode
            events[idx].flags = flags
        }
        events = events // Trigger SwiftUI refresh
    }

    /// Scale timestamps of specific event indices relative to a base time.
    func scaleTime(of indices: IndexSet, by factor: Double, relativeTo baseTime: TimeInterval) {
        let f = max(0.01, factor)
        for i in indices where events.indices.contains(i) {
            events[i].time = baseTime + (events[i].time - baseTime) * f
        }
        events.sort { $0.time < $1.time }
        liveDuration = events.last?.time ?? 0
    }


    /// Stretch (>1) or compress (<1) the timestamps of every event.
    func scaleTime(by factor: Double) {
        let f = max(0.01, factor)
        for i in events.indices {
            events[i].time *= f
        }
        liveDuration = events.last?.time ?? 0
    }

    /// Add or subtract a constant from the timestamps of selected events.
    func shiftTime(of indices: IndexSet, by delta: TimeInterval) {
        for i in indices where events.indices.contains(i) {
            events[i].time = max(0, events[i].time + delta)
        }
        events.sort { $0.time < $1.time }
        liveDuration = events.last?.time ?? 0
    }

    /// Drop everything before `index` and rebase remaining timestamps to start at 0.
    func trimBefore(index: Int) {
        guard events.indices.contains(index), index > 0 else { return }
        let cutoff = events[index].time
        events.removeFirst(index)
        for i in events.indices {
            events[i].time = max(0, events[i].time - cutoff)
        }
        liveDuration = max(0, liveDuration - cutoff)
    }

    /// Drop everything after `index`.
    func trimAfter(index: Int) {
        guard events.indices.contains(index), index < events.count - 1 else { return }
        let lastKeptTime = events[index].time
        events.removeSubrange((index + 1)..<events.count)
        // Snap liveDuration to last kept event (discard trailing wait after trimmed region)
        liveDuration = lastKeptTime
    }

    func clearAll() {
        events.removeAll()
        liveDuration = 0
    }

    func setLiveDuration(_ newDuration: Double) {
        liveDuration = max(0, newDuration)
    }

    /// Insert a wait of `milliseconds` at `index` (shifting subsequent events forward in time).
    /// `index == 0` adds the wait at the very start. `index == events.count` extends the end.
    func insertWait(at index: Int, milliseconds: Double) {
        let delta = max(0, milliseconds / 1000.0)
        guard delta > 0, !events.isEmpty else { return }
        let clamped = max(0, min(index, events.count))
        for i in clamped..<events.count {
            events[i].time += delta
        }
        liveDuration = events.last?.time ?? 0
    }

    func insertClick(at index: Int) {
        let t = events.isEmpty ? 0 : (index > 0 && index <= events.count ? events[index - 1].time + 0.1 : events.last!.time + 0.1)
        let clamped = max(0, min(index, events.count))
        let down = RecordedEvent(kind: .leftMouseDown, time: t, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .leftMouseUp, time: t + 0.1, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<events.count { events[i].time += 0.2 }
        events.insert(contentsOf: [down, up], at: clamped)
        events.sort { $0.time < $1.time }
        liveDuration = events.last?.time ?? 0
    }
    
    func insertDrag(at index: Int) {
        let t = events.isEmpty ? 0 : (index > 0 && index <= events.count ? events[index - 1].time + 0.1 : events.last!.time + 0.1)
        let clamped = max(0, min(index, events.count))
        let down = RecordedEvent(kind: .leftMouseDown, time: t, x: 100, y: 100, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let drag = RecordedEvent(kind: .leftMouseDragged, time: t + 0.2, x: 200, y: 200, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .leftMouseUp, time: t + 0.4, x: 200, y: 200, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<events.count { events[i].time += 0.5 }
        events.insert(contentsOf: [down, drag, up], at: clamped)
        events.sort { $0.time < $1.time }
        liveDuration = events.last?.time ?? 0
    }
    
    func insertKeystroke(at index: Int) {
        let t = events.isEmpty ? 0 : (index > 0 && index <= events.count ? events[index - 1].time + 0.1 : events.last!.time + 0.1)
        let clamped = max(0, min(index, events.count))
        // default to space bar (49)
        let down = RecordedEvent(kind: .keyDown, time: t, x: 0, y: 0, keyCode: 49, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
        let up = RecordedEvent(kind: .keyUp, time: t + 0.1, x: 0, y: 0, keyCode: 49, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
        for i in clamped..<events.count { events[i].time += 0.2 }
        events.insert(contentsOf: [down, up], at: clamped)
        events.sort { $0.time < $1.time }
        liveDuration = events.last?.time ?? 0
    }

    func reorderGroup(sourceEventIndices: [Int], beforeEventIndex: Int?) {
        guard !events.isEmpty else { return }
        let sortedSource = sourceEventIndices.sorted()
        guard !sortedSource.isEmpty else { return }
        
        let groups = EventGrouper().group(events, liveDuration: liveDuration)
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
            intervals[i] = nonWaitGroups[i+1].startTime - nonWaitGroups[i].endTime
        }
        let end_delay = liveDuration - nonWaitGroups.last!.endTime
        
        var newOrder = Array(0..<n)
        let movingSet = Set(movingIndices)
        newOrder.removeAll { movingSet.contains($0) }
        
        let adjTargetIdx = targetIdx - movingIndices.filter { $0 < targetIdx }.count
        let clampedTarget = max(0, min(adjTargetIdx, newOrder.count))
        newOrder.insert(contentsOf: movingIndices, at: clampedTarget)
        
        var newTimes = [Int: TimeInterval]()
        var current_time = start_delay
        
        for idx in newOrder {
            let g = nonWaitGroups[idx]
            let g_startTime = g.startTime
            let g_endTime = g.endTime
            let g_duration = g_endTime - g_startTime
            
            for evIdx in g.eventIndices {
                let offset = events[evIdx].time - g_startTime
                newTimes[evIdx] = current_time + offset
            }
            
            let post_wait = (idx == n - 1) ? end_delay : intervals[idx]
            current_time = current_time + g_duration + post_wait
        }
        
        for (evIdx, t) in newTimes {
            events[evIdx].time = t
        }
        
        events.sort { $0.time < $1.time }
    }

    /// Duplicate a group of events. The copies are placed right after the originals
    /// and subsequent events are shifted forward in time.
    func duplicateEvents(at indices: [Int]) {
        let sorted = indices.sorted()
        guard !sorted.isEmpty else { return }

        let sourceEvents = sorted.map { events[$0] }
        let srcBaseTime = sourceEvents[0].time
        let srcDuration = (sourceEvents.last!.time - srcBaseTime) + 0.1

        // Shift all events after the source group forward
        let afterIdx = (sorted.last! + 1)
        for i in afterIdx..<events.count { events[i].time += srcDuration }

        // Create copies with shifted timestamps
        var copies: [RecordedEvent] = []
        for ev in sourceEvents {
            var copy = ev
            copy.time += srcDuration
            copies.append(copy)
        }

        events.insert(contentsOf: copies, at: afterIdx)
        liveDuration = events.last?.time ?? 0
    }

    @discardableResult
    func startRecording() -> Bool {
        guard !isRecording else { return true }
        events.removeAll()
        pending.removeAll()
        liveDuration = 0
        startTime = CFAbsoluteTimeGetCurrent()

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)     |
            (1 << CGEventType.leftMouseUp.rawValue)       |
            (1 << CGEventType.rightMouseDown.rawValue)    |
            (1 << CGEventType.rightMouseUp.rawValue)      |
            (1 << CGEventType.mouseMoved.rawValue)        |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)           |
            (1 << CGEventType.keyUp.rawValue)             |
            (1 << CGEventType.flagsChanged.rawValue)      |
            (1 << CGEventType.scrollWheel.rawValue)       |
            (1 << CGEventType.otherMouseDown.rawValue)    |
            (1 << CGEventType.otherMouseUp.rawValue)      |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<Recorder>.fromOpaque(refcon).takeUnretainedValue()
            recorder.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("TinyRecorder: failed to create event tap. Grant Accessibility & Input Monitoring permission.")
            return false
        }

        tap = newTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        isRecording = true
        startDisplayTimer()
        return true
    }

    func stopRecording() {
        guard isRecording else { return }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        stopDisplayTimer()
        flushPending()
        isRecording = false
        liveDuration = events.last?.time ?? 0
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        events.append(contentsOf: pending)
        pending.removeAll()
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isRecording {
                self.flushPending()
                self.liveDuration = CFAbsoluteTimeGetCurrent() - self.startTime
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // Re-enable on tap timeout / disable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        guard let kind = RecordedEvent.Kind(rawValue: Int(type.rawValue)) else { return }

        if kind == .mouseMoved && !UserDefaults.standard.bool(forKey: "recordMouseMoves") {
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if kind.isKey, ignoredKeyCodes.contains(keyCode) { return }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let loc = event.location
        let recorded = RecordedEvent(
            kind: kind,
            time: elapsed,
            x: loc.x,
            y: loc.y,
            keyCode: keyCode,
            flags: event.flags.rawValue,
            mouseButton: event.getIntegerValueField(.mouseEventButtonNumber),
            clickCount: event.getIntegerValueField(.mouseEventClickState),
            scrollDeltaY: {
                let p = Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
                return p == 0 ? Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 12 : p
            }(),
            scrollDeltaX: {
                let p = Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
                return p == 0 ? Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * 12 : p
            }()
        )

        // The tap's run-loop source is on the main run loop, so this executes
        // on the main thread already — append directly. The display timer
        // flushes into the @Published array at 10 Hz, and stopRecording()
        // flushes synchronously, so no tail events are ever lost.
        if Thread.isMainThread {
            pending.append(recorded)
        } else {
            DispatchQueue.main.async { self.pending.append(recorded) }
        }
    }
}
