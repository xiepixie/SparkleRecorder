import Foundation
import SparkleRecorderCore

enum LiveSemanticRecordingSessionError: Error, Equatable {
    case alreadyStarted
    case notStarted
    case alreadyFinished
}

enum LiveSemanticRecordingStartResult: Equatable {
    case started(preflight: SemanticRecordingPreflightResult, bundleDirectory: URL)
    case blocked(preflight: SemanticRecordingPreflightResult)

    var preflight: SemanticRecordingPreflightResult {
        switch self {
        case .started(let preflight, _), .blocked(let preflight):
            return preflight
        }
    }
}

struct LiveSemanticRecordingFinishResult: Equatable {
    var bundle: SemanticRecordingBundle
    var bundleDirectory: URL
}

struct LiveSemanticRecordingSessionDependencies: @unchecked Sendable {
    var store: RecordingBundleStore
    var preflightClient: SemanticRecordingPreflightClient
    var makeCaptureClient: @Sendable (URL) -> SemanticRecordingCaptureClient

    init(
        store: RecordingBundleStore = RecordingBundleStore(),
        preflightClient: SemanticRecordingPreflightClient = .live,
        makeCaptureClient: @escaping @Sendable (URL) -> SemanticRecordingCaptureClient = { directory in
            LiveSemanticCaptureClient.live(bundleDirectory: directory)
        }
    ) {
        self.store = store
        self.preflightClient = preflightClient
        self.makeCaptureClient = makeCaptureClient
    }
}

actor LiveSemanticRecordingSession {
    private let configuration: SemanticRecordingCaptureConfiguration
    private let dependencies: LiveSemanticRecordingSessionDependencies

    private var lifecycle: SemanticRecordingLifecycle?
    private var bundleDirectory: URL?
    private var didFinish = false

    init(
        configuration: SemanticRecordingCaptureConfiguration = SemanticRecordingCaptureConfiguration(),
        dependencies: LiveSemanticRecordingSessionDependencies = LiveSemanticRecordingSessionDependencies()
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
    }

    func start(recordingTime: TimeInterval = 0) async throws -> LiveSemanticRecordingStartResult {
        guard !didFinish else {
            throw LiveSemanticRecordingSessionError.alreadyFinished
        }
        guard lifecycle == nil else {
            throw LiveSemanticRecordingSessionError.alreadyStarted
        }

        let lifecycleConfiguration = SemanticRecordingLifecycleConfiguration(
            captureConfiguration: configuration
        )
        let preflight = await dependencies.preflightClient.evaluate(
            policy: lifecycleConfiguration.preflightPolicy
        )
        guard preflight.isReadyToStart else {
            return .blocked(preflight: preflight)
        }

        let directory = try await dependencies.store.createBundleDirectory(
            recordingID: configuration.recordingID
        )
        let captureClient = dependencies.makeCaptureClient(directory)
        let sessionFactory = SemanticRecordingCaptureSessionFactory { configuration in
            SemanticRecordingCaptureSession(
                configuration: configuration,
                client: captureClient
            )
        }
        let lifecycle = SemanticRecordingLifecycle(
            configuration: lifecycleConfiguration,
            preflightClient: .fixed(preflight.snapshot),
            sessionFactory: sessionFactory
        )

        switch try await lifecycle.start(recordingTime: recordingTime) {
        case .started(let startedPreflight):
            self.lifecycle = lifecycle
            bundleDirectory = directory
            return .started(preflight: startedPreflight, bundleDirectory: directory)
        case .blocked(let blockedPreflight):
            return .blocked(preflight: blockedPreflight)
        }
    }

    func record(_ event: RecordedEvent, index: Int) async throws {
        try await requireLifecycle().record(event, index: index)
    }

    func addSuppression(_ suppression: RecordingSuppressionRecord) async throws {
        try await requireLifecycle().addSuppression(suppression)
    }

    func finish(recordingTime: TimeInterval) async throws -> LiveSemanticRecordingFinishResult {
        let activeLifecycle = try requireLifecycle()
        guard let directory = bundleDirectory else {
            throw LiveSemanticRecordingSessionError.notStarted
        }
        let bundle = try await activeLifecycle.finish(recordingTime: recordingTime)
        try await dependencies.store.write(bundle, to: directory)
        lifecycle = nil
        bundleDirectory = nil
        didFinish = true
        return LiveSemanticRecordingFinishResult(
            bundle: bundle,
            bundleDirectory: directory
        )
    }

    private func requireLifecycle() throws -> SemanticRecordingLifecycle {
        guard !didFinish else {
            throw LiveSemanticRecordingSessionError.alreadyFinished
        }
        guard let lifecycle else {
            throw LiveSemanticRecordingSessionError.notStarted
        }
        return lifecycle
    }
}
