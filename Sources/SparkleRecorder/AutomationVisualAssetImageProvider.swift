import CoreGraphics
import Foundation
import ImageIO
import SparkleRecorderCore

struct AutomationVisualAssetWorkflowPackage: Sendable {
    var workflowID: UUID
    var visualAssets: AutomationWorkflowDraftVisualAssets?
    var packageDirectory: URL

    init(
        workflowID: UUID,
        visualAssets: AutomationWorkflowDraftVisualAssets?,
        packageDirectory: URL
    ) {
        self.workflowID = workflowID
        self.visualAssets = visualAssets
        self.packageDirectory = packageDirectory
    }
}

extension AutomationVisualAssetWorkflowPackage {
    static func packages(
        workflows: [AutomationWorkflow],
        roots: [AutomationVisualAssetPackageRoot]
    ) -> [AutomationVisualAssetWorkflowPackage] {
        let workflowsByID = Dictionary(uniqueKeysWithValues: workflows.map { ($0.id, $0) })
        return roots.compactMap { root in
            guard let workflow = workflowsByID[root.workflowID],
                  workflow.visualAssets?.hasPackageFileAssets == true else {
                return nil
            }
            return AutomationVisualAssetWorkflowPackage(
                workflowID: root.workflowID,
                visualAssets: workflow.visualAssets,
                packageDirectory: root.packageDirectoryURL
            )
        }
    }
}

struct AutomationVisualAssetImageProviders: Sendable {
    var imageProvider: AutomationVisualImageProvider
    var baselineProvider: AutomationVisualImageProvider

    static func draftPackage(
        visualAssets: AutomationWorkflowDraftVisualAssets?,
        packageDirectory: URL
    ) -> AutomationVisualAssetImageProviders {
        let package = AutomationVisualAssetWorkflowPackage(
            workflowID: UUID(),
            visualAssets: visualAssets,
            packageDirectory: packageDirectory
        )
        return AutomationVisualAssetImageProviders(
            imageProvider: provider(
                kind: .image,
                packages: [package],
                scope: .anyWorkflow
            ),
            baselineProvider: provider(
                kind: .baseline,
                packages: [package],
                scope: .anyWorkflow
            )
        )
    }

    static func workflowPackage(
        workflowID: UUID,
        visualAssets: AutomationWorkflowDraftVisualAssets?,
        packageDirectory: URL
    ) -> AutomationVisualAssetImageProviders {
        workflowPackages([
            AutomationVisualAssetWorkflowPackage(
                workflowID: workflowID,
                visualAssets: visualAssets,
                packageDirectory: packageDirectory
            )
        ])
    }

    static func workflowPackages(
        _ packages: [AutomationVisualAssetWorkflowPackage]
    ) -> AutomationVisualAssetImageProviders {
        AutomationVisualAssetImageProviders(
            imageProvider: provider(kind: .image, packages: packages, scope: .matchingWorkflow),
            baselineProvider: provider(kind: .baseline, packages: packages, scope: .matchingWorkflow)
        )
    }

    static func workflowPackageRoots(
        loadPackages: @escaping @Sendable () async -> [AutomationVisualAssetWorkflowPackage]
    ) -> AutomationVisualAssetImageProviders {
        AutomationVisualAssetImageProviders(
            imageProvider: dynamicProvider(kind: .image, loadPackages: loadPackages),
            baselineProvider: dynamicProvider(kind: .baseline, loadPackages: loadPackages)
        )
    }

    private enum AssetKind: Sendable {
        case image
        case baseline
    }

    private enum ProviderScope: Sendable {
        case anyWorkflow
        case matchingWorkflow

        func includes(
            _ package: AutomationVisualAssetWorkflowPackage,
            request: AutomationConditionEvaluationRequest
        ) -> Bool {
            switch self {
            case .anyWorkflow:
                return true
            case .matchingWorkflow:
                return package.workflowID == request.workflowID
            }
        }
    }

    private static func provider(
        kind: AssetKind,
        packages: [AutomationVisualAssetWorkflowPackage],
        scope: ProviderScope
    ) -> AutomationVisualImageProvider {
        let normalizedPackages = packages.map { package in
            AutomationVisualAssetWorkflowPackage(
                workflowID: package.workflowID,
                visualAssets: package.visualAssets,
                packageDirectory: package.packageDirectory.standardizedFileURL
            )
        }
        return { request, reference in
            for package in normalizedPackages where scope.includes(package, request: request) {
                guard package.packageDirectory.isFileURL,
                      let relativePath = relativePath(
                        for: reference,
                        kind: kind,
                        visualAssets: package.visualAssets
                      ) else {
                    continue
                }

                let url = package.packageDirectory
                    .appendingPathComponent(relativePath, isDirectory: false)
                    .standardizedFileURL
                if let image = loadImage(at: url) {
                    return image
                }
            }
            return nil
        }
    }

    private static func dynamicProvider(
        kind: AssetKind,
        loadPackages: @escaping @Sendable () async -> [AutomationVisualAssetWorkflowPackage]
    ) -> AutomationVisualImageProvider {
        { request, reference in
            let packages = await loadPackages()
            return try await provider(
                kind: kind,
                packages: packages,
                scope: .matchingWorkflow
            )(request, reference)
        }
    }

    private static func relativePath(
        for reference: String,
        kind: AssetKind,
        visualAssets: AutomationWorkflowDraftVisualAssets?
    ) -> String? {
        switch kind {
        case .image:
            return visualAssets?.imagePath(for: reference)
        case .baseline:
            return visualAssets?.baselinePath(for: reference)
        }
    }

    private static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
