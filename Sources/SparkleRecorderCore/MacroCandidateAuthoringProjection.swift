import Foundation

/// Projects a complete candidate document onto the narrow JSON interface that an
/// external author is allowed to edit. Source-owned Playback Surface bodies,
/// Library placement, runtime statistics, caches, evidence references and protected
/// execution configuration remain owned by the app and are restored from the accepted
/// source during normalization; authored events reference surfaces only by surfaceId.
public enum MacroCandidateAuthoringProjection {
    public static func encode(_ document: MacroCandidateDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(document))
    }

    private struct Document: Encodable {
        var macro: Macro
        var sourceRevision: String
        var summary: String
        var coverage: [MacroCandidateCoverage]
        var uncertainActionIDs: [String]
        var model: String

        init(_ document: MacroCandidateDocument) {
            macro = Macro(document.macro)
            sourceRevision = document.sourceRevision
            summary = document.summary
            coverage = document.coverage
            uncertainActionIDs = document.uncertainActionIDs
            model = document.model
        }
    }

    private struct Macro: Encodable {
        var id: UUID
        var name: String
        var events: [RecordedEvent]
        var createdAt: Date
        var modifiedAt: Date
        var version: Int

        init(_ macro: SavedMacro) {
            id = macro.id
            name = macro.name
            events = macro.events
            createdAt = macro.createdAt
            modifiedAt = macro.modifiedAt
            version = macro.version
        }
    }
}
