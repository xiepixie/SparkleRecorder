// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SparkleRecorder",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SparkleRecorder", targets: ["SparkleRecorder"]),
        .library(name: "SparkleRecorderCore", targets: ["SparkleRecorderCore"])
    ],
    targets: [
        .target(
            name: "SparkleRecorderCore",
            path: "Sources/SparkleRecorder",
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
                "MacroTransformer.swift",
                "main.swift",
                "WindowSurfaceCapture.swift",
                "WindowTracker.swift",
                "EventTapThread.swift",
                "PermissionCenter.swift",
                "RecordingSurfaceTracker.swift",
                "Components",
                "ScreenCaptureService.swift",
                "VisionDetector.swift",
                "LocatorEngine.swift",
                "TrajectorySampler.swift"
            ],
            sources: [
                "RecordedEvent.swift",
                "TextMacroFormat.swift",
                "MacroImport.swift",
                "SavedMacro.swift",
                "MouseKeyboardSynthesizer.swift",
                "PointResolver.swift",
                "EventGrouper.swift",
                "CoordinateMapper.swift"
            ]
        ),
        .executableTarget(
            name: "SparkleRecorder",
            dependencies: ["SparkleRecorderCore"],
            path: "Sources/SparkleRecorder",
            exclude: [
                "RecordedEvent.swift",
                "TextMacroFormat.swift",
                "MacroImport.swift",
                "SavedMacro.swift",
                "MouseKeyboardSynthesizer.swift",
                "PointResolver.swift",
                "EventGrouper.swift",
                "CoordinateMapper.swift"
            ]
        ),
        .testTarget(
            name: "SparkleRecorderTests",
            dependencies: ["SparkleRecorderCore"],
            path: "Tests/SparkleRecorderTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
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
