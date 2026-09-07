import CoreGraphics
import Foundation

public struct ScrollGestureCompactionConfiguration: Equatable, Sendable {
    public var sampleInterval: TimeInterval
    public var maximumContinuousGap: TimeInterval

    public init(
        sampleInterval: TimeInterval = 1.0 / 30.0,
        maximumContinuousGap: TimeInterval = 0.12
    ) {
        self.sampleInterval = sampleInterval.isFinite && sampleInterval > 0
            ? sampleInterval
            : 1.0 / 30.0
        self.maximumContinuousGap = maximumContinuousGap.isFinite && maximumContinuousGap > 0
            ? maximumContinuousGap
            : 0.12
    }
}

public struct ScrollGestureCompactionOutput: Equatable, Sendable {
    public var event: RecordedEvent
    public var evidenceSampleRange: ClosedRange<Int>?

    public init(event: RecordedEvent, evidenceSampleRange: ClosedRange<Int>? = nil) {
        self.event = event
        self.evidenceSampleRange = evidenceSampleRange
    }
}

/// Time-based compaction for continuous scroll input.
///
/// The compactor never changes semantic action grouping. It only lowers the
/// density of the playable event stream while preserving cumulative scroll
/// delta and exact boundaries for reversals, phase changes, target changes and
/// long pauses. Discrete wheel events pass through untouched.
public struct ScrollGestureCompactor: Sendable {
    public var configuration: ScrollGestureCompactionConfiguration

    private struct Sample: Sendable {
        var event: RecordedEvent
        var evidenceSampleIndex: Int?
    }

    private struct ActiveGesture: Sendable {
        var lastEvent: RecordedEvent
        var lastDirection: CGVector?
        var nextGridTime: TimeInterval
        var pending: [Sample]
    }

    private var active: ActiveGesture?

    public init(configuration: ScrollGestureCompactionConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        active = nil
    }

    public mutating func process(
        _ event: RecordedEvent,
        evidenceSampleIndex: Int? = nil
    ) -> [ScrollGestureCompactionOutput] {
        guard isCompactableContinuousScroll(event) else {
            var output = finish()
            output.append(passThrough(event, evidenceSampleIndex: evidenceSampleIndex))
            return output
        }

        guard var gesture = active else {
            return startGesture(event, evidenceSampleIndex: evidenceSampleIndex)
        }

        if mustStartNewGesture(previous: gesture.lastEvent, current: event, lastDirection: gesture.lastDirection) {
            var output = flushPending(&gesture, at: gesture.lastEvent.time)
            active = nil
            output += startGesture(event, evidenceSampleIndex: evidenceSampleIndex)
            return output
        }

        var output: [ScrollGestureCompactionOutput] = []
        let epsilon = 0.000_000_1
        if abs(event.time - gesture.nextGridTime) <= epsilon {
            gesture.pending.append(.init(event: event, evidenceSampleIndex: evidenceSampleIndex))
            output += flushPending(&gesture, at: gesture.nextGridTime)
            advanceGrid(&gesture, beyond: event.time)
        } else if event.time > gesture.nextGridTime {
            output += flushPending(&gesture, at: gesture.nextGridTime)
            advanceGrid(&gesture, beyond: event.time)
            gesture.pending.append(.init(event: event, evidenceSampleIndex: evidenceSampleIndex))
        } else {
            gesture.pending.append(.init(event: event, evidenceSampleIndex: evidenceSampleIndex))
        }

        gesture.lastEvent = event
        if let direction = direction(of: event) {
            gesture.lastDirection = direction
        }
        active = gesture
        return output
    }

    public mutating func finish() -> [ScrollGestureCompactionOutput] {
        guard var gesture = active else { return [] }
        let output = flushPending(&gesture, at: gesture.lastEvent.time)
        active = nil
        return output
    }

    private mutating func startGesture(
        _ event: RecordedEvent,
        evidenceSampleIndex: Int?
    ) -> [ScrollGestureCompactionOutput] {
        active = ActiveGesture(
            lastEvent: event,
            lastDirection: direction(of: event),
            nextGridTime: event.time + configuration.sampleInterval,
            pending: []
        )
        return [passThrough(event, evidenceSampleIndex: evidenceSampleIndex)]
    }

    private func isCompactableContinuousScroll(_ event: RecordedEvent) -> Bool {
        event.kind == .scrollWheel && event.scrollPayload?.isContinuous == true
    }

    private func mustStartNewGesture(
        previous: RecordedEvent,
        current: RecordedEvent,
        lastDirection: CGVector?
    ) -> Bool {
        guard current.time >= previous.time else { return true }
        if current.time - previous.time > configuration.maximumContinuousGap { return true }
        if metadataChanged(previous, current) { return true }
        if let previousDirection = lastDirection,
           let currentDirection = direction(of: current),
           previousDirection.dx * currentDirection.dx + previousDirection.dy * currentDirection.dy < 0 {
            return true
        }
        return false
    }

