import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SparkleRecorderCore

struct SemanticRecordingFrameObservationIndexer: Sendable {
    private let visionIndexer: VisionRecordingIndexer
    private let windowIndexer: SemanticRecordingWindowObservationIndexer

    init(
        visionIndexer: VisionRecordingIndexer,
        windowIndexer: SemanticRecordingWindowObservationIndexer = SemanticRecordingWindowObservationIndexer()
    ) {
        self.visionIndexer = visionIndexer
        self.windowIndexer = windowIndexer
    }

    func indexFrame(_ request: SemanticRecordingFrameIndexRequest) async throws -> [RecordingVisualObservation] {
        let visionObservations = try await visionIndexer.indexFrame(request)
        let windowObservations = await windowIndexer.indexFrame(request)
        return visionObservations + windowObservations
    }
}

struct SemanticRecordingWindowObservationIndexer: Sendable {
    private let idProvider: SemanticRecordingCaptureIDProvider

    init(
        idProvider: SemanticRecordingCaptureIDProvider = SemanticRecordingCaptureIDProvider()
    ) {
        self.idProvider = idProvider
    }

    func indexFrame(_ request: SemanticRecordingFrameIndexRequest) async -> [RecordingVisualObservation] {
        guard let window = SemanticRecordingWindowSnapshot.matching(target: request.target) else {
            return []
        }

        var observations = [
            windowObservation(
                for: window,
                request: request
            )
        ]

        if let accessibilityObservation = accessibilityObservation(
            for: window,
            request: request
        ) {
            observations.append(accessibilityObservation)
        }

        return observations
    }

    private func windowObservation(
        for window: SemanticRecordingWindowSnapshot,
        request: SemanticRecordingFrameIndexRequest
    ) -> RecordingVisualObservation {
        RecordingVisualObservation(
            id: idProvider.next(.visualObservation),
            kind: .windowSnapshot,
            recordingTime: request.frame.recordingTime,
            frameID: request.frame.id,
            bounds: window.bounds.map(Self.bounds),
            text: window.title,
            provider: "CoreGraphics.CGWindowListCopyWindowInfo",
            providerVersion: "0.1",
            labels: ["window", request.target.kind.rawValue],
            metadata: window.metadata,
            createdAt: request.createdAt
        )
    }

    private func accessibilityObservation(
        for window: SemanticRecordingWindowSnapshot,
        request: SemanticRecordingFrameIndexRequest
    ) -> RecordingVisualObservation? {
        guard let processID = window.processID,
              AXIsProcessTrusted() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let element = Self.focusedElement(in: appElement) ?? appElement
        var metadata = Self.accessibilityMetadata(for: element)
        metadata["windowID"] = String(window.windowID)
        metadata["processID"] = String(processID)
        if let ownerName = window.ownerName {
            metadata["ownerName"] = ownerName
        }

        guard !metadata.isEmpty else {
            return nil
        }

        return RecordingVisualObservation(
            id: idProvider.next(.visualObservation),
            kind: .axElement,
            recordingTime: request.frame.recordingTime,
            frameID: request.frame.id,
            bounds: Self.accessibilityBounds(for: element).map(Self.bounds),
            text: metadata["title"] ?? metadata["role"],
            provider: "ApplicationServices.AXUIElement",
            providerVersion: "0.1",
            labels: ["accessibility", request.target.kind.rawValue],
            metadata: metadata,
            createdAt: request.createdAt
        )
    }

    private static func focusedElement(in appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func accessibilityMetadata(for element: AXUIElement) -> [String: String] {
        var metadata: [String: String] = [:]
        metadata["role"] = stringAttribute(element, kAXRoleAttribute)
        metadata["subrole"] = stringAttribute(element, kAXSubroleAttribute)
        metadata["title"] = stringAttribute(element, kAXTitleAttribute)
        metadata["description"] = stringAttribute(element, kAXDescriptionAttribute)
        metadata["identifier"] = stringAttribute(element, kAXIdentifierAttribute)
        return metadata.filter { !$0.value.isEmpty }
    }

    private static func stringAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private static func accessibilityBounds(for element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )
        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        AXValueGetValue(position, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &dimensions)
        return CGRect(origin: point, size: dimensions)
    }

    private static func bounds(_ rect: CGRect) -> RecordingBounds {
        RecordingBounds(
            rect: RecordingRect(
                x: Double(rect.origin.x),
                y: Double(rect.origin.y),
                width: Double(rect.width),
                height: Double(rect.height)
            ),
            coordinateSpace: .screenPixels
        )
    }
}

private struct SemanticRecordingWindowSnapshot: Sendable {
    var windowID: UInt32
    var ownerName: String?
    var processID: pid_t?
    var title: String?
    var bounds: CGRect?
    var layer: Int?
    var bundleIdentifier: String?

    var metadata: [String: String] {
        var values: [String: String] = ["windowID": String(windowID)]
        values["ownerName"] = ownerName
        values["processID"] = processID.map(String.init)
        values["title"] = title
        values["layer"] = layer.map(String.init)
        values["bundleIdentifier"] = bundleIdentifier
        return values
    }

    static func matching(target: RecordingCaptureTarget) -> SemanticRecordingWindowSnapshot? {
        guard target.kind == .window ||
              target.windowID != nil ||
              target.appBundleIdentifier?.isEmpty == false ||
              target.windowTitle?.isEmpty == false else {
            return nil
        }

        return allWindows().first { window in
            if let windowID = target.windowID, window.windowID != windowID {
                return false
            }
            if let bundleIdentifier = target.appBundleIdentifier,
               window.bundleIdentifier != bundleIdentifier {
                return false
            }
            if let title = target.windowTitle,
               !title.isEmpty,
               window.title != title {
                return false
            }
            return true
        }
    }

    private static func allWindows() -> [SemanticRecordingWindowSnapshot] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowInfoList.compactMap { info in
            guard let windowID = uint32(info[kCGWindowNumber as String]),
                  (int(info[kCGWindowLayer as String]) ?? 0) == 0 else {
                return nil
            }
            let processID = pid(info[kCGWindowOwnerPID as String])
            return SemanticRecordingWindowSnapshot(
                windowID: windowID,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                processID: processID,
                title: info[kCGWindowName as String] as? String,
                bounds: rect(info[kCGWindowBounds as String]),
                layer: int(info[kCGWindowLayer as String]),
                bundleIdentifier: processID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            )
        }
    }

    private static func uint32(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt32(value)
        }
        if let value = value as? Int32, value >= 0 {
            return UInt32(value)
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int32 {
            return Int(value)
        }
        if let value = value as? UInt32 {
            return Int(value)
        }
        return nil
    }

    private static func pid(_ value: Any?) -> pid_t? {
        int(value).map(pid_t.init)
    }

    private static func rect(_ value: Any?) -> CGRect? {
        guard let bounds = value as? [String: Any],
              let x = double(bounds["X"]),
              let y = double(bounds["Y"]),
              let width = double(bounds["Width"]),
              let height = double(bounds["Height"]) else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? CGFloat {
            return Double(value)
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }
}
