import Testing
@testable import SparkleRecorderCore

@Suite("Keyboard action presentation")
struct KeyboardActionPresentationTests {
    @Test("Shortcut presentation uses physical key code and modifiers instead of layout-produced Unicode")
    func shortcutPresentationUsesKeyCodeAndModifiers() {
        var commandC = RecordedEvent.make(.keyDown, time: 0, keyCode: 8, flags: ModFlag.command)
        commandC.unicodeString = "c"
        var optionTwo = RecordedEvent.make(.keyDown, time: 0.1, keyCode: 19, flags: ModFlag.option)
        optionTwo.unicodeString = "™"

        #expect(KeyboardActionPresentation.label(kind: .shortcut, eventIndices: [0], events: [commandC]) == "⌘C")
        #expect(KeyboardActionPresentation.label(kind: .shortcut, eventIndices: [1], events: [commandC, optionTwo]) == "⌥2")
    }

    @Test("Special and modifier-only keys keep semantic macOS names")
    func specialAndModifierOnlyKeysKeepSemanticNames() {
        var returnKey = RecordedEvent.make(.keyDown, time: 0, keyCode: 36)
        returnKey.unicodeString = "\r"
        let commandOnly = RecordedEvent.make(.flagsChanged, time: 0.1, keyCode: 55, flags: ModFlag.command)
        let rightOptionOnly = RecordedEvent.make(.flagsChanged, time: 0.2, keyCode: 61, flags: ModFlag.option)

        #expect(KeyboardActionPresentation.label(kind: .keyPress, eventIndices: [0], events: [returnKey]) == "Return")
        #expect(KeyboardActionPresentation.label(kind: .modifierHold, eventIndices: [1], events: [returnKey, commandOnly]) == "⌘")
        #expect(KeyboardActionPresentation.label(kind: .modifierHold, eventIndices: [2], events: [returnKey, commandOnly, rightOptionOnly]) == "⌥")
    }

    @Test("Real recorded Option and Command sequences survive reconstruction with semantic labels")
    func realRecordedModifierSequencesSurviveReconstruction() throws {
        let optionFlags: UInt64 = 524_576
        let idleFlags: UInt64 = 256
        let optionDown = RecordedEvent.make(.flagsChanged, time: 0, keyCode: 58, flags: optionFlags)
        var optionTwoDown = RecordedEvent.make(.keyDown, time: 0.2, keyCode: 19, flags: optionFlags)
        optionTwoDown.unicodeString = "™"
        var optionTwoUp = RecordedEvent.make(.keyUp, time: 0.38, keyCode: 19, flags: optionFlags)
        optionTwoUp.unicodeString = "™"
        let optionUp = RecordedEvent.make(.flagsChanged, time: 0.42, keyCode: 58, flags: idleFlags)
        let optionEvents = [optionDown, optionTwoDown, optionTwoUp, optionUp]

        let optionAction = try #require(
            MacroActionReconstructor.reconstruct(events: optionEvents, sourceRevision: "option-source")
                .first(where: { $0.kind == .shortcut })
        )
        #expect(KeyboardActionPresentation.label(
            kind: optionAction.kind,
            eventIndices: optionAction.sourceEventIndices,
            events: optionEvents
        ) == "⌥2")

        let commandFlags: UInt64 = 1_048_840
        let commandDown = RecordedEvent.make(.flagsChanged, time: 0, keyCode: 55, flags: commandFlags)
        var commandWDown = RecordedEvent.make(.keyDown, time: 0.2, keyCode: 13, flags: commandFlags)
        commandWDown.unicodeString = "w"
        var commandWUp = RecordedEvent.make(.keyUp, time: 0.4, keyCode: 13, flags: commandFlags)
        commandWUp.unicodeString = "w"
        let commandUp = RecordedEvent.make(.flagsChanged, time: 0.42, keyCode: 55, flags: idleFlags)
        let commandEvents = [commandDown, commandWDown, commandWUp, commandUp]

        let commandAction = try #require(
            MacroActionReconstructor.reconstruct(events: commandEvents, sourceRevision: "command-source")
                .first(where: { $0.kind == .shortcut })
        )
        #expect(KeyboardActionPresentation.label(
            kind: commandAction.kind,
            eventIndices: commandAction.sourceEventIndices,
            events: commandEvents
        ) == "⌘W")
    }

    @Test("Plain text input remains readable text rather than key chords")
    func plainTextInputRemainsReadable() {
        var a = RecordedEvent.make(.keyDown, time: 0, keyCode: 0)
        a.unicodeString = "a"
        var b = RecordedEvent.make(.keyDown, time: 0.1, keyCode: 11)
        b.unicodeString = "b"

        #expect(KeyboardActionPresentation.label(kind: .textInput, eventIndices: [0, 1], events: [a, b]) == "ab")
    }
}
