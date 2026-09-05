import Foundation

/// Built once when evidence changes. Queries retain the earliest chronological
/// matching action, including overlapping 100 ms highlights for point actions.
public struct MacroReconstructionVideoIndex: Sendable {
    private struct Segment: Sendable {
        var rows: [MacroReconstructionProjectedAction]
        var maximumEnds: [Double]
    }
    private let segments: [String: Segment]
    private let rowsByID: [String: MacroReconstructionProjectedAction]
    public var isEmpty: Bool { segments.isEmpty }

    public init(rows: [MacroReconstructionProjectedAction]) {
        var byID: [String: MacroReconstructionProjectedAction] = [:]
        var grouped: [String: [MacroReconstructionProjectedAction]] = [:]
        for row in rows {
            byID[row.action.id] = row
            guard let id = row.videoSegmentID, let range = row.videoRange,
                  range.startTime.isFinite, range.duration.isFinite, range.duration >= 0,
                  (range.startTime + max(0.1, range.duration)).isFinite else { continue }
            grouped[id, default: []].append(row)
        }
        rowsByID = byID
        segments = grouped.mapValues { values in
            let sorted = values.enumerated().sorted {
                let lhs = $0.element.videoRange!.startTime, rhs = $1.element.videoRange!.startTime
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }.map(\.element)
            var end = -Double.infinity
            let ends = sorted.map { row in
                let range = row.videoRange!
                end = max(end, range.startTime + max(0.1, range.duration))
                return end
            }
            return Segment(rows: sorted, maximumEnds: ends)
        }
    }

    public func row(actionID: String) -> MacroReconstructionProjectedAction? { rowsByID[actionID] }

    public func activeRow(at time: Double, segmentID: String) -> MacroReconstructionProjectedAction? {
        guard time.isFinite, time >= 0, let segment = segments[segmentID] else { return nil }
        var lower = 0, upper = segment.rows.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if segment.maximumEnds[middle] < time { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower < segment.rows.count,
              segment.rows[lower].videoRange!.startTime <= time else { return nil }
        return segment.rows[lower]
    }
}
