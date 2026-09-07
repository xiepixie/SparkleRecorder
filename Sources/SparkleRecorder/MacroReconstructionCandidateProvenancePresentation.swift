import Foundation

struct MacroReconstructionCandidateProvenancePresentation: Equatable, Sendable {
    var title: String
    var detail: String
    var systemImage: String

    static func make(from provenance: MacroCandidateImportProvenance?) -> Self {
        guard let provenance, provenance.source == .reconstructionPackage else {
            return Self(
                title: String(localized: "Standalone candidate", table: "EditorUX"),
                detail: String(localized: "Package provenance unavailable.", table: "EditorUX"),
                systemImage: "doc"
            )
        }

        var details: [String] = []
        if let objective = provenance.objective {
            details.append(String(localized: objective == .robust ? "Robust" : "Faithful", table: "EditorUX"))
        }
        if provenance.visualEvidenceIncluded == true {
            details.append(String(localized: "Visual evidence included", table: "EditorUX"))
        } else {
            details.append(String(localized: "Actions only", table: "EditorUX"))
        }
        if provenance.mechanicalEvidenceIncluded == true {
            details.append(String(localized: "Mechanical input evidence included", table: "EditorUX"))
        }
        if provenance.sourceEventsMatchRecording == true {
            details.append(String(localized: "Recording aligned", table: "EditorUX"))
        } else {
            details.append(String(localized: "Recording alignment unavailable", table: "EditorUX"))
        }

        return Self(
            title: String(localized: "Verified AI package", table: "EditorUX"),
            detail: details.joined(separator: " · "),
            systemImage: "checkmark.seal"
        )
    }
}
