import AppKit

@MainActor
enum HUDApplicationPresentation {
    /// App-level hiding suppresses even newly ordered nonactivating panels.
    /// Keep ordinary windows explicitly ordered out, then allow only the HUD
    /// to appear without taking activation away from the recording/playback app.
    static func prepareToShow() {
        guard NSApp.isHidden else { return }
        for window in NSApp.windows { window.orderOut(nil) }
        NSApp.unhideWithoutActivation()
    }
}
