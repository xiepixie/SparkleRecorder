import Foundation

/// Builds a new immutable Candidate document from an editor working copy.
/// Coverage whose candidate action identities still exist is preserved. Structural
/// edits that invalidate an old target are narrowed to unresolved source actions
/// rather than silently inventing a replacement mapping.
public enum MacroCandidateEditorDraftBuilder {
    public static func document(
        from base: MacroCandidateDocument,
        editedMacro: SavedMacro
    ) throws -> MacroCandidateDocument {
        let oldCandidateIDs = Set(
            try MacroActionReconstructor.reconstruct(
                events: base.macro.events,
                sourceRevision: MacroCandidateCapabilities.current.candidateActionRevision
            ).map(\.id)
        )
        let newCandidateIDs = Set(
            try MacroActionReconstructor.reconstruct(
                events: editedMacro.events,
                sourceRevision: MacroCandidateCapabilities.current.candidateActionRevision
            ).map(\.id)
        )

        var result = base
        result.macro.events = editedMacro.events
        result.macro.surfaces = editedMacro.surfaces
        result.macro.modifiedAt = editedMacro.modifiedAt

        var uncertain = Set(
            base.uncertainActionIDs.filter { id in
                !oldCandidateIDs.contains(id) || newCandidateIDs.contains(id)
            }
        )

        result.coverage = base.coverage.map { item in
            guard item.disposition != .removedAsNoise else { return item }

            let survivingTargets = item.candidateActionIDs.filter(newCandidateIDs.contains)
            let allTargetsSurvive = survivingTargets.count == item.candidateActionIDs.count

            if item.disposition == .unresolved {
                var updated = item
                updated.candidateActionIDs = survivingTargets
                uncertain.insert(item.sourceActionID)
                return updated
            }

            guard allTargetsSurvive, !survivingTargets.isEmpty else {
                uncertain.insert(item.sourceActionID)
                return MacroCandidateCoverage(
                    sourceActionID: item.sourceActionID,
                    disposition: .unresolved,
                    candidateActionIDs: survivingTargets,
                    reason: "Edited locally; the previous candidate action mapping changed and needs review."
                )
            }

            return item
        }

        result.uncertainActionIDs = base.uncertainActionIDs.filter { uncertain.contains($0) }
        for item in result.coverage where item.disposition == .unresolved {
            if !result.uncertainActionIDs.contains(item.sourceActionID) {
                result.uncertainActionIDs.append(item.sourceActionID)
            }
        }
        return result
    }
}
