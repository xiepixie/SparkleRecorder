import Foundation

public enum MacroReconstructionProjectionIssue: String, Equatable, Sendable {
    case missingSourceTime
    case videoUnavailable
    case crossesVideoSegments
    case geometryUnavailable
}

/// Evidence projection only; this does not execute actions or establish live alignment quality.
public struct MacroReconstructionProjectedAction: Equatable, Sendable {
    public let action: MacroReconstructedAction
    public let sessionRange: RecordingTimeRange?
    public let videoSegmentID: String?
    public let videoRange: RecordingTimeRange?
    public let startFramePoint: PointValue?
    public let endFramePoint: PointValue?
    public let issues: [MacroReconstructionProjectionIssue]
}

public enum MacroReconstructionProjector {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidEventIndex(Int)
        case invalidSessionTime(Int)
        case nonMonotonicSessionTime(Int)
    }

    /// Times are supplied by the recording adapter; absent indices remain unavailable.
    /// Source playback timestamps are never substituted for session timestamps.
    public static func project(
        events: [RecordedEvent],
        sourceRevision: String,
        sessionTimesByEventIndex: [Int: Double],
        videoClock: RecordingVideoClockMapping,
        geometry: RecordingGeometryHistory
    ) throws -> [MacroReconstructionProjectedAction] {
        let actions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: sourceRevision)
        var previousSessionTime: Double?
        for index in sessionTimesByEventIndex.keys.sorted() {
            guard events.indices.contains(index) else { throw ValidationError.invalidEventIndex(index) }
            guard let time = sessionTimesByEventIndex[index], time.isFinite, time >= 0 else {
                throw ValidationError.invalidSessionTime(index)
            }
            if let previousSessionTime, time < previousSessionTime {
                throw ValidationError.nonMonotonicSessionTime(index)
            }
            previousSessionTime = time
        }

        // Derived waits have no event indices; their two boundaries refer to adjacent source events.
        var firstIndexByTime: [Double: Int] = [:]
        var lastIndexByTime: [Double: Int] = [:]
        for (index, event) in events.enumerated() {
            if firstIndexByTime[event.time] == nil { firstIndexByTime[event.time] = index }
            lastIndexByTime[event.time] = index
        }

        return actions.map { action in
            let startIndex = action.sourceEventIndices.min() ?? lastIndexByTime[action.startTime]
            let endIndex = action.sourceEventIndices.max() ?? firstIndexByTime[action.endTime]
            guard action.sourceEventIndices.allSatisfy({ sessionTimesByEventIndex[$0] != nil }),
                  let startIndex, let endIndex,
                  let start = sessionTimesByEventIndex[startIndex],
                  let end = sessionTimesByEventIndex[endIndex], end >= start else {
                return MacroReconstructionProjectedAction(
                    action: action, sessionRange: nil, videoSegmentID: nil, videoRange: nil,
                    startFramePoint: nil, endFramePoint: nil, issues: [.missingSourceTime]
                )
            }

            var issues: [MacroReconstructionProjectionIssue] = []
            var segmentID: String?
            var videoRange: RecordingTimeRange?
            if let firstSegment = videoClock.segmentID(forRecordingTime: start),
               let lastSegment = videoClock.segmentID(forRecordingTime: end) {
                if firstSegment != lastSegment {
                    issues.append(.crossesVideoSegments)
                } else if let videoStart = videoClock.videoTime(forRecordingTime: start, segmentID: firstSegment),
                          let videoEnd = videoClock.videoTime(forRecordingTime: end, segmentID: firstSegment) {
                    segmentID = firstSegment
                    videoRange = RecordingTimeRange(startTime: videoStart, duration: videoEnd - videoStart)
                } else {
                    issues.append(.videoUnavailable)
                }
            } else {
                issues.append(.videoUnavailable)
            }

            func framePoint(_ point: PointValue?, time: Double) -> PointValue? {
                guard let point, let surfaceID = action.surfaceID else { return nil }
                return geometry.framePoint(forGlobalPoint: point, surfaceID: surfaceID, recordingTime: time)
            }
            let startPoint = framePoint(action.startPoint, time: start)
            let endPoint = framePoint(action.endPoint, time: end)
            if (action.startPoint != nil && startPoint == nil) || (action.endPoint != nil && endPoint == nil) {
                issues.append(.geometryUnavailable)
            }
            return MacroReconstructionProjectedAction(
                action: action,
                sessionRange: RecordingTimeRange(startTime: start, duration: end - start),
                videoSegmentID: segmentID, videoRange: videoRange,
                startFramePoint: startPoint, endFramePoint: endPoint, issues: issues
            )
        }
    }
}
