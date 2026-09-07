import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Workflow Package Import Conflict Tests")
struct AutomationWorkflowPackageImportConflictTests {
    @Test("Current workflow conflicts are detected from the import-time workflow set")
    func detectsCurrentWorkflowConflict() {
        let existing = AutomationWorkflow(name: "Created while panel was open")
        var imported = existing
        imported.name = "Imported replacement"
        let item = AutomationWorkflowPackageImportItem(
            workflow: imported,
            packageDirectoryURL: URL(fileURLWithPath: "/tmp/package-a")
        )

        let plan = AutomationWorkflowPackageImportConflictPlan.make(
            importItems: [item],
            currentWorkflows: [existing]
        )

        #expect(plan.requiresResolution)
        #expect(plan.currentWorkflowIDs == [existing.id])
        #expect(plan.duplicateImportedIDs.isEmpty)
    }

    @Test("Duplicate IDs inside one package require conflict resolution")
    func detectsDuplicateImportedIDs() {
        let workflow = AutomationWorkflow(name: "Repeated")
        let first = AutomationWorkflowPackageImportItem(
            workflow: workflow,
            packageDirectoryURL: URL(fileURLWithPath: "/tmp/package-a")
        )
        let second = AutomationWorkflowPackageImportItem(
            workflow: workflow,
            packageDirectoryURL: URL(fileURLWithPath: "/tmp/package-b")
        )

        let plan = AutomationWorkflowPackageImportConflictPlan.make(
            importItems: [first, second],
            currentWorkflows: []
        )

        #expect(plan.requiresResolution)
        #expect(plan.duplicateImportedIDs == [workflow.id])
    }

    @Test("Add Copies preserves non-conflicts and copies only colliding workflow identities")
    func copiesOnlyConflicts() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let existing = AutomationWorkflow(name: "Existing")
        var colliding = existing
        colliding.name = "Imported existing"
        let untouched = AutomationWorkflow(name: "Untouched")
        let collidingDirectory = URL(fileURLWithPath: "/tmp/colliding")
        let untouchedDirectory = URL(fileURLWithPath: "/tmp/untouched")
        let items = [
            AutomationWorkflowPackageImportItem(
                workflow: colliding,
                packageDirectoryURL: collidingDirectory
            ),
            AutomationWorkflowPackageImportItem(
                workflow: untouched,
                packageDirectoryURL: untouchedDirectory
            )
        ]
        let copiedID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let plan = AutomationWorkflowPackageImportConflictPlan.make(
            importItems: items,
            currentWorkflows: [existing]
        )

        let result = plan.addingCopies(items, now: now, makeID: { copiedID })

        let copied = try #require(result.first)
        #expect(copied.workflow.id == copiedID)
        #expect(copied.workflow.name == "Imported existing Copy")
        #expect(copied.workflow.createdAt == now)
        #expect(copied.workflow.modifiedAt == now)
        #expect(copied.packageDirectoryURL == collidingDirectory)

        let preserved = try #require(result.last)
        #expect(preserved.workflow == untouched)
        #expect(preserved.packageDirectoryURL == untouchedDirectory)
    }

    @Test("Import without existing or duplicate IDs needs no resolution")
    func noConflictNeedsNoResolution() {
        let workflow = AutomationWorkflow(name: "New")
        let item = AutomationWorkflowPackageImportItem(
            workflow: workflow,
            packageDirectoryURL: URL(fileURLWithPath: "/tmp/new")
        )

        let plan = AutomationWorkflowPackageImportConflictPlan.make(
            importItems: [item],
            currentWorkflows: []
        )

        #expect(!plan.requiresResolution)
        #expect(plan.currentWorkflowIDs.isEmpty)
        #expect(plan.duplicateImportedIDs.isEmpty)
    }
}
