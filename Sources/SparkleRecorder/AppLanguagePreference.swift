import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    static let storageKey = "SparkleRecorder.appLanguage"
    static let appleLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    var languageIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var title: String {
        switch self {
        case .system:
            return String(localized: "System Default", table: "Settings")
        case .english:
            return String(localized: "English", table: "Settings")
        case .simplifiedChinese:
            return String(localized: "Simplified Chinese", table: "Settings")
        }
    }

    static func current(defaults: UserDefaults = .standard) -> AppLanguagePreference {
        guard let rawValue = defaults.string(forKey: storageKey) else {
            return .system
        }
        return AppLanguagePreference(rawValue: rawValue) ?? .system
    }

    static func bootstrap(defaults: UserDefaults = .standard) {
        let preference = current(defaults: defaults)
        guard let languageIdentifier = preference.languageIdentifier else { return }
        if defaults.stringArray(forKey: appleLanguagesKey)?.first != languageIdentifier {
            defaults.set([languageIdentifier], forKey: appleLanguagesKey)
            defaults.synchronize()
        }
    }

    func matches(languageIdentifiers: [String]) -> Bool {
        guard let languageIdentifier else { return true }
        guard let activeIdentifier = languageIdentifiers.first else { return false }
        return activeIdentifier == languageIdentifier
            || activeIdentifier.hasPrefix(languageIdentifier + "-")
    }

    func apply(defaults: UserDefaults = .standard) {
        switch self {
        case .system:
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .english, .simplifiedChinese:
            guard let languageIdentifier else { return }
            defaults.set(rawValue, forKey: Self.storageKey)
            defaults.set([languageIdentifier], forKey: Self.appleLanguagesKey)
        }
        defaults.synchronize()
    }
}
