import Foundation
import Combine
import AppKit
import SparkleRecorderCore



/// Built-in library filters (in addition to user tags).
enum LibraryFilter: Hashable {
    case all
    case favorites
    case recent
    case mostPlayed
    case withHotkey
    case tag(String)
    case accent(String)

    var label: String {
        switch self {
        case .all:        return String(localized: "All Macros", table: "EditorUX")
        case .favorites:  return String(localized: "Favorites", table: "Common")
        case .recent:     return String(localized: "Recent", table: "Common")
        case .mostPlayed: return String(localized: "Most Played", table: "Common")
        case .withHotkey: return String(localized: "Has Hotkey", table: "Common")
        case .tag(let t): return t
        case .accent(let name): return accentDisplayName(name)
        }
    }

    var systemImage: String {
        switch self {
        case .all:        return "tray.full"
        case .favorites:  return "star.fill"
        case .recent:     return "clock"
        case .mostPlayed: return "chart.bar.fill"
        case .withHotkey: return "keyboard"
        case .tag:        return "tag.fill"
        case .accent:     return "circle.fill"
        }
    }
}



enum MacroLibraryIssue: Equatable, Sendable {
    case loadLibrary(String)
    case readMacro(String)
    case saveChanges(String)
}

enum MacroChainUpdateResult: Equatable, Sendable {
    case applied
    case sourceMissing
    case targetMissing
    case selfReference
    case cycle
}

/// The user's saved macros. Auto-persists to Application Support.
@MainActor
final class MacroLibrary: ObservableObject {
    @Published private(set) var macros: [SavedMacro] = []
    @Published var currentMacroID: UUID?
    @Published private(set) var issue: MacroLibraryIssue?

    var currentMacro: SavedMacro? {
        guard let id = currentMacroID else { return nil }
        return macros.first { $0.id == id }
    }

    /// All distinct tags across macros, sorted alphabetically.
    var allTags: [String] {
        let set = Set(macros.flatMap { $0.tags })
        return set.sorted()
    }

    /// All distinct macro accent labels currently in use, sorted like the color menu.
    var allAccents: [String] {
        let set = Set(macros.compactMap { normalizedAccentName($0.accent) })
        return set.sorted {
            let left = accentSortIndex($0)
            let right = accentSortIndex($1)
            if left != right { return left < right }
            return accentDisplayName($0).localizedCaseInsensitiveCompare(accentDisplayName($1)) == .orderedAscending
        }
    }

    private let client: MacroRepositoryClient
    /// Writes are serialized per Macro, not across the whole Library. Mutations
    /// of one Macro must stay ordered, while unrelated Macros must never extend
    /// recording finalization latency.
    private var persistenceTails: [UUID: Task<Void, Never>] = [:]
    private var persistenceGenerations: [UUID: UInt64] = [:]
    private var persistenceGeneration: UInt64 = 0

    init(client: MacroRepositoryClient = .live) {
        self.client = client
        Task {
            await load()
        }
    }

    // MARK: - Persistence

    func load() async {
        do {
            let loaded = try await client.loadAllManifests()
            self.macros = loaded
            
            if let idString = UserDefaults.standard.string(forKey: "currentMacroID"),
               let id = UUID(uuidString: idString),
               self.macros.contains(where: { $0.id == id }) {
                self.currentMacroID = id
            } else {
                self.currentMacroID = self.macros.first?.id
            }
        } catch {
            issue = .loadLibrary(error.localizedDescription)
            NSLog("SparkleRecorder: Failed to load from MacroRepository: \(error)")
        }
    }

    func save() {
        persistCurrentSelection()
        let reordered = assignLibraryOrder()

        // Library ordering is the only cross-Macro concern here. Persist only
        // entries whose stored order actually changed; individual edits already
        // enqueue their own metadata on the per-Macro persistence tail.
        for macro in reordered {
            enqueuePersistence(for: macro.id, "save library order for \(macro.id)") { [client] in
                try await client.saveMetadata(macro)
            }
        }
    }

