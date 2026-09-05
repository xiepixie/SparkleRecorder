import AppKit
import Combine
import SparkleRecorderCore
import SwiftUI

@MainActor
final class PlaybackFeedbackState: ObservableObject {
    @Published var action: PlaybackActionFeedback?
}

/// Presentation-only observer. It never activates the app or handles input.
@MainActor
final class PlaybackHUDController {
    private var panel: PlaybackFeedbackPanel?
    private var subscription: AnyCancellable?
    private let player: Player

    init(player: Player) {
        self.player = player
        subscription = player.$isPlaying.removeDuplicates().sink { [weak self] playing in
            self?.setVisible(playing)
        }
    }

    private func setVisible(_ visible: Bool) {
        guard visible else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil {
            let panel = PlaybackFeedbackPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 76),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isMovable = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.sharingType = .none
            panel.contentView = NSHostingView(rootView: PlaybackFeedbackView(feedback: player.feedback))
            self.panel = panel
        }
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                                         y: screen.visibleFrame.minY + 18))
        }
        panel.orderFrontRegardless()
    }
}

private final class PlaybackFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct PlaybackFeedbackView: View {
    @ObservedObject var feedback: PlaybackFeedbackState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(String(localized: "Playing", table: "Recording"), systemImage: "play.fill")
                    .font(.caption.bold())
                Spacer()
                if let action = feedback.action {
                    Text("\(action.stepNumber) / \(action.stepCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(feedback.action.map(PlaybackFeedbackLabel.text) ?? String(localized: "Preparing playback…", table: "Recording"))
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 310, height: 76)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)))
        .allowsHitTesting(false)
    }
}

enum PlaybackFeedbackLabel {
    static func text(_ action: PlaybackActionFeedback) -> String {
        switch action.kind {
        case .keyDown, .keyUp:
            let label = action.kind == .keyDown
                ? String(localized: "Key down", table: "Recording")
                : String(localized: "Key up", table: "Recording")
            guard let code = action.keyCode else { return label }
            return label + " · " + modifiers(action.modifierFlags) + key(code)
        case .flagsChanged:
            let flags = modifiers(action.modifierFlags)
            return flags.isEmpty ? String(localized: "Modifiers released", table: "Recording") : flags
        case .leftMouseDown: return String(localized: "Left mouse down", table: "Recording")
        case .leftMouseUp: return String(localized: "Left mouse up", table: "Recording")
        case .rightMouseDown: return String(localized: "Right mouse down", table: "Recording")
        case .rightMouseUp: return String(localized: "Right mouse up", table: "Recording")
        case .otherMouseDown: return String(localized: "Mouse button down", table: "Recording")
        case .otherMouseUp: return String(localized: "Mouse button up", table: "Recording")
        case .mouseMoved: return String(localized: "Moving pointer", table: "Recording")
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return String(localized: "Dragging", table: "Recording")
        case .scrollWheel: return String(localized: "Scrolling", table: "Recording")
        case .waitForText: return String(localized: "Waiting for text", table: "Recording")
        case .verifyText: return String(localized: "Checking text", table: "Recording")
        }
    }

    private static func modifiers(_ flags: UInt64) -> String {
        [(UInt64(1 << 18), "⌃"), (UInt64(1 << 19), "⌥"), (UInt64(1 << 17), "⇧"), (UInt64(1 << 20), "⌘")]
            .filter { flags & $0.0 != 0 }.map(\.1).joined()
    }

    private static func key(_ code: UInt16) -> String {
        let labels: [UInt16: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑"]
        return labels[code] ?? "#\(code)"
    }
}
