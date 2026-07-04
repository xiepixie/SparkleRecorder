import Foundation

public struct HotkeyBinding: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    public var name: String
    public var modifiers: UInt32

    public init(keyCode: UInt32, name: String, modifiers: UInt32 = 0) {
        self.keyCode = keyCode
        self.name = name
        self.modifiers = modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        self.name = try container.decode(String.self, forKey: .name)
        self.modifiers = try container.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? 0
    }
}

/// A saved macro entry in the library.
public struct SavedMacro: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var events: [RecordedEvent]
    public var createdAt: Date
    public var modifiedAt: Date
    public var version: Int = 3

    // Playback configuration
    public var loops: Int = 1
    public var speed: Double = 1.0

    // Playback surface metadata
    public var surface: PlaybackSurface?
    public var followWindowOffset: Bool = true

    // Personalization
    /// SF Symbol name or single emoji used as the card icon.
    public var icon: String?
    /// Card accent color (hex like "#F44" or named "blue", "green", etc.). Defaults pick auto.
    public var accent: String?
    /// User-defined tags for filtering / grouping.
    public var tags: [String] = []
    /// Pinned to the top of the library and to the "Favorites" library filter.
    public var favorite: Bool = false
    /// Per-macro global hotkey (F-key only, for reliability).
    public var hotkey: HotkeyBinding?
    /// Free-form user notes shown in the editor inspector.
    public var notes: String = ""
    /// Optional chain — when this macro finishes playing, immediately play this next macro.
    public var chainTo: UUID?

    // Statistics
    public var playCount: Int = 0
    public var lastPlayedAt: Date?
    public var totalRunTime: TimeInterval = 0

    public var duration: TimeInterval { events.last?.time ?? 0 }
    public var eventCount: Int { events.count }
    public var clickCount: Int {
        events.filter { $0.kind == .leftMouseDown || $0.kind == .rightMouseDown || $0.kind == .otherMouseDown }.count
    }
    public var keyCount: Int { events.filter { $0.kind.isKey }.count }
    public var scrollCount: Int { events.filter { $0.kind == .scrollWheel }.count }

    public enum CodingKeys: String, CodingKey {
        case id, name, events, createdAt, modifiedAt, version
        case loops, speed, surface, followWindowOffset
        case icon, accent, tags, favorite, hotkey, notes, chainTo
        case playCount, lastPlayedAt, totalRunTime
    }

    public init(id: UUID = UUID(),
                name: String,
                events: [RecordedEvent],
                createdAt: Date = Date(),
                modifiedAt: Date = Date(),
                version: Int = 3,
                loops: Int = 1,
                speed: Double = 1.0,
                surface: PlaybackSurface? = nil,
                followWindowOffset: Bool = true,
                icon: String? = nil,
                accent: String? = nil,
                tags: [String] = [],
                favorite: Bool = false,
                hotkey: HotkeyBinding? = nil,
                notes: String = "",
                chainTo: UUID? = nil,
                playCount: Int = 0,
                lastPlayedAt: Date? = nil,
                totalRunTime: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.events = events
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.version = version
        self.loops = loops
        self.speed = speed
        self.surface = surface
        self.followWindowOffset = followWindowOffset
        self.icon = icon
        self.accent = accent
        self.tags = tags
        self.favorite = favorite
        self.hotkey = hotkey
        self.notes = notes
        self.chainTo = chainTo
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.totalRunTime = totalRunTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.events = try c.decode([RecordedEvent].self, forKey: .events)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 3
        self.loops = try c.decodeIfPresent(Int.self, forKey: .loops) ?? 1
        self.speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        self.surface = try c.decodeIfPresent(PlaybackSurface.self, forKey: .surface)
        self.followWindowOffset = try c.decodeIfPresent(Bool.self, forKey: .followWindowOffset) ?? true
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.accent = try c.decodeIfPresent(String.self, forKey: .accent)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        self.hotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .hotkey)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.chainTo = try c.decodeIfPresent(UUID.self, forKey: .chainTo)
        self.playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        self.lastPlayedAt = try c.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        self.totalRunTime = try c.decodeIfPresent(TimeInterval.self, forKey: .totalRunTime) ?? 0
    }
}
