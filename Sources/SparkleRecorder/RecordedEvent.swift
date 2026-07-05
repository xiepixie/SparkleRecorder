import Foundation
import CoreGraphics

public enum CoordinateBinding: String, Codable {
    case targetWindow
    case globalScreen
    case unbound
}

public enum CoordinateStrategy: String, Codable {
    case windowLocalPreferred
    case normalizedPreferred
    case absoluteOnly
    case locatorOnly
}

public enum LocatorFallbackPolicy: String, Codable {
    case fail
    case allowCoordinateFallback
}

public struct BehaviorGroupID: Codable, Equatable, Hashable {
    public var rawValue: UUID
    
    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct PointValue: Codable, Equatable {
    public var x: CGFloat
    public var y: CGFloat
    
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

public enum TextMatchMode: String, Codable, Equatable {
    case contains
    case exact
}

public struct TextAnchor: Codable, Equatable {
    public var text: String
    public var matchMode: TextMatchMode
    public var observedFrame: RectValue
    public var searchRegion: RectValue?
    public var occurrenceHint: Int?
    public var coordinateFallback: PointValue?
    public var observedContentNormalizedFrame: RectValue?
    public var searchContentNormalizedRegion: RectValue?
    public var coordinateFallbackContentNormalized: PointValue?
    
    public init(
        text: String,
        matchMode: TextMatchMode = .contains,
        observedFrame: RectValue,
        searchRegion: RectValue? = nil,
        occurrenceHint: Int? = nil,
        coordinateFallback: PointValue? = nil,
        observedContentNormalizedFrame: RectValue? = nil,
        searchContentNormalizedRegion: RectValue? = nil,
        coordinateFallbackContentNormalized: PointValue? = nil
    ) {
        self.text = text
        self.matchMode = matchMode
        self.observedFrame = observedFrame
        self.searchRegion = searchRegion
        self.occurrenceHint = occurrenceHint
        self.coordinateFallback = coordinateFallback
        self.observedContentNormalizedFrame = observedContentNormalizedFrame
        self.searchContentNormalizedRegion = searchContentNormalizedRegion
        self.coordinateFallbackContentNormalized = coordinateFallbackContentNormalized
    }
}

public struct ScrollPayload: Codable, Equatable {
    public var deltaX: CGFloat
    public var deltaY: CGFloat
    public var lineDeltaX: Int32?
    public var lineDeltaY: Int32?
    public var phase: Int
    public var momentumPhase: Int?
    public var fixedDeltaX: Double?
    public var fixedDeltaY: Double?
    public var isContinuous: Bool
    
    public init(
        deltaX: CGFloat,
        deltaY: CGFloat,
        lineDeltaX: Int32? = nil,
        lineDeltaY: Int32? = nil,
        phase: Int,
        momentumPhase: Int? = nil,
        fixedDeltaX: Double? = nil,
        fixedDeltaY: Double? = nil,
        isContinuous: Bool
    ) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.lineDeltaX = lineDeltaX
        self.lineDeltaY = lineDeltaY
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.fixedDeltaX = fixedDeltaX
        self.fixedDeltaY = fixedDeltaY
        self.isContinuous = isContinuous
    }
}

public struct RecordedEvent: Codable, Equatable {
    public enum Kind: Int, Codable {
        case leftMouseDown      = 1
        case leftMouseUp        = 2
        case rightMouseDown     = 3
        case rightMouseUp       = 4
        case mouseMoved         = 5
        case leftMouseDragged   = 6
        case rightMouseDragged  = 7
        case keyDown            = 10
        case keyUp              = 11
        case flagsChanged       = 12
        case scrollWheel        = 22
        case otherMouseDown     = 25
        case otherMouseUp       = 26
        case otherMouseDragged  = 27
        case waitForText        = 100
        case verifyText         = 101

        public var isMouse: Bool {
            switch self {
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                 .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                 .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                 .scrollWheel:
                return true
            default:
                return false
            }
        }

        public var isKey: Bool {
            switch self {
            case .keyDown, .keyUp, .flagsChanged: return true
            default: return false
            }
        }
    }