    /// Termination-sensitive persistence. Unlike the fire-and-forget mutation paths,
    /// this does not return until the current in-memory events and metadata have
    /// reached the repository.
    func persistEventsAndMetadataImmediately(id: UUID, events: [RecordedEvent]) async {
        guard let index = macros.firstIndex(where: { $0.id == id }) else { return }
        macros[index].events = events
        macros[index].refreshCachesFromEvents()
        macros[index].modifiedAt = Date()
        let macro = macros[index]
        enqueuePersistence(for: id, "persist events and metadata for \(id)") { [client] in
            try await client.saveEvents(events, id)
            try await client.saveMetadata(macro)
        }
        await flushPendingPersistence(for: id)
    }

    func persistAllMetadataImmediately() async {
        await flushPendingPersistence()
        persistCurrentSelection()
        assignLibraryOrder()
        for macro in macros {
            do {
                try await client.saveMetadata(macro)
            } catch {
                issue = .saveChanges(error.localizedDescription)
                NSLog("SparkleRecorder: Failed to persist macro metadata before termination: \(error)")
            }
        }
    }

    private func persistCurrentSelection() {
        if let id = currentMacroID {
            UserDefaults.standard.set(id.uuidString, forKey: "currentMacroID")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentMacroID")
        }
    }

    // MARK: - Mutations

    /// Insert a fully-built macro (used by importers to preserve metadata).
    func insert(_ macro: SavedMacro, select: Bool = true) {
        macros.insert(macro, at: 0)
        if select {
            currentMacroID = macro.id
        }
        enqueuePersistence(for: macro.id, "save imported macro \(macro.id)") { [client] in
            try await client.saveEvents(macro.events, macro.id)
            try await client.saveMetadata(macro)
        }
        save()
    }

    @discardableResult
    func add(events: [RecordedEvent], name: String? = nil, loops: Int = 1) -> SavedMacro {
        let n = (name?.isEmpty == false) ? name! : autoName()
        let m = SavedMacro(name: n, events: events, loops: loops)
        macros.insert(m, at: insertionIndex())
        currentMacroID = m.id
        enqueuePersistence(for: m.id, "save recorded events for \(m.id)") { [client] in
            try await client.saveEvents(m.events, m.id)
        }
        save()
        return m
    }

    /// New macros sit below favorites, at the top of the non-favorite section.
    private func insertionIndex() -> Int {
        macros.firstIndex(where: { !$0.favorite }) ?? macros.count
    }

    func setLoops(id: UUID, loops: Int) {
        mutate(id) { $0.loops = max(0, loops) }
    }

    func setSpeed(id: UUID, speed: Double) {
        mutate(id) { $0.speed = max(0.1, min(10.0, speed)) }
    }

    func setIcon(id: UUID, icon: String?) {
        mutate(id) { $0.icon = icon }
    }

    func setAccent(id: UUID, accent: String?) {
        mutate(id) { $0.accent = accent }
    }

    func setHotkey(id: UUID, hotkey: HotkeyBinding?) {
        // Make sure no other macro has this hotkey.
        if let hotkey {
            for i in macros.indices where macros[i].id != id {
                guard let existing = macros[i].hotkey,
                      HotkeyConflictPolicy.conflicts(existing, hotkey) else { continue }
                macros[i].hotkey = nil
                macros[i].modifiedAt = Date()
                let clearedMacro = macros[i]
                enqueuePersistence(for: clearedMacro.id, "clear conflicting hotkey for \(clearedMacro.id)") { [client] in
                    try await client.saveMetadata(clearedMacro)
                }
            }
        }
        mutate(id) { $0.hotkey = hotkey }
    }

    func setNotes(id: UUID, notes: String) {
        mutate(id) { $0.notes = notes }
    }

    /// Initializes the legacy/single-window recording fallback. Editor code must
    /// use `rebindSurface`, `addSurface`, and `removeSurface` so a multi-surface
    /// Macro can never be collapsed accidentally.
    func setSingleRecordedSurface(id: UUID, surface: PlaybackSurface?) {
        mutate(id) {
            if let surface {
                $0.surfaces = ["surface-1": surface]
            } else {
                $0.surfaces = [:]
            }
        }
    }
    
    func setSurfaces(id: UUID, surfaces: [String: PlaybackSurface]) {
        mutate(id) {
            $0.surfaces = surfaces
        }
    }

