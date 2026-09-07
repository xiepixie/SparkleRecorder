import Foundation

public extension MacroReconstructionAuthoringContract {
    static let eventKindDescriptors: [MacroCandidateEventKindDescriptor] = RecordedEvent.Kind.allCases.map { kind in
        switch kind {
        case .leftMouseDown:
            .init(code: kind.rawValue, name: "leftMouseDown", family: "pointer", executableMeaning: "Press the left mouse button.", authoringNotes: ["Balance with leftMouseUp unless disabled."])
        case .leftMouseUp:
            .init(code: kind.rawValue, name: "leftMouseUp", family: "pointer", executableMeaning: "Release the left mouse button.", authoringNotes: ["Requires an unmatched leftMouseDown."])
        case .rightMouseDown:
            .init(code: kind.rawValue, name: "rightMouseDown", family: "pointer", executableMeaning: "Press the right mouse button.", authoringNotes: ["Balance with rightMouseUp unless disabled."])
        case .rightMouseUp:
            .init(code: kind.rawValue, name: "rightMouseUp", family: "pointer", executableMeaning: "Release the right mouse button.", authoringNotes: ["Requires an unmatched rightMouseDown."])
        case .mouseMoved:
            .init(code: kind.rawValue, name: "mouseMoved", family: "pointer", executableMeaning: "Move the pointer without pressing a button.")
        case .leftMouseDragged:
            .init(code: kind.rawValue, name: "leftMouseDragged", family: "pointer", executableMeaning: "Move while the left button is held.", authoringNotes: ["Requires active leftMouseDown.", "Text-locator gestures cannot drag."])
        case .rightMouseDragged:
            .init(code: kind.rawValue, name: "rightMouseDragged", family: "pointer", executableMeaning: "Move while the right button is held.", authoringNotes: ["Requires active rightMouseDown.", "Text-locator gestures cannot drag."])
        case .keyDown:
            .init(code: kind.rawValue, name: "keyDown", family: "keyboard", executableMeaning: "Press a physical keyboard key.", authoringNotes: ["Balance with keyUp unless disabled.", "Use keyCode + flags for shortcut identity; unicodeString is readable text evidence."])
        case .keyUp:
            .init(code: kind.rawValue, name: "keyUp", family: "keyboard", executableMeaning: "Release a physical keyboard key.", authoringNotes: ["Requires a matching unmatched keyDown."])
        case .flagsChanged:
            .init(code: kind.rawValue, name: "flagsChanged", family: "keyboard", executableMeaning: "Change transient modifier-key state.", authoringNotes: ["Command/Option/Shift/Control must be released before the candidate ends."])
        case .scrollWheel:
            .init(code: kind.rawValue, name: "scrollWheel", family: "scroll", executableMeaning: "Apply one mouse-wheel or trackpad scroll event.", authoringNotes: ["Preserve scrollPayload when available; do not recreate dense mechanical evidence as playback events."])
        case .otherMouseDown:
            .init(code: kind.rawValue, name: "otherMouseDown", family: "pointer", executableMeaning: "Press a non-left/non-right mouse button.", authoringNotes: ["mouseButton identifies the button and must later be released."])
        case .otherMouseUp:
            .init(code: kind.rawValue, name: "otherMouseUp", family: "pointer", executableMeaning: "Release a non-left/non-right mouse button.", authoringNotes: ["Requires matching otherMouseDown."])
        case .otherMouseDragged:
            .init(code: kind.rawValue, name: "otherMouseDragged", family: "pointer", executableMeaning: "Drag while another mouse button is held.", authoringNotes: ["Requires matching active otherMouseDown."])
        case .waitForText:
            .init(code: kind.rawValue, name: "waitForText", family: "textObservation", executableMeaning: "Wait until a Text Anchor is present or absent.", authoringNotes: ["verifyMustExist=false means wait for disappearance.", "Requires textAnchor, finite textTimeout, and explicit surfaceId."])
        case .verifyText:
            .init(code: kind.rawValue, name: "verifyText", family: "textObservation", executableMeaning: "Observe a Text Anchor once and verify expected presence or absence.", authoringNotes: ["Requires textAnchor, finite textTimeout, and explicit surfaceId.", "This is a single observation, not a stability wait."])
        }
    }

    static let actionKindDescriptors: [MacroReconstructionActionKindDescriptor] = ActionGroupKind.allCases.map { kind in
        let exported = kind != .sequence
        return switch kind {
        case .click:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "balanced mouse down/up events", meaning: "One pointer click gesture.")
        case .doubleClick:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "two or three nearby balanced click gestures", meaning: "A multi-click at one point.")
        case .longPress:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "mouse down/up with preserved hold duration", meaning: "A pointer button is intentionally held without a drag.")
        case .drag:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "mouse down + dragged events + mouse up", meaning: "A path-sensitive pointer drag.")
        case .scroll:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "scrollWheel events", meaning: "One compact scroll burst or segment.")
        case .keyPress:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "keyDown + keyUp", meaning: "One ordinary physical key press.")
        case .keyHold:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "keyDown + keyUp with preserved duration", meaning: "A deliberately held key.")
        case .keyRepeat:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "repeated keyDown events followed by keyUp", meaning: "OS key-repeat or repeated key-down evidence.")
        case .shortcut:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "modifier flagsChanged events plus balanced keyDown/keyUp", meaning: "A keyboard chord such as Command-C or Option-2. Use keyCode + flags, not produced unicodeString, for identity.")
        case .modifierHold:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "flagsChanged modifier press followed by release", meaning: "A modifier is intentionally held without another key.")
        case .textInput:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "balanced keyDown/keyUp pairs carrying readable unicodeString", meaning: "Adjacent ordinary text entry; shortcuts are not text input.")
        case .wait:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "time gap between executable events; no event kind exists", meaning: "A derived fixed delay in the source timeline.")
        case .mouseMove:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "mouseMoved events", meaning: "Pointer motion without a button gesture.")
        case .waitForText:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "kind=100 waitForText with verifyMustExist=true or omitted", meaning: "Wait for matching text to appear.")
        case .waitForTextGone:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "kind=100 waitForText with verifyMustExist=false", meaning: "Wait for matching text to disappear.")
        case .verifyText:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "kind=101 verifyText with verifyMustExist=true/false", meaning: "Single text-presence observation.")
        case .repeatedClick:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "four or more nearby balanced click gestures", meaning: "A rapid repeated click at one point.")
        case .multiPointClick:
            .init(name: kind.rawValue, exportedByReconstructor: exported, candidateRepresentation: "rapid balanced click gestures at different points", meaning: "A rapid sequence of coordinate clicks across multiple points.")
        case .sequence:
            .init(name: kind.rawValue, exportedByReconstructor: false, candidateRepresentation: "behaviorGroupID/behaviorGroupName annotations across executable events", meaning: "Editor-authored behavior grouping. Source reconstruction strips behavior annotations, so sequence is not emitted as source evidence.")
        }
    }
}
