// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TinyRecorder",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TinyRecorder", targets: ["TinyRecorder"]),
        .library(name: "TinyRecorderCore", targets: ["TinyRecorderCore"])
    ],
    targets: [
        .target(
            name: "TinyRecorderCore",
            path: "Sources/TinyRecorder",
            exclude: [
                "AppDelegate.swift",
                "AppState.swift",
                "CountdownOverlay.swift",
                "HotkeyManager.swift",
                "MacroEditor.swift",
                "MacroLibrary.swift",
                "MainWindowController.swift",
                "MenuBarController.swift",
                "Player.swift",
                "PopoverContentView.swift",
                "Recorder.swift",
                "RecordingHUD.swift",
                "SoundController.swift",
                "VisualEffects.swift",
                "WelcomeWindow.swift",
                "main.swift",
                "WindowSurfaceCapture.swift"
            ],
            sources: [
                "RecordedEvent.swift",
                "TextMacroFormat.swift",
                "MacroImport.swift",
                "SavedMacro.swift",
                "MouseKeyboardSynthesizer.swift",
                "PointResolver.swift",
                "EventGrouper.swift"
            ]
        ),
        .executableTarget(
            name: "TinyRecorder",
            dependencies: ["TinyRecorderCore"],
            path: "Sources/TinyRecorder",
            exclude: [
                "RecordedEvent.swift",
                "TextMacroFormat.swift",
                "MacroImport.swift",
                "SavedMacro.swift",
                "MouseKeyboardSynthesizer.swift",
                "PointResolver.swift",
                "EventGrouper.swift"
            ]
        ),
        .testTarget(
            name: "TinyRecorderTests",
            dependencies: ["TinyRecorderCore"],
            path: "Tests/TinyRecorderTests",
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
