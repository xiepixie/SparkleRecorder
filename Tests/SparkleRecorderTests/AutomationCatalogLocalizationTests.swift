import Foundation
import Testing

@Suite("Automation Catalog Localization Tests")
struct AutomationCatalogLocalizationTests {
  @Test("Automation catalog has English and Simplified Chinese translations")
  func catalogStringsAreLocalized() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let catalogs: [String: [String]] = [
      "Automation": [
        "%d macros · %d steps",
        "%d executions",
        "1 macro",
        "All automations",
        "All run history",
        "Automations",
        "Build Automation Sequence…",
        "Change the search or status filter.",
        "Choose an automation to manage its schedule and runs.",
        "Copy diagnostics",
        "Create Automation",
        "Create Automation…",
        "Create from Macro Library",
        "Create one from a macro, then choose when it runs.",
        "Current status",
        "Delete automation",
        "Delete automation “%@”?",
        "Delete automation?",
        "Diagnostics",
        "Edit automation",
        "Execution ID",
        "New advanced workflow",
        "No automations",
        "No evidence",
        "No matching automations",
        "Open Macro Library",
        "Open the workflow editor to preserve its advanced settings.",
        "Open the workflow editor to repair this automation.",
        "Pause automation",
        "Recent runs",
        "Resume automation",
        "Schedules / sequences",
        "Run now",
        "Run this automation to create its first result and evidence record.",
        "Search automations",
        "Sequence",
        "Sequence could not be opened",
        "Select an automation",
        "Single macro",
        "The automation configuration will be removed. Its macros and saved run history will remain.",
        "Workflow Editor",
      ],
      "Common": ["Active", "Total"],
    ]

    for (table, keys) in catalogs {
      let data = try Data(
        contentsOf:
          root
          .appendingPathComponent("Sources/SparkleRecorder")
          .appendingPathComponent("\(table).xcstrings"))
      let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
      let strings = try #require(object["strings"] as? [String: Any])
      for key in keys {
        let entry = try #require(strings[key] as? [String: Any], "Missing \(table) key: \(key)")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        #expect(localizations["en"] != nil, "Missing English \(table) translation: \(key)")
        #expect(localizations["zh-Hans"] != nil, "Missing Chinese \(table) translation: \(key)")
      }
    }
  }
}
