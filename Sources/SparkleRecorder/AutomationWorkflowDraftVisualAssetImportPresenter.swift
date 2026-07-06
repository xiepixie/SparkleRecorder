import AppKit
import CryptoKit
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

@MainActor
enum AutomationWorkflowDraftVisualAssetImportPresenter {
    static func importAsset(
        kind: AutomationWorkflowDraftVisualAssetImportKind,
        packageDirectory: URL,
        preferredKey: String,
        preferredLabel: String,
        onImported: @escaping (AutomationWorkflowDraftVisualAssetImportResult) -> Void,
        onCancelled: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = kind.pickerTitle
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                onCancelled()
                return
            }

            Task {
                do {
                    let result = try await importSelectedAsset(
                        url: url,
                        kind: kind,
                        packageDirectory: packageDirectory,
                        preferredKey: preferredKey,
                        preferredLabel: preferredLabel
                    )
                    await MainActor.run {
                        onImported(result)
                    }
                } catch {
                    await MainActor.run {
                        onError(String(
                            format: NSLocalizedString("Could not import visual asset: %@", comment: ""),
                            String(describing: error)
                        ))
                    }
                }
            }
        }
    }

    nonisolated private static func importSelectedAsset(
        url: URL,
        kind: AutomationWorkflowDraftVisualAssetImportKind,
        packageDirectory: URL,
        preferredKey: String,
        preferredLabel: String
    ) async throws -> AutomationWorkflowDraftVisualAssetImportResult {
        let startedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if startedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let key = preferredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = key.isEmpty ? defaultKey(from: url) : key
        let label = preferredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? url.deletingPathExtension().lastPathComponent : label

        let fileExtension = safeFileExtension(from: url)
        let relativeDirectory = "assets/\(kind.directoryName)"
        let relativePath = "\(relativeDirectory)/\(safeFileStem(for: resolvedKey)).\(fileExtension)"
        guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(relativePath) == relativePath else {
            throw AutomationWorkflowDraftVisualAssetImportError.invalidRelativePath
        }

        let destinationDirectory = packageDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(kind.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = packageDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try data.write(to: destinationURL, options: .atomic)

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        return AutomationWorkflowDraftVisualAssetImportResult(
            asset: AutomationWorkflowDraftVisualImageAsset(
                key: resolvedKey,
                label: resolvedLabel,
                path: relativePath,
                sha256: digest
            ),
            relativePath: relativePath
        )
    }

    nonisolated private static func defaultKey(from url: URL) -> String {
        safeFileStem(for: url.deletingPathExtension().lastPathComponent)
    }

    nonisolated private static func safeFileExtension(from url: URL) -> String {
        let rawExtension = url.pathExtension.lowercased()
        let cleaned = rawExtension.filter { character in
            character.isLetter || character.isNumber
        }
        guard !cleaned.isEmpty, cleaned.count <= 8 else {
            return "png"
        }
        return cleaned
    }

    nonisolated private static func safeFileStem(for value: String) -> String {
        let stem = value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
            .reduce(into: "") { partial, character in
                if partial.last == "_" && character == "_" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return stem.isEmpty ? "visual_asset" : stem
    }
}
