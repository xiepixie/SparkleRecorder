// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SparkleRecorder",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SparkleRecorder", targets: ["SparkleRecorder"]),
        .library(name: "SparkleRecorderCore", targets: ["SparkleRecorderCore"])
    ],
    targets: [
        .target(
            name: "SparkleRecorderCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "SparkleRecorder",
            dependencies: ["SparkleRecorderCore"],
            resources: [
                .process("Localizable.xcstrings"),
                .process("InfoPlist.xcstrings"),
                .process("Automation.xcstrings"),
                .process("Recording.xcstrings"),
                .process("EditorUX.xcstrings"),
                .process("Settings.xcstrings"),
                .process("Common.xcstrings")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SparkleRecorderTests",
            dependencies: ["SparkleRecorderCore", "SparkleRecorder"],
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
    swiftLanguageModes: [.v6]
)
