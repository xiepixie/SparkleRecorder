import Foundation
import CoreGraphics

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

        public var isMouse: Bool {
            switch self {
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                 .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                 .otherMouseDown, .otherMouseUp, .otherMouseDragged:
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

    public init(kind: Kind, time: TimeInterval, x: CGFloat, y: CGFloat, keyCode: UInt16, flags: UInt64, mouseButton: Int64, clickCount: Int64, scrollDeltaY: Int32, scrollDeltaX: Int32) {
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
