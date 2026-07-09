import AppKit
import SwiftUI
import SparkleRecorderCore
import UniformTypeIdentifiers

struct AutomationWorkflowDraftVisualAssetEditorView: View {
    let document: AutomationWorkflowDraftDocument
    let sourceDirectory: URL?
    let onRegisterAsset: (String, AutomationWorkflowDraftVisualImageAsset) -> Void

    @State private var assetKind = imageKind
    @State private var key = ""
    @State private var label = ""
    @State private var packagePath = ""
    @State private var message = ""
    @State private var messageIsWarning = false
    @State private var isCapturingBaseline = false
    @State private var isImportingAsset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AutomationSectionHeader(
                title: String(localized: "DRAFT VISUAL ASSETS", table: "Common"),
                count: assetCount
            )

            HStack(spacing: 8) {
                assetSummary(
                    title: String(localized: "Images", table: "Common"),
                    count: visualAssets.images.count,
                    systemImage: "photo"
                )
                assetSummary(
                    title: String(localized: "Baselines", table: "Common"),
                    count: visualAssets.baselines.count,
                    systemImage: "rectangle.dashed"
                )
                Spacer(minLength: 0)
                Label(packageRootLabel, systemImage: sourceDirectory == nil ? "folder.badge.questionmark" : "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    assetKindPicker
                    keyField
                    labelField
                }
                VStack(alignment: .leading, spacing: 8) {
                    assetKindPicker
                    keyField
                    labelField
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    packagePathField
                    assetActionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    packagePathField
                    assetActionButtons
                }
            }

