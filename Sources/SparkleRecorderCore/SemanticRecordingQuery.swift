import CryptoKit
import Foundation

public enum SemanticRecordingSuggestionAvailability: String, Codable, Equatable, Sendable {
    case deterministicFixture
    case persistedBundle
    case unavailable
}

public enum SemanticRecordingQueryAvailability: String, Codable, Equatable, Sendable {
    case deterministicFixture
    case persistedBundle
    case unavailable
}

public struct SemanticRecordingSuggestionQuery: Codable, Equatable, Sendable {
    public var allowedKinds: [RecordingSuggestionKind]

    public init(allowedKinds: [RecordingSuggestionKind]) {
        self.allowedKinds = allowedKinds
    }

    public static func kinds(_ kinds: [RecordingSuggestionKind]) -> Self {
        SemanticRecordingSuggestionQuery(allowedKinds: kinds)
    }
}

public struct SemanticRecordingSuggestionResult: Codable, Equatable, Sendable {
    public var availability: SemanticRecordingSuggestionAvailability
    public var query: SemanticRecordingSuggestionQuery
    public var suggestions: [RecordingSuggestion]
    public var unavailableReason: String?

    public init(
        availability: SemanticRecordingSuggestionAvailability,
        query: SemanticRecordingSuggestionQuery = .kinds([]),
        suggestions: [RecordingSuggestion],
        unavailableReason: String? = nil
    ) {
        self.availability = availability
        self.query = query
        self.suggestions = suggestions
        self.unavailableReason = unavailableReason
    }
}

public struct SemanticRecordingOCRSearchQuery: Codable, Equatable, Sendable {
    public var text: String
    public var matchMode: TextMatchMode

    public init(text: String, matchMode: TextMatchMode = .contains) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.matchMode = matchMode
    }
}

public struct SemanticRecordingOCRSearchMatch: Codable, Equatable, Sendable {
    public var observation: RecordingVisualObservation
    public var queryResults: [RecordingQueryResult]

    public init(
        observation: RecordingVisualObservation,
        queryResults: [RecordingQueryResult]
    ) {
        self.observation = observation
        self.queryResults = queryResults
    }
}

public struct SemanticRecordingOCRSearchResult: Codable, Equatable, Sendable {
    public var availability: SemanticRecordingQueryAvailability
    public var query: SemanticRecordingOCRSearchQuery
    public var matches: [SemanticRecordingOCRSearchMatch]
    public var unavailableReason: String?

    public init(
        availability: SemanticRecordingQueryAvailability,
        query: SemanticRecordingOCRSearchQuery,
        matches: [SemanticRecordingOCRSearchMatch],
        unavailableReason: String? = nil
    ) {
        self.availability = availability
        self.query = query
        self.matches = matches
        self.unavailableReason = unavailableReason
    }
}

public struct SemanticRecordingVisualSearchQuery: Equatable, Sendable {
    public var text: String?
    public var matchMode: TextMatchMode
    public var kind: RecordingVisualObservationKind?
    public var label: String?

    public init(
        text: String? = nil,
        matchMode: TextMatchMode = .contains,
        kind: RecordingVisualObservationKind? = nil,
        label: String? = nil
    ) {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmedText?.isEmpty == true ? nil : trimmedText
        self.matchMode = matchMode
        self.kind = kind
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = trimmedLabel?.isEmpty == true ? nil : trimmedLabel
    }
}

public struct SemanticRecordingVisualSearchMatch: Equatable, Sendable {
    public var observation: RecordingVisualObservation

    public init(observation: RecordingVisualObservation) {
        self.observation = observation
    }
}

public enum SemanticRecordingQueryEngine {
    public static func deterministicQueryResults(
        for bundle: SemanticRecordingBundle,
        fixture: String?
    ) -> [RecordingQueryResult] {
        guard fixture == "checkout" else {
            return []
        }
        return SemanticRecordingFixture.checkoutQueryResults(bundle: bundle)
    }

