import Foundation
import SparkleRecorderCore
import Testing

@Suite("Semantic Recording Query Tests")
struct SemanticRecordingQueryTests {
    @Test("OCR search matches fixture observations and links deterministic query evidence")
    func ocrSearchMatchesFixtureObservations() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let queryResults = SemanticRecordingQueryEngine.deterministicQueryResults(
            for: bundle,
            fixture: "checkout"
        )

        let matches = SemanticRecordingQueryEngine.ocrSearch(
            bundle: bundle,
            query: SemanticRecordingOCRSearchQuery(text: "order"),
            queryResults: queryResults
        )

        #expect(matches.map(\.observation.id) == [SemanticRecordingFixture.ocrObservationID])
        #expect(matches.first?.observation.text == "Order confirmed")
        #expect(matches.first?.queryResults.map(\.id) == [SemanticRecordingFixture.queryResultID])
        #expect(matches.first?.queryResults.first?.evidence.first?.frameID == SemanticRecordingFixture.afterClickFrameID)
    }

    @Test("Deterministic OCR search is fixture scoped and carries availability")
    func deterministicOCRSearchIsFixtureScoped() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let query = SemanticRecordingOCRSearchQuery(text: "order")

        let fixtureResult = SemanticRecordingQueryEngine.deterministicOCRSearch(
            for: bundle,
            fixture: "checkout",
            query: query
        )
        let storedResult = SemanticRecordingQueryEngine.deterministicOCRSearch(
            for: bundle,
            fixture: nil,
            query: query
        )

        #expect(fixtureResult.availability == .deterministicFixture)
        #expect(fixtureResult.query == query)
        #expect(fixtureResult.matches.map(\.observation.id) == [SemanticRecordingFixture.ocrObservationID])
        #expect(fixtureResult.matches.first?.queryResults.map(\.id) == [SemanticRecordingFixture.queryResultID])
        #expect(fixtureResult.unavailableReason == nil)
        #expect(storedResult.availability == .unavailable)
        #expect(storedResult.matches.isEmpty)
        #expect(storedResult.unavailableReason?.contains("checkout fixture") == true)
    }

    @Test("OCR search exact mode requires the whole observed text")
    func ocrSearchExactModeRequiresWholeObservedText() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()

        let partialMatches = SemanticRecordingQueryEngine.ocrSearch(
            bundle: bundle,
            query: SemanticRecordingOCRSearchQuery(text: "order", matchMode: .exact)
        )
        let exactMatches = SemanticRecordingQueryEngine.ocrSearch(
            bundle: bundle,
            query: SemanticRecordingOCRSearchQuery(text: "Order confirmed", matchMode: .exact)
        )

        #expect(partialMatches.isEmpty)
        #expect(exactMatches.map(\.observation.id) == [SemanticRecordingFixture.ocrObservationID])
    }

    @Test("Visual search filters observations by kind label and text")
    func visualSearchFiltersObservations() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()

        let templateMatches = SemanticRecordingQueryEngine.visualSearch(
            bundle: bundle,
            query: SemanticRecordingVisualSearchQuery(
                kind: .imageTemplateCandidate,
                label: "button"
            )
        )
        let textMatches = SemanticRecordingQueryEngine.visualSearch(
            bundle: bundle,
            query: SemanticRecordingVisualSearchQuery(text: "confirmation")
        )
        let unmatched = SemanticRecordingQueryEngine.visualSearch(
            bundle: bundle,
            query: SemanticRecordingVisualSearchQuery(
                text: "confirmation",
                kind: .imageTemplateCandidate
            )
        )

        #expect(templateMatches.map(\.observation.id) == [SemanticRecordingFixture.templateObservationID])
        #expect(templateMatches.first?.observation.artifactRef?.path == "visual-index/templates/checkout-button.png")
        #expect(textMatches.map(\.observation.id) == [SemanticRecordingFixture.ocrObservationID])
        #expect(unmatched.isEmpty)
    }

    @Test("Deterministic suggestions include persisted-bundle evidence proposals")
    func deterministicSuggestionsIncludePersistedBundleEvidenceProposals() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()

        let conditionResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: "checkout",
            query: .kinds([.conditionCandidate])
        )
        let locatorResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: "checkout",
            query: .kinds([.locatorReplacement, .fragileClick])
        )
        let storedResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: nil,
            query: .kinds([.conditionCandidate])
        )
        let storedLocatorResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: nil,
            query: .kinds([.locatorReplacement, .fragileClick])
        )

        #expect(conditionResult.availability == .deterministicFixture)
        #expect(conditionResult.suggestions.map(\.id) == [SemanticRecordingFixture.suggestionID])
        #expect(conditionResult.suggestions.first?.kind == .conditionCandidate)
        #expect(locatorResult.availability == .deterministicFixture)
        #expect(locatorResult.query.allowedKinds == [.locatorReplacement, .fragileClick])
        #expect(locatorResult.suggestions.isEmpty)
        #expect(storedResult.availability == .persistedBundle)
        #expect(storedResult.query.allowedKinds == [.conditionCandidate])
        #expect(storedResult.unavailableReason == nil)
        #expect(storedResult.suggestions.map(\.kind) == [.conditionCandidate, .conditionCandidate])
        #expect(storedResult.suggestions.contains {
            $0.title == "Create OCR wait for \"Order confirmed\"" &&
                $0.evidence.first?.observationIDs == [SemanticRecordingFixture.ocrObservationID] &&
                $0.evidence.first?.artifactRef?.path == "visual-index/ocr/confirmation-region.png"
        })
        #expect(storedResult.suggestions.contains {
            $0.title == "Create image condition for button" &&
                $0.evidence.first?.observationIDs == [SemanticRecordingFixture.templateObservationID] &&
                $0.evidence.first?.artifactRef?.path == "visual-index/templates/checkout-button.png"
        })
        #expect(storedLocatorResult.availability == .persistedBundle)
        #expect(storedLocatorResult.query.allowedKinds == [.locatorReplacement, .fragileClick])
        #expect(storedLocatorResult.suggestions.map(\.kind) == [.locatorReplacement])
        #expect(storedLocatorResult.suggestions.first?.title == "Review image locator for button")
    }

    @Test("Deterministic query results are codable for CLI and future MCP callers")
    func deterministicQueryResultsAreCodable() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let ocrResult = SemanticRecordingQueryEngine.deterministicOCRSearch(
            for: bundle,
            fixture: "checkout",
            query: SemanticRecordingOCRSearchQuery(text: "order")
        )
        let suggestionResult = SemanticRecordingQueryEngine.deterministicSuggestions(
            for: bundle,
            fixture: "checkout",
            query: .kinds([.conditionCandidate])
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        let decodedOCRResult = try decoder.decode(
            SemanticRecordingOCRSearchResult.self,
            from: encoder.encode(ocrResult)
        )
        let decodedSuggestionResult = try decoder.decode(
            SemanticRecordingSuggestionResult.self,
            from: encoder.encode(suggestionResult)
        )

        #expect(decodedOCRResult == ocrResult)
        #expect(decodedSuggestionResult == suggestionResult)
    }
}
