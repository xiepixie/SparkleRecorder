import Foundation
import Testing

@Suite("Automation Linear Sequence Localization Tests")
struct AutomationLinearSequenceLocalizationTests {
  @Test("Quick Sequence surface has English and Simplified Chinese translations")
  func quickSequenceStringsAreLocalized() throws {
    let catalogURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/SparkleRecorder/Automation.xcstrings")
    let data = try Data(contentsOf: catalogURL)
    let root = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let strings = try #require(root["strings"] as? [String: Any])

    for key in Self.keys {
      let entry = try #require(strings[key] as? [String: Any], "Missing key: \(key)")
      let localizations = try #require(entry["localizations"] as? [String: Any])
      #expect(localizations["en"] != nil, "Missing English: \(key)")
      #expect(localizations["zh-Hans"] != nil, "Missing Simplified Chinese: \(key)")
    }
  }

  private static let keys = [
    "Quick sequence",
    "Continue immediately",
    "Wait for a duration",
    "Wait for screen text",
    "Manual only",
    "Every day",
    "Every week",
    "Add macro",
    "Add login or navigation macro",
    "No wait",
    "Open target application",
    "Start preparation",
    "Wait after window appears",
    "Use this for startup loading. If login or navigation is required, create a sequence with preparation macros.",
    "Move earlier",
    "Move later",
    "Remove step",
    "Sequence name",
    "Save sequence",
    "Advanced edit…",
    "Sequence saved.",
    "Sequence saved. Test started.",
    "Sequence saved, but the test could not start.",
  ]
}
