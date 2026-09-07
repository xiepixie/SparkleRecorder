import AppKit
import AVFoundation
import CoreMedia
import CoreImage
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
    case movieWritingFailed(String)
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
        var writer: RecordingMovieWriter
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

        let writer = try RecordingMovieWriter(url: outputURL)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        do { try await stream.startCapture() }
        catch { await writer.cancel(); throw error }

        sessions[request.segmentID] = MovieSession(
            stream: stream, writer: writer, frameSize: resolved.frameSize
        )

        return SemanticRecordingMovieHandle(
            segmentID: request.segmentID,
            artifactRef: request.artifactRef,
            target: request.target,
            startTime: request.recordingTime,
            fileType: "mov",
            codec: "AVAssetWriter-H264",
            frameSize: resolved.frameSize
        )
    }

    func finish(_ request: SemanticRecordingMovieFinishRequest) async throws -> SemanticRecordingMovieFinishResult {
        guard let session = sessions.removeValue(forKey: request.handle.segmentID) else {
            throw ScreenCaptureKitSemanticCaptureError.missingMovieSession
        }

        do { try await session.stream.stopCapture() }
        catch { await session.writer.cancel(); throw error }
        let written = try await session.writer.finish()
        try Self.validateRecordedMovie(
            at: bundleDirectory.appendingRecordingArtifactRef(request.handle.artifactRef)
        )

        let asset = AVURLAsset(url: bundleDirectory.appendingRecordingArtifactRef(request.handle.artifactRef))
        let track = try await asset.loadTracks(withMediaType: .video).first
        let range = try await track?.load(.timeRange)
        let startPTS = range?.start.seconds
        let duration = range?.duration.seconds
        // The .mov contract maps each successfully appended T to T - sessionStart.
        // Release those anchors only after the completed file confirms that origin.
        let fileOriginVerified = startPTS == 0 && duration.map { $0.isFinite && $0 > 0 } == true
        let samples = written.samples.map { sample in
            var sample = sample
            if !fileOriginVerified { sample.writtenVideoTime = nil }
            return sample
        }
        let evidence = RecordingMovieTimingEvidence(segmentID: request.handle.segmentID,
            samples: samples, omittedSampleCount: written.omitted,
            fileTrackStartPTS: startPTS, fileTrackDuration: duration,
            alignmentUnavailableReason: fileOriginVerified ? "" : "Written file origin could not be verified.")
        return SemanticRecordingMovieFinishResult(
            duration: duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? max(0, request.recordingTime - request.handle.startTime),
            frameSize: session.frameSize,
            fileType: request.handle.fileType,
            codec: request.handle.codec,
            timingEvidence: evidence
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
        let requestedHost = CaptureHostClock.now()
        let sampleBuffer = try await SCScreenshotManager.captureSampleBuffer(
            contentFilter: resolved.filter,
            configuration: resolved.configuration
        )
        let receivedHost = CaptureHostClock.now()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let image = CIContext().createCGImage(CIImage(cvPixelBuffer: pixelBuffer), from: CIImage(cvPixelBuffer: pixelBuffer).extent) else {
            throw ScreenCaptureKitSemanticCaptureError.pngEncodingFailed
        }
        let evidence = RecordingTimingOutput.sample(sampleBuffer)
        let actualHost = evidence?.displayedHostTime
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
            displayScale: evidence?.displayScale ?? resolved.displayScale,
            capturedHostTime: actualHost ?? (requestedHost + receivedHost) / 2,
            timestampUncertainty: actualHost == nil ? (receivedHost - requestedHost) / 2 : 0
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
        let capturedAt = Date.now
        _ = presentationTime // Stream PTS is not a Unix timestamp.

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
            guard window.owningApplication != nil else { return false }
            return RecordingCaptureTargetMatcher.matches(
                RecordingCaptureWindowIdentity(
                    windowID: window.windowID,
                    bundleIdentifier: window.owningApplication?.bundleIdentifier,
                    title: window.title
                ),
                target: target
            )
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


private enum CaptureHostClock {
    static func seconds(_ ticks: UInt64) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(ticks) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
    static func now() -> Double { seconds(mach_absolute_time()) }
}

/// All writer state is confined to the SCStream callback queue. Only samples
/// accepted by the writer become file-clock evidence; backpressure drops frames.
private final class RecordingMovieWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Written: Sendable {
        var samples: [RecordingCaptureSampleTiming]
        var omitted: Int
    }
    let queue = DispatchQueue(label: "app.sparklerecorder.movie-writer")
    private let writer: AVAssetWriter
    private var input: AVAssetWriterInput?
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?
    private var failure: Error?
    private var finishing = false
    private var samples: [RecordingCaptureSampleTiming] = []
    private var omitted = 0

    init(url: URL) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !finishing, failure == nil,
              var sample = RecordingTimingOutput.sample(buffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        if let lastPTS, CMTimeCompare(pts, lastPTS) <= 0 { return }
        if input == nil {
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: sample.imageSize.width,
                AVVideoHeightKey: sample.imageSize.height
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                failure = ScreenCaptureKitSemanticCaptureError.movieWritingFailed("Cannot add video input.")
                return
            }
            writer.add(input)
            guard writer.startWriting() else {
                failure = writer.error ?? ScreenCaptureKitSemanticCaptureError.movieWritingFailed("Cannot start writing.")
                return
            }
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
            self.input = input
        }
        guard let input, let firstPTS else { return }
        guard input.isReadyForMoreMediaData else { omitted += 1; return }
        guard input.append(buffer) else {
            failure = writer.error ?? ScreenCaptureKitSemanticCaptureError.movieWritingFailed("Cannot append video sample.")
            return
        }
        lastPTS = pts
        sample.writtenVideoTime = CMTimeSubtract(pts, firstPTS).seconds
        // Keep the first bounded prefix. Never claim alignment beyond retained anchors.
        if samples.count < 18_000 { samples.append(sample) } else { omitted += 1 }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                finishing = true
                writer.cancelWriting()
                continuation.resume()
            }
        }
    }

    func finish() async throws -> Written {
        try await withCheckedThrowingContinuation { continuation in
            // stopCapture has returned; this barrier drains all earlier append calls.
            queue.async { [self] in
                finishing = true
                if let failure {
                    writer.cancelWriting()
                    continuation.resume(throwing: failure)
                    return
                }
                guard let input, lastPTS != nil else {
                    writer.cancelWriting()
                    continuation.resume(throwing: ScreenCaptureKitSemanticCaptureError.movieWritingFailed("No video samples were recorded."))
                    return
                }
                input.markAsFinished()
                writer.finishWriting { [self] in
                    queue.async { [self] in
                        guard writer.status == .completed else {
                            continuation.resume(throwing: writer.error ?? ScreenCaptureKitSemanticCaptureError.movieWritingFailed("Cannot finalize video."))
                            return
                        }
                        continuation.resume(returning: Written(samples: samples, omitted: omitted))
                    }
                }
            }
        }
    }
}

private enum RecordingTimingOutput {
    static func sample(_ buffer: CMSampleBuffer) -> RecordingCaptureSampleTiming? {
        let attachments = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first ?? [:]
        if let status = attachments[.status] as? Int, status != SCFrameStatus.complete.rawValue { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard pts.isFinite, let image = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let duration = CMSampleBufferGetDuration(buffer).seconds
        let host = (attachments[.displayTime] as? NSNumber).map { CaptureHostClock.seconds($0.uint64Value) }
        return .init(presentationTime: pts, displayedHostTime: host, receivedHostTime: CaptureHostClock.now(),
                     duration: duration.isFinite && duration > 0 ? duration : nil,
                     screenRect: (attachments[.screenRect] as? CGRect).map(RectValue.init),
                     contentRect: (attachments[.contentRect] as? CGRect).map(RectValue.init),
                     imageSize: .init(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image)),
                     displayScale: (attachments[.scaleFactor] as? NSNumber)?.doubleValue)
    }
}
