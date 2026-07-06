import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Suppression Tests")
struct SemanticRecordingSuppressionTests {
    @Test("Suppression producer emits privacy and exclusion records")
    func suppressionProducerEmitsPrivacyAndExclusionRecords() throws {
        let ids = SuppressionIDFixture(values: [
            .suppression: [
                uuid("7B000000-0000-0000-0000-000000000001"),
                uuid("7B000000-0000-0000-0000-000000000002"),
                uuid("7B000000-0000-0000-0000-000000000003"),
                uuid("7B000000-0000-0000-0000-000000000004"),
                uuid("7B000000-0000-0000-0000-000000000005"),
                uuid("7B000000-0000-0000-0000-000000000006"),
                uuid("7B000000-0000-0000-0000-000000000007")
            ]
        ])
        let producer = SemanticRecordingSuppressionProducer(
            rules: SemanticRecordingSuppressionRules(
                excludedApplicationBundleIDs: ["COM.EXAMPLE.SECURE"],
                excludedWindowTitleFragments: ["private checkout"],
                excludedDomains: ["payments.example.com"],
                maximumArtifactByteCount: 10
            ),
            ids: ids.provider
        )
        let redactedRef = try RecordingArtifactRef("redacted/frame.png")
        let context = SemanticRecordingSuppressionContext(
            recordingTime: 2.4,
            timeRange: RecordingTimeRange(startTime: 2.0, duration: 0.8),
            target: RecordingCaptureTarget(
                kind: .window,
                surfaceID: "secure-window",
                windowID: 42,
                appBundleIdentifier: "com.example.secure",
                windowTitle: "Private Checkout - Card"
            ),
            frameID: uuid("7B000000-0000-0000-0000-000000000101"),
            eventID: uuid("7B000000-0000-0000-0000-000000000102"),
            domain: "https://www.payments.example.com/session",
            secureInputEnabled: true,
            passwordFieldFocused: true,
            privateRegion: true,
            artifactByteCount: 11,
            redactedArtifactRef: redactedRef,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        let records = producer.records(for: context)

        #expect(records.map(\.reason) == [
            .secureInput,
            .passwordField,
            .excludedApplication,
            .excludedWindow,
            .excludedDomain,
            .privateRegion,
            .oversizedArtifact
        ])
        #expect(records.allSatisfy { $0.recordingTime == 2.4 })
        #expect(records.allSatisfy { $0.target?.surfaceID == "secure-window" })
        #expect(records.allSatisfy { $0.redactedArtifactRef == redactedRef })
        #expect(records.first?.detail?.contains("Secure Input") == true)
    }

    @Test("Suppression producer normalizes domains and ignores unmatched rules")
    func suppressionProducerNormalizesDomainsAndIgnoresUnmatchedRules() {
        let ids = SuppressionIDFixture(values: [
            .suppression: [uuid("7C000000-0000-0000-0000-000000000001")]
        ])
        let producer = SemanticRecordingSuppressionProducer(
            rules: SemanticRecordingSuppressionRules(
                excludedApplicationBundleIDs: ["com.example.secure"],
                excludedWindowTitleFragments: ["secret"],
                excludedDomains: ["example.com"],
                maximumArtifactByteCount: 100
            ),
            ids: ids.provider
        )

        let allowed = producer.records(for: SemanticRecordingSuppressionContext(
            target: RecordingCaptureTarget(
                kind: .window,
                appBundleIdentifier: "com.example.notes",
                windowTitle: "Public Notes"
            ),
            domain: "example.org",
            artifactByteCount: 100
        ))
        let excludedSubdomain = producer.records(for: SemanticRecordingSuppressionContext(
            target: RecordingCaptureTarget(kind: .window),
            domain: "https://login.example.com/path"
        ))

        #expect(allowed.isEmpty)
        #expect(excludedSubdomain.map(\.reason) == [.excludedDomain])
    }

    private func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return uuid
    }
}

private final class SuppressionIDFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SemanticRecordingCaptureIDKind: [UUID]]
    private var counters: [SemanticRecordingCaptureIDKind: Int] = [:]

    init(values: [SemanticRecordingCaptureIDKind: [UUID]]) {
        self.values = values
    }

    var provider: SemanticRecordingCaptureIDProvider {
        SemanticRecordingCaptureIDProvider { [self] kind in
            lock.lock()
            defer { lock.unlock() }

            let index = counters[kind, default: 0]
            counters[kind] = index + 1
            if let ids = values[kind], ids.indices.contains(index) {
                return ids[index]
            }
            let fallback = String(format: "7D000000-0000-0000-0000-%012d", index + 1)
            return UUID(uuidString: fallback) ?? UUID()
        }
    }
}
