import Foundation

/// Stable identity used when re-resolving a recorded window for keyframes or metadata.
/// A live window title is descriptive state, not identity, once an OS window ID exists.
public struct RecordingCaptureWindowIdentity: Equatable, Sendable {
    public var windowID: UInt32
    public var bundleIdentifier: String?
    public var title: String?

    public init(
        windowID: UInt32,
        bundleIdentifier: String? = nil,
        title: String? = nil
    ) {
        self.windowID = windowID
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}

public enum RecordingCaptureTargetMatcher {
    public static func matches(
        _ candidate: RecordingCaptureWindowIdentity,
        target: RecordingCaptureTarget
    ) -> Bool {
        if let expectedWindowID = target.windowID {
            guard candidate.windowID == expectedWindowID else { return false }
            if let expectedBundle = nonEmpty(target.appBundleIdentifier) {
                guard nonEmpty(candidate.bundleIdentifier) == expectedBundle else { return false }
            }
            return true
        }

        if let expectedBundle = nonEmpty(target.appBundleIdentifier),
           nonEmpty(candidate.bundleIdentifier) != expectedBundle {
            return false
        }
        if let expectedTitle = nonEmpty(target.windowTitle),
           nonEmpty(candidate.title) != expectedTitle {
            return false
        }

        return nonEmpty(target.appBundleIdentifier) != nil || nonEmpty(target.windowTitle) != nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
