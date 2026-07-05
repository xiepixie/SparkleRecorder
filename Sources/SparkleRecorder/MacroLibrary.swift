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
        case .all:        return NSLocalizedString("All Macros", comment: "")
        case .favorites:  return NSLocalizedString("Favorites", comment: "")
        case .recent:     return NSLocalizedString("Recent", comment: "")
        case .mostPlayed: return NSLocalizedString("Most Played", comment: "")
        case .withHotkey: return NSLocalizedString("Has Hotkey", comment: "")
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



/// The user's saved macros. Auto-persists to Application Support.
@MainActor
final class MacroLibrary: ObservableObject {
    @Published private(set) var macros: [SavedMacro] = []
    @Published var currentMacroID: UUID?

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
               let id = UUID(uuidString: idString) {
                self.currentMacroID = id
            } else {
                self.currentMacroID = self.macros.first?.id
            }
        } catch {
            NSLog("SparkleRecorder: Failed to load from MacroRepository: \(error)")
        }
    }

    func save() {
        // currentMacroID is saved to UserDefaults
        if let id = currentMacroID {
            UserDefaults.standard.set(id.uuidString, forKey: "currentMacroID")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentMacroID")
        }
        
        // For array re-ordering (if drag-and-drop was used), we save all metadata
        for macro in macros {
            Task { try? await client.saveMetadata(macro) }
        }
    }

    // MARK: - Mutations

    /// Insert a fully-built macro (used by importers to preserve metadata).
    func insert(_ macro: SavedMacro) {
        macros.insert(macro, at: 0)
        currentMacroID = macro.id
        Task { try? await client.saveEvents(macro.events, macro.id) }
        Task { try? await client.saveMetadata(macro) }
        save()
    }

    @discardableResult
    func add(events: [RecordedEvent], name: String? = nil, loops: Int = 1) -> SavedMacro {
        let n = (name?.isEmpty == false) ? name! : autoName()
        let m = SavedMacro(name: n, events: events, loops: loops)
        macros.insert(m, at: insertionIndex())
        currentMacroID = m.id
        Task { try? await client.saveEvents(m.events, m.id) }
        Task { try? await client.saveMetadata(m) }
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
        if let hk = hotkey {
            for i in macros.indices where macros[i].id != id && macros[i].hotkey?.keyCode == hk.keyCode {
                macros[i].hotkey = nil
                macros[i].modifiedAt = Date()
            }
        }
        mutate(id) { $0.hotkey = hotkey }
    }

    func setNotes(id: UUID, notes: String) {
        mutate(id) { $0.notes = notes }
    }

    func setSurface(id: UUID, surface: PlaybackSurface?) {
        mutate(id) { 
            if let surface = surface {
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

    func setFollowWindowOffset(id: UUID, enabled: Bool) {
        mutate(id) { $0.followWindowOffset = enabled }
    }

    func setChainTo(id: UUID, target: UUID?) {
        // Refuse self-chains and any link that would close a cycle
        // (walk capped by macro count in case a cycle already exists via import).
        if let target {
            if target == id { return }
            var cursor: UUID? = target
            var hops = 0
            while let c = cursor, hops <= macros.count {
                if c == id { return }   // would create a cycle
                cursor = macros.first(where: { $0.id == c })?.chainTo
                hops += 1
            }
        }
        mutate(id) { $0.chainTo = target }
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
        mutate(id) {
            $0.events = events
            $0.refreshCachesFromEvents()
        }
        Task { try? await client.saveEvents(events, id) }
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
            Task { try? await client.saveMetadata(m) }
        }
        macros.removeAll { $0.id == id }
        if currentMacroID == id {
            currentMacroID = macros.first?.id
        }
        Task { try? await client.deleteMacro(id) }
        save()
    }

    func deleteMany(ids: Set<UUID>) {
        for id in ids {
            for i in macros.indices where macros[i].chainTo == id {
                macros[i].chainTo = nil
                let m = macros[i]
                Task { try? await client.saveMetadata(m) }
            }
        }
        macros.removeAll { ids.contains($0.id) }
        if let cur = currentMacroID, ids.contains(cur) {
            currentMacroID = macros.first?.id
        }
        for id in ids {
            Task { try? await client.deleteMacro(id) }
        }
        save()
    }

    func duplicate(id: UUID) {
        guard let src = macros.first(where: { $0.id == id }) else { return }
        var copy = src
        copy.id = UUID()
        copy.name = src.name + " copy"
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        copy.hotkey = nil // hotkey is unique
        copy.playCount = 0
        copy.lastPlayedAt = nil
        copy.totalRunTime = 0
        copy.favorite = false
        
        // Fetch full events before duplicating!
        Task {
            if let events = try? await client.loadEvents(id) {
                var newCopy = copy
                newCopy.events = events
                newCopy.refreshCachesFromEvents()
                let finalCopy = newCopy
                
                if let idx = self.macros.firstIndex(where: { $0.id == id }) {
                    self.macros.insert(finalCopy, at: idx + 1)
                } else {
                    self.macros.insert(finalCopy, at: 0)
                }
                self.save()
                
                try? await client.saveEvents(events, finalCopy.id)
                try? await client.saveMetadata(finalCopy)
            }
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
        save()
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
        let m = macros[idx]
        Task { try? await client.saveMetadata(m) }
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
        if s < 60 { return NSLocalizedString("just now", comment: "") }
        if s < 3600 {
            let format = NSLocalizedString("%dm ago", comment: "")
            return String(format: format, Int(s / 60))
        }
        if s < 86_400 {
            let format = NSLocalizedString("%dh ago", comment: "")
            return String(format: format, Int(s / 3600))
        }
        if s < 604_800 {
            let format = NSLocalizedString("%dd ago", comment: "")
            return String(format: format, Int(s / 86_400))
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
