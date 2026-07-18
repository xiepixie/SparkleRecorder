import Foundation
import Testing
@testable import SparkleRecorder

@Suite("App Language Preference Tests")
struct AppLanguagePreferenceTests {
    @Test("Language override persists its app preference and Apple language")
    func overridePersistence() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguagePreference.simplifiedChinese.apply(defaults: defaults)

        #expect(AppLanguagePreference.current(defaults: defaults) == .simplifiedChinese)
        #expect(defaults.stringArray(forKey: AppLanguagePreference.appleLanguagesKey) == ["zh-Hans"])
    }

    @Test("System default removes the app language override")
    func systemDefaultRemovesOverride() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppLanguagePreference.english.apply(defaults: defaults)

        AppLanguagePreference.system.apply(defaults: defaults)

        #expect(AppLanguagePreference.current(defaults: defaults) == .system)
        let persistentDomain = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(persistentDomain[AppLanguagePreference.appleLanguagesKey] == nil)
        #expect(persistentDomain[AppLanguagePreference.storageKey] == nil)
    }

    @Test("Explicit language recognizes regional variants")
    func languageMatching() {
        #expect(AppLanguagePreference.english.matches(languageIdentifiers: ["en-CN"]))
        #expect(AppLanguagePreference.simplifiedChinese.matches(languageIdentifiers: ["zh-Hans-CN"]))
        #expect(!AppLanguagePreference.simplifiedChinese.matches(languageIdentifiers: ["en-CN"]))
        #expect(AppLanguagePreference.system.matches(languageIdentifiers: []))
    }

    @Test("Bootstrap repairs a missing Apple language override")
    func bootstrapRepairsOverride() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            AppLanguagePreference.simplifiedChinese.rawValue,
            forKey: AppLanguagePreference.storageKey
        )

        AppLanguagePreference.bootstrap(defaults: defaults)

        #expect(defaults.stringArray(forKey: AppLanguagePreference.appleLanguagesKey) == ["zh-Hans"])
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
