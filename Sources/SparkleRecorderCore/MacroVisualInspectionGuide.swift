import CoreGraphics
import Foundation

/// Deterministic parameters for navigating exported recording evidence.
/// These values define search/crop hints only; they never establish a locator.
public struct MacroVisualInspectionPolicy: Codable, Equatable, Sendable {
    public var videoPreRoll: Double
    public var videoPostRoll: Double
    public var frameCandidateWindowBefore: Double
    public var frameCandidateWindowAfter: Double
    public var maximumFrameCandidates: Int
    public var maximumObservationSummaries: Int
    public var maximumObservationTextCharacters: Int
    public var maximumObservationLabels: Int
    public var primaryWidthFraction: Double
    public var primaryHeightFraction: Double
    public var contextWidthFraction: Double
    public var contextHeightFraction: Double
    public var minimumPrimaryWidthPixels: Double
    public var minimumPrimaryHeightPixels: Double

    public init(
        videoPreRoll: Double = 0.25,
        videoPostRoll: Double = 0.75,
        frameCandidateWindowBefore: Double = 0.50,
        frameCandidateWindowAfter: Double = 0.90,
        maximumFrameCandidates: Int = 4,
        maximumObservationSummaries: Int = 24,
        maximumObservationTextCharacters: Int = 512,
        maximumObservationLabels: Int = 16,
        primaryWidthFraction: Double = 0.24,
        primaryHeightFraction: Double = 0.20,
        contextWidthFraction: Double = 0.56,
        contextHeightFraction: Double = 0.44,
        minimumPrimaryWidthPixels: Double = 320,
        minimumPrimaryHeightPixels: Double = 180
    ) {
        self.videoPreRoll = max(0, videoPreRoll)
        self.videoPostRoll = max(0, videoPostRoll)
        self.frameCandidateWindowBefore = max(0, frameCandidateWindowBefore)
        self.frameCandidateWindowAfter = max(0, frameCandidateWindowAfter)
        self.maximumFrameCandidates = max(1, maximumFrameCandidates)
        self.maximumObservationSummaries = max(1, maximumObservationSummaries)
        self.maximumObservationTextCharacters = max(1, maximumObservationTextCharacters)
        self.maximumObservationLabels = max(1, maximumObservationLabels)
        self.primaryWidthFraction = Self.clampedFraction(primaryWidthFraction)
        self.primaryHeightFraction = Self.clampedFraction(primaryHeightFraction)
        self.contextWidthFraction = max(self.primaryWidthFraction, Self.clampedFraction(contextWidthFraction))
        self.contextHeightFraction = max(self.primaryHeightFraction, Self.clampedFraction(contextHeightFraction))
        self.minimumPrimaryWidthPixels = max(1, minimumPrimaryWidthPixels)
        self.minimumPrimaryHeightPixels = max(1, minimumPrimaryHeightPixels)
    }

    public static let `default` = MacroVisualInspectionPolicy()

    private static func clampedFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(1, max(0.01, value))
    }
}

public struct MacroVisualInspectionRegion: Codable, Equatable, Sendable {
    public var framePixels: RecordingBounds
    public var normalizedFrame: RecordingBounds

    public init(framePixels: RecordingBounds, normalizedFrame: RecordingBounds) {
        self.framePixels = framePixels
        self.normalizedFrame = normalizedFrame
    }
}

public enum MacroVisualInspectionFocusRole: String, Codable, Equatable, Sendable {
    case start
    case end
    case target
}

public struct MacroVisualInspectionFocus: Codable, Equatable, Sendable {
    public var role: MacroVisualInspectionFocusRole
    public var recordingTime: Double
    public var framePoint: PointValue
    public var frameSize: RecordingImageSize
    public var primaryRegion: MacroVisualInspectionRegion
    public var contextRegion: MacroVisualInspectionRegion

    public init(
        role: MacroVisualInspectionFocusRole,
        recordingTime: Double,
        framePoint: PointValue,
        frameSize: RecordingImageSize,
        primaryRegion: MacroVisualInspectionRegion,
        contextRegion: MacroVisualInspectionRegion
    ) {
        self.role = role
        self.recordingTime = max(0, recordingTime)
        self.framePoint = framePoint
        self.frameSize = frameSize
        self.primaryRegion = primaryRegion
        self.contextRegion = contextRegion
    }
}

public struct MacroVisualInspectionFrameCandidate: Codable, Equatable, Sendable {
    public var frameID: UUID
    public var artifactPath: String
    public var recordingTime: Double
    public var videoTime: Double?
    public var imageSize: RecordingImageSize?
    public var source: RecordingFrameCaptureSource
    public var surfaceID: String?

