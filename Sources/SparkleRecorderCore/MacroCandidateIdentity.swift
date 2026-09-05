import CryptoKit
import Foundation

public enum MacroCandidateIdentity {
    /// Stable executable content identity. Never encode the entire SavedMacro:
    /// invalid or changing run statistics and caches must not poison identity.
    public static func revision(of macro: SavedMacro) throws -> String {
        struct Executable: Encodable {
            var version: Int
            var events: [RecordedEvent]
            var surfaces: [String: PlaybackSurface]
            var loops: Int
            var speed: Double
            var followWindowOffset: Bool
            var chainTo: UUID?
        }
        let events = macro.events.map { event in
            var copy = event
            copy.behaviorGroupID = nil
            copy.behaviorGroupName = nil
            return copy
        }
        let surfaces = macro.surfaces.mapValues { surface in
            var copy = surface
            copy.capturedAt = Date(timeIntervalSinceReferenceDate: 0)
            return copy
        }
        let payload = Executable(version: macro.version, events: events, surfaces: surfaces,
                                 loops: macro.loops, speed: macro.speed,
                                 followWindowOffset: macro.followWindowOffset, chainTo: macro.chainTo)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let digest = SHA256.hash(data: try encoder.encode(payload))
            return "macro-executable/v1/" + digest.map { String(format: "%02x", $0) }.joined()
        } catch {
            throw MacroCandidateValidationError.invalidExecutableIdentity(String(describing: error))
        }
    }
}
