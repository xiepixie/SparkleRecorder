import SwiftUI
import SparkleRecorderCore

struct CompactMacroRowMetadataView: View {
    let macro: SavedMacro
    let automationSummary: AutomationMacroScheduleSummary?
    let isCurrent: Bool
    let onAssignHotkey: () -> Void
    let onSchedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(macro.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isCurrent ? Brand.libraryBlue : .primary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(durationText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let hotkey = macro.hotkey {
                    Button(action: onAssignHotkey) {
                        KeyCapView(text: hotkey.name, size: .sm)
                    }
                    .buttonStyle(.plain)
                    .help(String(
                        format: String(localized: "Hotkey: %@ — click to change", table: "EditorUX"),
                        hotkey.name
                    ))
                }

                if macro.favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AnyShapeStyle(.yellow))
                }

                if let surface = macro.surfaces.values.first {
                    Label(
                        surface.appName ?? String(localized: "Target window", table: "Recording"),
                        systemImage: "window.badge.key"
                    )
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
                    .help(targetWindowHelp(surface))
                }

                if let automationSummary {
                    Button(action: onSchedule) {
                        Label(automationSummary.statusText, systemImage: "calendar.badge.checkmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 190, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Edit automatic run…", table: "Automation"))
                }
            }
        }
    }

    private func targetWindowHelp(_ surface: PlaybackSurface) -> String {
        let appName = surface.appName ?? String(localized: "Target window", table: "Recording")
        guard let title = surface.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return appName
        }
        return "\(appName) — \(title)"
    }

    private var durationText: String {
        let duration = macro.duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let centiseconds = Int((duration - floor(duration)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

struct CompactMacroRowActionsView: View {
    let hasTargetWindow: Bool
    let onReconstruct: () -> Void
    let onShowEvidence: () -> Void
    let onSchedule: () -> Void
    let onChooseTargetWindow: () -> Void
    let onEdit: () -> Void
    let onPlay: () -> Void

    @State private var playHovered = false
    @State private var editHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button(action: onReconstruct) {
                    Label(
                        String(localized: "AI-assisted reconstruction…", table: "EditorUX"),
                        systemImage: "wand.and.stars"
                    )
                }
                Button(action: onShowEvidence) {
                    Label(
                        String(localized: "Latest run…", table: "Automation"),
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                Button(action: onSchedule) {
                    Label(
                        String(localized: "Run automatically…", table: "Automation"),
                        systemImage: "calendar.badge.clock"
                    )
                }
                Divider()
                Button(action: onChooseTargetWindow) {
                    Label(
                        hasTargetWindow
                            ? String(localized: "Change Target Window…", table: "Recording")
                            : String(localized: "Choose Target Window…", table: "Recording"),
                        systemImage: "window.badge.key"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "More actions", table: "EditorUX"))

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(editHovered ? Brand.libraryBlue : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { editHovered = $0 }
            .help(String(localized: "Edit in Main Window", table: "Common"))

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Brand.libraryGreen.opacity(playHovered ? 1.0 : 0.85))
                            .shadow(color: Brand.libraryGreen.opacity(0.3), radius: 4, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .onHover { playHovered = $0 }
            .help(String(localized: "Play", table: "Common"))
        }
    }
}
