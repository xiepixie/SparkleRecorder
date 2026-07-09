import Cocoa
import SwiftUI

/// Hosts the library UI in a real, dockable window with proper macOS chrome.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let controller: MenuBarController

    init(controller: MenuBarController) {
        self.controller = controller

        let host = NSHostingController(
            rootView: PopoverContentView(controller: controller, isWindow: true)
                .environmentObject(controller.recorder)
                .environmentObject(controller.player)
                .environmentObject(controller.state)
                .environmentObject(controller.library)
        )

        let win = NSWindow(contentViewController: host)
        win.title = "SparkleRecorder"
        win.setContentSize(NSSize(width: 1080, height: 740))
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        win.minSize = NSSize(width: 720, height: 560)
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.toolbarStyle = .unified
        win.backgroundColor = .clear
        win.isMovableByWindowBackground = true
        super.init(window: win)
        win.delegate = self
        
        if !win.setFrameUsingName("SparkleRecorder.MainWindow") {
            win.center()
        }
        win.setFrameAutosaveName("SparkleRecorder.MainWindow")
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Dedicated Settings window (HIG: Settings belongs in its own window,
/// not a popover spawned inside the menu-bar popover).
final class SettingsWindowController: NSWindowController {
    init(controller: MenuBarController) {
        let host = NSHostingController(
            rootView: SettingsPanel(controller: controller, inWindow: true)
                .environmentObject(controller.state)
                .environmentObject(controller.library)
        )
        let win = NSWindow(contentViewController: host)
        win.title = NSLocalizedString("Settings", comment: "")
        win.setContentSize(NSSize(width: 600, height: 640))
        win.styleMask = [.titled, .closable, .resizable]
        win.minSize = NSSize(width: 520, height: 460)
        win.isReleasedWhenClosed = false
        super.init(window: win)
        
        if !win.setFrameUsingName("SparkleRecorder.Settings") {
            win.center()
        }
        win.setFrameAutosaveName("SparkleRecorder.Settings")
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
