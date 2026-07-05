import CoreGraphics
import Foundation

public struct RawInputEvent: Equatable, Sendable {
    public var kind: RecordedEvent.Kind
    public var timestamp: UInt64
    public var location: CGPoint
    public var keyCode: UInt16
    public var flags: UInt64
    public var mouseButton: Int64
    public var clickCount: Int64
    public var unicodeString: String?
    public var scrollSample: RecordingScrollSample?

    public init(
        kind: RecordedEvent.Kind,
        timestamp: UInt64,
        location: CGPoint,
        keyCode: UInt16 = 0,
        flags: UInt64 = 0,
        mouseButton: Int64 = 0,
        clickCount: Int64 = 0,
        unicodeString: String? = nil,
        scrollSample: RecordingScrollSample? = nil
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.location = location
        self.keyCode = keyCode
        self.flags = flags
        self.mouseButton = mouseButton
        self.clickCount = clickCount
        self.unicodeString = unicodeString
        self.scrollSample = scrollSample
    }
}

public struct RecordingPipelineOutput: Sendable {
    public var registry: RecordingSurfaceRegistry
    public var event: RecordedEvent

    public init(registry: RecordingSurfaceRegistry, event: RecordedEvent) {
        self.registry = registry
        self.event = event
    }
}

public struct RecordingEventPipeline: Sendable {
    public var recordMouseMoves: Bool
    public var ignoredKeyCodes: Set<UInt16>
    public var resumeOffsetDuration: TimeInterval
    public var surfaceMatcher: SurfaceMatcher
    public private(set) var registry: RecordingSurfaceRegistry
    public private(set) var baseTimestamp: UInt64?
    public private(set) var dragSampler: RecordingDragSampler

    private var lastDroppedDragInput: RawInputEvent?

    public init(
        recordMouseMoves: Bool = false,
        ignoredKeyCodes: Set<UInt16> = [],
        resumeOffsetDuration: TimeInterval = 0,
        surfaceMatcher: SurfaceMatcher = SurfaceMatcher(),
        registry: RecordingSurfaceRegistry = RecordingSurfaceRegistry(),
        baseTimestamp: UInt64? = nil,
        dragSampler: RecordingDragSampler = RecordingDragSampler()
    ) {
        self.recordMouseMoves = recordMouseMoves
        self.ignoredKeyCodes = ignoredKeyCodes
        self.resumeOffsetDuration = resumeOffsetDuration
        self.surfaceMatcher = surfaceMatcher
        self.registry = registry
        self.baseTimestamp = baseTimestamp
        self.dragSampler = dragSampler
    }

    public mutating func reset(
        recordMouseMoves: Bool,
        ignoredKeyCodes: Set<UInt16>,
        resumeOffsetDuration: TimeInterval,
        registry: RecordingSurfaceRegistry = RecordingSurfaceRegistry()
    ) {
        self.recordMouseMoves = recordMouseMoves
        self.ignoredKeyCodes = ignoredKeyCodes
        self.resumeOffsetDuration = resumeOffsetDuration
        self.registry = registry
        baseTimestamp = nil
        dragSampler = RecordingDragSampler(configuration: dragSampler.configuration)
        lastDroppedDragInput = nil
    }

    public mutating func process(
        _ input: RawInputEvent,
        trackedActiveSurface: PlaybackSurface?
    ) -> [RecordingPipelineOutput] {
        if input.kind == .mouseMoved, !recordMouseMoves {
            return []
        }

        let eventTime = RecordingTimeline.eventTime(
            timestamp: input.timestamp,
            baseTimestamp: baseTimestamp,
            resumeOffsetDuration: resumeOffsetDuration
        )
        baseTimestamp = eventTime.baseTimestamp

        if input.kind.isKey, ignoredKeyCodes.contains(input.keyCode) {
            return []
        }

        var outputs: [RecordingPipelineOutput] = []

        if input.kind.isDragged {
            let decision = dragSampler.processDrag(location: input.location, time: eventTime.elapsed)
            if !decision.shouldKeep {
                lastDroppedDragInput = input
                return []
            }
            lastDroppedDragInput = nil
        } else if input.kind.startsMouseGesture {
            dragSampler.processMouseDown(location: input.location, time: eventTime.elapsed)
            lastDroppedDragInput = nil
        } else if input.kind.endsMouseGesture {
            _ = dragSampler.processMouseUp()
            if let droppedInput = lastDroppedDragInput {
                let droppedTime = RecordingTimeline.eventTime(
                    timestamp: droppedInput.timestamp,
                    baseTimestamp: baseTimestamp,
                    resumeOffsetDuration: resumeOffsetDuration
                )
                outputs.append(makeOutput(
                    from: droppedInput,
                    elapsed: droppedTime.elapsed,
                    trackedActiveSurface: trackedActiveSurface
                ))
                lastDroppedDragInput = nil
            }
        }

        outputs.append(makeOutput(
            from: input,
            elapsed: eventTime.elapsed,
            trackedActiveSurface: trackedActiveSurface
        ))
        return outputs
    }

    private mutating func makeOutput(
        from input: RawInputEvent,
        elapsed: TimeInterval,
        trackedActiveSurface: PlaybackSurface?
    ) -> RecordingPipelineOutput {
        let targetId = registry.update(
            eventKind: input.kind,
            trackedActiveSurface: trackedActiveSurface,
            surfaceMatcher: surfaceMatcher
        )

        let coordinateBinding = RecordingCoordinateBinder.bind(
            location: input.location,
            targetSurfaceId: targetId,
            surfaces: registry.activeSurfaces
        )
        if let updatedSurface = coordinateBinding.updatedSurface, let targetId {
            registry.activeSurfaces[targetId] = updatedSurface
        }
        let coordinateFields = coordinateBinding.fields
        let scrollResult = makeScrollResult(for: input)

        let event = RecordedEvent(
            kind: input.kind,
            time: elapsed,
            x: input.location.x,
            y: input.location.y,
            keyCode: input.keyCode,
            flags: input.flags,
            mouseButton: input.mouseButton,
            clickCount: input.clickCount,
            scrollDeltaY: scrollResult?.playbackDeltaY ?? 0,
            scrollDeltaX: scrollResult?.playbackDeltaX ?? 0,
            windowLocalX: coordinateFields.windowLocalX,
            windowLocalY: coordinateFields.windowLocalY,
            windowNormalizedX: coordinateFields.windowNormalizedX,
            windowNormalizedY: coordinateFields.windowNormalizedY,
            contentLocalX: coordinateFields.contentLocalX,
            contentLocalY: coordinateFields.contentLocalY,
            contentNormalizedX: coordinateFields.contentNormalizedX,
            contentNormalizedY: coordinateFields.contentNormalizedY,
            coordinateBinding: coordinateFields.coordinateBinding,
            coordinateStrategy: nil,
            surfaceId: targetId,
            scrollPayload: scrollResult?.payload,
            unicodeString: input.unicodeString
        )

        return RecordingPipelineOutput(registry: registry, event: event)
    }

    private func makeScrollResult(for input: RawInputEvent) -> RecordingScrollResult? {
        guard input.kind == .scrollWheel, let sample = input.scrollSample else { return nil }
        return RecordingScrollPayloadBuilder.build(from: sample)
    }
}

extension RecordedEvent.Kind {
    fileprivate var startsMouseGesture: Bool {
        switch self {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    fileprivate var endsMouseGesture: Bool {
        switch self {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    fileprivate var isDragged: Bool {
        switch self {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}