    public var kind: Kind
    /// Seconds since the start of the recording.
    public var time: TimeInterval
    public var x: CGFloat
    public var y: CGFloat
    public var keyCode: UInt16
    public var flags: UInt64
    public var mouseButton: Int64
    public var clickCount: Int64
    public var scrollDeltaY: Int32
    public var scrollDeltaX: Int32
    
    // Phase 3: Advanced Scroll & Keyboard
    public var scrollPayload: ScrollPayload?
    public var unicodeString: String?
    
    // Phase 1: Flat fields implementation
    public var windowLocalX: CGFloat?
    public var windowLocalY: CGFloat?
    public var windowNormalizedX: CGFloat?
    public var windowNormalizedY: CGFloat?
    
    // Phase 12: Content-Frame Coordinate Upgrade
    public var contentLocalX: CGFloat?
    public var contentLocalY: CGFloat?
    public var contentNormalizedX: CGFloat?
    public var contentNormalizedY: CGFloat?
    
    public var coordinateBinding: CoordinateBinding?
    public var coordinateStrategy: CoordinateStrategy?
    public var locatorFallbackPolicy: LocatorFallbackPolicy?
    
    // Multi-App workflow window surface mapping
    public var surfaceId: String?
    
    // Phase 8 & 10: OCR & Semantic Actions (Upgraded to TextAnchor)
    public var textAnchor: TextAnchor?
    public var textTimeout: TimeInterval?
    public var verifyMustExist: Bool?
    
    // Editor-only semantic binding. Raw playback still uses the underlying events.
    public var behaviorGroupID: BehaviorGroupID?
    public var behaviorGroupName: String?


    public init(
        kind: Kind, time: TimeInterval, x: CGFloat, y: CGFloat, keyCode: UInt16,
        flags: UInt64, mouseButton: Int64, clickCount: Int64, scrollDeltaY: Int32, scrollDeltaX: Int32,
        windowLocalX: CGFloat? = nil, windowLocalY: CGFloat? = nil,
        windowNormalizedX: CGFloat? = nil, windowNormalizedY: CGFloat? = nil,
        contentLocalX: CGFloat? = nil, contentLocalY: CGFloat? = nil,
        contentNormalizedX: CGFloat? = nil, contentNormalizedY: CGFloat? = nil,
        coordinateBinding: CoordinateBinding? = nil, coordinateStrategy: CoordinateStrategy? = nil,
        locatorFallbackPolicy: LocatorFallbackPolicy? = nil,
        surfaceId: String? = nil,
        scrollPayload: ScrollPayload? = nil,
        unicodeString: String? = nil,
        textAnchor: TextAnchor? = nil,
        textTimeout: TimeInterval? = nil,
        verifyMustExist: Bool? = nil,
        behaviorGroupID: BehaviorGroupID? = nil,
        behaviorGroupName: String? = nil
    ) {
        self.kind = kind
        self.time = time
        self.x = x
        self.y = y
        self.keyCode = keyCode
        self.flags = flags
        self.mouseButton = mouseButton
        self.clickCount = clickCount
        self.scrollDeltaY = scrollDeltaY
        self.scrollDeltaX = scrollDeltaX
        
        self.windowLocalX = windowLocalX
        self.windowLocalY = windowLocalY
        self.windowNormalizedX = windowNormalizedX
        self.windowNormalizedY = windowNormalizedY
        self.contentLocalX = contentLocalX
        self.contentLocalY = contentLocalY
        self.contentNormalizedX = contentNormalizedX
        self.contentNormalizedY = contentNormalizedY
        self.coordinateBinding = coordinateBinding
        self.coordinateStrategy = coordinateStrategy
        self.locatorFallbackPolicy = locatorFallbackPolicy
        self.surfaceId = surfaceId
        
        self.scrollPayload = scrollPayload
        self.unicodeString = unicodeString
        self.textAnchor = textAnchor
        self.textTimeout = textTimeout
        self.verifyMustExist = verifyMustExist
        self.behaviorGroupID = behaviorGroupID
        self.behaviorGroupName = behaviorGroupName
    }

    public var location: CGPoint {
        get { CGPoint(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }
}

public struct Macro: Codable {
    public var events: [RecordedEvent]
    public var createdAt: Date
    public var version: Int = 1

    public var duration: TimeInterval {
        events.last?.time ?? 0
    }
}
