import Foundation
import SparkleRecorderCore

struct AutomationVisualAssetPackageRootAssociation: Sendable {
    struct Request: Sendable {
        var workflow: AutomationWorkflow
        var packageDirectoryURL: URL?
        var source: AutomationVisualAssetPackageRootSource

        init(
            workflow: AutomationWorkflow,
            packageDirectoryURL: URL?,
            source: AutomationVisualAssetPackageRootSource
        ) {
            self.workflow = workflow
            self.packageDirectoryURL = packageDirectoryURL
            self.source = source
        }
    }

    private let client: AutomationVisualAssetPackageRootClient

    init(client: AutomationVisualAssetPackageRootClient) {
        self.client = client
    }

    static func fileBacked() -> AutomationVisualAssetPackageRootAssociation {
        AutomationVisualAssetPackageRootAssociation(client: .fileBacked())
    }

    static func inMemory() -> AutomationVisualAssetPackageRootAssociation {
        AutomationVisualAssetPackageRootAssociation(client: .inMemory())
    }

    func persist(
        _ requests: [Request],
        associatedAt: Date = .now
    ) async throws {
        guard !requests.isEmpty else {
            return
        }

        let roots = requests.flatMap { request -> [AutomationVisualAssetPackageRoot] in
            guard let packageDirectoryURL = request.packageDirectoryURL else {
                return []
            }
            return AutomationVisualAssetPackageRoot.roots(
                for: [request.workflow],
                packageDirectoryURL: packageDirectoryURL,
                source: request.source,
                associatedAt: associatedAt
            )
        }

        let requestedWorkflowIDs = Set(requests.map(\.workflow.id))
        let rootedWorkflowIDs = Set(roots.map(\.workflowID))
        let unrootedWorkflowIDs = requestedWorkflowIDs.subtracting(rootedWorkflowIDs)

        if !roots.isEmpty {
            try await client.upsertRoots(roots)
        }
        if !unrootedWorkflowIDs.isEmpty {
            try await client.removeRoots(unrootedWorkflowIDs)
        }
    }
}
