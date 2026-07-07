import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import SparkleRecorderCore

enum ScreenCaptureKitSemanticCaptureError: Error {
    case noMatchingWindow
    case noMatchingDisplay
    case missingMovieSession
    case missingLiveFrameSession
    case missingMovieFile(String)
    case emptyMovieFile(String)
    case pngEncodingFailed
}

enum LiveSemanticCaptureClient {
    static func live(bundleDirectory: URL) -> SemanticRecordingCaptureClient {
        let movieRecorder = ScreenCaptureKitMovieRecorder(bundleDirectory: bundleDirectory)
        let frameSource = ScreenCaptureKitFrameSource(bundleDirectory: bundleDirectory)
        let frameIndexer = SemanticRecordingFrameObservationIndexer(
            visionIndexer: VisionRecordingIndexer(bundleDirectory: bundleDirectory)
        )

        return SemanticRecordingCaptureClient(
            startMovie: { request in
                try await movieRecorder.start(request)
            },
            finishMovie: { request in
                try await movieRecorder.finish(request)
            },
            captureFrame: { request in
                try await frameSource.capture(request)
            },
            indexFrame: { request in
                try await frameIndexer.indexFrame(request)
            }
        )
    }
}

actor ScreenCaptureKitMovieRecorder {
    private struct MovieSession {
        var stream: SCStream
        var output: SCRecordingOutput
        var delegate: RecordingOutputDelegate
        var frameSize: RecordingImageSize?
    }

    private let bundleDirectory: URL
    private var sessions: [UUID: MovieSession] = [:]

    init(bundleDirectory: URL) {
        self.bundleDirectory = bundleDirectory
    }

    func start(_ request: SemanticRecordingMovieStartRequest) async throws -> SemanticRecordingMovieHandle {
        let outputURL = bundleDirectory.appendingRecordingArtifactRef(request.artifactRef)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let resolved = try await ScreenCaptureKitTargetResolver.resolve(target: request.target)
        let stream = SCStream(filter: resolved.filter, configuration: resolved.configuration, delegate: nil)

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mov
        outputConfiguration.videoCodecType = .h264

        let delegate = RecordingOutputDelegate()
        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: delegate)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        sessions[request.segmentID] = MovieSession(
            stream: stream,
            output: output,
            delegate: delegate,
            frameSize: resolved.frameSize
        )

        return SemanticRecordingMovieHandle(
            segmentID: request.segmentID,
            artifactRef: request.artifactRef,
            target: request.target,
            startTime: request.recordingTime,
            fileType: "mov",
            codec: "SCRecordingOutput",
            frameSize: resolved.frameSize
        )
    }

    func finish(_ request: SemanticRecordingMovieFinishRequest) async throws -> SemanticRecordingMovieFinishResult {
        guard let session = sessions.removeValue(forKey: request.handle.segmentID) else {
            throw ScreenCaptureKitSemanticCaptureError.missingMovieSession
        }

        try session.stream.removeRecordingOutput(session.output)
        try await session.stream.stopCapture()
        if let failure = session.delegate.takeFailure() {
            throw failure
        }
        try Self.validateRecordedMovie(
            at: bundleDirectory.appendingRecordingArtifactRef(request.handle.artifactRef)
        )

        return SemanticRecordingMovieFinishResult(
            duration: max(0, request.recordingTime - request.handle.startTime),
            frameSize: session.frameSize,
            fileType: request.handle.fileType,
            codec: request.handle.codec
        )
    }

    private static func validateRecordedMovie(at url: URL) throws {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ScreenCaptureKitSemanticCaptureError.missingMovieFile(url.path)
        }
        let byteCount = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .intValue
        guard (byteCount ?? 0) > 0 else {
            throw ScreenCaptureKitSemanticCaptureError.emptyMovieFile(url.path)
        }
    }
}

actor ScreenCaptureKitFrameSource {
    private let bundleDirectory: URL

    init(bundleDirectory: URL) {
        self.bundleDirectory = bundleDirectory
    }

    func capture(_ request: SemanticRecordingFrameCaptureRequest) async throws -> SemanticRecordingCapturedFrame {
        let resolved = try await ScreenCaptureKitTargetResolver.resolve(target: request.target)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: resolved.filter,
            configuration: resolved.configuration
        )
        let outputURL = bundleDirectory.appendingRecordingArtifactRef(request.artifactRef)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScreenCaptureKitSemanticCaptureError.pngEncodingFailed
        }
        try pngData.write(to: outputURL, options: .atomic)

        return SemanticRecordingCapturedFrame(
            imageSize: RecordingImageSize(width: image.width, height: image.height),
            displayScale: resolved.displayScale
        )
    }
}

