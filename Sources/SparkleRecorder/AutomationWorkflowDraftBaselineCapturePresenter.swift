import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import SparkleRecorderCore

@MainActor
enum AutomationWorkflowDraftBaselineCapturePresenter {
    static func captureBaseline(
        packageDirectory: URL,
        preferredKey: String,
        preferredLabel: String,
        onCaptured: @escaping (AutomationWorkflowDraftBaselineCaptureResult) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            onError(String(localized: "No display is available for baseline capture.", table: "Common"))
            return
        }

        let key = preferredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baselineKey = key.isEmpty ? defaultBaselineKey() : key
        let label = preferredLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayID = displayID(for: screen)

        AutomationScreenRegionPicker.pickRegion(
            instructionTitle: String(localized: "Drag to capture baseline", table: "Recording"),
            onPicked: { selection in
            guard let region = selection.searchRegion(in: .displayAbsolute) else {
                onError(String(localized: "Could not resolve the selected baseline region.", table: "Common"))
                return
            }
            let previewImage = selection.preview?.cgImage

            Task {
                do {
                    let result = try await captureAndStoreBaseline(
                        packageDirectory: packageDirectory,
                        displayID: displayID,
                        region: region,
                        previewImage: previewImage,
                        key: baselineKey,
                        label: label.isEmpty ? nil : label
                    )
                    await MainActor.run {
                        onCaptured(result)
                    }
                } catch {
                    await MainActor.run {
                        onError(String(
                            format: String(localized: "Could not capture baseline: %@", table: "Common"),
                            String(describing: error)
                        ))
                    }
                }
            }
        },
            onCancelled: {
                onError(String(localized: "Baseline capture cancelled.", table: "Common"))
            }
        )
    }

    nonisolated private static func captureAndStoreBaseline(
        packageDirectory: URL,
        displayID: CGDirectDisplayID,
        region: RectValue,
        previewImage: CGImage?,
        key: String,
        label: String?
    ) async throws -> AutomationWorkflowDraftBaselineCaptureResult {
        let cropped: CGImage
        if let previewImage {
            cropped = previewImage
        } else {
            let image = try await ScreenCaptureService.shared.captureDisplay(displayID: displayID)
            guard let fallbackCrop = crop(image: image, region: region) else {
                throw AutomationWorkflowDraftBaselineCaptureError.emptyRegion
            }
            cropped = fallbackCrop
        }

        let pngData = try pngData(for: cropped)
        let fileName = safeFileStem(for: key) + ".png"
        let relativePath = "assets/baselines/\(fileName)"
        guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(relativePath) == relativePath else {
            throw AutomationWorkflowDraftBaselineCaptureError.invalidRelativePath
        }

        let directoryURL = packageDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("baselines", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = packageDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try pngData.write(to: fileURL, options: .atomic)

        let digest = SHA256.hash(data: pngData)
            .map { String(format: "%02x", $0) }
            .joined()
        return AutomationWorkflowDraftBaselineCaptureResult(
            asset: AutomationWorkflowDraftVisualImageAsset(
                key: key,
                label: label,
                path: relativePath,
                sha256: digest
            ),
            relativePath: relativePath
        )
    }

    nonisolated private static func crop(image: CGImage, region: RectValue) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let requested = CGRect(
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height
        ).integral
        let clipped = requested.intersection(imageBounds)
        guard !clipped.isNull,
              clipped.width >= 2,
              clipped.height >= 2 else {
            return nil
        }
        return image.cropping(to: clipped)
    }

    nonisolated private static func pngData(for image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw AutomationWorkflowDraftBaselineCaptureError.pngEncodingFailed
        }
        return data
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
    }

    private static func defaultBaselineKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "baseline_\(formatter.string(from: Date()))"
    }

    nonisolated private static func safeFileStem(for key: String) -> String {
        let stem = key
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
        return stem.isEmpty ? "baseline" : stem
    }
}
