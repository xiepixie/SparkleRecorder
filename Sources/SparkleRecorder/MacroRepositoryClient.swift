import Foundation
import SparkleRecorderCore

public struct MacroRepositoryClient: Sendable {
    public var loadAllManifests: @Sendable () async throws -> [SavedMacro]
    public var loadEvents: @Sendable (_ id: UUID) async throws -> [RecordedEvent]
    public var saveMetadata: @Sendable (_ macro: SavedMacro) async throws -> Void
    public var saveEvents: @Sendable (_ events: [RecordedEvent], _ id: UUID) async throws -> Void
    public var deleteMacro: @Sendable (_ id: UUID) async throws -> Void
    public var packageURL: @Sendable (_ id: UUID) -> URL
    public var saveRunEvidence: @Sendable (_ id: UUID, _ report: RunReport, _ screenshot: Data?) async throws -> Void
}

extension MacroRepositoryClient {
    public static var live: MacroRepositoryClient {
        return MacroRepositoryClient(
            loadAllManifests: { try await MacroRepository.shared.loadAllManifests() },
            loadEvents: { try await MacroRepository.shared.loadEvents(for: $0) },
            saveMetadata: { try await MacroRepository.shared.saveMetadata($0) },
            saveEvents: { events, id in try await MacroRepository.shared.saveEvents(events, for: id) },
            deleteMacro: { try await MacroRepository.shared.deleteMacro(id: $0) },
            packageURL: { MacroRepository.shared.packageURL(for: $0) },
            saveRunEvidence: { id, report, screenshot in try await MacroRepository.shared.saveRunEvidence(id: id, report: report, screenshot: screenshot) }
        )
    }
}
