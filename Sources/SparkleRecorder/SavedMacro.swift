import Foundation

public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
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

public struct MacroSemanticRecordingReference: Codable, Equatable, Sendable {
    public var recordingID: UUID
    public var bundleRelativePath: String
    public var manifestRelativePath: String
    public var capturedAt: Date
    public var eventCount: Int

    public init(
        recordingID: UUID,
        bundleRelativePath: String,
        manifestRelativePath: String,
        capturedAt: Date = Date(),
        eventCount: Int
    ) {
        self.recordingID = recordingID
        self.bundleRelativePath = bundleRelativePath
        self.manifestRelativePath = manifestRelativePath
        self.capturedAt = capturedAt
        self.eventCount = max(0, eventCount)
    }
}

public struct MacroPlayableSanitizationSummary: Codable, Equatable, Sendable {
    public var recordingID: UUID?
    public var appliedAt: Date
    public var sanitizedEventCount: Int
    public var withheldReadableFieldCount: Int
    public var reviewRequiredEventCount: Int
    public var reviewRequiredFieldCount: Int

    public init(
        recordingID: UUID? = nil,
        appliedAt: Date = Date(),
        sanitizedEventCount: Int,
        withheldReadableFieldCount: Int,
        reviewRequiredEventCount: Int,
        reviewRequiredFieldCount: Int
    ) {
        self.recordingID = recordingID
        self.appliedAt = appliedAt
        self.sanitizedEventCount = max(0, sanitizedEventCount)
        self.withheldReadableFieldCount = max(0, withheldReadableFieldCount)
        self.reviewRequiredEventCount = max(0, reviewRequiredEventCount)
        self.reviewRequiredFieldCount = max(0, reviewRequiredFieldCount)
    }
}

/// A saved macro entry in the library.
public struct SavedMacro: Codable, Identifiable, Equatable, Sendable {
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
    public var surfaces: [String: PlaybackSurface] = [:]
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
    /// Optional semantic recording evidence captured alongside the playable event stream.
    public var semanticRecording: MacroSemanticRecordingReference?
    /// Summary of readable playable macro metadata withheld because semantic evidence was sensitive.
    public var playableSanitization: MacroPlayableSanitizationSummary?

    // Statistics
    public var playCount: Int = 0
    public var lastPlayedAt: Date?
    public var totalRunTime: TimeInterval = 0
    
    // Cached values for fast loading without parsing the heavy events array
    public var cachedDuration: TimeInterval?
    public var cachedEventCount: Int?
    public var cachedWaveformBars: [WaveformBar]?

    public var duration: TimeInterval { cachedDuration ?? (events.last?.time ?? 0) }
    public var eventCount: Int { cachedEventCount ?? events.count }
    public var waveformBars: [WaveformBar] {
        if let cachedWaveformBars, !cachedWaveformBars.isEmpty {
            return cachedWaveformBars
        }
        return WaveformProjection.timedBars(from: events, maxBars: Self.previewWaveformBarLimit, duration: duration)
    }
    public var clickCount: Int {
        events.filter { $0.kind == .leftMouseDown || $0.kind == .rightMouseDown || $0.kind == .otherMouseDown }.count
    }
    public var keyCount: Int { events.filter { $0.kind.isKey }.count }
    public var scrollCount: Int { events.filter { $0.kind == .scrollWheel }.count }

    public enum CodingKeys: String, CodingKey {
        case id, name, events, createdAt, modifiedAt, version
        case loops, speed, surface, surfaces, followWindowOffset
        case icon, accent, tags, favorite, hotkey, notes, chainTo
        case semanticRecording, playableSanitization
        case playCount, lastPlayedAt, totalRunTime
        case cachedDuration, cachedEventCount, cachedWaveformBars
    }

    public static let previewWaveformBarLimit = 60

