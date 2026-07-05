import CoreGraphics

public enum PreviewPathEdit: Equatable, Sendable {
    case start(CGSize)
    case end(CGSize)
    case body(CGSize)
    case point(index: Int, translation: CGSize)
}

public struct PreviewPathGeometry: Equatable, Sendable {
    public var startPoint: CGPoint?
    public var endPoint: CGPoint?
    public var path: [CGPoint]

    public init(startPoint: CGPoint?, endPoint: CGPoint?, path: [CGPoint]) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.path = path
    }
}

public enum PreviewPathProjector {
    public static func geometry(
        dragPath: [CGPoint],
        selectedPoint: CGPoint?,
        previewsPointSequence: Bool,
        edit: PreviewPathEdit?
    ) -> PreviewPathGeometry {
        let projectedPath = displayPath(
            dragPath: dragPath,
            selectedPoint: selectedPoint,
            previewsPointSequence: previewsPointSequence,
            edit: edit
        )

        if previewsPointSequence {
            return PreviewPathGeometry(
                startPoint: projectedPath.first,
                endPoint: projectedPath.last,
                path: projectedPath
            )
        }

        let projectedStart: CGPoint? = {
            guard let selectedPoint else { return nil }
            switch edit {
            case .start(let translation), .body(let translation):
                return translated(selectedPoint, by: translation)
            case .end, .point, nil:
                return selectedPoint
            }
        }()

        let projectedEnd: CGPoint? = {
            guard let rawEndPoint = dragPath.last else { return selectedPoint }
            switch edit {
            case .end(let translation), .body(let translation):
                return translated(rawEndPoint, by: translation)
            case .start, .point, nil:
                return rawEndPoint
            }
        }()

        return PreviewPathGeometry(
            startPoint: projectedStart,
            endPoint: projectedEnd,
            path: projectedPath
        )
    }

    public static func displayPath(
        dragPath: [CGPoint],
        selectedPoint: CGPoint?,
        previewsPointSequence: Bool,
        edit: PreviewPathEdit?
    ) -> [CGPoint] {
        guard dragPath.count > 1 else { return [] }
        guard let edit else { return dragPath }

        switch edit {
        case .start(let translation):
            if previewsPointSequence {
                return dragPath
            }
            guard let start = selectedPoint ?? dragPath.first,
                  let end = dragPath.last else {
                return dragPath
            }
            let newStart = translated(start, by: translation)
            return dragPath.map {
                conformPathPoint($0, oldStart: start, oldEnd: end, newStart: newStart, newEnd: end)
            }

        case .end(let translation):
            if previewsPointSequence {
                return dragPath
            }
            guard let start = selectedPoint ?? dragPath.first,
                  let end = dragPath.last else {
                return dragPath
            }
            let newEnd = translated(end, by: translation)
            return dragPath.map {
                conformPathPoint($0, oldStart: start, oldEnd: end, newStart: start, newEnd: newEnd)
            }

        case .body(let translation):
            return dragPath.map { translated($0, by: translation) }

        case .point(let pointIndex, let translation):
            guard dragPath.indices.contains(pointIndex) else { return dragPath }
            return dragPath.enumerated().map { index, point in
                index == pointIndex ? translated(point, by: translation) : point
            }
        }
    }

    public static func startPoint(
        selectedPoint: CGPoint?,
        dragPath: [CGPoint],
        previewsPointSequence: Bool,
        edit: PreviewPathEdit?
    ) -> CGPoint? {
        if previewsPointSequence {
            return displayPath(
                dragPath: dragPath,
                selectedPoint: selectedPoint,
                previewsPointSequence: previewsPointSequence,
                edit: edit
            ).first
        }
        guard let selectedPoint else { return nil }
        switch edit {
        case .start(let translation), .body(let translation):
            return translated(selectedPoint, by: translation)
        case .end, .point, nil:
            return selectedPoint
        }
    }

    public static func endPoint(
        selectedPoint: CGPoint?,
        dragPath: [CGPoint],
        previewsPointSequence: Bool,
        edit: PreviewPathEdit?
    ) -> CGPoint? {
        if previewsPointSequence {
            return displayPath(
                dragPath: dragPath,
                selectedPoint: selectedPoint,
                previewsPointSequence: previewsPointSequence,
                edit: edit
            ).last
        }
        guard let endPoint = dragPath.last else { return selectedPoint }
        switch edit {
        case .end(let translation), .body(let translation):
            return translated(endPoint, by: translation)
        case .start, .point, nil:
            return endPoint
        }
    }

    public static func conformPathPoint(
        _ point: CGPoint,
        oldStart: CGPoint,
        oldEnd: CGPoint,
        newStart: CGPoint,
        newEnd: CGPoint
    ) -> CGPoint {
        let mainVector = CGPoint(x: oldEnd.x - oldStart.x, y: oldEnd.y - oldStart.y)
        let newVector = CGPoint(x: newEnd.x - newStart.x, y: newEnd.y - newStart.y)
        let oldLen2 = mainVector.x * mainVector.x + mainVector.y * mainVector.y

        guard oldLen2 > 0.001 else {
            return CGPoint(
                x: point.x + newStart.x - oldStart.x,
                y: point.y + newStart.y - oldStart.y
            )
        }

        let mainVectorPerp = CGPoint(x: -mainVector.y, y: mainVector.x)
        let newVectorPerp = CGPoint(x: -newVector.y, y: newVector.x)
        let dx = point.x - oldStart.x
        let dy = point.y - oldStart.y
        let u = (dx * mainVector.x + dy * mainVector.y) / oldLen2
        let v = (dx * mainVectorPerp.x + dy * mainVectorPerp.y) / oldLen2

        return CGPoint(
            x: newStart.x + u * newVector.x + v * newVectorPerp.x,
            y: newStart.y + u * newVector.y + v * newVectorPerp.y
        )
    }

    private static func translated(_ point: CGPoint, by translation: CGSize) -> CGPoint {
        CGPoint(x: point.x + translation.width, y: point.y + translation.height)
    }
}
