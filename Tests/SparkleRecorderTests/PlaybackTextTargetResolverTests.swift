import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Playback text target resolver")
struct PlaybackTextTargetResolverTests {
    @Test("Text surface selection never guesses among multiple Playback Surfaces")
    func textSurfaceSelectionIsExplicitOrUniquelyLegacy() {
        let first = TestFixtures.surface(appName: "Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "First")
        let second = TestFixtures.surface(appName: "Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "Second")
        var event = RecordedEvent.make(.waitForText, time: 0)

        #expect(PlaybackTextSurfaceSelection.resolve(event: event, surfaces: ["one": first]) == "one")
        #expect(PlaybackTextSurfaceSelection.resolve(event: event, surfaces: ["one": first, "two": second]) == nil)

        event.surfaceId = "two"
        #expect(PlaybackTextSurfaceSelection.resolve(event: event, surfaces: ["one": first, "two": second]) == "two")
        event.surfaceId = "missing"
        #expect(PlaybackTextSurfaceSelection.resolve(event: event, surfaces: ["one": first, "two": second]) == nil)
    }

    @Test("Content-normalized text geometry never guesses among multiple surfaces")
    func normalizedGeometryRequiresExplicitSurfaceAtRuntime() async {
        let anchor = TextAnchor(
            text: "Ready",
            observedFrame: RectValue(x: 0, y: 0, width: 20, height: 10),
            searchContentNormalizedRegion: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.2)
        )
        let event = RecordedEvent(
            kind: .waitForText,
            time: 0,
            x: 0,
            y: 0,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 0,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            textAnchor: anchor,
            textTimeout: 1
        )
        let surface = TestFixtures.surface(
            recordedFrame: RectValue(x: 0, y: 0, width: 800, height: 600)
        )
        let secondSurfaceID = "secondary"
        let secondSurface = TestFixtures.surface(
            appName: "Finder",
            bundleIdentifier: "com.apple.finder",
            windowTitle: "Second",
            recordedFrame: RectValue(x: 900, y: 0, width: 800, height: 600)
        )
        let context = PlaybackContext(
            surfaces: [TestFixtures.surfaceId: surface, secondSurfaceID: secondSurface],
            currentSurfaceFrames: [
                TestFixtures.surfaceId: RectValue(x: 100, y: 100, width: 800, height: 600),
                secondSurfaceID: RectValue(x: 900, y: 100, width: 800, height: 600)
            ],
            currentContentFrames: [
                TestFixtures.surfaceId: RectValue(x: 100, y: 140, width: 800, height: 560),
                secondSurfaceID: RectValue(x: 900, y: 140, width: 800, height: 560)
            ]
        )

        do {
            _ = try await PlaybackTextTargetResolver().resolve(event: event, context: context, anchor: anchor)
            Issue.record("Resolver guessed a surface for content-normalized geometry")
        } catch let error as PointResolveError {
            switch error {
            case .missingSurface(let id):
                #expect(id == "nil")
            default:
                Issue.record("Unexpected point resolution error: \(String(describing: error))")
            }
        } catch {
            Issue.record("Unexpected error: \(String(describing: error))")
        }
    }
}
