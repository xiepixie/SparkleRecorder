import CoreGraphics
import Foundation
import SparkleRecorderCore

private final class RawEventContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<RawInputEvent>.Continuation?
    var keepAlive: Any?

    func set(_ continuation: AsyncStream<RawInputEvent>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func yield(_ event: RawInputEvent) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(event)
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

private final class RecordingDiagnosticContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<RecordingEngineDiagnostic>.Continuation?

    func set(_ continuation: AsyncStream<RecordingEngineDiagnostic>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func yield(_ diagnostic: RecordingEngineDiagnostic) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(diagnostic)
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

extension RecordingEngineClient {
    public static func live(mask: CGEventMask) -> Self {
        let thread = EventTapThread(mask: mask)
        let continuationBox = RawEventContinuationBox()
        let diagnosticBox = RecordingDiagnosticContinuationBox()

        final class Adapter: EventTapThreadDelegate, @unchecked Sendable {
            let continuationBox: RawEventContinuationBox
            let diagnosticBox: RecordingDiagnosticContinuationBox

            init(
                continuationBox: RawEventContinuationBox,
                diagnosticBox: RecordingDiagnosticContinuationBox
            ) {
                self.continuationBox = continuationBox
                self.diagnosticBox = diagnosticBox
            }

            func eventTapThread(_ thread: EventTapThread, didReceive type: CGEventType, event: CGEvent) {
                guard let input = RawInputEvent(eventType: type, event: event) else { return }
                continuationBox.yield(input)
            }

            func eventTapThreadDidDisableByUserInput(_ thread: EventTapThread) {
                diagnosticBox.yield(RecordingEngineDiagnostic(
                    kind: .eventTapDisabledByUserInput,
                    detail: "The event tap was disabled by user input, which commonly indicates Secure Input."
                ))
            }
        }

        let adapter = Adapter(
            continuationBox: continuationBox,
            diagnosticBox: diagnosticBox
        )
        continuationBox.keepAlive = adapter
        thread.delegate = adapter

        return Self(
            events: {
                AsyncStream(bufferingPolicy: .bufferingNewest(2_048)) { continuation in
                    continuationBox.set(continuation)
                    continuation.onTermination = { @Sendable _ in
                        thread.stop()
                        continuationBox.finish()
                        diagnosticBox.finish()
                    }
                }
            },
            diagnostics: {
                AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
                    diagnosticBox.set(continuation)
                    continuation.onTermination = { @Sendable _ in
                        diagnosticBox.finish()
                    }
                }
            },
            start: {
                let started = thread.startAndWait()
                if !started {
                    thread.stop()
                    continuationBox.finish()
                    diagnosticBox.finish()
                }
                return started
            },
            stop: {
                thread.stop()
                continuationBox.finish()
                diagnosticBox.finish()
            }
        )
    }
}

private extension RawInputEvent {
    init?(eventType: CGEventType, event: CGEvent) {
        guard let kind = RecordedEvent.Kind(rawValue: Int(eventType.rawValue)) else { return nil }

        let unicodeString: String?
        if kind.isKey {
            var characters = [UniChar](repeating: 0, count: 4)
            var actualLength = 0
            event.keyboardGetUnicodeString(
                maxStringLength: characters.count,
                actualStringLength: &actualLength,
                unicodeString: &characters
            )
            unicodeString = actualLength > 0
                ? String(utf16CodeUnits: characters, count: actualLength)
                : nil
        } else {
            unicodeString = nil
        }

        self.init(
            kind: kind,
            timestamp: UInt64(event.timestamp),
            location: event.location,
            keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            mouseButton: event.getIntegerValueField(.mouseEventButtonNumber),
            clickCount: event.getIntegerValueField(.mouseEventClickState),
            unicodeString: unicodeString,
            scrollSample: kind == .scrollWheel ? RecordingScrollSample(event: event) : nil
        )
    }
}

private extension RecordingScrollSample {
    init(event: CGEvent) {
        self.init(
            pointDeltaX: Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
            pointDeltaY: Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
            lineDeltaX: Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            lineDeltaY: Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            phase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
            momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
            fixedRawX: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2),
            fixedRawY: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        )
    }
}
