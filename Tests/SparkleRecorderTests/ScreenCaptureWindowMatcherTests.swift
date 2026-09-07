import CoreGraphics
import Testing
@testable import SparkleRecorder

@Suite("Screen capture window matching")
struct ScreenCaptureWindowMatcherTests {
    @Test("Stable recorded window ID wins when the browser title drifts")
    func stableRecordedWindowIDWinsAcrossTitleDrift() throws {
        let recordedFrame = CGRect(x: 0, y: 39, width: 2056, height: 1290)
        let candidates = [
            ScreenCaptureWindowDescriptor(
                windowID: 23774,
                bundleIdentifier: "com.google.Chrome",
                title: "ChatGPT",
                frame: recordedFrame,
                hasOwningApplication: true
            ),
            ScreenCaptureWindowDescriptor(
                windowID: 99999,
                bundleIdentifier: "com.google.Chrome",
                title: "ChatGPT: Chat, Work, Create & Code with AI - Google Chrome - Rong",
                frame: CGRect(x: 300, y: 120, width: 1600, height: 1000),
                hasOwningApplication: true
            )
        ]
        let request = ScreenCaptureWindowRequest(
            bundleIdentifier: "com.google.Chrome",
            title: "ChatGPT: Chat, Work, Create & Code with AI - Google Chrome - Rong",
            recordedWindowID: 23774,
            expectedFrame: recordedFrame
        )

        let index = try #require(ScreenCaptureWindowMatcher.bestMatchIndex(candidates: candidates, request: request))

        #expect(candidates[index].windowID == 23774)
    }

    @Test("Legacy title-only capture still selects the exact matching window")
    func legacyTitleOnlyCaptureStillMatchesExactly() throws {
        let candidates = [
            ScreenCaptureWindowDescriptor(
                windowID: 11,
                bundleIdentifier: "com.google.Chrome",
                title: "Other page",
                frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                hasOwningApplication: true
            ),
            ScreenCaptureWindowDescriptor(
                windowID: 12,
                bundleIdentifier: "com.google.Chrome",
                title: "ChatGPT",
                frame: CGRect(x: 50, y: 50, width: 900, height: 700),
                hasOwningApplication: true
            )
        ]
        let request = ScreenCaptureWindowRequest(
            bundleIdentifier: "com.google.Chrome",
            title: "ChatGPT",
            recordedWindowID: nil,
            expectedFrame: nil
        )

        let index = try #require(ScreenCaptureWindowMatcher.bestMatchIndex(candidates: candidates, request: request))

        #expect(candidates[index].windowID == 12)
    }

    @Test("Resolved current frame wins over a stale matching browser title after the recorded ID is gone")
    func expectedFrameWinsOverStaleMatchingTitle() throws {
        let currentFrame = CGRect(x: 0, y: 39, width: 2056, height: 1290)
        let candidates = [
            ScreenCaptureWindowDescriptor(
                windowID: 30001,
                bundleIdentifier: "com.google.Chrome",
                title: "ChatGPT",
                frame: currentFrame,
                hasOwningApplication: true
            ),
            ScreenCaptureWindowDescriptor(
                windowID: 30002,
                bundleIdentifier: "com.google.Chrome",
                title: "ChatGPT: Chat, Work, Create & Code with AI - Google Chrome - Rong",
                frame: CGRect(x: 420, y: 180, width: 1200, height: 820),
                hasOwningApplication: true
            )
        ]
        let request = ScreenCaptureWindowRequest(
            bundleIdentifier: "com.google.Chrome",
            title: "ChatGPT: Chat, Work, Create & Code with AI - Google Chrome - Rong",
            recordedWindowID: 23774,
            expectedFrame: currentFrame
        )

        let index = try #require(ScreenCaptureWindowMatcher.bestMatchIndex(candidates: candidates, request: request))

        #expect(candidates[index].windowID == 30001)
    }

    @Test("Current frame selects the same browser window when the recorded ID is gone and title changed")
    func expectedFrameRecoversTitleDriftAfterWindowIDChanges() throws {
        let currentFrame = CGRect(x: 0, y: 39, width: 2056, height: 1290)
        let candidates = [
            ScreenCaptureWindowDescriptor(
                windowID: 30001,
                bundleIdentifier: "com.google.Chrome",
                title: "ChatGPT",
                frame: currentFrame,
                hasOwningApplication: true
            ),
            ScreenCaptureWindowDescriptor(
                windowID: 30002,
                bundleIdentifier: "com.google.Chrome",
                title: "Other page",
                frame: CGRect(x: 500, y: 200, width: 1100, height: 800),
                hasOwningApplication: true
            )
        ]
        let request = ScreenCaptureWindowRequest(
            bundleIdentifier: "com.google.Chrome",
            title: "Old ChatGPT title",
            recordedWindowID: 23774,
            expectedFrame: currentFrame
        )

        let index = try #require(ScreenCaptureWindowMatcher.bestMatchIndex(candidates: candidates, request: request))

        #expect(candidates[index].windowID == 30001)
    }
}
