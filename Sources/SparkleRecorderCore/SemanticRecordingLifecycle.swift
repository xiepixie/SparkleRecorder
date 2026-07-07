import Foundation

public struct SemanticRecordingLifecycleConfiguration: Equatable, Sendable {
    public var captureConfiguration: SemanticRecordingCaptureConfiguration
    public var preflightPolicy: SemanticRecordingPreflightPolicy

    public init(
        captureConfiguration: SemanticRecordingCaptureConfiguration = SemanticRecordingCaptureConfiguration(),
        preflightPolicy: SemanticRecordingPreflightPolicy? = nil
    ) {
        var resolvedPolicy = preflightPolicy ?? SemanticRecordingPreflightPolicy(
            capturePolicy: captureConfiguration.capturePolicy
        )
        resolvedPolicy.capturePolicy = captureConfiguration.capturePolicy
        self.captureConfiguration = captureConfiguration
        self.preflightPolicy = resolvedPolicy
    }
}

public struct SemanticRecordingCaptureSessionFactory: @unchecked Sendable {
    public var make: @Sendable (SemanticRecordingCaptureConfiguration) -> SemanticRecordingCaptureSession

    public init(
        make: @escaping @Sendable (SemanticRecordingCaptureConfiguration) -> SemanticRecordingCaptureSession
    ) {
        self.make = make
    }
}

public enum SemanticRecordingLifecycleStartResult: Equatable, Sendable {
    case started(SemanticRecordingPreflightResult)
    case blocked(SemanticRecordingPreflightResult)

    public var preflight: SemanticRecordingPreflightResult {
        switch self {
        case .started(let result), .blocked(let result):
            return result
        }
    }
}

public enum SemanticRecordingLifecycleError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case alreadyFinished
    case startBlocked(SemanticRecordingPreflightResult)
}

public actor SemanticRecordingLifecycle {
    private let configuration: SemanticRecordingLifecycleConfiguration
    private let preflightClient: SemanticRecordingPreflightClient
    private let sessionFactory: SemanticRecordingCaptureSessionFactory

    private var session: SemanticRecordingCaptureSession?
    private var blockedPreflight: SemanticRecordingPreflightResult?
    private var didFinish = false

    public init(
        configuration: SemanticRecordingLifecycleConfiguration = SemanticRecordingLifecycleConfiguration(),
        preflightClient: SemanticRecordingPreflightClient,
        sessionFactory: SemanticRecordingCaptureSessionFactory
    ) {
        self.configuration = configuration
        self.preflightClient = preflightClient
        self.sessionFactory = sessionFactory
    }

    public func evaluatePreflight() async -> SemanticRecordingPreflightResult {
        await preflightClient.evaluate(policy: configuration.preflightPolicy)
    }

    public func start(recordingTime: TimeInterval = 0) async throws -> SemanticRecordingLifecycleStartResult {
        guard !didFinish else {
            throw SemanticRecordingLifecycleError.alreadyFinished
        }
        guard session == nil else {
            throw SemanticRecordingLifecycleError.alreadyStarted
        }

        let preflight = await evaluatePreflight()
        guard preflight.isReadyToStart else {
            blockedPreflight = preflight
            return .blocked(preflight)
        }

        let newSession = sessionFactory.make(configuration.captureConfiguration)
        try await newSession.start(recordingTime: recordingTime)
        session = newSession
        blockedPreflight = nil
        return .started(preflight)
    }

    public func record(_ event: RecordedEvent, index: Int) async throws {
        let activeSession = try requireSession()
        try await activeSession.record(event, index: index)
    }

    public func addSuppression(_ suppression: RecordingSuppressionRecord) async throws {
        let activeSession = try requireSession()
        await activeSession.addSuppression(suppression)
    }

    public func finish(recordingTime: TimeInterval) async throws -> SemanticRecordingBundle {
        let activeSession = try requireSession()
        let bundle = try await activeSession.finish(recordingTime: recordingTime)
        didFinish = true
        session = nil
        return bundle
    }

    public func cancel(recordingTime: TimeInterval) async {
        guard !didFinish else {
            return
        }

        if let session {
            await session.cancel(recordingTime: recordingTime)
        }
        didFinish = true
        session = nil
        blockedPreflight = nil
    }

    private func requireSession() throws -> SemanticRecordingCaptureSession {
        guard !didFinish else {
            throw SemanticRecordingLifecycleError.alreadyFinished
        }
        if let session {
            return session
        }
        if let blockedPreflight {
            throw SemanticRecordingLifecycleError.startBlocked(blockedPreflight)
        }
        throw SemanticRecordingLifecycleError.notStarted
    }
}
