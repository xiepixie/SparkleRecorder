import SwiftUI
import AppKit
import SparkleRecorderCore
import Carbon.HIToolbox

struct ShortcutRecording {
    let keyCode: UInt32
    let name: String
    let carbonModifiers: UInt32
    let eventFlags: UInt64

    var hotkeyBinding: HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, name: name, modifiers: carbonModifiers)
    }
}

struct ShortcutRecorderField: View {
    @Binding var currentBinding: HotkeyBinding?
    let allHotkeys: Set<UInt32>
    var allowsClear = true
    var recordingPrompt = NSLocalizedString("Type shortcut...", comment: "")
    var emptyPrompt = NSLocalizedString("Click to record shortcut", comment: "")
    var onRecord: (ShortcutRecording) -> Void = { _ in }
    
    @State private var isRecording = false
    @State private var recordedEventFlags: UInt64 = 0
    @State private var localEventMonitor: Any?
    @State private var isHovered = false
    @State private var clearHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                HStack(spacing: 6) {
                    Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                        .foregroundStyle(isRecording ? .red : .secondary)
                    Text(displayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isRecording ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if allowsClear, currentBinding != nil, !isRecording {
                Button {
                    currentBinding = nil
                    onRecord(ShortcutRecording(keyCode: 0, name: "", carbonModifiers: 0, eventFlags: 0)) // Clear callback
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(clearHovered ? .primary : .tertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    clearHovered = hover
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28) // Slightly more compact for sidebars
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isRecording ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isRecording ? Color.accentColor : (isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1)),
                    lineWidth: isRecording ? 1.5 : 1
                )
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private var displayText: String {
        if isRecording {
            let modifiers = modifierString(flags: recordedEventFlags)
            return modifiers.isEmpty ? recordingPrompt : "\(modifiers) \(recordingPrompt)"
        } else if let b = currentBinding {
            return b.name
        } else {
            return emptyPrompt
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        stopRecording()
        isRecording = true
        recordedEventFlags = 0
        let previousKeyCode = currentBinding?.keyCode
        if allowsClear {
            currentBinding = nil
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                self.recordedEventFlags = Self.eventFlags(from: event.modifierFlags)
                return nil
            }

            let keyCode = UInt32(event.keyCode)

            if Self.modifierKeyCodes.contains(keyCode) {
                return nil
            }

            let recording = Self.recording(from: event)

            if !allHotkeys.contains(keyCode) || keyCode == previousKeyCode {
                self.currentBinding = recording.hotkeyBinding
                self.onRecord(recording)
            }

            self.stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        recordedEventFlags = 0
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    private static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func recording(from event: NSEvent) -> ShortcutRecording {
        let flags = event.modifierFlags
        let eventFlags = eventFlags(from: flags)
        let keyCode = UInt32(event.keyCode)
        return ShortcutRecording(
            keyCode: keyCode,
            name: displayName(for: event, eventFlags: eventFlags),
            carbonModifiers: carbonModifiers(from: flags),
            eventFlags: eventFlags
        )
    }

    private static func displayName(for event: NSEvent, eventFlags: UInt64) -> String {
        let modifiers = modifierString(flags: eventFlags)
        if let key = keyName(event.keyCode) {
            return modifiers + key
        }
        if let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty {
            return modifiers + characters
        }
        return modifiers + String(event.keyCode)
    }

    private static func eventFlags(from flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: UInt64 = 0
        if flags.contains(.control) { result |= ModFlag.control }
        if flags.contains(.option) { result |= ModFlag.option }
        if flags.contains(.shift) { result |= ModFlag.shift }
        if flags.contains(.command) { result |= ModFlag.command }
        return result
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
