import Testing
@testable import SparkleRecorderCore

@Suite("Recording Capture Target Matcher Tests")
struct RecordingCaptureTargetMatcherTests {
    @Test("Stable window ID survives title changes within the same app")
    func stableWindowIDSurvivesTitleChanges() {
        let target = RecordingCaptureTarget(
            kind: .window,
            windowID: 42,
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Page A - Google Chrome"
        )
        let live = RecordingCaptureWindowIdentity(
            windowID: 42,
            bundleIdentifier: "com.google.Chrome",
            title: "Page B - Google Chrome"
        )

        #expect(RecordingCaptureTargetMatcher.matches(live, target: target))
    }

    @Test("Stable window ID still checks application identity")
    func stableWindowIDChecksApplicationIdentity() {
        let target = RecordingCaptureTarget(
            kind: .window,
            windowID: 42,
            appBundleIdentifier: "com.example.target",
            windowTitle: "Old title"
        )

        #expect(!RecordingCaptureTargetMatcher.matches(
            RecordingCaptureWindowIdentity(
                windowID: 42,
                bundleIdentifier: "com.example.other",
                title: "Old title"
            ),
            target: target
        ))
        #expect(!RecordingCaptureTargetMatcher.matches(
            RecordingCaptureWindowIdentity(
                windowID: 41,
                bundleIdentifier: "com.example.target",
                title: "Old title"
            ),
            target: target
        ))
    }

    @Test("Title remains a fallback identity when no window ID was recorded")
    func titleIsFallbackWithoutWindowID() {
        let target = RecordingCaptureTarget(
            kind: .window,
            appBundleIdentifier: "com.example.target",
            windowTitle: "Expected"
        )

        #expect(RecordingCaptureTargetMatcher.matches(
            RecordingCaptureWindowIdentity(
                windowID: 7,
                bundleIdentifier: "com.example.target",
                title: "Expected"
            ),
            target: target
        ))
        #expect(!RecordingCaptureTargetMatcher.matches(
            RecordingCaptureWindowIdentity(
                windowID: 7,
                bundleIdentifier: "com.example.target",
                title: "Different"
            ),
            target: target
        ))
    }
}
