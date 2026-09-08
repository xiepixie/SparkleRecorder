import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LibraryHeader: View {
    let controller: MenuBarController
    @Binding var search: String
    @Binding var showSearch: Bool
    let isWindow: Bool
    let macroCount: Int
    @EnvironmentObject var state: AppState

    private var statusText: String {
        if state.isRecording { return String(localized: "Recording…", table: "Recording") }
        if state.isPlaying     { return String(localized: "Playing…", table: "Common") }
        let format = String(localized: "Idle · %d macros", table: "EditorUX")
        return String(format: format, macroCount)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Brand row
            if !isWindow {
                LibraryBrandStrip(
                    statusText: statusText,
                    isRecording: state.isRecording,
                    onSettings: { controller.showSettingsWindow() }
                )
            }

            HStack(spacing: 12) {
                // Big record button
                Button {
                    controller.toggleRecording()
                } label: {
                    HStack(spacing: 10) {
                        if state.isRecording {
                            Image(systemName: "stop.fill").font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                        } else {
                            RecDot(size: 8, glassWhite: false, isAnimated: false)
                        }
                        Text(state.isRecording ? String(localized: "Stop recording", table: "Recording") : String(localized: "Record macro", table: "Recording"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(state.isRecording ? .white : .primary)
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            KeyCapView(text: state.recordHotkey.name, size: .sm, variant: .glass)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(state.isRecording ? Brand.red500.opacity(0.8) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(state.isRecording ? Brand.red500 : Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: state.isRecording ? Brand.red500.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(HoverPressButtonStyle(hoverScale: 1.012))
                .accessibilityLabel(state.isRecording ? String(localized: "Stop recording", table: "Recording") : String(localized: "Record macro", table: "Recording"))
                
                // Search Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSearch.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                        Text("Search", tableName: "Common")
                            .font(.system(size: 11, weight: .medium))
                        KeyCapView(text: "⌘", size: .sm)
                        KeyCapView(text: "K", size: .sm)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10) // match the height better
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }

            if !state.isRecording {
                recordingEvidenceStatus
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var recordingEvidenceStatus: some View {
        let mode = state.recordingPermissionReadiness.evidenceMode
        if mode == .visualEvidenceBlocked {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: evidenceIcon(for: mode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(evidenceTint(for: mode))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(evidenceTitle(for: mode))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(evidenceDetail(for: mode))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(String(localized: "Grant…", table: "Settings")) {
                    controller.openScreenCapturePrefs()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(evidenceTint(for: mode).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(evidenceTint(for: mode).opacity(0.2), lineWidth: 0.5)
            )
        } else {
            HStack(spacing: 6) {
                Image(systemName: evidenceIcon(for: mode))
                    .font(.system(size: 9.5))
                    .foregroundStyle(evidenceTint(for: mode))
                Text(evidenceTitle(for: mode))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Text(evidenceDetail(for: mode))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private func evidenceTitle(for mode: RecordingEvidenceMode) -> String {
        switch mode {
        case .actionsOnly:
            return String(localized: "Record actions only", table: "Recording")
        case .actionsAndVisualEvidence:
            return String(localized: "Evidence ready", table: "Automation")
        case .visualEvidenceBlocked:
            return String(localized: "Screen Recording required", table: "Common")
        }
    }

    private func evidenceDetail(for mode: RecordingEvidenceMode) -> String {
        switch mode {
        case .actionsOnly:
            return String(localized: "Enable visual evidence before your next recording to review it alongside video.", table: "EditorUX")
        case .actionsAndVisualEvidence:
            return String(localized: "Frames, OCR, and privacy exclusions stay separate from playable macro events.", table: "EditorUX")
        case .visualEvidenceBlocked:
            return String(localized: "Screen Recording is required while visual evidence is enabled.", table: "Recording")
        }
    }

    private func evidenceIcon(for mode: RecordingEvidenceMode) -> String {
        switch mode {
        case .actionsOnly: return "record.circle"
        case .actionsAndVisualEvidence: return "film.stack.fill"
        case .visualEvidenceBlocked: return "exclamationmark.triangle.fill"
        }
    }

    private func evidenceTint(for mode: RecordingEvidenceMode) -> Color {
        switch mode {
        case .actionsOnly: return .secondary
        case .actionsAndVisualEvidence: return .green
        case .visualEvidenceBlocked: return .orange
        }
    }
}