    @discardableResult
    func rebindSurface(id: UUID, surfaceID: String, surface: PlaybackSurface) -> Bool {
        guard let macro = macros.first(where: { $0.id == id }),
              let surfaces = try? MacroPlaybackSurfaceEditing.rebind(
                surfaceID: surfaceID,
                to: surface,
                in: macro.surfaces
              ) else { return false }
        setSurfaces(id: id, surfaces: surfaces)
        return true
    }

    @discardableResult
    func addSurface(id: UUID, surface: PlaybackSurface) -> String? {
        guard let macro = macros.first(where: { $0.id == id }) else { return nil }
        let result = MacroPlaybackSurfaceEditing.add(surface, to: macro.surfaces)
        setSurfaces(id: id, surfaces: result.surfaces)
        return result.surfaceID
    }

    @discardableResult
    func removeSurface(id: UUID, surfaceID: String) -> Bool {
        guard let macro = macros.first(where: { $0.id == id }) else { return false }
        // Library manifests intentionally omit events. Never infer that a Surface is
        // unused from an unloaded manifest; the Editor keeps the selected Macro's
        // complete event list synchronized before allowing removal.
        if macro.events.isEmpty, macro.eventCount > 0 { return false }
        guard let surfaces = try? MacroPlaybackSurfaceEditing.remove(
                surfaceID: surfaceID,
                from: macro.surfaces,
                events: macro.events
              ) else { return false }
        setSurfaces(id: id, surfaces: surfaces)
        return true
    }

    func setFollowWindowOffset(id: UUID, enabled: Bool) {
        mutate(id) { $0.followWindowOffset = enabled }
    }

    @discardableResult
    func setChainTo(id: UUID, target: UUID?) -> MacroChainUpdateResult {
        guard macros.contains(where: { $0.id == id }) else {
            return .sourceMissing
        }

        // Refuse self-chains, dangling targets, and links that would close a cycle.
        // The walk is capped by macro count so imported legacy cycles cannot hang.
        if let target {
            guard target != id else { return .selfReference }
            guard macros.contains(where: { $0.id == target }) else {
                return .targetMissing
            }

            var cursor: UUID? = target
            var hops = 0
            while let current = cursor, hops <= macros.count {
                if current == id { return .cycle }
                cursor = macros.first(where: { $0.id == current })?.chainTo
                hops += 1
            }
        }

        mutate(id) { $0.chainTo = target }
        return .applied
    }

    func attachSemanticRecording(
        id: UUID,
        reference: MacroSemanticRecordingReference
    ) {
        mutate(id) {
            $0.semanticRecording = reference
        }
    }

    @discardableResult
    func applyPlayableSanitization(
        id: UUID,
        plan: SemanticRecordingPlayableSanitizationPlan,
        appliedAt: Date = Date()
    ) async -> MacroPlayableSanitizationSummary? {
        guard !plan.isEmpty,
              macros.contains(where: { $0.id == id }) else {
            return nil
        }

        // The recording save for this Macro may still be queued. Unrelated Macro
        // writes are irrelevant and must not extend sanitization/finalization.
        await flushPendingPersistence(for: id)

        let sourceEvents: [RecordedEvent]
        let inMemoryEvents = macros.first { $0.id == id }?.events ?? []
        if inMemoryEvents.isEmpty {
            do {
                sourceEvents = try await client.loadEvents(id)
            } catch {
                return nil
            }
        } else {
            sourceEvents = inMemoryEvents
        }

        guard let index = macros.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let sanitizedEvents = plan.playbackPreservingSanitizedEvents(from: sourceEvents)
        let summary = plan.summary(appliedAt: appliedAt)
        macros[index].playableSanitization = summary
        macros[index].modifiedAt = appliedAt
        let eventsChanged = sanitizedEvents != sourceEvents
        if eventsChanged {
            macros[index].events = sanitizedEvents
            macros[index].refreshCachesFromEvents()
        }

        let updated = macros[index]
        enqueuePersistence(for: id, "save playable sanitization for \(id)") { [client] in
            if eventsChanged {
                try await client.saveEvents(sanitizedEvents, id)
            }
            try await client.saveMetadata(updated)
        }
        await flushPendingPersistence(for: id)
        persistCurrentSelection()
        return summary
    }

