import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Visual Asset Package Root Association Tests")
struct AutomationVisualAssetPackageRootAssociationTests {
    @Test("Persists roots for workflows with package file assets")
    func persistsRootsForPackageAssets() async throws {
        let store = AutomationInMemoryVisualAssetPackageRootStore()
        let association = AutomationVisualAssetPackageRootAssociation(
            client: .inMemory(store: store)
        )
        let workflow = workflowWithPackageAsset()
        let directory = URL(fileURLWithPath: "/tmp/workflow-package", isDirectory: true)
        let associatedAt = Date(timeIntervalSince1970: 123)

        try await association.persist(
            [
                .init(
                    workflow: workflow,
                    packageDirectoryURL: directory,
                    source: .aiDraftImport
                )
            ],
            associatedAt: associatedAt
        )

        let roots = await store.loadRoots()
        #expect(roots == [
            AutomationVisualAssetPackageRoot(
                workflowID: workflow.id,
                packageDirectoryPath: directory.standardizedFileURL.path,
                source: .aiDraftImport,
                associatedAt: associatedAt
            )
        ])
    }

    @Test("Removes stale roots when a workflow no longer has package file assets")
    func removesStaleRootsForUnrootedWorkflow() async throws {
        let workflowID = UUID()
        let existing = AutomationVisualAssetPackageRoot(
            workflowID: workflowID,
            packageDirectoryPath: "/tmp/old-package",
            source: .workflowPackageImport,
            associatedAt: Date(timeIntervalSince1970: 10)
        )
        let store = AutomationInMemoryVisualAssetPackageRootStore(roots: [existing])
        let association = AutomationVisualAssetPackageRootAssociation(
            client: .inMemory(store: store)
        )
        let workflow = AutomationWorkflow(id: workflowID, name: "No assets")

        try await association.persist([
            .init(
                workflow: workflow,
                packageDirectoryURL: URL(fileURLWithPath: "/tmp/new-package", isDirectory: true),
                source: .workflowPackageImport
            )
        ])

        #expect(await store.loadRoots().isEmpty)
    }

    @Test("Batch association keeps rooted workflows while clearing unrooted workflows")
    func batchesRootedAndUnrootedWorkflows() async throws {
        let rooted = workflowWithPackageAsset()
        let unrooted = AutomationWorkflow(name: "No assets")
        let store = AutomationInMemoryVisualAssetPackageRootStore(
            roots: [
                AutomationVisualAssetPackageRoot(
                    workflowID: unrooted.id,
                    packageDirectoryPath: "/tmp/stale",
                    source: .manual
                )
            ]
        )
        let association = AutomationVisualAssetPackageRootAssociation(
            client: .inMemory(store: store)
        )
        let directory = URL(fileURLWithPath: "/tmp/batch-package", isDirectory: true)

        try await association.persist([
            .init(
                workflow: rooted,
                packageDirectoryURL: directory,
                source: .workflowPackageImport
            ),
            .init(
                workflow: unrooted,
                packageDirectoryURL: nil,
                source: .workflowPackageImport
            )
        ])

        let roots = await store.loadRoots()
        #expect(roots.count == 1)
        #expect(roots.first?.workflowID == rooted.id)
        #expect(roots.first?.packageDirectoryPath == directory.standardizedFileURL.path)
    }

    private func workflowWithPackageAsset() -> AutomationWorkflow {
        AutomationWorkflow(
            name: "Visual workflow",
            visualAssets: AutomationWorkflowDraftVisualAssets(
                images: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "ready",
                        path: "assets/ready.png"
                    )
                ]
            )
        )
    }
}
