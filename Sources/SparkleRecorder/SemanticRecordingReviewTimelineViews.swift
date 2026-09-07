import SwiftUI
import SparkleRecorderCore

struct SemanticRecordingReviewTimelineView: View {
    let rows: [SemanticRecordingReviewProjection.TimelineRow]
    let onSelectRow: (SemanticRecordingReviewProjection.TimelineRow) -> Void
    let onSelectFrame: (UUID?, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Timeline", table: "EditorUX"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.50))

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    SemanticRecordingReviewTimelineRowView(
                        row: row,
                        onSelect: { onSelectRow(row) },
                        onSelectFrame: { frameID in
                            onSelectFrame(frameID, row.id)
                        }
                    )
                }
            }
        }
    }
}

private struct SemanticRecordingReviewTimelineRowView: View {
    let row: SemanticRecordingReviewProjection.TimelineRow
    let onSelect: () -> Void
    let onSelectFrame: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            title
            frameLinks
            evidenceSummary
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(row.isSelected ? Color.white.opacity(0.085) : Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    row.isSelected
                        ? Color(red: 0.34, green: 0.72, blue: 0.95).opacity(0.52)
                        : Color.white.opacity(0.07),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(Self.timeLabel(row.recordingTime))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    row.isSelected
                        ? Color(red: 0.34, green: 0.72, blue: 0.95)
                        : Color.white.opacity(0.46)
                )
            Text(SemanticRecordingReviewLabelPresentation.timelineEventKind(row.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.42))
            Spacer()
            if row.suggestionCount > 0 {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.72, blue: 0.30))
            }
        }
    }

    private var title: some View {
        Text(row.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
    }

    private var frameLinks: some View {
        HStack(spacing: 8) {
            SemanticRecordingReviewTimelineFrameChip(
                title: String(localized: "Before frame", table: "EditorUX"),
                frameID: row.beforeFrameID,
                action: { onSelectFrame(row.beforeFrameID) }
            )
            SemanticRecordingReviewTimelineFrameChip(
                title: String(localized: "After frame", table: "EditorUX"),
                frameID: row.afterFrameID,
                action: { onSelectFrame(row.afterFrameID) }
            )
        }
    }

    private var evidenceSummary: some View {
        Text(String(
            format: String(localized: "%d overlays · %d refs", table: "EditorUX"),
            row.observationCount,
            row.sourcePreviewCount
        ))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.46))
    }

    private static func timeLabel(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }
}

private struct SemanticRecordingReviewTimelineFrameChip: View {
    let title: String
    let frameID: UUID?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(shortID)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        .disabled(frameID == nil)
    }

    private var shortID: String {
        guard let frameID else { return "not set" }
        return String(frameID.uuidString.suffix(8))
    }
}

struct SemanticRecordingReviewFrameStripView: View {
    let frames: [SemanticRecordingReviewProjection.FrameStripItem]
    let onSelect: (SemanticRecordingReviewProjection.FrameStripItem) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(frames) { frame in
                SemanticRecordingReviewFrameStripItemView(
                    frame: frame,
                    onSelect: { onSelect(frame) }
                )
            }
        }
        .frame(width: 440, alignment: .leading)
        .clipped()
    }
}

private struct SemanticRecordingReviewFrameStripItemView: View {
    let frame: SemanticRecordingReviewProjection.FrameStripItem
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Self.timeLabel(frame.recordingTime))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    frame.isSelected
                        ? Color(red: 0.34, green: 0.72, blue: 0.95)
                        : Color.white.opacity(0.50)
                )
            Text(SemanticRecordingReviewLabelPresentation.frameCaptureSource(frame.source))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(referenceLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            frame.isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    frame.isSelected
                        ? Color(red: 0.34, green: 0.72, blue: 0.95).opacity(0.45)
                        : Color.white.opacity(0.07),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
    }

    private var referenceLabel: String {
        String(
            format: frame.isRedacted
                ? String(localized: "Redacted · %@", table: "EditorUX")
                : String(localized: "Ref · %@", table: "EditorUX"),
            frame.imageRefPath
        )
    }

    private static func timeLabel(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }
}
