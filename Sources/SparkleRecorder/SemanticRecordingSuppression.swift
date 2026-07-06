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

public struct SemanticRecordingSuppressionSettings: Codable, Equatable, Sendable {
    public var excludedApplicationBundleIDs: [String]
    public var excludedWindowTitleFragments: [String]
    public var excludedDomains: [String]
    public var maximumArtifactByteCount: Int?

    public init(
        excludedApplicationBundleIDs: [String] = [],
        excludedWindowTitleFragments: [String] = [],
        excludedDomains: [String] = [],
        maximumArtifactByteCount: Int? = nil
    ) {
        self.excludedApplicationBundleIDs = Self.normalizedUnique(
            excludedApplicationBundleIDs,
            normalizer: Self.normalizedIdentifier
        )
        self.excludedWindowTitleFragments = Self.normalizedUnique(
            excludedWindowTitleFragments,
            normalizer: Self.normalizedTitleFragment
        )
        self.excludedDomains = Self.normalizedUnique(
            excludedDomains,
            normalizer: Self.normalizedDomain
        )
        self.maximumArtifactByteCount = maximumArtifactByteCount.flatMap { bytes in
            let clamped = max(0, bytes)
            return clamped == 0 ? nil : clamped
        }
    }

    public var rules: SemanticRecordingSuppressionRules {
        SemanticRecordingSuppressionRules(
            excludedApplicationBundleIDs: Set(excludedApplicationBundleIDs),
            excludedWindowTitleFragments: excludedWindowTitleFragments,
            excludedDomains: Set(excludedDomains),
            maximumArtifactByteCount: maximumArtifactByteCount
        )
    }

    public static func parseListText(_ value: String) -> [String] {
        value
            .split { character in
                character == "," ||
                    character == ";" ||
                    character == "\n" ||
                    character == "\r" ||
                    character == "\t"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func listText(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private static func normalizedUnique(
        _ values: [String],
        normalizer: (String) -> String
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let normalized = normalizer(value)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            output.append(normalized)
        }
        return output
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

public struct SemanticRecordingCaptureSuppressionDecision: Equatable, Sendable {
    public var reasons: [RecordingSuppressionReason]

    public var shouldSuppressCapture: Bool {
        !reasons.isEmpty
    }

    public init(reasons: [RecordingSuppressionReason] = []) {
        self.reasons = reasons
    }

    public static let allow = SemanticRecordingCaptureSuppressionDecision()
}

public extension RecordingSuppressionReason {
    var redactsSemanticEvidence: Bool {
        switch self {
        case .secureInput,
             .passwordField,
             .excludedApplication,
             .excludedWindow,
             .excludedDomain,
             .privateRegion,
             .userDeleted,
             .unknown:
            return true

        case .oversizedArtifact:
            return false
        }
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
        for match in suppressionMatches(for: context) {
            append(
                &records,
                reason: match.reason,
                detail: match.detail,
                context: context
            )
        }
        return records
    }

    public func captureSuppressionDecision(
        for context: SemanticRecordingSuppressionContext
    ) -> SemanticRecordingCaptureSuppressionDecision {
        let reasons = suppressionMatches(for: context)
            .map(\.reason)
            .filter(Self.reasonSuppressesCapture)
        return SemanticRecordingCaptureSuppressionDecision(reasons: reasons)
    }

    private func suppressionMatches(
        for context: SemanticRecordingSuppressionContext
    ) -> [SemanticRecordingSuppressionMatch] {
        var matches: [SemanticRecordingSuppressionMatch] = []
        append(
            &matches,
            reason: context.secureInputEnabled ? .secureInput : nil,
            detail: "Secure Input was active; keyboard and visual evidence were withheld."
        )
        append(
            &matches,
            reason: context.passwordFieldFocused ? .passwordField : nil,
            detail: "A password or secure text field was focused; typed content and frame evidence were withheld."
        )
        append(
            &matches,
            reason: rules.excludes(applicationBundleID: context.target.appBundleIdentifier) ? .excludedApplication : nil,
            detail: "The target application is excluded from semantic recording evidence."
        )
        append(
            &matches,
            reason: rules.excludes(windowTitle: context.target.windowTitle) ? .excludedWindow : nil,
            detail: "The target window title matched an excluded semantic recording pattern."
        )
        append(
            &matches,
            reason: rules.excludes(domain: context.domain) ? .excludedDomain : nil,
            detail: "The target domain is excluded from semantic recording evidence."
        )
        append(
            &matches,
            reason: context.privateRegion ? .privateRegion : nil,
            detail: "The selected frame region was marked private and withheld."
        )
        append(
            &matches,
            reason: rules.exceedsArtifactLimit(byteCount: context.artifactByteCount) ? .oversizedArtifact : nil,
            detail: "The captured artifact exceeded the semantic recording retention size limit."
        )
        return matches
    }

    private static func reasonSuppressesCapture(
        _ reason: RecordingSuppressionReason
    ) -> Bool {
        switch reason {
        case .secureInput,
             .passwordField,
             .excludedApplication,
             .excludedWindow,
             .excludedDomain,
             .privateRegion:
            return true

        case .oversizedArtifact,
             .userDeleted,
             .unknown:
            return false
        }
    }

    private func append(
        _ matches: inout [SemanticRecordingSuppressionMatch],
        reason: RecordingSuppressionReason?,
        detail: String
    ) {
        guard let reason else { return }
        matches.append(SemanticRecordingSuppressionMatch(
            reason: reason,
            detail: detail
        ))
    }

    private func append(
        _ records: inout [RecordingSuppressionRecord],
        reason: RecordingSuppressionReason,
        detail: String,
        context: SemanticRecordingSuppressionContext
    ) {
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

private struct SemanticRecordingSuppressionMatch {
    var reason: RecordingSuppressionReason
    var detail: String
}
