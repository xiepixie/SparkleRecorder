import AppKit
import AVFoundation
import SwiftUI

/// Distribution-safe video preview for macro reconstruction.
///
/// Avoid SwiftUI's AVKit `VideoPlayer` here: macOS 26 distributed builds have
/// reported crashes in `_AVKit_SwiftUI`. Keep the existing `AVPlayer` model, but
/// render it through `AVPlayerLayer` so Review never instantiates that private layer.
struct MacroReconstructionVideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> MacroReconstructionPlayerLayerView {
        MacroReconstructionPlayerLayerView(player: player)
    }

    func updateNSView(_ nsView: MacroReconstructionPlayerLayerView, context: Context) {
        nsView.setPlayer(player)
    }

    static func dismantleNSView(_ nsView: MacroReconstructionPlayerLayerView, coordinator: ()) {
        nsView.setPlayer(nil)
    }
}

final class MacroReconstructionPlayerLayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let playPauseButton = NSButton()
    private let scrubber = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "0:00 / --:--")
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var isScrubbing = false

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)

        playPauseButton.isBordered = false
        playPauseButton.imagePosition = .imageOnly
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayback)
        playPauseButton.toolTip = String(localized: "Play", table: "Common")
        playPauseButton.setAccessibilityLabel(String(localized: "Play", table: "Common"))
        addSubview(playPauseButton)

        scrubber.isContinuous = true
        scrubber.target = self
        scrubber.action = #selector(scrubberChanged)
        scrubber.setAccessibilityLabel(String(localized: "Playback", table: "Settings"))
        addSubview(scrubber)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        addSubview(timeLabel)

        setPlayer(player)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let controlsHeight: CGFloat = 30
        let gap: CGFloat = 6
        let videoHeight = max(0, bounds.height - controlsHeight - gap)
        playerLayer.frame = CGRect(x: 0, y: controlsHeight + gap, width: bounds.width, height: videoHeight)

        let buttonWidth: CGFloat = 28
        let labelWidth: CGFloat = 92
        playPauseButton.frame = CGRect(x: 0, y: 0, width: buttonWidth, height: controlsHeight)
        timeLabel.frame = CGRect(x: max(buttonWidth, bounds.width - labelWidth), y: 0, width: labelWidth, height: controlsHeight)
        let scrubberX = buttonWidth + 6
        let scrubberWidth = max(0, bounds.width - scrubberX - labelWidth - 8)
        scrubber.frame = CGRect(x: scrubberX, y: 0, width: scrubberWidth, height: controlsHeight)
    }

    func setPlayer(_ newPlayer: AVPlayer?) {
        guard player !== newPlayer else { return }
        removeTimeObserver()
        player = newPlayer
        playerLayer.player = newPlayer
        installTimeObserver()
        updateControls(time: newPlayer?.currentTime().seconds ?? 0)
    }

    @objc private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        updatePlayPauseButton()
    }

    @objc private func scrubberChanged() {
        guard let player,
              let duration = finiteDuration(of: player),
              duration > 0 else { return }
        isScrubbing = true
        let target = duration * scrubber.doubleValue
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isScrubbing = false
            }
        }
        updateControls(time: target)
    }

    private func installTimeObserver() {
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updateControls(time: time.seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func updateControls(time: Double) {
        let duration = player.flatMap(finiteDuration(of:))
        if !isScrubbing, let duration, duration > 0, time.isFinite {
            scrubber.doubleValue = min(max(time / duration, 0), 1)
        }
        scrubber.isEnabled = duration.map { $0 > 0 } ?? false
        timeLabel.stringValue = "\(Self.timeString(time)) / \(duration.map(Self.timeString) ?? "--:--")"
        updatePlayPauseButton()
    }

    private func updatePlayPauseButton() {
        let isPlaying = player?.timeControlStatus == .playing
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        let title = isPlaying
            ? String(localized: "Pause", table: "Common")
            : String(localized: "Play", table: "Common")
        playPauseButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        playPauseButton.toolTip = title
        playPauseButton.setAccessibilityLabel(title)
    }

    private func finiteDuration(of player: AVPlayer) -> Double? {
        let seconds = player.currentItem?.duration.seconds ?? .nan
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