    public init(
        frameID: UUID,
        artifactPath: String,
        recordingTime: Double,
        videoTime: Double?,
        imageSize: RecordingImageSize?,
        source: RecordingFrameCaptureSource,
        surfaceID: String?
    ) {
        self.frameID = frameID
        self.artifactPath = artifactPath
        self.recordingTime = max(0, recordingTime)
        self.videoTime = videoTime.map { max(0, $0) }
        self.imageSize = imageSize
        self.source = source
        self.surfaceID = surfaceID
    }
}

public struct MacroVisualInspectionVideoCandidate: Codable, Equatable, Sendable {
    public var segmentID: String
    public var artifactPath: String
    public var actionVideoRange: RecordingTimeRange
    public var inspectionVideoRange: RecordingTimeRange

    public init(
        segmentID: String,
        artifactPath: String,
        actionVideoRange: RecordingTimeRange,
        inspectionVideoRange: RecordingTimeRange
    ) {
        self.segmentID = segmentID
        self.artifactPath = artifactPath
        self.actionVideoRange = actionVideoRange
        self.inspectionVideoRange = inspectionVideoRange
    }
}

public struct MacroVisualInspectionObservationSummary: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: RecordingVisualObservationKind
    public var recordingTime: Double
    public var frameID: UUID?
    public var bounds: RecordingBounds?
    public var text: String?
    public var confidence: Double?
    public var score: Double?
    public var labels: [String]

    public init(
        observation: RecordingVisualObservation,
        maximumTextCharacters: Int,
        maximumLabels: Int
    ) {
        id = observation.id
        kind = observation.kind
        recordingTime = observation.recordingTime
        frameID = observation.frameID
        bounds = observation.bounds
        if let value = observation.text {
            let limit = max(1, maximumTextCharacters)
            text = value.count > limit ? String(value.prefix(limit)) + "..." : value
        } else {
            text = nil
        }
        confidence = observation.confidence
        score = observation.score
        labels = Array(observation.labels.prefix(max(1, maximumLabels)))
    }
}

public struct MacroVisualInspectionAction: Codable, Equatable, Sendable {
    public var actionID: String
    public var kind: String
    public var sourceEventIndices: [Int]
    public var surfaceID: String?
    public var sessionRange: RecordingTimeRange?
    public var video: MacroVisualInspectionVideoCandidate?
    public var focuses: [MacroVisualInspectionFocus]
    public var frames: [MacroVisualInspectionFrameCandidate]
    public var observationCount: Int
    public var observations: [MacroVisualInspectionObservationSummary]
    public var issues: [String]

    public init(
        actionID: String,
        kind: String,
        sourceEventIndices: [Int],
        surfaceID: String?,
        sessionRange: RecordingTimeRange?,
        video: MacroVisualInspectionVideoCandidate?,
        focuses: [MacroVisualInspectionFocus],
        frames: [MacroVisualInspectionFrameCandidate],
        observationCount: Int = 0,
        observations: [MacroVisualInspectionObservationSummary] = [],
        issues: [String]
    ) {
        self.actionID = actionID
        self.kind = kind
        self.sourceEventIndices = sourceEventIndices
        self.surfaceID = surfaceID
        self.sessionRange = sessionRange
        self.video = video
        self.focuses = focuses
        self.frames = frames
        self.observationCount = observationCount
        self.observations = observations
        self.issues = issues
    }
}

/// AI-facing navigation map for visual evidence. The guide tells a capable AI
/// where to seek/crop/zoom; it deliberately does not perform screenshots or OCR.
public struct MacroVisualInspectionGuide: Codable, Equatable, Sendable {
    public var version: String
    public var coordinateConvention: String
    public var policy: MacroVisualInspectionPolicy
    public var actions: [MacroVisualInspectionAction]

    public init(
        version: String = "macro-visual-inspection/v1",
        coordinateConvention: String = "Top-left origin. framePixels are tied to the measured aligned video frameSize at that action time. normalizedFrame is clamped to [0,1] and is the portable crop hint for an exported key image whose imageSize differs from the focus frameSize.",
        policy: MacroVisualInspectionPolicy,
        actions: [MacroVisualInspectionAction]
    ) {
        self.version = version
        self.coordinateConvention = coordinateConvention
        self.policy = policy
        self.actions = actions
    }
}

