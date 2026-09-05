import Foundation
import Testing

@Suite("Library Menu Localization Tests")
struct LibraryMenuLocalizationTests {
    @Test("Card context and customization menus have English and Simplified Chinese copy")
    func cardMenusAreLocalized() throws {
        let root = repositoryRoot()
        let catalogs: [String: [String]] = [
            "Automation": [
                "%@ sequence",
                "%d macros · %@",
                "Add at least one macro.",
                "Add macro",
                "Advanced edit…",
                "Applications remain open after the sequence",
                "Cancel test (%d)",
                "Continue immediately",
                "Clear OCR area",
                "Could not create the sequence.",
                "Could not save the sequence.",
                "Each macro once",
                "Draw area",
                "Edit automatic run…",
                "Enter the screen text to wait for.",
                "Give the sequence a name.",
                "Latest run…",
                "Manual only",
                "Match",
                "Move earlier",
                "Move later",
                "New sequence",
                "Entire target screen",
                "Pick from screen",
                "Quick sequence",
                "Remove step",
                "Run automatically…",
                "Save & test in 5 seconds",
                "Save sequence",
                "Sequence name",
                "Sequence saved.",
                "Sequence saved. Next run: %@",
                "Sequence saved. Test started.",
                "Sequence saved, but the test could not start.",
                "Starting test…",
                "Text to find",
                "Text wait timeouts must be greater than zero.",
                "Then",
                "Timing",
                "Wait",
                "Wait durations must be greater than zero.",
                "Wait for a duration",
                "Wait for screen text",
            ],
            "Common": [
                "Add Tag…",
                "Assign Hotkey…",
                "Bind Active Window",
                "Chain To",
                "Clear Hotkey",
                "Clear Window Binding",
                "Color",
                "Create Sequence…",
                "Custom…",
                "Delete",
                "Duplicate",
                "Edit…",
                "Export",
                "Favorite",
                "Follow Window Position",
                "None",
                "Notes…",
                "Play",
                "Rename…",
                "Speed",
                "Unfavorite",
            ],
            "EditorUX": ["As Text…"],
            "Recording": ["As SparkleRecorder File…"],
        ]

        for (table, keys) in catalogs {
            let catalogURL = root
                .appendingPathComponent("Sources/SparkleRecorder")
                .appendingPathComponent("\(table).xcstrings")
            let data = try Data(contentsOf: catalogURL)
            let rootObject = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let strings = try #require(rootObject["strings"] as? [String: Any])

            for key in keys {
                let entry = try #require(strings[key] as? [String: Any], "Missing \(table) key: \(key)")
                let localizations = try #require(entry["localizations"] as? [String: Any])
                #expect(localizations["en"] != nil, "Missing English \(table) translation: \(key)")
                #expect(localizations["zh-Hans"] != nil, "Missing Simplified Chinese \(table) translation: \(key)")
            }
        }
    }

    @Test("Scheduled-run terminology is consistent in Simplified Chinese")
    func scheduledRunTerminologyIsConsistent() throws {
        let strings = try catalogStrings(table: "Automation")
        let expected: [String: String] = [
            "Edit automatic run": "编辑定时运行",
            "Latest run": "最近一次运行",
            "Run automatically": "定时运行",
            "Turn off automatic runs": "关闭定时运行",
        ]

        for (key, value) in expected {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let simplifiedChinese = try #require(localizations["zh-Hans"] as? [String: Any])
            let stringUnit = try #require(simplifiedChinese["stringUnit"] as? [String: Any])
            #expect(stringUnit["value"] as? String == value)
        }
    }

    private func catalogStrings(table: String) throws -> [String: Any] {
        let catalogURL = repositoryRoot()
            .appendingPathComponent("Sources/SparkleRecorder")
            .appendingPathComponent("\(table).xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(rootObject["strings"] as? [String: Any])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
