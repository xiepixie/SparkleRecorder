import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Preview Path Projector Tests")
struct PreviewPathProjectorTests {
    @Test("Body edit translates the whole path and endpoints")
    func bodyEditTranslatesPath() {
        let path = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10)
        ]
        let edit = PreviewPathEdit.body(CGSize(width: 5, height: -2))
        let projected = PreviewPathProjector.displayPath(
            dragPath: path,
            selectedPoint: path.first,
            previewsPointSequence: false,
            edit: edit
        )

        #expect(projected == [
            CGPoint(x: 5, y: -2),
            CGPoint(x: 15, y: -2),
            CGPoint(x: 15, y: 8)
        ])
        #expect(PreviewPathProjector.startPoint(
            selectedPoint: path.first,
            dragPath: path,
            previewsPointSequence: false,
            edit: edit
        ) == CGPoint(x: 5, y: -2))
        #expect(PreviewPathProjector.endPoint(
            selectedPoint: path.first,
            dragPath: path,
            previewsPointSequence: false,
            edit: edit
        ) == CGPoint(x: 15, y: 8))

        let geometry = PreviewPathProjector.geometry(
            dragPath: path,
            selectedPoint: path.first,
            previewsPointSequence: false,
            edit: edit
        )
        #expect(geometry.startPoint == CGPoint(x: 5, y: -2))
        #expect(geometry.endPoint == CGPoint(x: 15, y: 8))
        #expect(geometry.path == projected)
    }

    @Test("Start edit conforms the drag path around the anchored end")
    func startEditConformsDragPath() {
        let path = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 5, y: 5),
            CGPoint(x: 10, y: 0)
        ]
        let projected = PreviewPathProjector.displayPath(
            dragPath: path,
            selectedPoint: path.first,
            previewsPointSequence: false,
            edit: .start(CGSize(width: 0, height: 10))
        )

        #expect(projected.count == 3)
        #expect(projected[0] == CGPoint(x: 0, y: 10))
        #expect(projected[1] == CGPoint(x: 10, y: 10))
        #expect(projected[2] == CGPoint(x: 10, y: 0))
    }

    @Test("Point sequence edits only the selected point")
    func pointSequenceEditsSinglePoint() {
        let path = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 5, y: 5),
            CGPoint(x: 10, y: 10)
        ]
        let projected = PreviewPathProjector.displayPath(
            dragPath: path,
            selectedPoint: nil,
            previewsPointSequence: true,
            edit: .point(index: 1, translation: CGSize(width: 2, height: -3))
        )

        #expect(projected == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 7, y: 2),
            CGPoint(x: 10, y: 10)
        ])

        let geometry = PreviewPathProjector.geometry(
            dragPath: path,
            selectedPoint: nil,
            previewsPointSequence: true,
            edit: .point(index: 1, translation: CGSize(width: 2, height: -3))
        )
        #expect(geometry.startPoint == CGPoint(x: 0, y: 0))
        #expect(geometry.endPoint == CGPoint(x: 10, y: 10))
        #expect(geometry.path == projected)
    }

    @Test("Geometry preserves point target endpoints when no path can be displayed")
    func geometryPreservesPointTargetEndpoints() {
        let point = CGPoint(x: 42, y: 24)

        let geometry = PreviewPathProjector.geometry(
            dragPath: [],
            selectedPoint: point,
            previewsPointSequence: false,
            edit: .body(CGSize(width: 3, height: 4))
        )

        #expect(geometry.startPoint == CGPoint(x: 45, y: 28))
        #expect(geometry.endPoint == CGPoint(x: 45, y: 28))
        #expect(geometry.path.isEmpty)
    }
}