public enum MacroVisualInspectionGuideProjector {
    public static func project(
        events: [RecordedEvent],
        sourceRevision: String,
        provenance: RecordingReconstructionProvenance,
        videoSegments: [RecordingVideoSegment],
        frames: [RecordingFrameReference],
        observations: [RecordingVisualObservation] = [],
        exportedVideoPaths: [UUID: String],
        exportedFramePaths: [UUID: String],
        policy: MacroVisualInspectionPolicy = .default
    ) throws -> MacroVisualInspectionGuide {
        var sourceTimes: [Int: Double] = [:]
        var duplicateSourceIndex = false
        for item in provenance.sourceEvents {
            if sourceTimes[item.sourceEventIndex] != nil {
                duplicateSourceIndex = true
                break
            }
            sourceTimes[item.sourceEventIndex] = item.sessionTime
        }
        if duplicateSourceIndex {
            sourceTimes.removeAll()
        }
        let videoClock: RecordingVideoClockMapping
        if let validatedClock = try? RecordingVideoClockMapping(segments: provenance.clockSegments) {
            videoClock = validatedClock
        } else {
            videoClock = try RecordingVideoClockMapping(segments: [])
        }
        let geometry: RecordingGeometryHistory
        if let validatedGeometry = try? RecordingGeometryHistory(snapshots: provenance.geometrySnapshots) {
            geometry = validatedGeometry
        } else {
            geometry = try RecordingGeometryHistory(snapshots: [])
        }
        let projected = try MacroReconstructionProjector.project(
            events: events,
            sourceRevision: sourceRevision,
            sessionTimesByEventIndex: sourceTimes,
            videoClock: videoClock,
            geometry: geometry
        )
        var segmentByID: [String: RecordingVideoSegment] = [:]
        for segment in videoSegments where segmentByID[segment.id.uuidString] == nil {
            segmentByID[segment.id.uuidString] = segment
        }

        let actionRows = projected.map { row in
            let action = row.action
            let video = videoCandidate(
                row: row,
                segmentByID: segmentByID,
                exportedVideoPaths: exportedVideoPaths,
                policy: policy
            )
            let actionFrames = frameCandidates(
                row: row,
                frames: frames,
                exportedFramePaths: exportedFramePaths,
                policy: policy
            )
            let observationSelection = observationCandidates(
                row: row,
                observations: observations,
                frames: frames,
                policy: policy
            )
            return MacroVisualInspectionAction(
                actionID: action.id,
                kind: action.kind.rawValue,
                sourceEventIndices: action.sourceEventIndices,
                surfaceID: action.surfaceID,
                sessionRange: row.sessionRange,
                video: video,
                focuses: focusRows(row: row, geometry: geometry, policy: policy),
                frames: actionFrames,
                observationCount: observationSelection.totalCount,
                observations: observationSelection.summaries,
                issues: row.issues.map(\.rawValue)
            )
        }
        return MacroVisualInspectionGuide(policy: policy, actions: actionRows)
    }

    private static func videoCandidate(
        row: MacroReconstructionProjectedAction,
        segmentByID: [String: RecordingVideoSegment],
        exportedVideoPaths: [UUID: String],
        policy: MacroVisualInspectionPolicy
    ) -> MacroVisualInspectionVideoCandidate? {
        guard let segmentID = row.videoSegmentID,
              let segment = segmentByID[segmentID],
              let artifactPath = exportedVideoPaths[segment.id],
              let actionRange = row.videoRange else { return nil }
        let start = max(0, actionRange.startTime - policy.videoPreRoll)
        let requestedEnd = actionRange.endTime + policy.videoPostRoll
        let end = min(segment.duration, max(start, requestedEnd))
        return MacroVisualInspectionVideoCandidate(
            segmentID: segmentID,
            artifactPath: artifactPath,
            actionVideoRange: actionRange,
            inspectionVideoRange: RecordingTimeRange(startTime: start, duration: end - start)
        )
    }

    private static func frameCandidates(
        row: MacroReconstructionProjectedAction,
        frames: [RecordingFrameReference],
        exportedFramePaths: [UUID: String],
        policy: MacroVisualInspectionPolicy
    ) -> [MacroVisualInspectionFrameCandidate] {
        guard let session = row.sessionRange else { return [] }
        let lower = max(0, session.startTime - policy.frameCandidateWindowBefore)
        let upper = session.endTime + policy.frameCandidateWindowAfter
        let midpoint = (session.startTime + session.endTime) / 2
        let surfaceID = row.action.surfaceID
        return frames
            .filter { frame in
                exportedFramePaths[frame.id] != nil
                    && frame.recordingTime >= lower
                    && frame.recordingTime <= upper
                    && (surfaceID == nil || frame.surfaceID == nil || frame.surfaceID == surfaceID)
            }
            .sorted { left, right in
                let leftDistance = abs(left.recordingTime - midpoint)
                let rightDistance = abs(right.recordingTime - midpoint)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return left.recordingTime < right.recordingTime
            }
            .prefix(policy.maximumFrameCandidates)
            .compactMap { frame in
                guard let path = exportedFramePaths[frame.id] else { return nil }
                return MacroVisualInspectionFrameCandidate(
                    frameID: frame.id,
                    artifactPath: path,
                    recordingTime: frame.recordingTime,
                    videoTime: frame.videoTime,
                    imageSize: frame.imageSize,
                    source: frame.source,
                    surfaceID: frame.surfaceID
                )
            }
    }

