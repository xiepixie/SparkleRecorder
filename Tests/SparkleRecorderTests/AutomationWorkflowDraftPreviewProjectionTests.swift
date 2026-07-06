import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Workflow Draft Preview Projection Tests")
struct AutomationWorkflowDraftPreviewProjectionTests {
    @Test("Preview projection resolves macro tasks and validation warnings")
    func previewProjectionResolvesMacroTasksAndValidationWarnings() throws {
        let macroID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Preview",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "tap",
                    type: "macro",
                    macroRef: AutomationWorkflowDraftMacroRef(name: "Tap")
                ),
                AutomationWorkflowDraftTask(
                    key: "wait_done",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(type: "ocrText", text: "Done"),
                    timeoutSeconds: 30
                )
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(from: "tap", to: "wait_done", trigger: "success")
            ]
        ))
        let catalog = [
            AutomationWorkflowDraftMacroCatalogEntry(
                id: macroID,
                name: "Tap",
                durationSeconds: 1
            )
        ]
        let result = AutomationWorkflowDraftValidator.validate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog)
        )
        let simulation = AutomationWorkflowDraftSimulator.simulate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog)
        )
        let importResult = AutomationWorkflowDraftImporter.dryRun(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog)
        )

        let projection = AutomationWorkflowDraftPreviewProjection(
            document: document,
            validationEnvelope: .workflowDraftValidation(command: "workflow draft validate", result: result),
            macroCatalogEnvelope: .workflowMacroCatalog(command: "workflow macros", macros: catalog),
            simulationEnvelope: .workflowDraftSimulation(command: "workflow draft simulate", result: simulation),
            importEnvelope: .workflowDraftImport(command: "workflow import --dry-run", result: importResult)
        )

        #expect(projection.workflowName == "Preview")
        #expect(projection.isReadyForImport)
        #expect(projection.statusLabel == "Dry-run passed")
        #expect(projection.taskRows.count == 2)
        #expect(projection.dependencyRows.first?.triggerLabel == "Success")
        #expect(projection.simulationRows.map(\.taskKey) == ["tap", "wait_done"])
        #expect(projection.resourceRows.first?.taskKey == "tap")
        #expect(projection.branchRows.first?.fired == true)
        #expect(projection.issueRows.contains { $0.code == AutomationWorkflowDraftIssueCode.missingTimeoutBranch.rawValue })
        #expect(projection.nextActionRows.contains { $0.reason.contains("timeout branch") })

        let macroRow = try #require(projection.taskRows.first)
        #expect(macroRow.macroResolution == .resolved(name: "Tap", id: macroID))

        let importPreview = try #require(projection.importPreview)
        #expect(importPreview.isImportable)
        #expect(importPreview.workflowName == "Preview")
        #expect(importPreview.taskCount == 2)
        #expect(importPreview.dependencyCount == 1)
        #expect(importPreview.taskIDRows.map(\.key) == ["tap", "wait_done"])
        #expect(importPreview.dependencyIDRows.map(\.key) == ["tap->wait_done:success"])
        #expect(importPreview.macroResolutionRows.first?.taskKey == "tap")
        #expect(importPreview.macroResolutionRows.first?.sourceLabel == "Matched by catalog name")
        #expect(projection.nextActionRows.contains { $0.command.contains("workflow import") })
    }

    @Test("Preview projection marks ambiguous macro names")
    func previewProjectionMarksAmbiguousMacroNames() throws {
        let firstID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Ambiguous",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "tap",
                    type: "macro",
                    macroRef: AutomationWorkflowDraftMacroRef(name: "Tap")
                )
            ]
        ))
        let catalog = [
            AutomationWorkflowDraftMacroCatalogEntry(id: firstID, name: "Tap"),
            AutomationWorkflowDraftMacroCatalogEntry(id: secondID, name: "Tap")
        ]
        let result = AutomationWorkflowDraftValidator.validate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog)
        )

        let projection = AutomationWorkflowDraftPreviewProjection(
            document: document,
            validationEnvelope: .workflowDraftValidation(command: "workflow draft validate", result: result),
            macroCatalogEnvelope: .workflowMacroCatalog(command: "workflow macros", macros: catalog)
        )

        let macroRow = try #require(projection.taskRows.first)
        #expect(projection.isValid == false)
        #expect(macroRow.macroResolution == .ambiguous(reference: "Tap", candidateCount: 2))
        #expect(projection.issueRows.contains {
            $0.severity == .error &&
            $0.code == AutomationWorkflowDraftIssueCode.ambiguousMacroRef.rawValue &&
            $0.candidateCount == 2
        })
    }

    @Test("Preview projection shows visual dry-run warnings")
    func previewProjectionShowsVisualDryRunWarnings() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Visual Watch",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "watch",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(
                        type: "regionChanged",
                        regionRef: "battle_result_area"
                    ),
                    timeoutSeconds: 30
                )
            ]
        ))
        let validation = AutomationWorkflowDraftValidator.validate(document)
        let importResult = AutomationWorkflowDraftImporter.dryRun(document)

        let projection = AutomationWorkflowDraftPreviewProjection(
            document: document,
            validationEnvelope: .workflowDraftValidation(command: "workflow draft validate", result: validation),
            macroCatalogEnvelope: .workflowMacroCatalog(command: "workflow macros", macros: []),
            importEnvelope: .workflowDraftImport(command: "workflow import --dry-run", result: importResult)
        )

        let importPreview = try #require(projection.importPreview)
        #expect(projection.isValid)
        #expect(projection.isReadyForImport)
        #expect(projection.statusLabel == "Dry-run passed")
        #expect(importPreview.workflowName == "Visual Watch")
        #expect(importPreview.taskIDRows.map(\.key) == ["watch"])
        #expect(importPreview.issueRows.contains {
            $0.severity == .warning &&
            $0.code == AutomationWorkflowDraftIssueCode.unresolvedRegionRef.rawValue &&
            $0.subject == "watch"
        })
    }

    @Test("Preview projection exposes fixed loop draft and expanded import")
    func previewProjectionExposesFixedLoopDraftAndExpandedImport() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Loop Preview",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "repeat_checkout",
                    type: "loop",
                    loop: AutomationWorkflowDraftLoop(
                        count: 2,
                        tasks: [
                            AutomationWorkflowDraftTask(key: "tap", type: "delay", delaySeconds: 1),
                            AutomationWorkflowDraftTask(
                                key: "wait_text",
                                type: "condition",
                                condition: AutomationWorkflowDraftCondition(type: "ocrText", text: "Done")
                            )
                        ]
                    )
                )
            ]
        ))
        let validation = AutomationWorkflowDraftValidator.validate(document)
        let simulation = AutomationWorkflowDraftSimulator.simulate(document)
        let importResult = AutomationWorkflowDraftImporter.dryRun(document)

        let projection = AutomationWorkflowDraftPreviewProjection(
            document: document,
            validationEnvelope: .workflowDraftValidation(command: "workflow draft validate", result: validation),
            macroCatalogEnvelope: .workflowMacroCatalog(command: "workflow macros", macros: []),
            simulationEnvelope: .workflowDraftSimulation(command: "workflow draft simulate", result: simulation),
            importEnvelope: .workflowDraftImport(command: "workflow import --dry-run", result: importResult)
        )

        let loopRow = try #require(projection.taskRows.first)
        let importPreview = try #require(projection.importPreview)

        #expect(projection.isValid)
        #expect(projection.isReadyForImport)
        #expect(loopRow.key == "repeat_checkout")
        #expect(loopRow.typeLabel == "Loop")
        #expect(loopRow.detail == "Repeats 2 times, 2 steps")
        #expect(projection.simulationRows.map(\.taskKey) == [
            "repeat_checkout__1__tap",
            "repeat_checkout__1__wait_text",
            "repeat_checkout__2__tap",
            "repeat_checkout__2__wait_text"
        ])
        #expect(importPreview.taskIDRows.map(\.key) == [
            "repeat_checkout__1__tap",
            "repeat_checkout__1__wait_text",
            "repeat_checkout__2__tap",
            "repeat_checkout__2__wait_text"
        ])
        #expect(importPreview.dependencyIDRows.map(\.key) == [
            "repeat_checkout__1__tap->repeat_checkout__1__wait_text:success",
            "repeat_checkout__1__wait_text->repeat_checkout__2__tap:conditionMatched",
            "repeat_checkout__2__tap->repeat_checkout__2__wait_text:success"
        ])
    }
}
