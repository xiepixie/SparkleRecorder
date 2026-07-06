import Foundation

public enum RecordingEngineDiagnosticKind: String, Codable, Equatable, Sendable {
    case eventTapDisabledByUserInput
}

public struct RecordingEngineDiagnostic: Codable, Equatable, Sendable {
    public var kind: RecordingEngineDiagnosticKind
    public var detail: String
    public var createdAt: Date

    public init(
        kind: RecordingEngineDiagnosticKind,
        detail: String,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.detail = detail
        self.createdAt = createdAt
    }
}

public struct RecordingEngineClient: @unchecked Sendable {
    public var events: @Sendable () -> AsyncStream<RawInputEvent>
    public var diagnostics: @Sendable () -> AsyncStream<RecordingEngineDiagnostic>
    public var start: @Sendable () -> Bool
    public var stop: @Sendable () -> Void
    
    public init(
        events: @escaping @Sendable () -> AsyncStream<RawInputEvent>,
        diagnostics: @escaping @Sendable () -> AsyncStream<RecordingEngineDiagnostic> = {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        start: @escaping @Sendable () -> Bool,
        stop: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.diagnostics = diagnostics
        self.start = start
        self.stop = stop
    }
}