    private static func observationCandidates(
        row: MacroReconstructionProjectedAction,
        observations: [RecordingVisualObservation],
        frames: [RecordingFrameReference],
        policy: MacroVisualInspectionPolicy
    ) -> (totalCount: Int, summaries: [MacroVisualInspectionObservationSummary]) {
        guard let session = row.sessionRange else { return (0, []) }
        let lower = max(0, session.startTime - policy.frameCandidateWindowBefore)
        let upper = session.endTime + policy.frameCandidateWindowAfter
        let midpoint = (session.startTime + session.endTime) / 2
        let surfaceID = row.action.surfaceID
        let frameSurfaceByID = Dictionary(uniqueKeysWithValues: frames.compactMap { frame in
            frame.surfaceID.map { (frame.id, $0) }
        })
        let matching = observations
            .filter { observation in
                guard observation.recordingTime >= lower, observation.recordingTime <= upper else { return false }
                guard let surfaceID, let frameID = observation.frameID,
                      let observationSurface = frameSurfaceByID[frameID] else { return true }
                return observationSurface == surfaceID
            }
            .sorted { left, right in
                let leftDistance = abs(left.recordingTime - midpoint)
                let rightDistance = abs(right.recordingTime - midpoint)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return left.recordingTime < right.recordingTime
            }
        return (
            matching.count,
            matching.prefix(policy.maximumObservationSummaries).map {
                MacroVisualInspectionObservationSummary(
                    observation: $0,
                    maximumTextCharacters: policy.maximumObservationTextCharacters,
                    maximumLabels: policy.maximumObservationLabels
                )
            }
        )
    }

    private static func focusRows(
        row: MacroReconstructionProjectedAction,
        geometry: RecordingGeometryHistory,
        policy: MacroVisualInspectionPolicy
    ) -> [MacroVisualInspectionFocus] {
        guard let session = row.sessionRange, let surfaceID = row.action.surfaceID else { return [] }
        var inputs: [(MacroVisualInspectionFocusRole, Double, PointValue?)] = []
        if let start = row.startFramePoint {
            inputs.append((row.endFramePoint == start ? .target : .start, session.startTime, start))
        }
        if let end = row.endFramePoint,
           row.startFramePoint == nil || row.startFramePoint != end {
            inputs.append((.end, session.endTime, end))
        }
        return inputs.compactMap { role, time, point in
            guard let point,
                  let snapshot = geometry.snapshot(surfaceID: surfaceID, recordingTime: time) else { return nil }
            let primary = region(
                around: point,
                frameSize: snapshot.frameSize,
                widthFraction: policy.primaryWidthFraction,
                heightFraction: policy.primaryHeightFraction,
                minimumWidth: policy.minimumPrimaryWidthPixels,
                minimumHeight: policy.minimumPrimaryHeightPixels
            )
            let context = region(
                around: point,
                frameSize: snapshot.frameSize,
                widthFraction: policy.contextWidthFraction,
                heightFraction: policy.contextHeightFraction,
                minimumWidth: max(policy.minimumPrimaryWidthPixels, primary.framePixels.rect.width),
                minimumHeight: max(policy.minimumPrimaryHeightPixels, primary.framePixels.rect.height)
            )
            return MacroVisualInspectionFocus(
                role: role,
                recordingTime: time,
                framePoint: point,
                frameSize: snapshot.frameSize,
                primaryRegion: primary,
                contextRegion: context
            )
        }
    }

    private static func region(
        around point: PointValue,
        frameSize: RecordingImageSize,
        widthFraction: Double,
        heightFraction: Double,
        minimumWidth: Double,
        minimumHeight: Double
    ) -> MacroVisualInspectionRegion {
        let frameWidth = max(1, Double(frameSize.width))
        let frameHeight = max(1, Double(frameSize.height))
        let width = min(frameWidth, max(minimumWidth, frameWidth * widthFraction))
        let height = min(frameHeight, max(minimumHeight, frameHeight * heightFraction))
        let maxX = max(0, frameWidth - width)
        let maxY = max(0, frameHeight - height)
        let x = min(maxX, max(0, Double(point.x) - width / 2))
        let y = min(maxY, max(0, Double(point.y) - height / 2))
        let pixelRect = RecordingRect(x: x, y: y, width: width, height: height)
        let normalizedRect = RecordingRect(
            x: x / frameWidth,
            y: y / frameHeight,
            width: width / frameWidth,
            height: height / frameHeight
        )
        return MacroVisualInspectionRegion(
            framePixels: RecordingBounds(rect: pixelRect, coordinateSpace: .framePixels),
            normalizedFrame: RecordingBounds(rect: normalizedRect, coordinateSpace: .normalizedFrame)
        )
    }
}