actor ScreenCaptureKitLiveFrameSource {
    private struct LiveFrameSession {
        var stream: SCStream
        var output: LiveFrameOutput
    }

    private var sessions: [UUID: LiveFrameSession] = [:]

    func start(
        target: RecordingCaptureTarget,
        sessionID: UUID = UUID()
    ) async throws -> (UUID, AsyncStream<AutomationVisualFrameSample>) {
        let resolved = try await ScreenCaptureKitTargetResolver.resolve(target: target)
        let stream = SCStream(filter: resolved.filter, configuration: resolved.configuration, delegate: nil)
        let output = LiveFrameOutput(
            provider: "ScreenCaptureKit.SCStreamOutput",
            fallbackImageSize: resolved.frameSize,
            fallbackDisplayScale: resolved.displayScale
        )
        let streamSamples = AsyncStream<AutomationVisualFrameSample> { continuation in
            output.setContinuation(continuation)
        }
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()

        sessions[sessionID] = LiveFrameSession(
            stream: stream,
            output: output
        )
        return (sessionID, streamSamples)
    }

    func startFrames(
        target: RecordingCaptureTarget,
        sessionID: UUID = UUID()
    ) async throws -> (UUID, AsyncStream<ScreenCaptureKitLiveFrame>) {
        let resolved = try await ScreenCaptureKitTargetResolver.resolve(target: target)
        let stream = SCStream(filter: resolved.filter, configuration: resolved.configuration, delegate: nil)
        let output = LiveFrameOutput(
            provider: "ScreenCaptureKit.SCStreamOutput",
            fallbackImageSize: resolved.frameSize,
            fallbackDisplayScale: resolved.displayScale
        )
        let frames = AsyncStream<ScreenCaptureKitLiveFrame> { continuation in
            output.setFrameContinuation(continuation)
        }
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()

        sessions[sessionID] = LiveFrameSession(
            stream: stream,
            output: output
        )
        return (sessionID, frames)
    }

    func stop(sessionID: UUID) async throws {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            throw ScreenCaptureKitSemanticCaptureError.missingLiveFrameSession
        }
        try session.stream.removeStreamOutput(session.output, type: .screen)
        try await session.stream.stopCapture()
        session.output.finishContinuations()
    }
}

final class ScreenCaptureKitLiveFrame: @unchecked Sendable {
    let sample: AutomationVisualFrameSample
    let sampleBuffer: CMSampleBuffer

    init(sample: AutomationVisualFrameSample, sampleBuffer: CMSampleBuffer) {
        self.sample = sample
        self.sampleBuffer = sampleBuffer
    }
}

