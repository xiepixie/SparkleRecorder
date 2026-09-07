import Foundation

/// Canonical system-maintained starting document for external reconstruction.
/// Export and package import both use this builder so the raw-event baseline,
/// source-action coverage, and authoring metadata cannot drift into two truths.
public enum MacroReconstructionCandidateTemplate {
    public static func document(source: SavedMacro) throws -> MacroCandidateDocument {
        let sourceRevision = try MacroCandidateIdentity.revision(of: source)
        let sourceActions = try MacroActionReconstructor.reconstruct(
            events: source.events,
            sourceRevision: sourceRevision
        )
        let candidateActions = try MacroActionReconstructor.reconstruct(
            events: source.events,
            sourceRevision: MacroReconstructionContractVersions.candidateActionRevision
        )
        return MacroCandidateDocument(
            macro: source,
            sourceRevision: sourceRevision,
            summary: "Unmodified source template; replace with the reconstructed macro and update coverage.",
            coverage: zip(sourceActions, candidateActions).map { original, candidate in
                MacroCandidateCoverage(
                    sourceActionID: original.id,
                    disposition: .preserved,
                    candidateActionIDs: [candidate.id],
                    reason: "Source template"
                )
            },
            model: "external-author"
        )
    }

    /// Returns the exact strict external-authoring representation that is serialized
    /// as candidate-template.json. This intentionally omits app-owned Macro fields.
    public static func strictDocument(source: SavedMacro) throws -> MacroCandidateDocument {
        try MacroCandidateValidator.decode(
            MacroCandidateAuthoringProjection.encode(try document(source: source))
        )
    }
}
