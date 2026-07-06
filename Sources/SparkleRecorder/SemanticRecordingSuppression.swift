import Foundation

public struct SemanticRecordingSuppressionRules: Codable, Equatable, Sendable {
    public var excludedApplicationBundleIDs: Set<String>
    public var excludedWindowTitleFragments: [String]
    public var excludedDomains: Set<String>
    public var maximumArtifactByteCount: Int?

    public init(
        excludedApplicationBundleIDs: Set<String> = [],
        excludedWindowTitleFragments: [String] = [],
        excludedDomains: Set<String> = [],
        maximumArtifactByteCount: Int? = nil
    ) {
        self.excludedApplicationBundleIDs = Set(excludedApplicationBundleIDs.map(Self.normalizedIdentifier))
            .filter { !$0.isEmpty }
        self.excludedWindowTitleFragments = excludedWindowTitleFragments
            .map(Self.normalizedTitleFragment)
            .filter { !$0.isEmpty }
        self.excludedDomains = Set(excludedDomains.map(Self.normalizedDomain))
            .filter { !$0.isEmpty }
        self.maximumArtifactByteCount = maximumArtifactByteCount.map { max(0, $0) }
    }

    public static let empty = SemanticRecordingSuppressionRules()

    func excludes(applicationBundleID: String?) -> Bool {
        guard let applicationBundleID else { return false }
        return excludedApplicationBundleIDs.contains(Self.normalizedIdentifier(applicationBundleID))
    }

    func excludes(windowTitle: String?) -> Bool {
        guard let windowTitle else { return false }
        let normalizedTitle = Self.normalizedTitleFragment(windowTitle)
        guard !normalizedTitle.isEmpty else { return false }
        return excludedWindowTitleFragments.contains { normalizedTitle.contains($0) }
    }

    func excludes(domain: String?) -> Bool {
        guard let domain else { return false }
        let normalizedDomain = Self.normalizedDomain(domain)
        guard !normalizedDomain.isEmpty else { return false }
        return excludedDomains.contains { excluded in
            normalizedDomain == excluded || normalizedDomain.hasSuffix(".\(excluded)")
        }
    }

    func exceedsArtifactLimit(byteCount: Int?) -> Bool {
        guard let maximumArtifactByteCount,
              let byteCount else {
            return false
        }
        return byteCount > maximumArtifactByteCount
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedTitleFragment(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedDomain(_ value: String) -> String {
        var domain = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.hasPrefix("http://") || domain.hasPrefix("https://"),
           let url = URL(string: domain),
           let host = url.host {
            domain = host
        }
        if domain.hasPrefix("www.") {
            domain.removeFirst(4)
        }
        return domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

public struct SemanticRecordingSuppressionContext: Equatable, Sendable {
    public var recordingTime: TimeInterval?
    public var timeRange: RecordingTimeRange?
    public var target: RecordingCaptureTarget
    public var frameID: UUID?
    public var eventID: UUID?
    public var domain: String?
    public var secureInputEnabled: Bool
    public var passwordFieldFocused: Bool
    public var privateRegion: Bool
    public var artifactByteCount: Int?
    public var redactedArtifactRef: RecordingArtifactRef?
    public var createdAt: Date

    public init(
        recordingTime: TimeInterval? = nil,
        timeRange: RecordingTimeRange? = nil,
        target: RecordingCaptureTarget = RecordingCaptureTarget(),
        frameID: UUID? = nil,
        eventID: UUID? = nil,
        domain: String? = nil,
        secureInputEnabled: Bool = false,
        passwordFieldFocused: Bool = false,
        privateRegion: Bool = false,
        artifactByteCount: Int? = nil,
        redactedArtifactRef: RecordingArtifactRef? = nil,
        createdAt: Date = Date.now
    ) {
        self.recordingTime = recordingTime.map { max(0, $0) }
        self.timeRange = timeRange
        self.target = target
        self.frameID = frameID
        self.eventID = eventID
        self.domain = domain
        self.secureInputEnabled = secureInputEnabled
        self.passwordFieldFocused = passwordFieldFocused
        self.privateRegion = privateRegion
        self.artifactByteCount = artifactByteCount.map { max(0, $0) }
        self.redactedArtifactRef = redactedArtifactRef
        self.createdAt = createdAt
    }
}

public struct SemanticRecordingSuppressionProducer: @unchecked Sendable {
    public var rules: SemanticRecordingSuppressionRules
    public var ids: SemanticRecordingCaptureIDProvider

    public init(
        rules: SemanticRecordingSuppressionRules = .empty,
        ids: SemanticRecordingCaptureIDProvider = SemanticRecordingCaptureIDProvider()
    ) {
        self.rules = rules
        self.ids = ids
    }

    public func records(
        for context: SemanticRecordingSuppressionContext
    ) -> [RecordingSuppressionRecord] {
        var records: [RecordingSuppressionRecord] = []
        append(
            &records,
            reason: context.secureInputEnabled ? .secureInput : nil,
            detail: "Secure Input was active; keyboard and visual evidence were withheld.",
            context: context
        )
        append(
            &records,
            reason: context.passwordFieldFocused ? .passwordField : nil,
            detail: "A password or secure text field was focused; typed content and frame evidence were withheld.",
            context: context
        )
        append(
            &records,
            reason: rules.excludes(applicationBundleID: context.target.appBundleIdentifier) ? .excludedApplication : nil,
            detail: "The target application is excluded from semantic recording evidence.",
            context: context
        )
        append(
            &records,
            reason: rules.excludes(windowTitle: context.target.windowTitle) ? .excludedWindow : nil,
            detail: "The target window title matched an excluded semantic recording pattern.",
            context: context
        )
        append(
            &records,
            reason: rules.excludes(domain: context.domain) ? .excludedDomain : nil,
            detail: "The target domain is excluded from semantic recording evidence.",
            context: context
        )
        append(
            &records,
            reason: context.privateRegion ? .privateRegion : nil,
            detail: "The selected frame region was marked private and withheld.",
            context: context
        )
        append(
            &records,
            reason: rules.exceedsArtifactLimit(byteCount: context.artifactByteCount) ? .oversizedArtifact : nil,
            detail: "The captured artifact exceeded the semantic recording retention size limit.",
            context: context
        )
        return records
    }

    private func append(
        _ records: inout [RecordingSuppressionRecord],
        reason: RecordingSuppressionReason?,
        detail: String,
        context: SemanticRecordingSuppressionContext
    ) {
        guard let reason else { return }
        records.append(RecordingSuppressionRecord(
            id: ids.next(.suppression),
            reason: reason,
            recordingTime: context.recordingTime,
            timeRange: context.timeRange,
            target: context.target,
            frameID: context.frameID,
            eventID: context.eventID,
            redactedArtifactRef: context.redactedArtifactRef,
            count: 1,
            detail: detail,
            createdAt: context.createdAt
        ))
    }
}
