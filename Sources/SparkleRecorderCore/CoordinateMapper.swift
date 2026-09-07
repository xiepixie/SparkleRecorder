import CoreGraphics

public struct CoordinateMapper: Sendable {
    public init() {}

    public func resolveWindowLocalPoint(_ localPoint: CGPoint, in frame: RectValue) -> CGPoint {
        CGPoint(x: frame.x + localPoint.x, y: frame.y + localPoint.y)
    }

    public func resolveNormalizedPoint(_ normalizedPoint: CGPoint, in frame: RectValue) -> CGPoint {
        CGPoint(
            x: frame.x + normalizedPoint.x * frame.width,
            y: frame.y + normalizedPoint.y * frame.height
        )
    }

    public func assertPointIsInsideWindow(
        _ point: CGPoint,
        in frame: RectValue,
        tolerance: CGFloat = 0
    ) -> Bool {
        frame.cgRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    public struct ResolvedContentFrame: Sendable {
        public let frame: CGRect
        public let source: Source
        public let role: String?
        public let subrole: String?
        public let confidence: Double

        public init(
            frame: CGRect,
            source: Source,
            role: String?,
            subrole: String?,
            confidence: Double
        ) {
            self.frame = frame
            self.source = source
            self.role = role
            self.subrole = subrole
            self.confidence = confidence
        }

        public enum Source: String, Sendable {
            case axIOSContentGroup
            case axWebArea
            case axScrollArea
            case axGroup
            case axGenericElement
            case fallbackTitleBar
            case fallbackOuterFrame
        }
    }
}
