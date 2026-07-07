import Foundation

public enum SemanticRecordingCaptureTargetMapper {
    public static func target(
        surface: PlaybackSurface?,
        surfaceID: String = "surface-1",
        fallbackDisplayID: UInt32? = nil
    ) -> RecordingCaptureTarget {
        guard let surface else {
            return RecordingCaptureTarget(
                kind: .display,
                surfaceID: surfaceID,
                displayID: fallbackDisplayID
            )
        }

        let appBundleIdentifier = surface.bundleIdentifier?.semanticTargetNonEmpty
        let appName = surface.appName?.semanticTargetNonEmpty
        let windowTitle = surface.windowTitle?.semanticTargetNonEmpty
        let hasWindowIdentity = surface.recordedWindowId != nil ||
            appBundleIdentifier != nil ||
            windowTitle != nil

        return RecordingCaptureTarget(
            kind: hasWindowIdentity ? .window : .display,
            surfaceID: surfaceID,
            displayID: surface.recordedDisplayId ?? fallbackDisplayID,
            windowID: surface.recordedWindowId,
            appBundleIdentifier: appBundleIdentifier,
            appName: appName,
            windowTitle: windowTitle
        )
    }
}

private extension String {
    var semanticTargetNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