private final class LiveFrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.sparklerecorder.semantic-live-frame")

    private let lock = NSLock()
    private let provider: String
    private let fallbackImageSize: RecordingImageSize
    private let fallbackDisplayScale: Double
    private var sampleContinuation: AsyncStream<AutomationVisualFrameSample>.Continuation?
    private var frameContinuation: AsyncStream<ScreenCaptureKitLiveFrame>.Continuation?

    init(
        provider: String,
        fallbackImageSize: RecordingImageSize,
        fallbackDisplayScale: Double
    ) {
        self.provider = provider
        self.fallbackImageSize = fallbackImageSize
        self.fallbackDisplayScale = fallbackDisplayScale
    }

    func setContinuation(_ continuation: AsyncStream<AutomationVisualFrameSample>.Continuation) {
        lock.lock()
        sampleContinuation = continuation
        lock.unlock()
    }

    func setFrameContinuation(_ continuation: AsyncStream<ScreenCaptureKitLiveFrame>.Continuation) {
        lock.lock()
        frameContinuation = continuation
        lock.unlock()
    }

    func finishContinuations() {
        lock.lock()
        let samples = sampleContinuation
        let frames = frameContinuation
        sampleContinuation = nil
        frameContinuation = nil
        lock.unlock()

        samples?.finish()
        frames?.finish()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              isCompleteFrame(sampleBuffer) else {
            return
        }

        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let width = imageBuffer.map(CVPixelBufferGetWidth) ?? fallbackImageSize.width
        let height = imageBuffer.map(CVPixelBufferGetHeight) ?? fallbackImageSize.height
        let attachments = screenCaptureKitAttachments(from: sampleBuffer)
        let displayScale = attachments[SCStreamFrameInfo.scaleFactor] as? Double
            ?? attachments[SCStreamFrameInfo.scaleFactor] as? CGFloat
            ?? fallbackDisplayScale
        let contentRect = (attachments[SCStreamFrameInfo.contentRect] as? CGRect).map(RectValue.init)
        let screenRect = (attachments[SCStreamFrameInfo.screenRect] as? CGRect).map(RectValue.init)
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let capturedAt = presentationTime.isFinite
            ? Date(timeIntervalSince1970: presentationTime)
            : Date.now

        let sample = AutomationVisualFrameSample(
            source: .screenCaptureKitStream,
            capturedAt: capturedAt,
            imageSize: RecordingImageSize(width: width, height: height),
            displayScale: Double(displayScale),
            displayBounds: screenRect,
            contentRect: contentRect,
            provider: provider
        )

        yield(sample: sample, sampleBuffer: sampleBuffer)
    }

    private func yield(sample: AutomationVisualFrameSample, sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let samples = sampleContinuation
        let frames = frameContinuation
        lock.unlock()

        samples?.yield(sample)
        frames?.yield(ScreenCaptureKitLiveFrame(sample: sample, sampleBuffer: sampleBuffer))
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        let attachments = screenCaptureKitAttachments(from: sampleBuffer)
        guard let status = attachments[SCStreamFrameInfo.status] as? Int else {
            return true
        }
        return status == SCFrameStatus.complete.rawValue
    }

    private func screenCaptureKitAttachments(from sampleBuffer: CMSampleBuffer) -> [SCStreamFrameInfo: Any] {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else {
            return [:]
        }
        return attachments
    }
}

private extension RectValue {
    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}

private final class RecordingOutputDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: Error?

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    func takeFailure() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        let result = failure
        failure = nil
        return result
    }
}

private struct ScreenCaptureKitResolvedTarget {
    var filter: SCContentFilter
    var configuration: SCStreamConfiguration
    var frameSize: RecordingImageSize
    var displayScale: Double
}

private enum ScreenCaptureKitTargetResolver {
    static func resolve(target: RecordingCaptureTarget) async throws -> ScreenCaptureKitResolvedTarget {
        let availableContent = try await SCShareableContent.current
        if target.kind == .window || target.windowID != nil || target.appBundleIdentifier != nil {
            if let window = matchingWindow(target: target, windows: availableContent.windows) {
                return await resolvedWindow(window)
            }
            if target.kind == .window {
                throw ScreenCaptureKitSemanticCaptureError.noMatchingWindow
            }
        }

        let displayID = target.displayID ?? CGMainDisplayID()
        guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureKitSemanticCaptureError.noMatchingDisplay
        }
        return resolvedDisplay(display)
    }

    private static func matchingWindow(target: RecordingCaptureTarget, windows: [SCWindow]) -> SCWindow? {
        windows.first { window in
            if let windowID = target.windowID, window.windowID != windowID {
                return false
            }
            if let bundleIdentifier = target.appBundleIdentifier,
               window.owningApplication?.bundleIdentifier != bundleIdentifier {
                return false
            }
            if let title = target.windowTitle, !title.isEmpty, window.title != title {
                return false
            }
            return window.owningApplication != nil
        }
    }

    private static func resolvedWindow(_ window: SCWindow) async -> ScreenCaptureKitResolvedTarget {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.scalesToFit = false

        return ScreenCaptureKitResolvedTarget(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            frameSize: RecordingImageSize(width: configuration.width, height: configuration.height),
            displayScale: scale
        )
    }

    private static func resolvedDisplay(_ display: SCDisplay) -> ScreenCaptureKitResolvedTarget {
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        return ScreenCaptureKitResolvedTarget(
            filter: SCContentFilter(display: display, excludingWindows: []),
            configuration: configuration,
            frameSize: RecordingImageSize(width: display.width, height: display.height),
            displayScale: 1
        )
    }
}
