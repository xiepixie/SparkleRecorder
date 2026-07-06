import Foundation

public enum SemanticRecordingPreflightPresentationStatus: String, Codable, Equatable, Sendable {
    case ready
    case degraded
    case blocked
}

public enum SemanticRecordingPreflightPresentationActionKind: String, Codable, Equatable, Sendable {
    case startRecording
    case continueDegraded
    case openPermissionSettings
    case retryPreflight
}

public struct SemanticRecordingPreflightPresentationAction: Codable, Equatable, Sendable {
    public var kind: SemanticRecordingPreflightPresentationActionKind
    public var label: String
    public var permission: SemanticRecordingPermissionKind?

    public init(
        kind: SemanticRecordingPreflightPresentationActionKind,
        label: String,
        permission: SemanticRecordingPermissionKind? = nil
    ) {
        self.kind = kind
        self.label = label
        self.permission = permission
    }
}

public struct SemanticRecordingPreflightIssuePresentation: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var permission: SemanticRecordingPermissionKind
    public var severity: SemanticRecordingPreflightSeverity
    public var title: String
    public var detail: String
    public var affectedCapabilityLabels: [String]
    public var action: SemanticRecordingPreflightPresentationAction

    public init(
        id: String,
        permission: SemanticRecordingPermissionKind,
        severity: SemanticRecordingPreflightSeverity,
        title: String,
        detail: String,
        affectedCapabilityLabels: [String],
        action: SemanticRecordingPreflightPresentationAction
    ) {
        self.id = id
        self.permission = permission
        self.severity = severity
        self.title = title
        self.detail = detail
        self.affectedCapabilityLabels = affectedCapabilityLabels
        self.action = action
    }
}

public struct SemanticRecordingPreflightPresentation: Codable, Equatable, Sendable {
    public var status: SemanticRecordingPreflightPresentationStatus
    public var canStart: Bool
    public var title: String
    public var summary: String
    public var availableCapabilityLabels: [String]
    public var issues: [SemanticRecordingPreflightIssuePresentation]
    public var primaryAction: SemanticRecordingPreflightPresentationAction
    public var secondaryAction: SemanticRecordingPreflightPresentationAction?

    public init(
        status: SemanticRecordingPreflightPresentationStatus,
        canStart: Bool,
        title: String,
        summary: String,
        availableCapabilityLabels: [String],
        issues: [SemanticRecordingPreflightIssuePresentation],
        primaryAction: SemanticRecordingPreflightPresentationAction,
        secondaryAction: SemanticRecordingPreflightPresentationAction? = nil
    ) {
        self.status = status
        self.canStart = canStart
        self.title = title
        self.summary = summary
        self.availableCapabilityLabels = availableCapabilityLabels
        self.issues = issues
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

public enum SemanticRecordingPreflightPresenter {
    public static func presentation(
        for result: SemanticRecordingPreflightResult
    ) -> SemanticRecordingPreflightPresentation {
        let issues = result.issues.map(issuePresentation)
        let availableCapabilityLabels = SemanticRecordingPreflightCapability.allCases
            .filter { result.hasCapability($0) }
            .map(capabilityLabel)

        if !result.isReadyToStart {
            let firstBlockingPermission = result.blockingIssues.first?.permission
            return SemanticRecordingPreflightPresentation(
                status: .blocked,
                canStart: false,
                title: "Semantic recording is blocked",
                summary: "Grant the required permissions before recording video, keyframes and playable macro events.",
                availableCapabilityLabels: availableCapabilityLabels,
                issues: issues,
                primaryAction: permissionAction(for: firstBlockingPermission),
                secondaryAction: retryAction
            )
        }

        if result.isDegraded {
            return SemanticRecordingPreflightPresentation(
                status: .degraded,
                canStart: true,
                title: "Semantic recording can start with limited context",
                summary: "The recording can proceed, but some semantic evidence will be omitted until the degraded permission is granted.",
                availableCapabilityLabels: availableCapabilityLabels,
                issues: issues,
                primaryAction: SemanticRecordingPreflightPresentationAction(
                    kind: .continueDegraded,
                    label: "Continue without full context"
                ),
                secondaryAction: permissionAction(for: result.degradedIssues.first?.permission)
            )
        }

        return SemanticRecordingPreflightPresentation(
            status: .ready,
            canStart: true,
            title: "Semantic recording is ready",
            summary: "Video, keyframes, playable events and semantic observations are available.",
            availableCapabilityLabels: availableCapabilityLabels,
            issues: [],
            primaryAction: SemanticRecordingPreflightPresentationAction(
                kind: .startRecording,
                label: "Start semantic recording"
            )
        )
    }

    private static let retryAction = SemanticRecordingPreflightPresentationAction(
        kind: .retryPreflight,
        label: "Check again"
    )

    private static func issuePresentation(
        _ issue: SemanticRecordingPreflightIssue
    ) -> SemanticRecordingPreflightIssuePresentation {
        SemanticRecordingPreflightIssuePresentation(
            id: issue.id,
            permission: issue.permission,
            severity: issue.severity,
            title: issueTitle(for: issue),
            detail: issue.message,
            affectedCapabilityLabels: issue.affectedCapabilities.map(capabilityLabel),
            action: permissionAction(for: issue.permission)
        )
    }

    private static func issueTitle(for issue: SemanticRecordingPreflightIssue) -> String {
        switch issue.severity {
        case .blocking:
            return "\(permissionLabel(issue.permission)) required"
        case .degraded:
            return "\(permissionLabel(issue.permission)) recommended"
        }
    }

    private static func permissionAction(
        for permission: SemanticRecordingPermissionKind?
    ) -> SemanticRecordingPreflightPresentationAction {
        guard let permission else {
            return retryAction
        }
        return SemanticRecordingPreflightPresentationAction(
            kind: .openPermissionSettings,
            label: "Open \(permissionLabel(permission)) settings",
            permission: permission
        )
    }

    private static func permissionLabel(_ permission: SemanticRecordingPermissionKind) -> String {
        switch permission {
        case .inputMonitoring:
            return "Input Monitoring"
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen Recording"
        }
    }

    private static func capabilityLabel(_ capability: SemanticRecordingPreflightCapability) -> String {
        switch capability {
        case .playableEvents:
            return "Playable macro events"
        case .movieRecording:
            return "Video recording"
        case .keyframeCapture:
            return "Event-aligned keyframes"
        case .visionOCR:
            return "OCR indexing"
        case .accessibilitySnapshots:
            return "AX element snapshots"
        case .windowMetadata:
            return "Window metadata"
        }
    }
}
