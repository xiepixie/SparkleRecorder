// swift-tools-version:6.0
import Foundation
import PackageDescription

let toolingSources = [
    "WorkflowCLIAsync.swift",
    "WorkflowCLIError.swift",
    "WorkflowCLIOutput.swift",
    "WorkflowCLIParsing.swift",
    "WorkflowDraftCLI.swift",
    "WorkflowMacroCatalog.swift",
    "WorkflowRecordingBundle.swift"
]

// SparkleRecorderTooling is intentionally carved out of the existing app source
// root so the migration can stay incremental. Keep source ownership explicit:
// Tooling compiles only its allowlist; every other top-level app entry is excluded.
// New app UI should prefer existing app subdirectories so Tooling ownership stays
// stable without expanding this Interface. The physical Tooling directory split
// remains the long-term fix for SwiftPM manifest file-list caching at this shared root;
// this revision also refreshes ownership after the feedback, manual-playback visibility,
// and shared window-server observation Modules were added.
let appSourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/SparkleRecorder", isDirectory: true)
let toolingSourceSet = Set(toolingSources)
// Top-level App files added while SwiftPM has a cached manifest can otherwise be
// reported as "unhandled" by the Tooling target until Package.swift changes.
// Keep newly introduced top-level App ownership explicit as a cache-safe fallback;
// the directory scan remains the general source of truth.
let toolingAlwaysExcludedAppSources: Set<String> = [
    "AutomationRunCenterDeletionConfirmation.swift",
    "AutomationRunCenterEvidenceSelection.swift",
    "AutomationRunCenterStorageUsageState.swift",
    "AutomationTaskAdvancedEditorView.swift",
    "AutomationTaskConditionEditorView.swift",
    "AutomationTaskFlowEditorView.swift",
    "AutomationTaskRunEditorView.swift",
    "AutomationVisualAssetPackageRootAssociation.swift",
    "AutomationWorkflowAuthoringState.swift",
    "AutomationWorkflowRecordingHandoff.swift",
    "AuxiliaryCaptureActivityCenter.swift",
    "MacroCandidateEditorSession.swift",
    "MacroReconstructionCandidateProvenancePresentation.swift",
    "MacroReconstructionLegacyV3PackageDecoder.swift",
    "MacroReconstructionPackageValidation.swift",
    "MacroReconstructionV4PackageDecoder.swift",
    "WindowContentFrameResolver.swift"
]
let discoveredToolingExcludes = (try? FileManager.default.contentsOfDirectory(atPath: appSourceRoot.path))?
    .filter { !toolingSourceSet.contains($0) } ?? []
let toolingExcludes = Set(discoveredToolingExcludes)
    .union(toolingAlwaysExcludedAppSources)
    .sorted()

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
        .target(
            name: "SparkleRecorderTooling",
            dependencies: ["SparkleRecorderCore"],
            path: "Sources/SparkleRecorder",
            exclude: toolingExcludes,
            sources: toolingSources,
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "SparkleRecorder",
            dependencies: ["SparkleRecorderCore", "SparkleRecorderTooling"],
            path: "Sources/SparkleRecorder",
            exclude: toolingSources,
            resources: [
                .process("InfoPlist.xcstrings"),
                .process("Localizable.xcstrings"),
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
            dependencies: ["SparkleRecorderCore", "SparkleRecorderTooling", "SparkleRecorder"],
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
