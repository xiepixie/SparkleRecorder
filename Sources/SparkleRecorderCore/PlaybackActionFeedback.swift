import Foundation

/// Ephemeral presentation data only. Never transports input text, locator text,
/// window titles, coordinates or the original RecordedEvent to a HUD.
public struct PlaybackActionFeedback: Equatable, Sendable {
    public let loopNumber: Int
    public let stepNumber: Int
    public let stepCount: Int
    public let kind: RecordedEvent.Kind
    public let keyCode: UInt16?
    public let modifierFlags: UInt64

    public init(event: RecordedEvent, loopNumber: Int, stepNumber: Int, stepCount: Int) {
        self.loopNumber = loopNumber
        self.stepNumber = stepNumber
        self.stepCount = stepCount
        kind = event.kind
        // Never reveal printable typing, including key-up events whose Unicode
        // payload is usually absent. Only shortcuts and control keys get labels.
        let isShortcut = event.flags & 0x1c0000 != 0
        let controlKeys: Set<UInt16> = [36, 48, 49, 51, 53, 117, 123, 124, 125, 126]
        keyCode = event.kind.isKey && (isShortcut || controlKeys.contains(event.keyCode)) ? event.keyCode : nil
        modifierFlags = event.kind.isKey ? event.flags & 0x1e0000 : 0
    }
}
