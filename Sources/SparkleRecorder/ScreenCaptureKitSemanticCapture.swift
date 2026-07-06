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

        return SemanticRecordingMovieFinishResult(
            duration: max(0, request.recordingTime - request.handle.startTime),
            frameSize: session.frameSize,
            fileType: request.handle.fileType,
            codec: request.handle.codec
        )
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
