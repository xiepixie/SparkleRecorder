import ApplicationServices
import Cocoa
import Foundation
import SparkleRecorderCore

struct SemanticRecordingSuppressionContextClient: @unchecked Sendable {
    var context: @Sendable (
        _ fallbackTarget: RecordingCaptureTarget,
        _ recordingTime: TimeInterval
    ) -> SemanticRecordingSuppressionContext

    init(
        context: @escaping @Sendable (
            _ fallbackTarget: RecordingCaptureTarget,
            _ recordingTime: TimeInterval
        ) -> SemanticRecordingSuppressionContext
    ) {
        self.context = context
    }
}

extension SemanticRecordingSuppressionContextClient {
    static let live = SemanticRecordingSuppressionContextClient { fallbackTarget, recordingTime in
        let target = SemanticRecordingSuppressionContextClient.currentCaptureTarget(
            fallback: fallbackTarget
        )
        return SemanticRecordingSuppressionContext(
            recordingTime: recordingTime,
            target: target,
            domain: SemanticRecordingSuppressionContextClient.domainCandidate(from: target),
            secureInputEnabled: false,
            passwordFieldFocused: SemanticRecordingSuppressionContextClient.focusedElementLooksSecure(
                target: target
            ),
            createdAt: Date()
        )
    }

    static let disabled = SemanticRecordingSuppressionContextClient { fallbackTarget, recordingTime in
        SemanticRecordingSuppressionContext(
            recordingTime: recordingTime,
            target: fallbackTarget
        )
    }

    private static func currentCaptureTarget(
        fallback: RecordingCaptureTarget
    ) -> RecordingCaptureTarget {
        guard let surface = try? WindowSurfaceCapture().captureFrontmostWindow() else {
            return fallback
        }
        return SemanticRecordingCaptureTargetMapper.target(surface: surface)
    }

    private static func focusedElementLooksSecure(
        target: RecordingCaptureTarget
    ) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let runningApplication = target.appBundleIdentifier.flatMap { bundleID in
            NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
            }
        } ?? NSWorkspace.shared.frontmostApplication

        guard let runningApplication else {
            return false
        }

        let axApplication = AXUIElementCreateApplication(runningApplication.processIdentifier)
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            axApplication,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedResult == .success,
              let focusedElement = focusedRef else {
            return false
        }

        let element = focusedElement as! AXUIElement
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, element: element)
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }

        let role = stringAttribute(kAXRoleAttribute as CFString, element: element)
        let roleDescription = stringAttribute(kAXRoleDescriptionAttribute as CFString, element: element)
        let title = stringAttribute(kAXTitleAttribute as CFString, element: element)
        let description = stringAttribute(kAXDescriptionAttribute as CFString, element: element)
        return [role, roleDescription, title, description]
            .contains { value in
                let normalized = value.lowercased()
                return normalized.contains("password") || normalized.contains("secure")
            }
    }

    private static func stringAttribute(
        _ attribute: CFString,
        element: AXUIElement
    ) -> String {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success,
              let value = valueRef as? String else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func domainCandidate(
        from target: RecordingCaptureTarget
    ) -> String? {
        guard let title = target.windowTitle else {
            return nil
        }

        let pattern = #"(?i)\b(?:https?://)?(?:www\.)?([a-z0-9][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: title,
                range: NSRange(title.startIndex..<title.endIndex, in: title)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[range])
    }
}

extension SemanticRecordingSuppressionRules {
    static var liveUserDefaults: Self {
        let defaults = UserDefaults.standard
        return SemanticRecordingSuppressionSettings(
            excludedApplicationBundleIDs: defaults.stringArray(
                forKey: "semanticRecordingExcludedApplicationBundleIDs"
            ) ?? [],
            excludedWindowTitleFragments: defaults.stringArray(
                forKey: "semanticRecordingExcludedWindowTitleFragments"
            ) ?? [],
            excludedDomains: defaults.stringArray(
                forKey: "semanticRecordingExcludedDomains"
            ) ?? [],
            maximumArtifactByteCount: defaults.object(
                forKey: "semanticRecordingMaximumArtifactByteCount"
            ) as? Int
        ).rules
    }
}

extension SemanticRecordingSuppressionProducer {
    static var liveUserDefaults: Self {
        SemanticRecordingSuppressionProducer(rules: .liveUserDefaults)
    }
}
