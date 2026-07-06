import Foundation

public enum SemanticRecordingPermissionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case inputMonitoring
    case accessibility
    case screenRecording
}

public enum SemanticRecordingPermissionState: String, Codable, Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

public struct SemanticRecordingPermissionSnapshot: Codable, Equatable, Sendable {
    public var inputMonitoring: SemanticRecordingPermissionState
    public var accessibility: SemanticRecordingPermissionState
    public var screenRecording: SemanticRecordingPermissionState

    public init(
        inputMonitoring: SemanticRecordingPermissionState,
        accessibility: SemanticRecordingPermissionState,
        screenRecording: SemanticRecordingPermissionState
    ) {
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    public func state(for permission: SemanticRecordingPermissionKind) -> SemanticRecordingPermissionState {
        switch permission {
        case .inputMonitoring:
            return inputMonitoring
        case .accessibility:
            return accessibility
        case .screenRecording:
            return screenRecording
        }
    }
}

public enum SemanticRecordingPreflightCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case playableEvents
    case movieRecording
    case keyframeCapture
    case visionOCR
    case accessibilitySnapshots
    case windowMetadata
}

public enum SemanticRecordingPreflightSeverity: String, Codable, Equatable, Sendable {
    case blocking
    case degraded
}

public struct SemanticRecordingPreflightIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var permission: SemanticRecordingPermissionKind
    public var state: SemanticRecordingPermissionState
    public var severity: SemanticRecordingPreflightSeverity
    public var affectedCapabilities: [SemanticRecordingPreflightCapability]
    public var message: String

    public init(
        permission: SemanticRecordingPermissionKind,
        state: SemanticRecordingPermissionState,
        severity: SemanticRecordingPreflightSeverity,
        affectedCapabilities: [SemanticRecordingPreflightCapability],
        message: String
    ) {
        self.permission = permission
        self.state = state
        self.severity = severity
        self.affectedCapabilities = affectedCapabilities
        self.message = message
        self.id = [
            permission.rawValue,
            state.rawValue,
            severity.rawValue,
            affectedCapabilities.map(\.rawValue).joined(separator: "+")
        ].joined(separator: ":")
    }
}

public struct SemanticRecordingPreflightPolicy: Codable, Equatable, Sendable {
    public var capturePolicy: RecordingCapturePolicy
    public var requiresPlayableEvents: Bool
    public var wantsVisionOCR: Bool
    public var wantsAccessibilitySnapshots: Bool
    public var wantsWindowMetadata: Bool

    public init(
        capturePolicy: RecordingCapturePolicy = RecordingCapturePolicy(),
        requiresPlayableEvents: Bool = true,
        wantsVisionOCR: Bool = true,
        wantsAccessibilitySnapshots: Bool = true,
        wantsWindowMetadata: Bool = true
    ) {
        self.capturePolicy = capturePolicy
        self.requiresPlayableEvents = requiresPlayableEvents
        self.wantsVisionOCR = wantsVisionOCR
        self.wantsAccessibilitySnapshots = wantsAccessibilitySnapshots
        self.wantsWindowMetadata = wantsWindowMetadata
    }
}

public struct SemanticRecordingPreflightResult: Codable, Equatable, Sendable {
    public var policy: SemanticRecordingPreflightPolicy
    public var snapshot: SemanticRecordingPermissionSnapshot
    public var availableCapabilities: Set<SemanticRecordingPreflightCapability>
    public var issues: [SemanticRecordingPreflightIssue]

    public init(
        policy: SemanticRecordingPreflightPolicy,
        snapshot: SemanticRecordingPermissionSnapshot,
        availableCapabilities: Set<SemanticRecordingPreflightCapability>,
        issues: [SemanticRecordingPreflightIssue]
    ) {
        self.policy = policy
        self.snapshot = snapshot
        self.availableCapabilities = availableCapabilities
        self.issues = issues
    }

    public var blockingIssues: [SemanticRecordingPreflightIssue] {
        issues.filter { $0.severity == .blocking }
    }

    public var degradedIssues: [SemanticRecordingPreflightIssue] {
        issues.filter { $0.severity == .degraded }
    }

    public var isReadyToStart: Bool {
        blockingIssues.isEmpty
    }

    public var isDegraded: Bool {
        !degradedIssues.isEmpty
    }

