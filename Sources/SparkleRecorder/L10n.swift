import SwiftUI

public enum L10nTable {
    public static let common = "Common"
    public static let automation = "Automation"
    public static let recording = "Recording"
    public static let settings = "Settings"
    public static let editorUX = "EditorUX"
}

public extension Text {
    static func common(_ key: LocalizedStringKey) -> Text {
        Text(key, tableName: L10nTable.common)
    }

    static func automation(_ key: LocalizedStringKey) -> Text {
        Text(key, tableName: L10nTable.automation)
    }

    static func recording(_ key: LocalizedStringKey) -> Text {
        Text(key, tableName: L10nTable.recording)
    }

    static func settings(_ key: LocalizedStringKey) -> Text {
        Text(key, tableName: L10nTable.settings)
    }

    static func editorUX(_ key: LocalizedStringKey) -> Text {
        Text(key, tableName: L10nTable.editorUX)
    }
}

/// A button that safely injects a tableName for the label, preventing implicit fallback to Localizable.xcstrings.
public struct LocalizedSystemButton: View {
    public let key: LocalizedStringKey
    public let tableName: String
    public let systemImage: String
    public let role: ButtonRole?
    public let action: () -> Void

    public init(
        _ key: LocalizedStringKey,
        tableName: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.key = key
        self.tableName = tableName
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role) {
            action()
        } label: {
            Label {
                Text(key, tableName: tableName)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

/// A label that safely injects a tableName.
public struct LocalizedSystemLabel: View {
    public let key: LocalizedStringKey
    public let tableName: String
    public let systemImage: String

    public init(_ key: LocalizedStringKey, tableName: String, systemImage: String) {
        self.key = key
        self.tableName = tableName
        self.systemImage = systemImage
    }

    public var body: some View {
        Label {
            Text(key, tableName: tableName)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
