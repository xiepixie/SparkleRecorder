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
        if state.isRecording { return NSLocalizedString("Recording…", comment: "") }
        if state.isPlaying     { return NSLocalizedString("Playing…", comment: "") }
        let format = NSLocalizedString("Idle · %d macros", comment: "")
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
                            RecDot(size: 8, glassWhite: false)
                        }
                        Text(state.isRecording ? NSLocalizedString("Stop recording", comment: "") : NSLocalizedString("Start recording", comment: ""))
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
                .accessibilityLabel(state.isRecording ? NSLocalizedString("Stop recording", comment: "") : NSLocalizedString("Start recording", comment: ""))
                
                // Search Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSearch.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                        Text(NSLocalizedString("Search", comment: ""))
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

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}
