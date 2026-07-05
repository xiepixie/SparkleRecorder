import CoreGraphics
import Foundation
@testable import SparkleRecorderCore

enum TestFixtures {
    static let surfaceId = "main"

    static func surface(
        appName: String? = "Finder",
        bundleIdentifier: String? = "com.apple.finder",
        windowTitle: String? = "Desktop",
        recordedFrame: RectValue = RectValue(x: 100, y: 100, width: 800, height: 600),
        recordedContentFrame: RectValue? = nil
    ) -> PlaybackSurface {
        PlaybackSurface(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            recordedFrame: recordedFrame,
            recordedContentFrame: recordedContentFrame
        )
    }

    static func playbackContext(
        surfaceId: String = surfaceId,
        surface: PlaybackSurface = surface(),
        currentFrame: RectValue = RectValue(x: 120, y: 140, width: 800, height: 600),
        currentContentFrame: RectValue? = nil,
        coordinateMode: CoordinateMode = .boundWindowOffset
    ) -> PlaybackContext {
        var contentFrames: [String: RectValue] = [:]
        if let currentContentFrame {
            contentFrames[surfaceId] = currentContentFrame
        }

        return PlaybackContext(
            surfaces: [surfaceId: surface],
            currentSurfaceFrames: [surfaceId: currentFrame],
            currentContentFrames: contentFrames,
            coordinateMode: coordinateMode
        )
    }

    static func clickEvent(
        time: TimeInterval = 0.1,
        x: CGFloat = 120,
        y: CGFloat = 240,
        surfaceId: String? = nil
    ) -> RecordedEvent {
        var event = RecordedEvent.make(
            .leftMouseDown,
            time: time,
            x: x,
            y: y,
            mouseButton: 0,
            clickCount: 1
        )
        event.surfaceId = surfaceId
        return event
    }

    static func clickPair(
        downTime: TimeInterval = 0.1,
        upTime: TimeInterval = 0.2,
        x: CGFloat = 100,
        y: CGFloat = 100
    ) -> [RecordedEvent] {
        [
            RecordedEvent.make(.leftMouseDown, time: downTime, x: x, y: y, mouseButton: 0, clickCount: 1),
            RecordedEvent.make(.leftMouseUp, time: upTime, x: x, y: y, mouseButton: 0, clickCount: 1)
        ]
    }
}
