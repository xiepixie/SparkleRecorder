import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Coordinate Binder Tests")
struct RecordingCoordinateBinderTests {
    @Test("Point inside a surface records window and content coordinates")
    func pointInsideSurfaceRecordsWindowAndContentCoordinates() throws {
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 200, height: 100),
            recordedContentFrame: RectValue(x: 100, y: 120, width: 200, height: 80)
        )

        let result = RecordingCoordinateBinder.bind(
            location: CGPoint(x: 150, y: 160),
            targetSurfaceId: TestFixtures.surfaceId,
            surfaces: [TestFixtures.surfaceId: surface]
        )
        let fields = result.fields

        #expect(fields.coordinateBinding == .targetWindow)
        #expect(fields.windowLocalX == 50)
        #expect(fields.windowLocalY == 40)
        #expect(fields.windowNormalizedX == 0.25)
        #expect(fields.windowNormalizedY == 0.5)
        #expect(fields.contentLocalX == 50)
        #expect(fields.contentLocalY == 40)
        #expect(fields.contentNormalizedX == 0.25)
        #expect(fields.contentNormalizedY == 0.5)
        #expect(result.updatedSurface == nil)
    }

    @Test("Point outside target surface records global binding without local fields")
    func pointOutsideTargetSurfaceRecordsGlobalBinding() {
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 200, height: 100),
            recordedContentFrame: RectValue(x: 100, y: 120, width: 200, height: 80)
        )

        let result = RecordingCoordinateBinder.bind(
            location: CGPoint(x: 40, y: 80),
            targetSurfaceId: TestFixtures.surfaceId,
            surfaces: [TestFixtures.surfaceId: surface]
        )
        let fields = result.fields

        #expect(fields.coordinateBinding == .globalScreen)
        #expect(fields.windowLocalX == nil)
        #expect(fields.contentNormalizedX == nil)
        #expect(result.updatedSurface == nil)
    }

    @Test("Missing target surface keeps recording unbound")
    func missingTargetSurfaceKeepsRecordingUnbound() {
        let result = RecordingCoordinateBinder.bind(
            location: CGPoint(x: 150, y: 160),
            targetSurfaceId: nil,
            surfaces: [:]
        )

        #expect(result.fields.coordinateBinding == .unbound)
        #expect(result.fields.windowLocalX == nil)
        #expect(result.updatedSurface == nil)
    }

    @Test("Missing content frame falls back to whole window and returns updated surface")
    func missingContentFrameFallsBackToWholeWindow() throws {
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 100, width: 200, height: 100),
            recordedContentFrame: nil
        )

        let result = RecordingCoordinateBinder.bind(
            location: CGPoint(x: 150, y: 160),
            targetSurfaceId: TestFixtures.surfaceId,
            surfaces: [TestFixtures.surfaceId: surface]
        )
        let updatedSurface = try #require(result.updatedSurface)

        #expect(result.fields.coordinateBinding == .targetWindow)
        #expect(result.fields.windowLocalX == 50)
        #expect(result.fields.windowLocalY == 60)
        #expect(result.fields.windowNormalizedY == 0.6)
        #expect(result.fields.contentLocalY == 60)
        #expect(result.fields.contentNormalizedY == 0.6)
        #expect(updatedSurface.recordedContentFrame == surface.recordedFrame)
        #expect(updatedSurface.contentFrameSource == RecordingCoordinateBinder.fallbackContentFrameSource)
    }
}
