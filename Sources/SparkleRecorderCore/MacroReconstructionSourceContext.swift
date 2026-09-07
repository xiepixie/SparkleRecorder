import Foundation

/// Minimal Playback Surface projection supplied to an external reconstruction author.
/// It intentionally omits local WindowServer/display identity and capture timestamps;
/// external authors only need stable semantic identity plus recorded geometry.
public struct MacroReconstructionSurfaceContext: Codable, Equatable, Sendable {
    public var id: String
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var windowTitlePattern: String?
    public var recordedFrame: RectValue
    public var recordedContentFrame: RectValue?
    public var contentElementRole: String?
    public var contentElementSubrole: String?
    public var contentFrameSource: String?

    public init(id: String, surface: PlaybackSurface) {
        self.id = id
        self.appName = surface.appName
        self.bundleIdentifier = surface.bundleIdentifier
        self.windowTitle = surface.windowTitle
        self.windowTitlePattern = surface.windowTitlePattern
        self.recordedFrame = surface.recordedFrame
        self.recordedContentFrame = surface.recordedContentFrame
        self.contentElementRole = surface.contentElementRole
        self.contentElementSubrole = surface.contentElementSubrole
        self.contentFrameSource = surface.contentFrameSource
    }
}

/// Lightweight, versioned source context supplied to an external reconstruction author.
/// Raw executable events intentionally do not live here: reconstruction.json is the
/// primary action inventory and candidate-template.json is the single exported copy of
/// the source event stream used at draft time. This file stays small enough to read up
/// front while still describing Playback Surfaces and protected execution facts.
public struct MacroReconstructionSourceContext: Codable, Equatable, Sendable {
    public static let currentVersion = MacroReconstructionContractVersions.sourceContext

    private enum CodingKeys: String, CodingKey {
        case version, sourceRevision, macroID, name, macroVersion, eventCount, duration
        case events // legacy v2 only; decoded for summary compatibility and never re-encoded
        case surfaces, protectedExecution
    }

    public struct ProtectedExecution: Codable, Equatable, Sendable {
        public var loops: Int
        public var speed: Double
        public var followWindowOffset: Bool
        public var hasChainedMacro: Bool

        public init(
            loops: Int,
            speed: Double,
            followWindowOffset: Bool,
            hasChainedMacro: Bool
        ) {
            self.loops = loops
            self.speed = speed
            self.followWindowOffset = followWindowOffset
            self.hasChainedMacro = hasChainedMacro
        }
    }

    public var version: String
    public var sourceRevision: String
    public var macroID: UUID
    public var name: String
    public var macroVersion: Int
    public var eventCount: Int
    public var duration: TimeInterval
    public var surfaces: [String: MacroReconstructionSurfaceContext]
    public var protectedExecution: ProtectedExecution

    public init(source: SavedMacro, sourceRevision: String) {
        self.version = Self.currentVersion
        self.sourceRevision = sourceRevision
        self.macroID = source.id
        self.name = source.name
        self.macroVersion = source.version
        self.eventCount = source.events.count
        self.duration = source.events.last?.time ?? 0
        self.surfaces = Dictionary(uniqueKeysWithValues: source.surfaces.map { id, surface in
            (id, MacroReconstructionSurfaceContext(id: id, surface: surface))
        })
        self.protectedExecution = ProtectedExecution(
            loops: source.loops,
            speed: source.speed,
            followWindowOffset: source.followWindowOffset,
            hasChainedMacro: source.chainTo != nil
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        sourceRevision = try container.decode(String.self, forKey: .sourceRevision)
        macroID = try container.decode(UUID.self, forKey: .macroID)
        name = try container.decode(String.self, forKey: .name)
        macroVersion = try container.decode(Int.self, forKey: .macroVersion)
        let legacyEvents = try container.decodeIfPresent([RecordedEvent].self, forKey: .events) ?? []
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount) ?? legacyEvents.count
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? (legacyEvents.last?.time ?? 0)
        surfaces = try container.decode([String: MacroReconstructionSurfaceContext].self, forKey: .surfaces)
        protectedExecution = try container.decode(ProtectedExecution.self, forKey: .protectedExecution)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(sourceRevision, forKey: .sourceRevision)
        try container.encode(macroID, forKey: .macroID)
        try container.encode(name, forKey: .name)
        try container.encode(macroVersion, forKey: .macroVersion)
        try container.encode(eventCount, forKey: .eventCount)
        try container.encode(duration, forKey: .duration)
        try container.encode(surfaces, forKey: .surfaces)
        try container.encode(protectedExecution, forKey: .protectedExecution)
    }
}
