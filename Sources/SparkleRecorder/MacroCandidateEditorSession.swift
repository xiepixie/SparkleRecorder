import Foundation
import SparkleRecorderCore

/// In-memory working copy for editing a Candidate without touching the accepted Macro.
/// Saving publishes a new immutable Candidate only when the working copy changed.
@MainActor
final class MacroCandidateEditorSession: ObservableObject {
    let baseCandidate: MacroStoredCandidate
    let repository: MacroRepository

    @Published private(set) var draftMacro: SavedMacro
    @Published private(set) var isDirty = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage = ""

    private let onSaved: @MainActor (MacroStoredCandidate) -> Void

    init(
        candidate: MacroStoredCandidate,
        repository: MacroRepository = .shared,
        onSaved: @escaping @MainActor (MacroStoredCandidate) -> Void
    ) {
        self.baseCandidate = candidate
        self.repository = repository
        self.draftMacro = candidate.macro
        self.onSaved = onSaved
    }

    var candidateID: UUID { baseCandidate.id }
    var macroID: UUID { baseCandidate.macro.id }
    var hasChanges: Bool { isDirty }

    func updateEvents(_ events: [RecordedEvent]) {
        guard events != draftMacro.events else { return }
        draftMacro.events = events
        draftMacro.modifiedAt = Date()
        draftMacro.refreshCachesFromEvents()
        isDirty = true
        statusMessage = ""
    }

    @discardableResult
    func rebindSurface(_ surfaceID: String, to surface: PlaybackSurface) -> Bool {
        do {
            let surfaces = try MacroPlaybackSurfaceEditing.rebind(
                surfaceID: surfaceID,
                to: surface,
                in: draftMacro.surfaces
            )
            guard surfaces != draftMacro.surfaces else { return true }
            draftMacro.surfaces = surfaces
            markDirty()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addSurface(_ surface: PlaybackSurface) -> String {
        let result = MacroPlaybackSurfaceEditing.add(surface, to: draftMacro.surfaces)
        draftMacro.surfaces = result.surfaces
        markDirty()
        return result.surfaceID
    }

    @discardableResult
    func removeSurface(_ surfaceID: String) -> Bool {
        do {
            let surfaces = try MacroPlaybackSurfaceEditing.remove(
                surfaceID: surfaceID,
                from: draftMacro.surfaces,
                events: draftMacro.events
            )
            draftMacro.surfaces = surfaces
            markDirty()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func assignSurface(_ surfaceID: String, toEventIndices eventIndices: [Int]) -> Bool {
        do {
            let events = try MacroPlaybackSurfaceEditing.assign(
                surfaceID: surfaceID,
                toEventIndices: eventIndices,
                in: draftMacro.events,
                surfaces: draftMacro.surfaces
            )
            updateEvents(events)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func markDirty() {
        draftMacro.modifiedAt = Date()
        isDirty = true
        errorMessage = nil
        statusMessage = ""
    }

    @discardableResult
    func save() async -> Bool {
        guard !isSaving else { return false }
        errorMessage = nil

        if !isDirty {
            onSaved(baseCandidate)
            return true
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let document = try MacroCandidateEditorDraftBuilder.document(
                from: baseCandidate.document,
                editedMacro: draftMacro
            )
            let stored = try await repository.importCandidateDraft(
                document,
                for: macroID,
                importProvenance: baseCandidate.importProvenance
            )
            statusMessage = String(
                localized: "Edited version saved as a new candidate. Test the new version before accepting it.",
                table: "EditorUX"
            )
            isDirty = false
            onSaved(stored)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