    func toggleFavorite(id: UUID) {
        mutate(id) { $0.favorite.toggle() }
        // Re-sort: favorites at top, preserve relative order otherwise.
        let favorites = macros.filter { $0.favorite }
        let rest = macros.filter { !$0.favorite }
        macros = favorites + rest
        save()
    }

    func addTag(id: UUID, _ tag: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        mutate(id) { if !$0.tags.contains(t) { $0.tags.append(t); $0.tags.sort() } }
    }

    func removeTag(id: UUID, _ tag: String) {
        mutate(id) { $0.tags.removeAll { $0 == tag } }
    }

    func updateEvents(id: UUID, events: [RecordedEvent]) {
        guard let index = macros.firstIndex(where: { $0.id == id }) else { return }
        macros[index].events = events
        macros[index].refreshCachesFromEvents()
        macros[index].modifiedAt = Date()
        let macro = macros[index]
        enqueuePersistence(for: id, "save edited events for \(id)") { [client] in
            try await client.saveEvents(events, id)
            try await client.saveMetadata(macro)
        }
    }
    
    func loadEvents(for id: UUID) async throws -> [RecordedEvent] {
        return try await client.loadEvents(id)
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(id) { $0.name = trimmed.isEmpty ? "Untitled" : trimmed }
    }

    func delete(id: UUID) {
        // If anyone chains to this, break the chain.
        for i in macros.indices where macros[i].chainTo == id {
            macros[i].chainTo = nil
            macros[i].modifiedAt = Date()
            let m = macros[i]
            enqueuePersistence(for: m.id, "break deleted macro chain for \(m.id)") { [client] in
                try await client.saveMetadata(m)
            }
        }
        macros.removeAll { $0.id == id }
        if currentMacroID == id {
            currentMacroID = macros.first?.id
        }
        enqueuePersistence(for: id, "delete macro \(id)") { [client] in
            try await client.deleteMacro(id)
        }
        save()
    }

    func deleteMany(ids: Set<UUID>) {
        for id in ids {
            for i in macros.indices where macros[i].chainTo == id {
                macros[i].chainTo = nil
                let m = macros[i]
                enqueuePersistence(for: m.id, "break deleted macro chain for \(m.id)") { [client] in
                    try await client.saveMetadata(m)
                }
            }
        }
        macros.removeAll { ids.contains($0.id) }
        if let cur = currentMacroID, ids.contains(cur) {
            currentMacroID = macros.first?.id
        }
        for id in ids {
            enqueuePersistence(for: id, "delete macro \(id)") { [client] in
                try await client.deleteMacro(id)
            }
        }
        save()
    }

    func duplicate(id: UUID) async throws -> SavedMacro? {
        guard let source = macros.first(where: { $0.id == id }) else { return nil }

        // Full events are repository-owned and may not be present in the manifest
        // cache. Only this source Macro's older writes can affect its snapshot.
        await flushPendingPersistence(for: id)

        do {
            let events = try await client.loadEvents(id)
            var copy = source
            copy.id = UUID()
            copy.name = source.name + " copy"
            copy.createdAt = Date()
            copy.modifiedAt = Date()
            copy.hotkey = nil
            copy.playCount = 0
            copy.lastPlayedAt = nil
            copy.totalRunTime = 0
            copy.favorite = false
            copy.events = events
            copy.refreshCachesFromEvents()

            let finalCopy = copy
            if let index = macros.firstIndex(where: { $0.id == id }) {
                macros.insert(finalCopy, at: index + 1)
            } else {
                macros.insert(finalCopy, at: 0)
            }
            enqueuePersistence(for: finalCopy.id, "save duplicated events for \(finalCopy.id)") { [client] in
                try await client.saveEvents(events, finalCopy.id)
            }
            save()
            return finalCopy
        } catch {
            issue = .readMacro(error.localizedDescription)
            NSLog("SparkleRecorder: Failed to duplicate macro \(id): \(error)")
            throw error
        }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        macros.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    /// Move a macro by id immediately before another id (for SwiftUI drag-and-drop).
    func move(id: UUID, before targetID: UUID) {
        guard let from = macros.firstIndex(where: { $0.id == id }),
              let to = macros.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        let macro = macros.remove(at: from)
        let insertAt = (from < to) ? to - 1 : to
        macros.insert(macro, at: insertAt)
        save()
    }

    func select(id: UUID) {
        currentMacroID = id
        persistCurrentSelection()
    }

    /// Atomically increment play stats.
    func recordPlay(id: UUID, runTime: TimeInterval) {
        mutate(id) {
            $0.playCount += 1
            $0.lastPlayedAt = Date()
            $0.totalRunTime += runTime
        }
    }

    // MARK: - Filtering

    func macros(for filter: LibraryFilter, search: String) -> [SavedMacro] {
        let trimmed = search.trimmingCharacters(in: .whitespaces).lowercased()
        let base: [SavedMacro]
        switch filter {
        case .all:        base = macros
        case .favorites:  base = macros.filter { $0.favorite }
        case .recent:
            let cutoff = Date().addingTimeInterval(-86_400 * 7) // last 7 days
            base = macros.filter { ($0.lastPlayedAt ?? $0.modifiedAt) >= cutoff }
        case .mostPlayed:
            base = macros.sorted { $0.playCount > $1.playCount }
                .filter { $0.playCount > 0 }
        case .withHotkey: base = macros.filter { $0.hotkey != nil }
        case .tag(let t): base = macros.filter { $0.tags.contains(t) }
        case .accent(let name):
            let target = normalizedAccentName(name)
            base = macros.filter { normalizedAccentName($0.accent) == target }
        }
        if trimmed.isEmpty { return base }
        return base.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.tags.contains { $0.lowercased().contains(trimmed) }
                || $0.notes.lowercased().contains(trimmed)
                || (normalizedAccentName($0.accent).map {
                    $0.lowercased().contains(trimmed) || accentDisplayName($0).lowercased().contains(trimmed)
                } ?? false)
        }
    }

