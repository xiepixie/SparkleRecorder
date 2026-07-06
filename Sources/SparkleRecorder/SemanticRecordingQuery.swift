import Foundation

public enum SemanticRecordingSuggestionAvailability: String, Codable, Equatable, Sendable {
    case deterministicFixture
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
}
