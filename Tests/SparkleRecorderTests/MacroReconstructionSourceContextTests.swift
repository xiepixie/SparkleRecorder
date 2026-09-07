import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro reconstruction source context")
struct MacroReconstructionSourceContextTests {
    @Test("AI source context exposes execution evidence without Library personalization")
    func sourceContextIsMinimalAndExplicit() throws {
        let surface = TestFixtures.surface(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "ChatGPT"
        )
        let chainedID = UUID()
        let macro = SavedMacro(
            name: "Private library macro",
            events: TestFixtures.clickPair(),
            loops: 3,
            speed: 1.25,
            surfaces: [TestFixtures.surfaceId: surface],
            followWindowOffset: true,
            icon: "bolt",
            accent: "blue",
            tags: ["private"],
            favorite: true,
            hotkey: HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048),
            notes: "do not export this note",
            chainTo: chainedID,
            playCount: 42,
            lastPlayedAt: Date(timeIntervalSince1970: 10),
            totalRunTime: 900
        )
        let revision = try MacroCandidateIdentity.revision(of: macro)
        let context = MacroReconstructionSourceContext(source: macro, sourceRevision: revision)
        let data = try JSONEncoder().encode(context)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(context.version == MacroReconstructionSourceContext.currentVersion)
        #expect(context.sourceRevision == revision)
        #expect(context.macroID == macro.id)
        #expect(context.eventCount == macro.events.count)
        #expect(context.duration == (macro.events.last?.time ?? 0))
        let projectedSurface = try #require(context.surfaces[TestFixtures.surfaceId])
        #expect(projectedSurface.bundleIdentifier == surface.bundleIdentifier)
        #expect(projectedSurface.windowTitle == surface.windowTitle)
        #expect(projectedSurface.recordedFrame == surface.recordedFrame)
        #expect(context.protectedExecution.loops == 3)
        #expect(context.protectedExecution.speed == 1.25)
        #expect(context.protectedExecution.followWindowOffset)
        #expect(context.protectedExecution.hasChainedMacro)

        #expect(object["events"] == nil)
        #expect(object["notes"] == nil)
        #expect(object["tags"] == nil)
        #expect(object["hotkey"] == nil)
        #expect(object["favorite"] == nil)
        #expect(object["playCount"] == nil)
        #expect(object["lastPlayedAt"] == nil)
        #expect(object["totalRunTime"] == nil)
        #expect(object["semanticRecording"] == nil)
        #expect(object["chainTo"] == nil)
        let surfaces = try #require(object["surfaces"] as? [String: Any])
        let serializedSurface = try #require(surfaces[TestFixtures.surfaceId] as? [String: Any])
        #expect(serializedSurface["capturedAt"] == nil)
        #expect(serializedSurface["recordedWindowId"] == nil)
        #expect(serializedSurface["recordedDisplayId"] == nil)
    }
}
