@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import QuartzCore
import SparkleRecorderCore

enum SemanticRecordingVideoRedactionRendererError: Error, Equatable, Sendable {
    case sourceVideoIsDirectory(String)
    case sourceVideoMissing(String)
    case noVideoTrack(String)
    case invalidVideoDuration(String)
    case compositionTrackUnavailable(String)
    case exportSessionUnavailable(String)
    case exportFailed(String, String)
    case redactedVideoMissing(String)
    case noRenderableRanges(UUID)
}

struct SemanticRecordingVideoRedactionRenderer {
    func render(
        segment: RecordingVideoSegment,
        redactions: [SemanticRecordingVideoRangeRedaction],
        redactedVideoRef: RecordingArtifactRef,
        sourceURL: URL,
        outputURL: URL
    ) async throws -> SemanticRecordingRenderedVideoRedaction {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw SemanticRecordingVideoRedactionRendererError
                .sourceVideoMissing(segment.artifactRef.path)
        }
        guard !isDirectory.boolValue else {
            throw SemanticRecordingVideoRedactionRendererError
                .sourceVideoIsDirectory(segment.artifactRef.path)
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SemanticRecordingVideoRedactionRendererError
                .noVideoTrack(segment.artifactRef.path)
        }

        let sourceDuration = try await asset.load(.duration)
        guard sourceDuration.seconds.isFinite,
              sourceDuration.seconds > 0 else {
            throw SemanticRecordingVideoRedactionRendererError
                .invalidVideoDuration(segment.artifactRef.path)
        }

        let frameDuration = try await frameDuration(for: sourceTrack)
        let renderableRanges = localRenderableRanges(
            redactions,
            segment: segment,
            sourceDuration: sourceDuration.seconds,
            minimumDuration: frameDuration.seconds
        )
        guard !renderableRanges.isEmpty else {
            throw SemanticRecordingVideoRedactionRendererError
                .noRenderableRanges(segment.id)
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SemanticRecordingVideoRedactionRendererError
                .compositionTrackUnavailable(segment.artifactRef.path)
        }

        let fullRange = CMTimeRange(start: .zero, duration: sourceDuration)
        try compositionTrack.insertTimeRange(fullRange, of: sourceTrack, at: .zero)
        compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
        try await copyAudioTracks(from: asset, to: composition, timeRange: fullRange)

        let renderSize = try await renderSize(for: sourceTrack)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = fullRange
        instruction.layerInstructions = [
            AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        ]
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = animationTool(
            renderSize: renderSize,
            duration: sourceDuration.seconds,
            redactionRanges: renderableRanges
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SemanticRecordingVideoRedactionRendererError
                .exportSessionUnavailable(segment.artifactRef.path)
        }
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = false

        do {
            try await exportSession.export(to: outputURL, as: .mov)
        } catch {
            throw SemanticRecordingVideoRedactionRendererError.exportFailed(
                redactedVideoRef.path,
                error.localizedDescription
            )
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw SemanticRecordingVideoRedactionRendererError
                .redactedVideoMissing(redactedVideoRef.path)
        }

        return SemanticRecordingRenderedVideoRedaction(
            videoSegmentID: segment.id,
            sourceVideoRef: segment.artifactRef,
            redactedVideoRef: redactedVideoRef,
            renderedRangeCount: renderableRanges.count,
            sourceSuppressionIDs: uniqueSuppressionIDs(redactions),
            reasons: uniqueReasons(redactions)
        )
    }

    private func copyAudioTracks(
        from asset: AVURLAsset,
        to composition: AVMutableComposition,
        timeRange: CMTimeRange
    ) async throws {
        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }
    }

    private func renderSize(for track: AVAssetTrack) async throws -> CGSize {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(preferredTransform)
        let width = abs(transformed.width)
        let height = abs(transformed.height)
        guard width >= 1, height >= 1 else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: width, height: height)
    }

    private func frameDuration(for track: AVAssetTrack) async throws -> CMTime {
        let nominalRate = try await track.load(.nominalFrameRate)
        guard nominalRate.isFinite, nominalRate >= 1 else {
            return CMTime(value: 1, timescale: 30)
        }
        return CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, Int32(nominalRate.rounded())))
        )
    }

    private func localRenderableRanges(
        _ redactions: [SemanticRecordingVideoRangeRedaction],
        segment: RecordingVideoSegment,
        sourceDuration: TimeInterval,
        minimumDuration: TimeInterval
    ) -> [RecordingTimeRange] {
        let minimum = max(1.0 / 30.0, minimumDuration)
        return redactions.compactMap { redaction in
            let localStart = max(0, redaction.timeRange.startTime - segment.startTime)
            let localEnd = min(sourceDuration, redaction.timeRange.endTime - segment.startTime)
            let adjustedEnd = min(sourceDuration, max(localEnd, localStart + minimum))
            guard adjustedEnd > localStart else {
                return nil
            }
            return RecordingTimeRange(
                startTime: localStart,
                duration: adjustedEnd - localStart
            )
        }
        .sorted {
            if $0.startTime == $1.startTime {
                return $0.duration < $1.duration
            }
            return $0.startTime < $1.startTime
        }
    }

    private func animationTool(
        renderSize: CGSize,
        duration: TimeInterval,
        redactionRanges: [RecordingTimeRange]
    ) -> AVVideoCompositionCoreAnimationTool {
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.isGeometryFlipped = true
        parentLayer.addSublayer(videoLayer)

        for range in redactionRanges {
            let overlay = CALayer()
            overlay.frame = videoLayer.frame
            overlay.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            overlay.opacity = 0
            overlay.add(
                opacityAnimation(for: range, duration: duration),
                forKey: "semanticRecordingRedactionOpacity"
            )
            parentLayer.addSublayer(overlay)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func opacityAnimation(
        for range: RecordingTimeRange,
        duration: TimeInterval
    ) -> CAKeyframeAnimation {
        let safeDuration = max(duration, 0.001)
        let start = max(0, min(1, range.startTime / safeDuration))
        let end = max(start, min(1, range.endTime / safeDuration))
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 0, 1, 1, 0, 0]
        animation.keyTimes = [
            NSNumber(value: 0),
            NSNumber(value: start),
            NSNumber(value: start),
            NSNumber(value: end),
            NSNumber(value: end),
            NSNumber(value: 1)
        ]
        animation.duration = safeDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        return animation
    }

    private func uniqueSuppressionIDs(
        _ redactions: [SemanticRecordingVideoRangeRedaction]
    ) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in redactions.flatMap(\.sourceSuppressionIDs) where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private func uniqueReasons(
        _ redactions: [SemanticRecordingVideoRangeRedaction]
    ) -> [RecordingSuppressionReason] {
        var result: [RecordingSuppressionReason] = []
        for reason in redactions.flatMap(\.reasons) where !result.contains(reason) {
            result.append(reason)
        }
        return result
    }
}
