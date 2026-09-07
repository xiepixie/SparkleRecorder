import Cocoa
import ApplicationServices
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var menuBar: MenuBarController!
    private var mainWindow: MainWindowController?
    private var terminationPreparationActive = false

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        menuBar = MenuBarController()
        menuBar.state.refreshPermissions()
        menuBar.showMainWindowHandler = { [weak self] in self?.presentMainWindow() }
        // Honor the saved Dock vs menu-bar-only preference.
        menuBar.applyAppearanceMode()

        // First-launch onboarding takes priority over the main window.
        if !menuBar.state.onboardingComplete {
            menuBar.showWelcomeIfNeeded()
        } else {
            promptForAccessibilityIfNeeded()
            // In menu-bar-only mode, launch quietly to the status item — no window.
            if !menuBar.state.menuBarOnly {
                showMainWindow(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        menuBar?.handleApplicationDidBecomeActive()
    }

    // Cmd-Q / Quit menu: delay process termination until live recording evidence
    // and repository writes have finished.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard menuBar != nil else { return .terminateNow }
        guard !terminationPreparationActive else { return .terminateLater }

        terminationPreparationActive = true
        Task { @MainActor [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            await menuBar.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // Bring the main window back when the user clicks the dock icon. If an input
    // session still owns the foreground target, silently consume the system
    // reopen instead of publishing an "interaction locked" error over the real
    // recording/playback completion status.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, menuBar?.preventsSystemWindowReopen != true {
            showMainWindow(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Language relaunch is scheduled only after applicationShouldTerminate has
        // finished recording/evidence/persistence cleanup, avoiding overlapping
        // old and new app instances.
        menuBar?.performPendingRelaunchIfNeeded()
    }

    // .tinyrec file open (Finder double-click, drag-drop on dock).
    func application(_ application: NSApplication, open urls: [URL]) {
        menuBar?.openExternalMacroFiles(urls)
    }

    private func promptForAccessibilityIfNeeded() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Main window

    @objc func showMainWindow(_ sender: Any?) {
        guard let menuBar else {
            presentMainWindow()
            return
        }
        menuBar.showMainWindow()
    }

    private func presentMainWindow() {
        if mainWindow == nil {
            mainWindow = MainWindowController(controller: menuBar)
        }
        mainWindow?.show()
    }

    // MARK: - File menu actions

    @objc func newRecording(_ sender: Any?) {
        menuBar?.toggleRecording()
    }

    @objc func importMacro(_ sender: Any?) {
        menuBar?.open()
    }

    @objc func exportMacro(_ sender: Any?) {
        menuBar?.exportAsScript()
    }

    @objc func exportText(_ sender: Any?) {
        menuBar?.exportAsText()
    }

    @objc func playMacro(_ sender: Any?) {
        menuBar?.play()
    }

    @objc func stopAll(_ sender: Any?) {
        menuBar?.stopAll()
    }

    @objc func openEditor(_ sender: Any?) {
        menuBar?.openEditor()
    }

    @objc func showPreferences(_ sender: Any?) {
        menuBar?.showSettingsWindow()
    }

    @objc func openAccessibilityPrefs(_ sender: Any?) {
        menuBar?.openAccessibilityPrefs()
    }

    @objc func showAbout(_ sender: Any?) {
        menuBar?.showAboutPanel()
    }

    @objc func showHelp(_ sender: Any?) {
        menuBar?.showHelp()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let menuBar else { return true }

        if menuItem.action == #selector(stopAll(_:)) {
            let mode = menuBar.stopMenuMode
            menuItem.title = mode.title
            return mode.isEnabled
        }

        let inputSessionProtectedActions: Set<Selector> = [
            #selector(newRecording(_:)),
            #selector(importMacro(_:)),
            #selector(exportMacro(_:)),
            #selector(exportText(_:)),
            #selector(playMacro(_:)),
            #selector(openEditor(_:)),
            #selector(showPreferences(_:)),
            #selector(showMainWindow(_:)),
            #selector(showAbout(_:)),
            #selector(showHelp(_:)),
            #selector(openAccessibilityPrefs(_:)),
        ]
        if let action = menuItem.action,
           inputSessionProtectedActions.contains(action) {
            return !menuBar.appMenuInteractionLocked
        }
        return true
    }

    // MARK: - Menu bar (top of screen)

    private func installMainMenu() {
        let main = NSMenu()

        // — App menu —
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(
            title: String(localized: "About SparkleRecorder", table: "Common"),
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(
            title: String(localized: "Settings", table: "Settings") + "…",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: String(localized: "Hide SparkleRecorder", table: "Common"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        let hideOthers = NSMenuItem(
            title: String(localized: "Hide Others", table: "Common"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(
            title: String(localized: "Show All", table: "Common"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: String(localized: "Quit SparkleRecorder", table: "Common"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu
        main.addItem(appItem)

        // — File menu —
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: String(localized: "File", table: "Common"))
        let newRec = NSMenuItem(title: String(localized: "New Recording", table: "Recording"), action: #selector(newRecording(_:)), keyEquivalent: "r")
        newRec.target = self
        fileMenu.addItem(newRec)
        let stop = NSMenuItem(title: String(localized: "Stop", table: "Common"), action: #selector(stopAll(_:)), keyEquivalent: ".")
        stop.target = self
        fileMenu.addItem(stop)
        fileMenu.addItem(.separator())
        let imp = NSMenuItem(title: String(localized: "Import Macro", table: "Common") + "…", action: #selector(importMacro(_:)), keyEquivalent: "o")
        imp.target = self
        imp.toolTip = String(
            localized: "Import a SparkleRecorder (.tinyrec), legacy Windows .rec, or text (.txt) macro.",
            table: "Common"
        )
        fileMenu.addItem(imp)
        let exp = NSMenuItem(title: String(localized: "Export as Shell Script", table: "Common") + "…", action: #selector(exportMacro(_:)), keyEquivalent: "e")
        exp.target = self
        fileMenu.addItem(exp)
        let expText = NSMenuItem(title: String(localized: "Export as Text", table: "Common") + "…", action: #selector(exportText(_:)), keyEquivalent: "e")
        expText.keyEquivalentModifierMask = [.command, .shift]
        expText.target = self
        fileMenu.addItem(expText)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(
            title: String(localized: "Close", table: "Common"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // — Edit menu — standard Cocoa items (Undo/Redo come from responder chain)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Edit", table: "Common"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Undo", table: "Common"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: String(localized: "Redo", table: "Common"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: String(localized: "Cut", table: "Common"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Copy", table: "Common"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Paste", table: "Common"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Delete", table: "Common"), action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: String(localized: "Select All", table: "Common"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // — Macro menu —
        let macroItem = NSMenuItem()
        let macroMenu = NSMenu(title: String(localized: "Macro", table: "EditorUX"))
        let play = NSMenuItem(title: String(localized: "Play", table: "Common"), action: #selector(playMacro(_:)), keyEquivalent: "p")
        play.target = self
        macroMenu.addItem(play)
        let openEdit = NSMenuItem(title: String(localized: "Open Editor", table: "Common") + "…", action: #selector(openEditor(_:)), keyEquivalent: "e")
        openEdit.keyEquivalentModifierMask = [.command, .option]
        openEdit.target = self
        macroMenu.addItem(openEdit)
        macroItem.submenu = macroMenu
        main.addItem(macroItem)

        // — Window menu —
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window", table: "Common"))
        windowMenu.addItem(NSMenuItem(
            title: String(localized: "Minimize", table: "Common"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: String(localized: "Zoom", table: "Common"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))
        windowMenu.addItem(.separator())
        let lib = NSMenuItem(title: String(localized: "Library", table: "Common"), action: #selector(showMainWindow(_:)), keyEquivalent: "0")
        lib.target = self
        windowMenu.addItem(lib)
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(
            title: String(localized: "Bring All to Front", table: "Common"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        // — Help menu —
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: String(localized: "Help", table: "Common"))
        let help = NSMenuItem(
            title: String(localized: "SparkleRecorder Help", table: "Common"),
            action: #selector(AppDelegate.showHelp(_:)),
            keyEquivalent: "?"
        )
        help.target = self
        helpMenu.addItem(help)
        helpItem.submenu = helpMenu
        main.addItem(helpItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }
}
