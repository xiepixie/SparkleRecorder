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

    @Test("Preview projection exposes visual asset provenance and thresholds")
    func previewProjectionExposesVisualAssetProvenanceAndThresholds() throws {
        let imageFrameID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
        let baselineFrameID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Visual Evidence",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "watch_image",
                        type: "condition",
                        condition: AutomationWorkflowDraftCondition(
                            type: "imageAppeared",
                            regionRef: "checkout_area",
                            imageRef: "checkout_template",
                            threshold: 0.88
                        )
                    ),
                    AutomationWorkflowDraftTask(
                        key: "watch_baseline",
                        type: "condition",
                        condition: AutomationWorkflowDraftCondition(
                            type: "regionChanged",
                            regionRef: "status_area",
                            baselineRef: "status_baseline",
                            threshold: 0.74
                        )
                    ),
                    AutomationWorkflowDraftTask(
                        key: "repeat_until_pixel",
                        type: "loop",
                        loop: AutomationWorkflowDraftLoop(
                            count: 1,
                            tasks: [
                                AutomationWorkflowDraftTask(
                                    key: "retry",
                                    type: "delay",
                                    delaySeconds: 0.2
                                )
                            ],
                            kind: AutomationWorkflowDraftLoopKind.repeatUntil,
                            until: AutomationWorkflowDraftCondition(
                                type: "pixelMatched",
                                regionRef: "status_pixel",
                                colorHex: "#FFFFFF",
                                threshold: 0.96
                            )
                        )
                    )
                ]
            ),
            visualAssets: AutomationWorkflowDraftVisualAssets(
                regions: [
                    AutomationWorkflowDraftVisualRegion(
                        key: "checkout_area",
                        label: "Checkout button",
                        bounds: RectValue(x: 10, y: 20, width: 120, height: 48),
                        space: .windowLocal
                    ),
                    AutomationWorkflowDraftVisualRegion(
                        key: "status_area",
                        bounds: RectValue(x: 200, y: 40, width: 160, height: 60),
                        space: .displayAbsolute
                    ),
                    AutomationWorkflowDraftVisualRegion(
                        key: "status_pixel",
                        bounds: RectValue(x: 0.45, y: 0.52, width: 0.02, height: 0.02),
                        space: .displayNormalized
                    )
                ],
                images: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "checkout_template",
                        path: "assets/images/checkout.png",
                        sha256: "abc123template",
                        sourceFrameID: imageFrameID,
                        sourceSurfaceID: "window:checkout",
                        sourceArtifactPath: "frames/000014-before-click.png",
                        sourceBounds: RectValue(x: 880, y: 620, width: 180, height: 48),
                        sourceBoundsSpace: .windowLocal
                    )
                ],
                baselines: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "status_baseline",
                        path: "assets/baselines/status.png",
                        sha256: "def456baseline",
                        sourceFrameID: baselineFrameID,
                        sourceSurfaceID: "window:checkout",
                        sourceArtifactPath: "frames/000018-after-click.png",
                        sourceBounds: RectValue(x: 200, y: 40, width: 160, height: 60),
                        sourceBoundsSpace: .displayAbsolute
                    )
                ]
            )
        )
        let validation = AutomationWorkflowDraftValidator.validate(document)

        let projection = AutomationWorkflowDraftPreviewProjection(
            document: document,
            validationEnvelope: .workflowDraftValidation(command: "workflow draft validate", result: validation),
            macroCatalogEnvelope: .workflowMacroCatalog(command: "workflow macros", macros: [])
        )

        #expect(projection.visualAssetRows.count == 3)

        let imageRow = try #require(projection.visualAssetRows.first { $0.assetKind == .imageTemplate })
        #expect(imageRow.taskKey == "watch_image")
        #expect(imageRow.roleLabel == "Task condition")
        #expect(imageRow.conditionLabel == "image appears")
        #expect(imageRow.assetKey == "checkout_template")
        #expect(imageRow.assetPath == "assets/images/checkout.png")
        #expect(imageRow.sha256 == "abc123template")
        #expect(imageRow.sourceFrameID == imageFrameID)
        #expect(imageRow.sourceFrameShortID == "70000000")
        #expect(imageRow.sourceSurfaceID == "window:checkout")
        #expect(imageRow.sourceArtifactPath == "frames/000014-before-click.png")
        #expect(imageRow.sourceBounds == RectValue(x: 880, y: 620, width: 180, height: 48))
        #expect(imageRow.sourceBoundsLabel == "x 880.0, y 620.0, w 180.0, h 48.0")
        #expect(imageRow.sourceBoundsSpace == .windowLocal)
        #expect(imageRow.sourceBoundsSpaceLabel == "Window local")
        #expect(imageRow.regionKey == "checkout_area")
        #expect(imageRow.regionLabel == "Checkout button")
        #expect(imageRow.regionBounds == RectValue(x: 10, y: 20, width: 120, height: 48))
        #expect(imageRow.regionBoundsLabel == "x 10.0, y 20.0, w 120.0, h 48.0")
        #expect(imageRow.regionSpace == .windowLocal)
        #expect(imageRow.regionSpaceLabel == "Window local")
        #expect(imageRow.threshold == 0.88)
        #expect(imageRow.thresholdLabel == "0.88 threshold")

        let baselineRow = try #require(projection.visualAssetRows.first { $0.assetKind == .baseline })
        #expect(baselineRow.taskKey == "watch_baseline")
        #expect(baselineRow.conditionLabel == "region changes")
        #expect(baselineRow.assetKey == "status_baseline")
        #expect(baselineRow.assetPath == "assets/baselines/status.png")
        #expect(baselineRow.sourceFrameID == baselineFrameID)
        #expect(baselineRow.sourceBoundsSpace == .displayAbsolute)
        #expect(baselineRow.regionKey == "status_area")
        #expect(baselineRow.regionBounds == RectValue(x: 200, y: 40, width: 160, height: 60))
        #expect(baselineRow.threshold == 0.74)

        let pixelRow = try #require(projection.visualAssetRows.first { $0.assetKind == .pixelSample })
        #expect(pixelRow.taskKey == "repeat_until_pixel")
        #expect(pixelRow.roleLabel == "Loop until")
        #expect(pixelRow.conditionLabel == "pixel matches #FFFFFF")
        #expect(pixelRow.assetKey == nil)
        #expect(pixelRow.sourceFrameID == nil)
        #expect(pixelRow.regionKey == "status_pixel")
        #expect(pixelRow.regionSpace == .displayNormalized)
        #expect(pixelRow.thresholdLabel == "0.96 threshold")
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
        let loopExpansionRow = try #require(projection.loopExpansionRows.first)
        let importPreview = try #require(projection.importPreview)

        #expect(projection.isValid)
        #expect(projection.isReadyForImport)
        #expect(loopRow.key == "repeat_checkout")
        #expect(loopRow.typeLabel == "Loop")
        #expect(loopRow.modeLabel == "Fixed count")
        #expect(loopRow.detail == "Repeats 2 times, 2 steps")
        #expect(loopExpansionRow.key == "repeat_checkout")
        #expect(loopExpansionRow.repeatCount == 2)
        #expect(loopExpansionRow.bodyStepCount == 2)
        #expect(loopExpansionRow.expandedTaskCount == 4)
        #expect(loopExpansionRow.summary == "Expands to 4 imported steps")
        #expect(loopExpansionRow.importBoundaryLabel == "Draft-only loop; imported workflow stays acyclic")
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

    @Test("Preview projection exposes repeat-until as draft-only loop intent")
    func previewProjectionExposesRepeatUntilAsDraftOnlyLoopIntent() throws {
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Repeat Until Preview",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "repeat_until_spinner",
                        type: "loop",
                        loop: AutomationWorkflowDraftLoop(
                            count: 1,
                            tasks: [
                                AutomationWorkflowDraftTask(
                                    key: "tap_refresh",
                                    type: "delay",
                                    delaySeconds: 0.25
                                ),
                                AutomationWorkflowDraftTask(
                                    key: "cooldown",
                                    type: "delay",
                                    delaySeconds: 0.5
                                )
                            ],
                            kind: AutomationWorkflowDraftLoopKind.repeatUntil,
                            until: AutomationWorkflowDraftCondition(
                                type: "imageDisappeared",
                                regionRef: "spinner_area",
                                imageRef: "spinner_template",
                                threshold: 0.82
                            ),
                            maxAttempts: 5,
                            timeoutSeconds: 30,
                            pollingSeconds: 0.5,
                            onFailure: AutomationWorkflowDraftLoopFailurePolicy.requireManualApproval
                        )
                    )
                ]
            ),
            visualAssets: AutomationWorkflowDraftVisualAssets(
                regions: [
                    AutomationWorkflowDraftVisualRegion(
                        key: "spinner_area",
                        bounds: RectValue(x: 10, y: 20, width: 80, height: 60)
                    )
                ],
                images: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "spinner_template",
                        path: "assets/spinner.png"
                    )
                ]
            )
        )
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

        let taskRow = try #require(projection.taskRows.first)
        let loopRow = try #require(projection.loopExpansionRows.first)
        let importPreview = try #require(projection.importPreview)

        #expect(!projection.isValid)
        #expect(!projection.isReadyForImport)
        #expect(projection.statusLabel == "Import blocked")
        #expect(taskRow.detail == "Repeat until image disappears, 2 steps")
        #expect(loopRow.key == "repeat_until_spinner")
        #expect(loopRow.modeLabel == "Repeat until")
        #expect(loopRow.repeatCount == 5)
        #expect(loopRow.bodyStepCount == 2)
        #expect(loopRow.expandedTaskCount == 0)
        #expect(loopRow.repeatMetricTitle == "max attempts")
        #expect(loopRow.expandedMetricTitle == "runtime steps")
        #expect(loopRow.untilLabel == "image disappears")
        #expect(loopRow.guardrailLabel == "max 5 attempts, 30.0s timeout, 0.5s polling, on failure: requireManualApproval")
        #expect(loopRow.summary == "Repeats body until image disappears")
        #expect(loopRow.importBoundaryLabel == "Draft-only repeat-until; import waits for structured runtime loop support")
        #expect(loopRow.capabilityLabel == "Review can preserve the loop intent; runtime attempt evidence is not active yet")
        #expect(projection.simulationRows.isEmpty)
        #expect(importPreview.isImportable == false)
        #expect(importPreview.issueRows.contains {
            $0.severity == .error &&
                $0.code == AutomationWorkflowDraftIssueCode.invalidLoop.rawValue &&
                $0.message.contains("draft-only")
        })
    }
}
