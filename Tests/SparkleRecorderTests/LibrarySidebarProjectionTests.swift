import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Library Sidebar Projection Tests")
struct LibrarySidebarProjectionTests {
    @Test("Sidebar counts and stats are derived in one projection")
    func sidebarProjectionMatchesLibrarySemantics() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let hotkey = HotkeyBinding(keyCode: 1, name: "F1")

        let first = SavedMacro(
            name: "First",
            events: [],
            modifiedAt: now.addingTimeInterval(-86_400),
            accent: "blue",
            tags: ["common", "work"],
            favorite: true,
            hotkey: hotkey,
            playCount: 3,
            totalRunTime: 12
        )
        let second = SavedMacro(
            name: "Second",
            events: [],
            modifiedAt: now.addingTimeInterval(-86_400 * 10),
            accent: "blue",
            tags: ["common"],
            lastPlayedAt: now.addingTimeInterval(-86_400 * 2),
            totalRunTime: 8
        )
        let third = SavedMacro(
            name: "Third",
            events: [],
            modifiedAt: now.addingTimeInterval(-86_400 * 20),
            accent: "red",
            tags: ["other"],
            playCount: 1,
            totalRunTime: 5
        )

        let projection = LibrarySidebarProjection(macros: [first, second, third], now: now)

        #expect(projection.count(for: .all) == 3)
        #expect(projection.count(for: .favorites) == 1)
        #expect(projection.count(for: .recent) == 2)
        #expect(projection.count(for: .mostPlayed) == 2)
        #expect(projection.count(for: .withHotkey) == 1)
        #expect(projection.count(for: .tag("common")) == 2)
        #expect(projection.count(for: .tag("work")) == 1)
        #expect(projection.count(for: .accent("Blue")) == 2)
        #expect(Set(projection.tags) == Set(["common", "work", "other"]))
        #expect(Set(projection.accents) == Set(["Blue", "Red"]))
        #expect(projection.totalMacros == 3)
        #expect(projection.totalPlays == 4)
        #expect(projection.totalSaved == 25)
    }
}