    private func metadataChanged(_ lhs: RecordedEvent, _ rhs: RecordedEvent) -> Bool {
        lhs.flags != rhs.flags
            || lhs.surfaceId != rhs.surfaceId
            || lhs.x != rhs.x
            || lhs.y != rhs.y
            || lhs.windowLocalX != rhs.windowLocalX
            || lhs.windowLocalY != rhs.windowLocalY
            || lhs.windowNormalizedX != rhs.windowNormalizedX
            || lhs.windowNormalizedY != rhs.windowNormalizedY
            || lhs.contentLocalX != rhs.contentLocalX
            || lhs.contentLocalY != rhs.contentLocalY
            || lhs.contentNormalizedX != rhs.contentNormalizedX
            || lhs.contentNormalizedY != rhs.contentNormalizedY
            || lhs.coordinateBinding != rhs.coordinateBinding
            || lhs.coordinateStrategy != rhs.coordinateStrategy
            || lhs.locatorFallbackPolicy != rhs.locatorFallbackPolicy
            || lhs.scrollPayload?.phase != rhs.scrollPayload?.phase
            || lhs.scrollPayload?.momentumPhase != rhs.scrollPayload?.momentumPhase
            || lhs.scrollPayload?.isContinuous != rhs.scrollPayload?.isContinuous
    }

    private func direction(of event: RecordedEvent) -> CGVector? {
        let payloadX = event.scrollPayload?.deltaX ?? 0
        let payloadY = event.scrollPayload?.deltaY ?? 0
        let dx = payloadX != 0 ? payloadX : CGFloat(event.scrollDeltaX)
        let dy = payloadY != 0 ? payloadY : CGFloat(event.scrollDeltaY)
        guard dx != 0 || dy != 0 else { return nil }
        return CGVector(dx: dx, dy: dy)
    }

    private func passThrough(
        _ event: RecordedEvent,
        evidenceSampleIndex: Int?
    ) -> ScrollGestureCompactionOutput {
        ScrollGestureCompactionOutput(
            event: event,
            evidenceSampleRange: evidenceSampleIndex.map { $0...$0 }
        )
    }

    private func flushPending(
        _ gesture: inout ActiveGesture,
        at time: TimeInterval
    ) -> [ScrollGestureCompactionOutput] {
        guard !gesture.pending.isEmpty else { return [] }
        let samples = gesture.pending
        gesture.pending.removeAll(keepingCapacity: true)
        return [ScrollGestureCompactionOutput(
            event: aggregate(samples.map(\.event), at: time),
            evidenceSampleRange: completeEvidenceRange(samples)
        )]
    }

    private func advanceGrid(_ gesture: inout ActiveGesture, beyond time: TimeInterval) {
        repeat {
            gesture.nextGridTime += configuration.sampleInterval
        } while gesture.nextGridTime <= time
    }

    private func completeEvidenceRange(_ samples: [Sample]) -> ClosedRange<Int>? {
        let indices = samples.compactMap(\.evidenceSampleIndex)
        guard indices.count == samples.count,
              let first = indices.first,
              let last = indices.last else { return nil }
        return min(first, last)...max(first, last)
    }

    private func aggregate(_ events: [RecordedEvent], at time: TimeInterval) -> RecordedEvent {
        precondition(!events.isEmpty)
        var result = events[events.count - 1]
        result.time = time
        result.scrollDeltaX = clampedInt32(events.reduce(Int64(0)) { $0 + Int64($1.scrollDeltaX) })
        result.scrollDeltaY = clampedInt32(events.reduce(Int64(0)) { $0 + Int64($1.scrollDeltaY) })

        if let template = result.scrollPayload {
            result.scrollPayload = ScrollPayload(
                deltaX: events.reduce(CGFloat(0)) { $0 + ($1.scrollPayload?.deltaX ?? 0) },
                deltaY: events.reduce(CGFloat(0)) { $0 + ($1.scrollPayload?.deltaY ?? 0) },
                lineDeltaX: summedOptionalInt32(events.map { $0.scrollPayload?.lineDeltaX }),
                lineDeltaY: summedOptionalInt32(events.map { $0.scrollPayload?.lineDeltaY }),
                phase: template.phase,
                momentumPhase: template.momentumPhase,
                fixedDeltaX: summedOptionalDouble(events.map { $0.scrollPayload?.fixedDeltaX }),
                fixedDeltaY: summedOptionalDouble(events.map { $0.scrollPayload?.fixedDeltaY }),
                isContinuous: template.isContinuous
            )
        }
        return result
    }

    private func summedOptionalInt32(_ values: [Int32?]) -> Int32? {
        guard values.contains(where: { $0 != nil }) else { return nil }
        return clampedInt32(values.reduce(Int64(0)) { $0 + Int64($1 ?? 0) })
    }

    private func summedOptionalDouble(_ values: [Double?]) -> Double? {
        guard values.contains(where: { $0 != nil }) else { return nil }
        return values.reduce(0) { $0 + ($1 ?? 0) }
    }

    private func clampedInt32(_ value: Int64) -> Int32 {
        if value > Int64(Int32.max) { return Int32.max }
        if value < Int64(Int32.min) { return Int32.min }
        return Int32(value)
    }
}