            if !message.isEmpty {
                Label(message, systemImage: messageImage)
                    .font(.caption)
                    .foregroundStyle(messageTint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            assetList
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var assetKindPicker: some View {
        Picker(String(localized: "Asset type", table: "Common"), selection: $assetKind) {
            Label(String(localized: "Image template", table: "Common"), systemImage: "photo")
                .tag(Self.imageKind)
            Label(String(localized: "Baseline", table: "Common"), systemImage: "rectangle.dashed")
                .tag(Self.baselineKind)
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 190)
    }

    private var keyField: some View {
        TextField(String(localized: "Asset key", table: "Common"), text: normalizedKey)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(maxWidth: 180)
    }

    private var labelField: some View {
        TextField(String(localized: "Label", table: "Common"), text: normalizedLabel)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(maxWidth: 220)
    }

    private var packagePathField: some View {
        TextField(String(localized: "Package-relative path", table: "Common"), text: normalizedPath)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
    }

    private var assetActionButtons: some View {
        AutomationWorkflowDraftVisualAssetActionButtonsView(
            hasSourceDirectory: sourceDirectory != nil,
            isImportingAsset: isImportingAsset,
            isCapturingBaseline: isCapturingBaseline,
            canRegister: canRegister,
            onChoosePackage: choosePackageFile,
            onImportExternalAsset: importExternalAsset,
            onCaptureBaseline: captureBaseline,
            onRegisterAsset: registerAsset
        )
    }

    @ViewBuilder
    private var assetList: some View {
        let rows = visibleAssetRows
        if rows.isEmpty {
            Label(String(localized: "No package image or baseline assets registered", table: "Common"), systemImage: "photo.on.rectangle.angled")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.caption)
                                .bold()
                                .lineLimit(1)
                            Text(row.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !row.provenance.isEmpty {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 4) {
                                        ForEach(row.provenance, id: \.self) { label in
                                            provenanceBadge(label)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(row.provenance, id: \.self) { label in
                                            provenanceBadge(label)
                                        }
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(row.kind)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.6)
                            )
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func assetSummary(title: String, count: Int, systemImage: String) -> some View {
        Label("\(title) \(count)", systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
            )
    }

    private func provenanceBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
            )
    }

    private var visualAssets: AutomationWorkflowDraftVisualAssets {
        document.visualAssets ?? AutomationWorkflowDraftVisualAssets()
    }

    private var assetCount: Int {
        visualAssets.images.count + visualAssets.baselines.count
    }

    private var packageRootLabel: String {
        sourceDirectory?.lastPathComponent ?? String(localized: "Open a draft file to choose package assets", table: "Common")
    }

    private var normalizedKey: Binding<String> {
        Binding(
            get: { key },
            set: { key = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private var normalizedLabel: Binding<String> {
        Binding(
            get: { label },
            set: { label = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private var normalizedPath: Binding<String> {
        Binding(
            get: { packagePath },
            set: { packagePath = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private var canRegister: Bool {
        !key.isEmpty && normalizedPackagePath != nil
    }

    private var normalizedPackagePath: String? {
        AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(packagePath)
    }

    private var messageImage: String {
        messageIsWarning ? "exclamationmark.triangle" : "info.circle"
    }

    private var messageTint: Color {
        messageIsWarning ? Brand.sigAmber : .secondary
    }

    private var visibleAssetRows: [VisibleAssetRow] {
        let imageRows = visualAssets.images.map { asset in
            visibleAssetRow(
                asset,
                idPrefix: "image",
                systemImage: "photo",
                kind: String(localized: "Image", table: "Common")
            )
        }
        let baselineRows = visualAssets.baselines.map { asset in
            visibleAssetRow(
                asset,
                idPrefix: "baseline",
                systemImage: "rectangle.dashed",
                kind: String(localized: "Baseline", table: "Common")
            )
        }
        return Array((imageRows + baselineRows).prefix(6))
    }

    private func visibleAssetRow(
        _ asset: AutomationWorkflowDraftVisualImageAsset,
        idPrefix: String,
        systemImage: String,
        kind: String
    ) -> VisibleAssetRow {
        VisibleAssetRow(
            id: "\(idPrefix)-\(asset.key)",
            systemImage: systemImage,
            title: asset.label ?? asset.key,
            path: asset.path ?? String(localized: "No path", table: "Common"),
            kind: kind,
            provenance: provenanceLabels(for: asset)
        )
    }

    private func provenanceLabels(for asset: AutomationWorkflowDraftVisualImageAsset) -> [String] {
        var labels: [String] = []
        if let sourceFrameID = asset.sourceFrameID {
            labels.append(
                String(
                    format: String(localized: "Frame %@", table: "Common"),
                    shortID(sourceFrameID.uuidString)
                )
            )
        }
        if let sourceBounds = asset.sourceBounds {
            labels.append(boundsLabel(sourceBounds, space: asset.sourceBoundsSpace))
        }
        if let sourceArtifactPath = asset.sourceArtifactPath {
            labels.append(
                String(
                    format: String(localized: "Source %@", table: "Common"),
                    compactPath(sourceArtifactPath)
                )
            )
        }
        if let sourceSurfaceID = asset.sourceSurfaceID {
            labels.append(
                String(
                    format: String(localized: "Surface %@", table: "Common"),
                    shortID(sourceSurfaceID)
                )
            )
        }
        if let sha256 = asset.sha256 {
            labels.append(
                String(
                    format: String(localized: "SHA %@", table: "Common"),
                    shortID(sha256)
                )
            )
        }
        return labels
    }

    private func boundsLabel(
        _ bounds: RectValue,
        space: AutomationOCRSearchRegionSpace?
    ) -> String {
        let boundsText = "\(formatNumber(bounds.x)),\(formatNumber(bounds.y)) \(formatNumber(bounds.width))x\(formatNumber(bounds.height))"
        guard let space else {
            return boundsText
        }
        return "\(space.rawValue) \(boundsText)"
    }

    private func compactPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 2 else {
            return path
        }
        return parts.suffix(2).joined(separator: "/")
    }

    private func shortID(_ value: String) -> String {
        String(value.prefix(8))
    }

    private func formatNumber(_ value: CGFloat) -> String {
        let doubleValue = Double(value)
        let roundedValue = doubleValue.rounded()
        if abs(doubleValue - roundedValue) < 0.01 {
            return String(Int(roundedValue))
        }
        return String(format: "%.3f", doubleValue)
    }

    private func choosePackageFile() {
        guard let sourceDirectory else {
            message = String(localized: "Open a draft from disk before choosing package files.", table: "Common")
            messageIsWarning = true
            return
        }

        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Package Visual Asset", table: "Common")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = sourceDirectory
        panel.allowedContentTypes = [.image]

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            guard let relativePath = relativePath(for: url, under: sourceDirectory),
                  let normalized = AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(relativePath) else {
                message = String(localized: "Choose an image inside the draft package folder.", table: "Common")
                messageIsWarning = true
                return
            }

            packagePath = normalized
            if key.isEmpty {
                key = defaultKey(from: url)
            }
            if label.isEmpty {
                label = url.deletingPathExtension().lastPathComponent
            }
            message = String(
                format: String(localized: "Selected package asset %@", table: "Common"),
                normalized
            )
            messageIsWarning = false
        }
    }

    private func registerAsset() {
        guard let normalizedPackagePath else {
            message = String(localized: "Use a safe package-relative path such as assets/icon.png.", table: "Common")
            messageIsWarning = true
            return
        }

        let asset = AutomationWorkflowDraftVisualImageAsset(
            key: key,
            label: label.isEmpty ? nil : label,
            path: normalizedPackagePath
        )
        onRegisterAsset(assetKind, asset)
        message = String(
            format: String(localized: "Registered %@ %@", table: "Common"),
            assetKind == Self.baselineKind ? String(localized: "baseline", table: "Common") : String(localized: "image", table: "Common"),
            key
        )
        messageIsWarning = false
    }

    private func importExternalAsset() {
        guard let sourceDirectory else {
            message = String(localized: "Open a draft from disk before importing visual assets.", table: "Common")
            messageIsWarning = true
            return
        }

        let registrationKind = assetKind
        let importKind = registrationKind == Self.baselineKind
            ? AutomationWorkflowDraftVisualAssetImportKind.baseline
            : .image
        isImportingAsset = true
        message = String(localized: "Choose an image to copy into this draft package.", table: "Common")
        messageIsWarning = false
        AutomationWorkflowDraftVisualAssetImportPresenter.importAsset(
            kind: importKind,
            packageDirectory: sourceDirectory,
            preferredKey: key,
            preferredLabel: label,
            onImported: { result in
                isImportingAsset = false
                key = result.asset.key
                label = result.asset.label ?? ""
                packagePath = result.relativePath
                onRegisterAsset(registrationKind, result.asset)
                message = String(
                    format: String(localized: "Imported asset %@", table: "Common"),
                    result.relativePath
                )
                messageIsWarning = false
            },
            onCancelled: {
                isImportingAsset = false
                message = ""
                messageIsWarning = false
            },
            onError: { errorMessage in
                isImportingAsset = false
                message = errorMessage
                messageIsWarning = true
            }
        )
    }

    private func captureBaseline() {
        guard let sourceDirectory else {
            message = String(localized: "Open a draft from disk before capturing a baseline.", table: "Common")
            messageIsWarning = true
            return
        }

        assetKind = Self.baselineKind
        isCapturingBaseline = true
        message = String(localized: "Draw a screen region to capture as a package baseline.", table: "Common")
        messageIsWarning = false
        AutomationWorkflowDraftBaselineCapturePresenter.captureBaseline(
            packageDirectory: sourceDirectory,
            preferredKey: key,
            preferredLabel: label,
            onCaptured: { result in
                isCapturingBaseline = false
                key = result.asset.key
                label = result.asset.label ?? ""
                packagePath = result.relativePath
                onRegisterAsset(Self.baselineKind, result.asset)
                message = String(
                    format: String(localized: "Captured baseline %@", table: "Common"),
                    result.relativePath
                )
                messageIsWarning = false
            },
            onError: { errorMessage in
                isCapturingBaseline = false
                message = errorMessage
                messageIsWarning = true
            }
        )
    }

    private func relativePath(for fileURL: URL, under rootURL: URL) -> String? {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else {
            return nil
        }
        guard zip(rootComponents, fileComponents).allSatisfy({ $0.0 == $0.1 }) else {
            return nil
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func defaultKey(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
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
    }

    private static let imageKind = "image"
    private static let baselineKind = "baseline"
}

private struct VisibleAssetRow: Identifiable {
    var id: String
    var systemImage: String
    var title: String
    var path: String
    var kind: String
    var provenance: [String]
}