    public func hasCapability(_ capability: SemanticRecordingPreflightCapability) -> Bool {
        availableCapabilities.contains(capability)
    }
}

public enum SemanticRecordingPreflightEvaluator {
    public static func evaluate(
        policy: SemanticRecordingPreflightPolicy,
        snapshot: SemanticRecordingPermissionSnapshot
    ) -> SemanticRecordingPreflightResult {
        var available = Set<SemanticRecordingPreflightCapability>()
        var issues: [SemanticRecordingPreflightIssue] = []

        if policy.requiresPlayableEvents {
            if snapshot.inputMonitoring == .authorized {
                available.insert(.playableEvents)
            } else {
                issues.append(issue(
                    permission: .inputMonitoring,
                    state: snapshot.inputMonitoring,
                    severity: .blocking,
                    affected: [.playableEvents],
                    message: "Input Monitoring is required to record playable macro events."
                ))
            }
        }

        if policy.capturePolicy.recordsVideo {
            if snapshot.screenRecording == .authorized {
                available.insert(.movieRecording)
            } else {
                issues.append(issue(
                    permission: .screenRecording,
                    state: snapshot.screenRecording,
                    severity: .blocking,
                    affected: [.movieRecording],
                    message: "Screen Recording is required to capture the semantic recording movie."
                ))
            }
        }

        if policy.capturePolicy.recordsKeyframes {
            if snapshot.screenRecording == .authorized {
                available.insert(.keyframeCapture)
                if policy.wantsVisionOCR {
                    available.insert(.visionOCR)
                }
            } else {
                var affected: [SemanticRecordingPreflightCapability] = [.keyframeCapture]
                if policy.wantsVisionOCR {
                    affected.append(.visionOCR)
                }
                issues.append(issue(
                    permission: .screenRecording,
                    state: snapshot.screenRecording,
                    severity: .blocking,
                    affected: affected,
                    message: "Screen Recording is required to capture event-aligned keyframes and OCR evidence."
                ))
            }
        }

        var accessibilityAffected: [SemanticRecordingPreflightCapability] = []
        if policy.wantsAccessibilitySnapshots {
            accessibilityAffected.append(.accessibilitySnapshots)
        }
        if policy.wantsWindowMetadata {
            accessibilityAffected.append(.windowMetadata)
        }
        if !accessibilityAffected.isEmpty {
            if snapshot.accessibility == .authorized {
                available.formUnion(accessibilityAffected)
            } else {
                issues.append(issue(
                    permission: .accessibility,
                    state: snapshot.accessibility,
                    severity: .degraded,
                    affected: accessibilityAffected,
                    message: "Accessibility is missing; semantic recording can continue without AX/window snapshots."
                ))
            }
        }

        return SemanticRecordingPreflightResult(
            policy: policy,
            snapshot: snapshot,
            availableCapabilities: available,
            issues: issues
        )
    }

    private static func issue(
        permission: SemanticRecordingPermissionKind,
        state: SemanticRecordingPermissionState,
        severity: SemanticRecordingPreflightSeverity,
        affected: [SemanticRecordingPreflightCapability],
        message: String
    ) -> SemanticRecordingPreflightIssue {
        SemanticRecordingPreflightIssue(
            permission: permission,
            state: state,
            severity: severity,
            affectedCapabilities: affected,
            message: message
        )
    }
}

public struct SemanticRecordingPreflightClient: @unchecked Sendable {
    public var permissionSnapshot: @Sendable () async -> SemanticRecordingPermissionSnapshot

    public init(
        permissionSnapshot: @escaping @Sendable () async -> SemanticRecordingPermissionSnapshot
    ) {
        self.permissionSnapshot = permissionSnapshot
    }

    public func evaluate(
        policy: SemanticRecordingPreflightPolicy = SemanticRecordingPreflightPolicy()
    ) async -> SemanticRecordingPreflightResult {
        let snapshot = await permissionSnapshot()
        return SemanticRecordingPreflightEvaluator.evaluate(
            policy: policy,
            snapshot: snapshot
        )
    }

    public static func fixed(
        _ snapshot: SemanticRecordingPermissionSnapshot
    ) -> SemanticRecordingPreflightClient {
        SemanticRecordingPreflightClient {
            snapshot
        }
    }
}