    // MARK: - Helpers

    private func mutate(_ id: UUID, _ body: (inout SavedMacro) -> Void) {
        guard let idx = macros.firstIndex(where: { $0.id == id }) else { return }
        body(&macros[idx])
        macros[idx].modifiedAt = Date()
        let macro = macros[idx]
        enqueuePersistence(for: id, "save metadata for \(id)") { [client] in
            try await client.saveMetadata(macro)
        }
    }

    @discardableResult
    private func assignLibraryOrder() -> [SavedMacro] {
        var changed: [SavedMacro] = []
        changed.reserveCapacity(macros.count)
        for index in macros.indices where macros[index].libraryOrder != index {
            macros[index].libraryOrder = index
            changed.append(macros[index])
        }
        return changed
    }

    private func enqueuePersistence(
        for id: UUID,
        _ label: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let previous = persistenceTails[id]
        persistenceGeneration &+= 1
        persistenceGenerations[id, default: 0] &+= 1
        persistenceTails[id] = Task {
            await previous?.value
            do {
                try await operation()
            } catch {
                self.issue = .saveChanges(error.localizedDescription)
                NSLog("SparkleRecorder: Persistence failed (\(label)): \(error)")
            }
        }
    }

    /// Waits only for writes that can change one Macro. This is the normal
    /// recording-finalization barrier; unrelated Library persistence stays in the
    /// background.
    func flushPendingPersistence(for id: UUID) async {
        while true {
            let generation = persistenceGenerations[id, default: 0]
            let tail = persistenceTails[id]
            await tail?.value
            guard persistenceGenerations[id, default: 0] == generation else { continue }
            return
        }
    }

    /// Full-Library durability barrier reserved for termination and operations
    /// whose contract genuinely spans every Macro.
    func flushPendingPersistence() async {
        while true {
            let generation = persistenceGeneration
            let tails = Array(persistenceTails.values)
            for tail in tails {
                await tail.value
            }
            guard persistenceGeneration == generation else { continue }
            return
        }
    }

    private func autoName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return "Macro " + f.string(from: Date())
    }
}

// MARK: - Relative-time helper

enum RelativeTime {
    static func string(from date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60 { return String(localized: "just now", table: "Common") }
        if s < 3600 {
            let format = String(localized: "%dm ago", table: "Common")
            return String(format: format, Int(s / 60))
        }
        if s < 86_400 {
            let format = String(localized: "%dh ago", table: "Common")
            return String(format: format, Int(s / 3600))
        }
        if s < 604_800 {
            let format = String(localized: "%dd ago", table: "Common")
            return String(format: format, Int(s / 86_400))
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