    public static func deterministicOCRSearch(
        for bundle: SemanticRecordingBundle,
        fixture: String?,
        query: SemanticRecordingOCRSearchQuery
    ) -> SemanticRecordingOCRSearchResult {
        guard fixture == "checkout" else {
            return SemanticRecordingOCRSearchResult(
                availability: .unavailable,
                query: query,
                matches: [],
                unavailableReason: "Deterministic OCR search is only available for the checkout fixture in this slice."
            )
        }

        return SemanticRecordingOCRSearchResult(
            availability: .deterministicFixture,
            query: query,
            matches: ocrSearch(
                bundle: bundle,
                query: query,
                queryResults: SemanticRecordingFixture.checkoutQueryResults(bundle: bundle)
            )
        )
    }

    public static func persistedOCRSearch(
        for bundle: SemanticRecordingBundle,
        query: SemanticRecordingOCRSearchQuery,
        queryResults: [RecordingQueryResult] = []
    ) -> SemanticRecordingOCRSearchResult {
        SemanticRecordingOCRSearchResult(
            availability: .persistedBundle,
            query: query,
            matches: ocrSearch(
                bundle: bundle,
                query: query,
                queryResults: queryResults
            )
        )
    }

    public static func ocrSearch(
        bundle: SemanticRecordingBundle,
        query: SemanticRecordingOCRSearchQuery,
        queryResults: [RecordingQueryResult] = []
    ) -> [SemanticRecordingOCRSearchMatch] {
        guard !query.text.isEmpty else {
            return []
        }

        return bundle.visualObservations
            .filter { observation in
                observation.kind == .ocrText &&
                    matches(observation.text ?? "", query: query.text, matchMode: query.matchMode)
            }
            .sorted { lhs, rhs in
                if lhs.recordingTime == rhs.recordingTime {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.recordingTime < rhs.recordingTime
            }
            .map { observation in
                SemanticRecordingOCRSearchMatch(
                    observation: observation,
                    queryResults: relatedQueryResults(
                        observationID: observation.id,
                        queryResults: queryResults
                    )
                )
            }
    }

    public static func visualSearch(
        bundle: SemanticRecordingBundle,
        query: SemanticRecordingVisualSearchQuery
    ) -> [SemanticRecordingVisualSearchMatch] {
        bundle.visualObservations
            .filter { observation in
                if let kind = query.kind,
                   observation.kind != kind {
                    return false
                }
                if let label = query.label,
                   !observation.labels.contains(where: { matches($0, query: label, matchMode: .exact) }) {
                    return false
                }
                if let text = query.text {
                    let searchable = ([observation.text].compactMap { $0 } + observation.labels)
                        .joined(separator: " ")
                    return matches(searchable, query: text, matchMode: query.matchMode)
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.recordingTime == rhs.recordingTime {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.recordingTime < rhs.recordingTime
            }
            .map(SemanticRecordingVisualSearchMatch.init(observation:))
    }

    public static func deterministicSuggestions(
        for bundle: SemanticRecordingBundle,
        fixture: String?,
        query: SemanticRecordingSuggestionQuery
    ) -> SemanticRecordingSuggestionResult {
        guard let fixture else {
            return persistedSuggestions(for: bundle, query: query)
        }

        guard fixture == "checkout" else {
            return SemanticRecordingSuggestionResult(
                availability: .unavailable,
                query: query,
                suggestions: [],
                unavailableReason: "Deterministic suggestions are only available for the checkout fixture in this slice."
            )
        }

        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        return SemanticRecordingSuggestionResult(
            availability: .deterministicFixture,
            query: query,
            suggestions: filterAndSort(suggestions: suggestions, allowedKinds: query.allowedKinds)
        )
    }

    public static func persistedSuggestions(
        for bundle: SemanticRecordingBundle,
        query: SemanticRecordingSuggestionQuery
    ) -> SemanticRecordingSuggestionResult {
        let suggestions = persistedSuggestionCandidates(for: bundle)
        return SemanticRecordingSuggestionResult(
            availability: .persistedBundle,
            query: query,
            suggestions: filterAndSort(suggestions: suggestions, allowedKinds: query.allowedKinds)
        )
    }

    public static func filterAndSort(
        suggestions: [RecordingSuggestion],
        allowedKinds: [RecordingSuggestionKind]
    ) -> [RecordingSuggestion] {
        suggestions
            .filter { allowedKinds.contains($0.kind) }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    if lhs.title == rhs.title {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.title < rhs.title
                }
                return lhs.confidence > rhs.confidence
            }
    }

    public static func matches(
        _ observedText: String,
        query: String,
        matchMode: TextMatchMode
    ) -> Bool {
        let observed = observedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return false
        }
        switch matchMode {
        case .contains:
            return observed.contains(needle)
        case .exact:
            return observed == needle
        }
    }

    private static func relatedQueryResults(
        observationID: UUID,
        queryResults: [RecordingQueryResult]
    ) -> [RecordingQueryResult] {
        queryResults
            .filter { result in
                result.kind == .ocrText &&
                    result.evidence.contains { evidence in
                        evidence.observationIDs.contains(observationID)
                    }
            }
            .sorted { lhs, rhs in
                if lhs.title == rhs.title {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.title < rhs.title
            }
    }

    private static func persistedSuggestionCandidates(for bundle: SemanticRecordingBundle) -> [RecordingSuggestion] {
        let eventsByFrameID = Dictionary(grouping: bundle.timelineEvents.compactMap { event -> (UUID, RecordingTimelineEvent)? in
            guard let frameID = event.frameID else {
                return nil
            }
            return (frameID, event)
        }, by: \.0)
            .mapValues { pairs in
                pairs.map(\.1).sorted { left, right in
                    if left.recordingTime == right.recordingTime {
                        return left.id.uuidString < right.id.uuidString
                    }
                    return left.recordingTime < right.recordingTime
                }
            }

        return bundle.visualObservations.flatMap { observation in
            persistedSuggestionCandidates(
                for: observation,
                bundleID: bundle.id,
                eventsByFrameID: eventsByFrameID
            )
        }
    }

    private static func persistedSuggestionCandidates(
        for observation: RecordingVisualObservation,
        bundleID: UUID,
        eventsByFrameID: [UUID: [RecordingTimelineEvent]]
    ) -> [RecordingSuggestion] {
        let evidence = RecordingEvidenceReference(
            frameID: observation.frameID,
            eventIDs: observation.frameID.flatMap { eventsByFrameID[$0]?.map(\.id) } ?? [],
            observationIDs: [observation.id],
            artifactRef: observation.artifactRef,
            bounds: observation.bounds,
            summary: persistedEvidenceSummary(for: observation)
        )

        switch observation.kind {
        case .ocrText:
            guard let text = observation.text?.nilIfBlankForSemanticQuery else {
                return []
            }
            return [
                RecordingSuggestion(
                    id: deterministicSuggestionID(bundleID: bundleID, observationID: observation.id, kind: .conditionCandidate),
                    recordingID: bundleID,
                    kind: .conditionCandidate,
                    title: "Create OCR wait for \"\(text)\"",
                    summary: "Persisted OCR text can become a reviewed wait condition without sending frame pixels to AI.",
                    confidence: confidence(from: observation.confidence, fallback: 0.72),
                    risk: "Requires Review confirmation; OCR text may be stale, partial, or suppressed.",
                    evidence: [evidence]
                )
            ]

        case .imageTemplateCandidate, .patternCandidate:
            let label = persistedObservationLabel(observation, fallback: "recorded pattern")
            return [
                RecordingSuggestion(
                    id: deterministicSuggestionID(bundleID: bundleID, observationID: observation.id, kind: .conditionCandidate),
                    recordingID: bundleID,
                    kind: .conditionCandidate,
                    title: "Create image condition for \(label)",
                    summary: "Persisted image or pattern evidence can become an image appeared/disappeared condition after Review.",
                    confidence: confidence(from: observation.score ?? observation.confidence, fallback: 0.68),
                    risk: "Review the crop and fallback before replacing timing or coordinate assumptions.",
                    evidence: [evidence]
                ),
                RecordingSuggestion(
                    id: deterministicSuggestionID(bundleID: bundleID, observationID: observation.id, kind: .locatorReplacement),
                    recordingID: bundleID,
                    kind: .locatorReplacement,
                    title: "Review image locator for \(label)",
                    summary: "The recorded crop can be reviewed as a safer locator candidate for fragile coordinate playback.",
                    confidence: confidence(from: observation.score ?? observation.confidence, fallback: 0.64),
                    risk: "Keep coordinate fallback until the locator is accepted and tested.",
                    evidence: [evidence]
                )
            ]

        case .regionBaseline, .regionDiff:
            let label = persistedObservationLabel(observation, fallback: "recorded region")
            return [
                RecordingSuggestion(
                    id: deterministicSuggestionID(bundleID: bundleID, observationID: observation.id, kind: .conditionCandidate),
                    recordingID: bundleID,
                    kind: .conditionCandidate,
                    title: "Create region-change condition for \(label)",
                    summary: "Persisted baseline or region-diff evidence can become a reviewed regionChanged condition.",
                    confidence: confidence(from: observation.score ?? observation.confidence, fallback: 0.66),
                    risk: "Review the watched region and threshold before using it to branch or repeat.",
                    evidence: [evidence]
                )
            ]

        case .pixelSample:
            let color = observation.metadata["colorHex"]?.nilIfBlankForSemanticQuery ?? "sampled color"
            return [
                RecordingSuggestion(
                    id: deterministicSuggestionID(bundleID: bundleID, observationID: observation.id, kind: .conditionCandidate),
                    recordingID: bundleID,
                    kind: .conditionCandidate,
                    title: "Create pixel condition for \(color)",
                    summary: "Persisted pixel sample evidence can become a reviewed pixelMatched condition.",
                    confidence: confidence(from: observation.score ?? observation.confidence, fallback: 0.62),
                    risk: "Pixel color can shift across displays; Review should confirm tolerance and fallback.",
                    evidence: [evidence]
                )
            ]

        case .axElement, .windowSnapshot:
            return []
        }
    }

    private static func persistedEvidenceSummary(for observation: RecordingVisualObservation) -> String {
        switch observation.kind {
        case .ocrText:
            return "Persisted OCR observation"
        case .imageTemplateCandidate:
            return "Persisted image-template observation"
        case .patternCandidate:
            return "Persisted pattern observation"
        case .regionBaseline:
            return "Persisted region-baseline observation"
        case .regionDiff:
            return "Persisted region-diff observation"
        case .pixelSample:
            return "Persisted pixel-sample observation"
        case .axElement:
            return "Persisted Accessibility observation"
        case .windowSnapshot:
            return "Persisted window observation"
        }
    }

    private static func persistedObservationLabel(
        _ observation: RecordingVisualObservation,
        fallback: String
    ) -> String {
        observation.labels.first?.nilIfBlankForSemanticQuery ??
            observation.text?.nilIfBlankForSemanticQuery ??
            fallback
    }

    private static func confidence(from value: Double?, fallback: Double) -> Double {
        min(0.89, max(0.35, value ?? fallback))
    }

    private static func deterministicSuggestionID(
        bundleID: UUID,
        observationID: UUID,
        kind: RecordingSuggestionKind
    ) -> UUID {
        let seed = "sparkle.semantic.suggestion.v1:\(bundleID.uuidString):\(observationID.uuidString):\(kind.rawValue)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension String {
    var nilIfBlankForSemanticQuery: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