    public init(id: UUID = UUID(),
                name: String,
                events: [RecordedEvent],
                createdAt: Date = Date(),
                modifiedAt: Date = Date(),
                version: Int = 3,
                loops: Int = 1,
                speed: Double = 1.0,
                surfaces: [String: PlaybackSurface] = [:],
                followWindowOffset: Bool = true,
                icon: String? = nil,
                accent: String? = nil,
                tags: [String] = [],
                favorite: Bool = false,
                hotkey: HotkeyBinding? = nil,
                notes: String = "",
                chainTo: UUID? = nil,
                semanticRecording: MacroSemanticRecordingReference? = nil,
                playableSanitization: MacroPlayableSanitizationSummary? = nil,
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
        self.surfaces = surfaces
        self.followWindowOffset = followWindowOffset
        self.icon = icon
        self.accent = accent
        self.tags = tags
        self.favorite = favorite
        self.hotkey = hotkey
        self.notes = notes
        self.chainTo = chainTo
        self.semanticRecording = semanticRecording
        self.playableSanitization = playableSanitization
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.totalRunTime = totalRunTime
        refreshCachesFromEvents()
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
        if let s = try c.decodeIfPresent(PlaybackSurface.self, forKey: .surface) {
            self.surfaces = ["surface-1": s]
        } else {
            self.surfaces = try c.decodeIfPresent([String: PlaybackSurface].self, forKey: .surfaces) ?? [:]
        }
        self.followWindowOffset = try c.decodeIfPresent(Bool.self, forKey: .followWindowOffset) ?? true
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.accent = try c.decodeIfPresent(String.self, forKey: .accent)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        self.hotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .hotkey)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.chainTo = try c.decodeIfPresent(UUID.self, forKey: .chainTo)
        self.semanticRecording = try c.decodeIfPresent(
            MacroSemanticRecordingReference.self,
            forKey: .semanticRecording
        )
        self.playableSanitization = try c.decodeIfPresent(
            MacroPlayableSanitizationSummary.self,
            forKey: .playableSanitization
        )
        self.playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        self.lastPlayedAt = try c.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        self.totalRunTime = try c.decodeIfPresent(TimeInterval.self, forKey: .totalRunTime) ?? 0
        self.cachedDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .cachedDuration)
        self.cachedEventCount = try c.decodeIfPresent(Int.self, forKey: .cachedEventCount)
        self.cachedWaveformBars = try c.decodeIfPresent([WaveformBar].self, forKey: .cachedWaveformBars)
        if !events.isEmpty {
            fillMissingCachesFromEvents()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(events, forKey: .events)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(version, forKey: .version)
        try c.encode(loops, forKey: .loops)
        try c.encode(speed, forKey: .speed)
        try c.encode(surfaces, forKey: .surfaces)
        try c.encode(followWindowOffset, forKey: .followWindowOffset)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(accent, forKey: .accent)
        try c.encode(tags, forKey: .tags)
        try c.encode(favorite, forKey: .favorite)
        try c.encodeIfPresent(hotkey, forKey: .hotkey)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(chainTo, forKey: .chainTo)
        try c.encodeIfPresent(semanticRecording, forKey: .semanticRecording)
        try c.encodeIfPresent(playableSanitization, forKey: .playableSanitization)
        try c.encode(playCount, forKey: .playCount)
        try c.encodeIfPresent(lastPlayedAt, forKey: .lastPlayedAt)
        try c.encode(totalRunTime, forKey: .totalRunTime)
        try c.encodeIfPresent(cachedDuration, forKey: .cachedDuration)
        try c.encodeIfPresent(cachedEventCount, forKey: .cachedEventCount)
        try c.encodeIfPresent(cachedWaveformBars, forKey: .cachedWaveformBars)
    }

    public var needsPreviewCacheRefresh: Bool {
        cachedDuration == nil || cachedEventCount == nil || cachedWaveformBars == nil
    }

    public mutating func refreshCachesFromEvents(maxWaveformBars: Int = Self.previewWaveformBarLimit) {
        cachedDuration = events.last?.time ?? 0
        cachedEventCount = events.count
        cachedWaveformBars = WaveformProjection.timedBars(from: events, maxBars: maxWaveformBars, duration: cachedDuration)
    }

    private mutating func fillMissingCachesFromEvents() {
        if cachedDuration == nil {
            cachedDuration = events.last?.time ?? 0
        }
        if cachedEventCount == nil {
            cachedEventCount = events.count
        }
        if cachedWaveformBars == nil {
            cachedWaveformBars = WaveformProjection.timedBars(
                from: events,
                maxBars: Self.previewWaveformBarLimit,
                duration: cachedDuration
            )
        }
    }
}

public extension SavedMacro {
    var playbackContext: PlaybackContext {
        guard !surfaces.isEmpty else {
            return PlaybackContext()
        }

        return PlaybackContext(
            surfaces: surfaces,
            currentSurfaceFrames: [:],
            coordinateMode: followWindowOffset ? .boundWindowOffset : .screenAbsolute
        )
    }
}
