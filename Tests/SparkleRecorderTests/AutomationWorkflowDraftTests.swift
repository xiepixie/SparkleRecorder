import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Workflow Draft Tests")
struct AutomationWorkflowDraftTests {
    @Test("Valid battle flow draft passes validation")
    func validBattleFlowDraftPassesValidation() {
        let tapID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let exitID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Battle exit",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "tap_screen",
                    type: "macro",
                    macroRef: AutomationWorkflowDraftMacroRef(name: "Tap Screen"),
                    resource: .foregroundInput
                ),
                AutomationWorkflowDraftTask(
                    key: "wait_exit",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(
                        type: "ocrText",
                        text: "Leave",
                        matchMode: .contains,
                        regionRef: "battle_result_area",
                        requireVisible: true
                    ),
                    timeoutSeconds: 120
                ),
                AutomationWorkflowDraftTask(
                    key: "click_exit",
                    type: "macro",
                    macroRef: AutomationWorkflowDraftMacroRef(id: exitID, name: "Click Leave"),
                    resource: .foregroundInput
                ),
                AutomationWorkflowDraftTask(
                    key: "notify_timeout",
                    type: "notification",
                    notification: AutomationWorkflowDraftNotification(
                        title: "Leave button did not appear",
                        severity: "warning"
                    )
                )
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(
                    from: "tap_screen",
                    to: "wait_exit",
                    trigger: "success",
                    delaySeconds: 1
                ),
                AutomationWorkflowDraftDependency(
                    from: "wait_exit",
                    to: "click_exit",
                    trigger: "conditionMatched"
                ),
                AutomationWorkflowDraftDependency(
                    from: "wait_exit",
                    to: "notify_timeout",
                    trigger: "timeout"
                )
            ]
        ))
        let context = AutomationWorkflowDraftValidationContext(macroCatalog: [
            AutomationWorkflowDraftMacroCatalogEntry(id: tapID, name: "Tap Screen"),
            AutomationWorkflowDraftMacroCatalogEntry(id: exitID, name: "Click Leave")
        ])

        let result = AutomationWorkflowDraftValidator.validate(document, context: context)

        #expect(result.isValid)
        #expect(result.issues.isEmpty)
    }

    @Test("Draft document round trips through Codable")
    func draftDocumentRoundTrips() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Round trip",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "wait_ready",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(
                        type: "ocrText",
                        text: "Ready",
                        matchMode: .exact
                    ),
                    timeoutSeconds: 30
                )
            ]
        ))

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(AutomationWorkflowDraftDocument.self, from: data)

        #expect(decoded == document)
    }

    @Test("Ambiguous macro names block validation")
    func ambiguousMacroNamesBlockValidation() {
        let firstID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
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
        let context = AutomationWorkflowDraftValidationContext(macroCatalog: [
            AutomationWorkflowDraftMacroCatalogEntry(id: firstID, name: "Tap"),
            AutomationWorkflowDraftMacroCatalogEntry(id: secondID, name: "Tap")
        ])

        let result = AutomationWorkflowDraftValidator.validate(document, context: context)

        #expect(!result.isValid)
        #expect(result.issues.contains {
            $0.code == .ambiguousMacroRef &&
            $0.taskKey == "tap" &&
            Set($0.candidates) == Set([firstID, secondID])
        })
    }

    @Test("Missing endpoints and duplicate task keys are errors")
    func missingEndpointsAndDuplicateTaskKeysAreErrors() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Bad graph",
            tasks: [
                AutomationWorkflowDraftTask(key: "same", type: "delay", delaySeconds: 1),
                AutomationWorkflowDraftTask(key: "same", type: "delay", delaySeconds: 2)
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(from: "same", to: "missing", trigger: "success")
            ]
        ))

        let result = AutomationWorkflowDraftValidator.validate(document)
        let codes = Set(result.issues.map(\.code))

        #expect(!result.isValid)
        #expect(codes.contains(.duplicateTaskKey))
        #expect(codes.contains(.missingDependencyEndpoint))
    }

    @Test("Condition timeout without timeout branch is a warning")
    func conditionTimeoutWithoutTimeoutBranchIsWarning() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Missing timeout branch",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "wait_done",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(type: "ocrText", text: "Done"),
                    timeoutSeconds: 60
                )
            ]
        ))

        let result = AutomationWorkflowDraftValidator.validate(document)

        #expect(result.isValid)
        #expect(result.issues.contains {
            $0.severity == .warning &&
            $0.code == .missingTimeoutBranch &&
            $0.taskKey == "wait_done"
        })
    }

    @Test("Cycle in dependencies blocks validation")
    func cycleInDependenciesBlocksValidation() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Cycle",
            tasks: [
                AutomationWorkflowDraftTask(key: "a", type: "delay", delaySeconds: 1),
                AutomationWorkflowDraftTask(key: "b", type: "delay", delaySeconds: 1)
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(from: "a", to: "b", trigger: "success"),
                AutomationWorkflowDraftDependency(from: "b", to: "a", trigger: "success")
            ]
        ))

        let result = AutomationWorkflowDraftValidator.validate(document)

        #expect(!result.isValid)
        #expect(result.issues.contains { $0.code == .cycleDetected })
    }

    @Test("Fixed loop draft expands to acyclic simulation and import")
    func fixedLoopDraftExpandsToAcyclicSimulationAndImport() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Fixed loop",
            tasks: [
                AutomationWorkflowDraftTask(key: "open", type: "delay", delaySeconds: 1),
                AutomationWorkflowDraftTask(
                    key: "repeat_battle",
                    type: "loop",
                    loop: AutomationWorkflowDraftLoop(
                        count: 3,
                        tasks: [
                            AutomationWorkflowDraftTask(key: "tap", type: "delay", delaySeconds: 2),
                            AutomationWorkflowDraftTask(
                                key: "wait",
                                type: "condition",
                                condition: AutomationWorkflowDraftCondition(
                                    type: "ocrText",
                                    text: "Again"
                                )
                            )
                        ]
                    )
                ),
                AutomationWorkflowDraftTask(
                    key: "done",
                    type: "notification",
                    notification: AutomationWorkflowDraftNotification(title: "Loop complete")
                )
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(from: "open", to: "repeat_battle", trigger: "success"),
                AutomationWorkflowDraftDependency(from: "repeat_battle", to: "done", trigger: "success")
            ]
        ))

        let validation = AutomationWorkflowDraftValidator.validate(document)
        let simulation = AutomationWorkflowDraftSimulator.simulate(document)
        let importResult = AutomationWorkflowDraftImporter.dryRun(document)
        let workflow = try #require(importResult.workflow)

        #expect(validation.isValid)
        #expect(importResult.isImportable)
        #expect(workflow.validationIssues().isEmpty)
        #expect(simulation.steps.map(\.taskKey) == [
            "open",
            "repeat_battle__1__tap",
            "repeat_battle__1__wait",
            "repeat_battle__2__tap",
            "repeat_battle__2__wait",
            "repeat_battle__3__tap",
            "repeat_battle__3__wait",
            "done"
        ])
        #expect(workflow.tasks.count == 8)
        #expect(workflow.dependencies.count == 7)
        let importedTaskKeys = Set(importResult.taskKeyToID.keys)
        #expect(importedTaskKeys.contains("repeat_battle__3__wait"))
        #expect(!importedTaskKeys.contains("repeat_battle"))
        #expect(importResult.dependencyKeyToID.keys.contains("repeat_battle__2__wait->repeat_battle__3__tap:conditionMatched"))
        #expect(importResult.dependencyKeyToID.keys.contains("repeat_battle__3__wait->done:conditionMatched"))
    }

    @Test("Repeat-until loop stays draft-only and does not expand")
    func repeatUntilLoopStaysDraftOnlyAndDoesNotExpand() throws {
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Wait for spinner",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "repeat_until_spinner_gone",
                        type: "loop",
                        loop: AutomationWorkflowDraftLoop(
                            count: 1,
                            tasks: [
                                AutomationWorkflowDraftTask(
                                    key: "tap_refresh",
                                    type: "delay",
                                    delaySeconds: 0.25
                                )
                            ],
                            kind: AutomationWorkflowDraftLoopKind.repeatUntil,
                            until: AutomationWorkflowDraftCondition(
                                type: "imageDisappeared",
                                regionRef: "spinner_area",
                                imageRef: "spinner_template",
                                threshold: 0.82
                            ),
                            maxAttempts: 4,
                            timeoutSeconds: 20,
                            pollingSeconds: 0.5,
                            onFailure: AutomationWorkflowDraftLoopFailurePolicy.failRun
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
        let importResult = AutomationWorkflowDraftImporter.dryRun(document)
        let expanded = AutomationWorkflowDraftLoopExpander.expandedDocument(document)
        let normalized = AutomationWorkflowDraftEditor.normalize(document).document
        let normalizedLoop = try #require(normalized.workflow.tasks.first?.loop)

        #expect(!validation.isValid)
        #expect(validation.issues.contains {
            $0.code == .invalidLoop &&
                $0.path == "$.workflow.tasks[0].loop.kind" &&
                $0.message.contains("draft-only")
        })
        #expect(!importResult.isImportable)
        #expect(expanded.workflow.tasks.map(\.key) == ["repeat_until_spinner_gone"])
        #expect(expanded.workflow.dependencies.isEmpty)
        #expect(expanded.workflow.tasks.first?.loop?.isRepeatUntil == true)
        #expect(normalizedLoop.kind == AutomationWorkflowDraftLoopKind.repeatUntil)
        #expect(normalizedLoop.until?.type == "imageDisappeared")
        #expect(normalizedLoop.until?.regionRef == "spinner_area")
        #expect(normalizedLoop.maxAttempts == 4)
        #expect(normalizedLoop.timeoutSeconds == 20)
        #expect(normalizedLoop.pollingSeconds == 0.5)
        #expect(normalizedLoop.onFailure == AutomationWorkflowDraftLoopFailurePolicy.failRun)
    }

    @Test("Repeat-until loop decodes without fixed count")
    func repeatUntilLoopDecodesWithoutFixedCount() throws {
        let data = Data("""
        {
          "schema": "sparkle.workflow.draft.v1",
          "workflow": {
            "name": "Decoded repeat until",
            "tasks": [
              {
                "key": "repeat_wait",
                "type": "loop",
                "loop": {
                  "kind": "repeatUntil",
                  "tasks": [
                    { "key": "tap", "type": "delay", "delaySeconds": 1.0 }
                  ],
                  "until": {
                    "type": "ocrText",
                    "text": "Done"
                  },
                  "maxAttempts": 3
                }
              }
            ],
            "dependencies": []
          }
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AutomationWorkflowDraftDocument.self, from: data)
        let loop = try #require(decoded.workflow.tasks.first?.loop)

        #expect(loop.count == 1)
        #expect(loop.isRepeatUntil)
        #expect(loop.tasks.map(\.key) == ["tap"])
        #expect(loop.until?.type == "ocrText")
        #expect(loop.until?.text == "Done")
        #expect(loop.maxAttempts == 3)
    }

    @Test("Draft editor can author fixed loop body")
    func draftEditorCanAuthorFixedLoopBody() throws {
        var document = try AutomationWorkflowDraftEditor
            .makeDocument(name: "Loop authoring")
            .document
        document = try AutomationWorkflowDraftEditor.addTask(
            AutomationWorkflowDraftTask(key: "repeat_checkout", type: "delay", delaySeconds: 1),
            to: document
        ).document

        let result = try AutomationWorkflowDraftEditor.setLoop(
            taskKey: "repeat_checkout",
            count: 2,
            tasks: [
                AutomationWorkflowDraftTask(key: " tap ", type: " delay ", delaySeconds: 1),
                AutomationWorkflowDraftTask(
                    key: " wait_done ",
                    type: " condition ",
                    condition: AutomationWorkflowDraftCondition(type: " ocrText ", text: " Done ")
                )
            ],
            in: document
        )
        let loopTask = try #require(result.document.workflow.tasks.first)
        let loop = try #require(loopTask.loop)
        let simulation = AutomationWorkflowDraftSimulator.simulate(result.document)
        let importResult = AutomationWorkflowDraftImporter.dryRun(result.document)

        #expect(result.operation == "draft loop set")
        #expect(result.isValid)
        #expect(result.changedTaskKeys == ["repeat_checkout"])
        #expect(loopTask.type == "loop")
        #expect(loopTask.delaySeconds == nil)
        #expect(loop.count == 2)
        #expect(loop.tasks.map(\.key) == ["tap", "wait_done"])
        #expect(loop.tasks.map(\.type) == ["delay", "condition"])
        #expect(loop.tasks[1].condition?.text == "Done")
        #expect(simulation.steps.map(\.taskKey) == [
            "repeat_checkout__1__tap",
            "repeat_checkout__1__wait_done",
            "repeat_checkout__2__tap",
            "repeat_checkout__2__wait_done"
        ])
        #expect(importResult.isImportable)
        #expect(importResult.workflow?.validationIssues().isEmpty == true)
    }

    @Test("Draft editor loop authoring clears incompatible task fields")
    func draftEditorLoopAuthoringClearsIncompatibleTaskFields() throws {
        let graphPosition = AutomationGraphPoint(x: 20, y: 40)
        let scheduledAt = Date(timeIntervalSince1970: 6_700)
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Loop cleanup",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "repeat_checkout",
                        type: "macro",
                        loop: AutomationWorkflowDraftLoop(
                            count: 3,
                            tasks: [
                                AutomationWorkflowDraftTask(key: "old", type: "delay", delaySeconds: 1)
                            ]
                        ),
                        macroRef: AutomationWorkflowDraftMacroRef(name: "Old macro"),
                        condition: AutomationWorkflowDraftCondition(type: "ocrText", text: "Old"),
                        delaySeconds: 2,
                        notification: AutomationWorkflowDraftNotification(title: "Old notification"),
                        schedule: AutomationWorkflowDraftSchedule(type: "once", startAt: scheduledAt),
                        resource: .foregroundInput,
                        maxResourceWaitSeconds: 5,
                        timeoutSeconds: 10,
                        pollingSeconds: 0.5,
                        retry: AutomationWorkflowDraftRetry(maxAttempts: 2),
                        joinPolicy: "all",
                        enabled: true,
                        graphPosition: graphPosition
                    )
                ]
            )
        )

        let result = try AutomationWorkflowDraftEditor.setLoop(
            taskKey: "repeat_checkout",
            count: 2,
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "wait_done",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(type: "ocrText", text: "Done")
                )
            ],
            in: document
        )
        let task = try #require(result.document.workflow.tasks.first)

        #expect(result.isValid)
        #expect(task.type == "loop")
        #expect(task.loop?.count == 2)
        #expect(task.loop?.tasks.map(\.key) == ["wait_done"])
        #expect(task.macroRef == nil)
        #expect(task.condition == nil)
        #expect(task.delaySeconds == nil)
        #expect(task.notification == nil)
        #expect(task.resource == nil)
        #expect(task.maxResourceWaitSeconds == nil)
        #expect(task.timeoutSeconds == nil)
        #expect(task.pollingSeconds == nil)
        #expect(task.retry == nil)
        #expect(task.joinPolicy == nil)
        #expect(task.schedule?.type == "once")
        #expect(task.enabled == true)
        #expect(task.graphPosition == graphPosition)
    }

    @Test("Loop draft validates fixed count and rejects nested loops")
    func loopDraftValidatesFixedCountAndRejectsNestedLoops() {
        let invalidCount = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Invalid loop",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "repeat",
                    type: "loop",
                    loop: AutomationWorkflowDraftLoop(
                        count: 0,
                        tasks: [AutomationWorkflowDraftTask(key: "tap", type: "delay", delaySeconds: 1)]
                    )
                )
            ]
        ))
        let nested = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Nested loop",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "outer",
                    type: "loop",
                    loop: AutomationWorkflowDraftLoop(
                        count: 2,
                        tasks: [
                            AutomationWorkflowDraftTask(
                                key: "inner",
                                type: "loop",
                                loop: AutomationWorkflowDraftLoop(
                                    count: 2,
                                    tasks: [AutomationWorkflowDraftTask(key: "tap", type: "delay", delaySeconds: 1)]
                                )
                            )
                        ]
                    )
                )
            ]
        ))

        let invalidCountResult = AutomationWorkflowDraftValidator.validate(invalidCount)
        let nestedResult = AutomationWorkflowDraftValidator.validate(nested)

        #expect(!invalidCountResult.isValid)
        #expect(invalidCountResult.issues.contains {
            $0.code == .invalidLoop &&
                $0.path == "$.workflow.tasks[0].loop.count"
        })
        #expect(!nestedResult.isValid)
        #expect(nestedResult.issues.contains {
            $0.code == .invalidLoop &&
                $0.path == "$.workflow.tasks[0].loop.tasks[0].type"
        })
    }

    @Test("Repeating schedule requires start, interval, and unit")
    func repeatingScheduleRequiresStartIntervalAndUnit() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Invalid schedule",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "scheduled",
                    type: "delay",
                    delaySeconds: 1,
                    schedule: AutomationWorkflowDraftSchedule(type: "repeating", every: 0, unit: "months")
                )
            ]
        ))

        let result = AutomationWorkflowDraftValidator.validate(document)

        #expect(!result.isValid)
        #expect(result.issues.filter { $0.code == .invalidSchedule }.count == 3)
    }

    @Test("Validation result maps to CLI envelope")
    func validationResultMapsToCLIEnvelope() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "CLI envelope",
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
                    timeoutSeconds: 10
                )
            ]
        ))
        let result = AutomationWorkflowDraftValidator.validate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: [])
        )

        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>
            .workflowDraftValidation(command: "workflow draft validate", result: result)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>.self,
            from: data
        )

        #expect(envelope.ok)
        #expect(envelope.errors.isEmpty)
        #expect(envelope.warnings.contains { $0.code == AutomationWorkflowDraftIssueCode.missingTimeoutBranch.rawValue })
        #expect(envelope.nextActions.contains { $0.reason.contains("timeout branch") })
        #expect(decoded == envelope)
    }

    @Test("Macro catalog entry projects saved macro metadata without event payload")
    func macroCatalogEntryProjectsSavedMacroMetadataWithoutEventPayload() throws {
        let macroID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        var macro = SavedMacro(
            id: macroID,
            name: "Click Leave",
            events: [
                .make(.leftMouseDown, time: 0.1, x: 10, y: 20),
                .make(.leftMouseUp, time: 0.2, x: 10, y: 20),
                .make(.scrollWheel, time: 1.5, scrollDeltaY: -3)
            ],
            surfaces: [
                "main": PlaybackSurface(
                    appName: "Battle",
                    bundleIdentifier: "com.example.battle",
                    windowTitle: "Result",
                    recordedFrame: RectValue(x: 100, y: 200, width: 800, height: 600),
                    recordedContentFrame: RectValue(x: 100, y: 230, width: 800, height: 570)
                )
            ],
            notes: "Tap the leave button"
        )
        macro.tags = ["battle", "exit"]
        let recordingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        macro.semanticRecording = MacroSemanticRecordingReference(
            recordingID: recordingID,
            bundleRelativePath: "SemanticRecordings/\(recordingID.uuidString)",
            manifestRelativePath: "SemanticRecordings/\(recordingID.uuidString)/manifest.json",
            eventCount: macro.eventCount
        )

        let entry = AutomationWorkflowDraftMacroCatalogEntry(macro: macro)
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>
            .workflowMacroCatalog(command: "workflow macros", macros: [entry], search: "result")
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>.self,
            from: encoded
        )

        #expect(entry.id == macroID)
        #expect(entry.durationSeconds == 1.5)
        #expect(entry.eventCount == 3)
        #expect(entry.clickCount == 1)
        #expect(entry.scrollCount == 1)
        #expect(entry.notes == "Tap the leave button")
        #expect(entry.resourceRequirement == .foregroundInput)
        #expect(entry.surfaces?.first?.bundleIdentifier == "com.example.battle")
        #expect(entry.semanticRecording?.recordingID == recordingID)
        #expect(decoded.data?.macros.first?.semanticRecording?.recordingID == recordingID)
        #expect(entry.matches(searchTerm: "leave"))
        #expect(entry.matches(searchTerm: "result"))
        #expect(!entry.matches(searchTerm: "upload"))
        #expect(decoded == envelope)
    }

    @Test("Draft simulation follows happy path with catalog durations")
    func draftSimulationFollowsHappyPathWithCatalogDurations() throws {
        let document = battleExitDocument()
        let startAt = Date(timeIntervalSince1970: 1_000)

        let result = AutomationWorkflowDraftSimulator.simulate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: battleExitCatalog()),
            options: AutomationWorkflowDraftSimulationOptions(startAt: startAt)
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>
            .workflowDraftSimulation(command: "workflow draft simulate", result: result)
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>.self,
            from: encoded
        )

        #expect(result.isSimulatable)
        #expect(result.steps.map(\.taskKey) == ["tap_screen", "wait_exit", "click_exit"])
        #expect(result.steps.map(\.outcome) == [.success, .conditionMatched, .success])
        #expect(result.steps[0].durationSeconds == 2)
        #expect(result.steps[1].plannedStartAt == startAt.addingTimeInterval(3))
        #expect(result.steps[2].plannedEndAt == startAt.addingTimeInterval(4))
        #expect(result.resourceTimeline.map(\.taskKey) == ["tap_screen", "click_exit"])
        #expect(result.branchDecisions.contains {
            $0.from == "wait_exit" &&
            $0.to == "click_exit" &&
            $0.trigger == "conditionMatched" &&
            $0.fired
        })
        #expect(result.branchDecisions.contains {
            $0.from == "wait_exit" &&
            $0.to == "notify_timeout" &&
            $0.trigger == "timeout" &&
            !$0.fired
        })
        #expect(result.skippedTaskKeys == ["notify_timeout"])
        #expect(decoded == envelope)
    }

    @Test("Draft simulation timeout scenario follows timeout branch")
    func draftSimulationTimeoutScenarioFollowsTimeoutBranch() {
        let startAt = Date(timeIntervalSince1970: 1_000)
        let result = AutomationWorkflowDraftSimulator.simulate(
            battleExitDocument(),
            context: AutomationWorkflowDraftValidationContext(macroCatalog: battleExitCatalog()),
            options: AutomationWorkflowDraftSimulationOptions(
                startAt: startAt,
                scenario: AutomationWorkflowDraftSimulationScenario(taskKey: "wait_exit", outcome: .timeout)
            )
        )

        #expect(result.isSimulatable)
        #expect(result.steps.map(\.taskKey) == ["tap_screen", "wait_exit", "notify_timeout"])
        #expect(result.steps[1].outcome == .timeout)
        #expect(result.steps[1].durationSeconds == 120)
        #expect(result.steps[2].plannedStartAt == startAt.addingTimeInterval(123))
        #expect(result.skippedTaskKeys == ["click_exit"])
        #expect(result.branchDecisions.contains {
            $0.from == "wait_exit" &&
            $0.to == "notify_timeout" &&
            $0.trigger == "timeout" &&
            $0.fired
        })
    }

    @Test("Draft simulation reports validation errors without planning")
    func draftSimulationReportsValidationErrorsWithoutPlanning() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Invalid",
            tasks: [
                AutomationWorkflowDraftTask(key: "same", type: "delay", delaySeconds: 1),
                AutomationWorkflowDraftTask(key: "same", type: "delay", delaySeconds: 2)
            ]
        ))

        let result = AutomationWorkflowDraftSimulator.simulate(document)

        #expect(!result.isSimulatable)
        #expect(result.steps.isEmpty)
        #expect(result.validationIssues.contains { $0.code == .duplicateTaskKey })
        #expect(result.skippedTaskKeys == ["same", "same"])
    }

    @Test("Draft import dry-run compiles importable workflow")
    func draftImportDryRunCompilesImportableWorkflow() throws {
        let importedAt = Date(timeIntervalSince1970: 2_000)
        let result = AutomationWorkflowDraftImporter.dryRun(
            battleExitDocument(),
            context: AutomationWorkflowDraftValidationContext(macroCatalog: battleExitCatalog()),
            options: AutomationWorkflowDraftImportOptions(importedAt: importedAt)
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>
            .workflowDraftImport(command: "workflow import", result: result)
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>.self,
            from: encoded
        )

        let workflow = try #require(result.workflow)

        #expect(result.isImportable)
        #expect(result.validationIssues.isEmpty)
        #expect(result.workflowValidationIssues.isEmpty)
        #expect(workflow.name == "Battle exit")
        #expect(workflow.createdAt == importedAt)
        #expect(workflow.tasks.count == 4)
        #expect(workflow.dependencies.count == 3)
        #expect(result.taskKeyToID.keys.sorted() == ["click_exit", "notify_timeout", "tap_screen", "wait_exit"])
        #expect(result.dependencyKeyToID.keys.sorted() == [
            "tap_screen->wait_exit:success",
            "wait_exit->click_exit:conditionMatched",
            "wait_exit->notify_timeout:timeout"
        ])
        #expect(result.macroResolutions.contains {
            $0.taskKey == "tap_screen" &&
            $0.macroID == UUID(uuidString: "10000000-0000-0000-0000-000000000001")! &&
            $0.source == .catalogName
        })
        #expect(result.macroResolutions.contains {
            $0.taskKey == "click_exit" &&
            $0.macroID == UUID(uuidString: "10000000-0000-0000-0000-000000000002")! &&
            $0.source == .id
        })
        #expect(envelope.ok)
        #expect(envelope.nextActions.contains { $0.command.contains("--confirm") })
        #expect(decoded == envelope)

        let waitTask = try #require(workflow.tasks.first { $0.name == "Leave" })
        if case .condition(let spec) = waitTask.kind {
            #expect(spec.timeout == 120)
            if case .ocrText(let condition) = spec.kind {
                #expect(condition.text == "Leave")
            } else {
                Issue.record("Expected OCR condition for wait_exit")
            }
        } else {
            Issue.record("Expected condition task for wait_exit")
        }
    }

    @Test("Draft import confirm result maps to confirmed CLI envelope")
    func draftImportConfirmResultMapsToConfirmedCLIEnvelope() throws {
        let result = AutomationWorkflowDraftImporter.compile(
            battleExitDocument(),
            context: AutomationWorkflowDraftValidationContext(macroCatalog: battleExitCatalog()),
            options: AutomationWorkflowDraftImportOptions(
                mode: .confirm,
                importedAt: Date(timeIntervalSince1970: 2_100)
            )
        )

        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>
            .workflowDraftImport(command: "workflow import", result: result)
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>.self,
            from: encoded
        )

        #expect(result.mode == .confirm)
        #expect(result.isImportable)
        #expect(envelope.ok)
        #expect(!envelope.nextActions.contains { $0.command.contains("--confirm") })
        #expect(envelope.nextActions.contains { $0.command.contains("Open SparkleRecorder Workflow page") })
        #expect(decoded == envelope)
    }

    @Test("Draft validator rejects unsupported join policy")
    func draftValidatorRejectsUnsupportedJoinPolicy() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Invalid join",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "joined",
                    type: "delay",
                    delaySeconds: 1,
                    joinPolicy: "sometimes"
                )
            ]
        ))

        let result = AutomationWorkflowDraftValidator.validate(document)

        #expect(result.issues.contains {
            $0.severity == .error &&
                $0.code == .invalidJoinPolicy &&
                $0.taskKey == "joined"
        })
    }

    @Test("Draft import and export preserve non-default join policy")
    func draftImportAndExportPreserveNonDefaultJoinPolicy() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Join policy",
            tasks: [
                AutomationWorkflowDraftTask(key: "left", type: "delay", delaySeconds: 1),
                AutomationWorkflowDraftTask(key: "right", type: "delay", delaySeconds: 1),
                AutomationWorkflowDraftTask(
                    key: "joined",
                    type: "delay",
                    delaySeconds: 1,
                    joinPolicy: AutomationJoinPolicy.any.rawValue
                )
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(from: "left", to: "joined", trigger: "success"),
                AutomationWorkflowDraftDependency(from: "right", to: "joined", trigger: "success")
            ]
        ))

        let importResult = AutomationWorkflowDraftImporter.dryRun(document)
        let workflow = try #require(importResult.workflow)
        let joinedTask = try #require(workflow.tasks.first { $0.name == "joined" })

        #expect(importResult.isImportable)
        #expect(joinedTask.joinPolicy == .any)

        let exportResult = AutomationWorkflowDraftExporter.export(workflow)
        let joinedDraft = try #require(exportResult.document.workflow.tasks.first { $0.key.hasPrefix("joined_") })

        #expect(exportResult.isExportable)
        #expect(joinedDraft.joinPolicy == AutomationJoinPolicy.any.rawValue)
    }

    @Test("Draft import and export preserve visual condition intent")
    func draftImportAndExportPreserveVisualConditionIntent() throws {
        let imageAsset = AutomationWorkflowDraftVisualImageAsset(
            key: "loading_spinner_template",
            label: "Loading spinner",
            path: "assets/loading-spinner.png"
        )
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Visual condition",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "wait_icon",
                        type: "condition",
                        condition: AutomationWorkflowDraftCondition(
                            type: "imageDisappeared",
                            regionRef: "battle_result_area",
                            requireVisible: false,
                            imageRef: "loading_spinner_template",
                            threshold: 0.91
                        ),
                        timeoutSeconds: 20,
                        pollingSeconds: 0.4
                    ),
                ]
            ),
            visualAssets: AutomationWorkflowDraftVisualAssets(images: [imageAsset])
        )

        let importResult = AutomationWorkflowDraftImporter.dryRun(document)
        let workflow = try #require(importResult.workflow)
        let task = try #require(workflow.tasks.first)

        #expect(importResult.isImportable)
        #expect(workflow.visualAssets?.images == [imageAsset])
        if case .condition(let spec) = task.kind,
           case .visual(let condition) = spec.kind {
            #expect(condition.type == .imageDisappeared)
            #expect(condition.regionRef == "battle_result_area")
            #expect(condition.imageRef == "loading_spinner_template")
            #expect(condition.threshold == 0.91)
            #expect(!condition.requireVisible)
        } else {
            Issue.record("Expected imported task to preserve visual condition")
        }

        let exportResult = AutomationWorkflowDraftExporter.export(workflow)
        let exportedTask = try #require(exportResult.document.workflow.tasks.first)
        let exportedCondition = try #require(exportedTask.condition)

        #expect(exportResult.isExportable)
        #expect(exportedCondition.type == "imageDisappeared")
        #expect(exportedCondition.regionRef == "battle_result_area")
        #expect(exportedCondition.imageRef == "loading_spinner_template")
        #expect(exportedCondition.threshold == 0.91)
        #expect(exportedCondition.requireVisible == false)
        #expect(exportResult.document.visualAssets?.images == [imageAsset])
    }

    @Test("Draft import and export preserve pixel sample radius")
    func draftImportAndExportPreservePixelSampleRadius() throws {
        let region = AutomationWorkflowDraftVisualRegion(
            key: "status_light",
            label: "Status light",
            bounds: RectValue(x: 10, y: 20, width: 30, height: 30),
            space: .displayAbsolute
        )
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Pixel radius flow",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "wait_status",
                        type: "condition",
                        condition: AutomationWorkflowDraftCondition(
                            type: "pixelMatched",
                            regionRef: "status_light",
                            pixel: AutomationGraphPoint(x: 0.5, y: 0.5),
                            colorHex: "#00FF00",
                            pixelSampleRadius: 2,
                            threshold: 0.93
                        )
                    )
                ]
            ),
            visualAssets: AutomationWorkflowDraftVisualAssets(regions: [region])
        )

        let importResult = AutomationWorkflowDraftImporter.dryRun(document)
        let workflow = try #require(importResult.workflow)
        let task = try #require(workflow.tasks.first)

        #expect(importResult.isImportable)
        if case .condition(let spec) = task.kind,
           case .visual(let condition) = spec.kind {
            #expect(condition.type == .pixelMatched)
            #expect(condition.regionRef == "status_light")
            #expect(condition.pixelSampleRadius == 2)
            #expect(condition.threshold == 0.93)
        } else {
            Issue.record("Expected imported task to preserve pixel condition")
        }

        let exportResult = AutomationWorkflowDraftExporter.export(workflow)
        let exportedCondition = try #require(exportResult.document.workflow.tasks.first?.condition)

        #expect(exportResult.isExportable)
        #expect(exportedCondition.type == "pixelMatched")
        #expect(exportedCondition.regionRef == "status_light")
        #expect(exportedCondition.pixelSampleRadius == 2)
        #expect(exportedCondition.threshold == 0.93)
    }

    @Test("Draft editor and patch update join policy")
    func draftEditorAndPatchUpdateJoinPolicy() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Join edit",
            tasks: [
                AutomationWorkflowDraftTask(key: "joined", type: "delay", delaySeconds: 1)
            ]
        ))

        let edited = try AutomationWorkflowDraftEditor.setTask(
            key: "joined",
            in: document,
            joinPolicy: AutomationJoinPolicy.firstMatched.rawValue
        )
        let patch = AutomationWorkflowDraftPatchDocument(ops: [
            AutomationWorkflowDraftPatchOperation(
                op: "setTask",
                key: "joined",
                joinPolicy: AutomationJoinPolicy.any.rawValue
            )
        ])
        let patched = try AutomationWorkflowDraftPatchApplier.apply(patch, to: edited.document)

        #expect(edited.document.workflow.tasks.first?.joinPolicy == AutomationJoinPolicy.firstMatched.rawValue)
        #expect(patched.document.workflow.tasks.first?.joinPolicy == AutomationJoinPolicy.any.rawValue)
    }

    @Test("Draft resource max wait imports, exports, edits, and patches")
    func draftResourceMaxWaitImportsExportsEditsAndPatches() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Resource wait",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "exclusive_delay",
                    type: "delay",
                    delaySeconds: 1,
                    resource: .foregroundInput,
                    maxResourceWaitSeconds: 12
                )
            ]
        ))

        let importResult = AutomationWorkflowDraftImporter.dryRun(document)
        let importedTask = try #require(importResult.workflow?.tasks.first)
        let exportResult = AutomationWorkflowDraftExporter.export(try #require(importResult.workflow))
        let exportedTask = try #require(exportResult.document.workflow.tasks.first)
        let edited = try AutomationWorkflowDraftEditor.setTask(
            key: "exclusive_delay",
            in: document,
            maxResourceWaitSeconds: 20
        )
        let patch = AutomationWorkflowDraftPatchDocument(ops: [
            AutomationWorkflowDraftPatchOperation(
                op: "setTask",
                key: "exclusive_delay",
                maxResourceWaitSeconds: 25
            )
        ])
        let patched = try AutomationWorkflowDraftPatchApplier.apply(patch, to: edited.document)

        #expect(importResult.isImportable)
        #expect(importedTask.resourceRequirement.resources == [.foregroundInput])
        #expect(importedTask.resourceRequirement.maxWaitDuration == 12)
        #expect(exportedTask.resource == .foregroundInput)
        #expect(exportedTask.maxResourceWaitSeconds == 12)
        #expect(edited.document.workflow.tasks.first?.maxResourceWaitSeconds == 20)
        #expect(patched.document.workflow.tasks.first?.maxResourceWaitSeconds == 25)
    }

    @Test("Draft import dry-run requires macro resolution")
    func draftImportDryRunRequiresMacroResolution() {
        let result = AutomationWorkflowDraftImporter.dryRun(
            AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
                name: "Needs catalog",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "tap",
                        type: "macro",
                        macroRef: AutomationWorkflowDraftMacroRef(name: "Tap Screen")
                    )
                ]
            ))
        )

        #expect(!result.isImportable)
        #expect(result.workflow == nil)
        #expect(result.validationIssues.contains {
            $0.severity == .error &&
            $0.code == .missingMacroRef &&
            $0.taskKey == "tap"
        })
        #expect(result.macroResolutions == [
            AutomationWorkflowDraftMacroResolution(
                taskKey: "tap",
                macroID: nil,
                macroName: "Tap Screen",
                source: .unresolved
            )
        ])
    }

    @Test("Draft import dry-run preserves visual conditions as core specs")
    func draftImportDryRunPreservesVisualConditionsAsCoreSpecs() throws {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Watch region",
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

        let result = AutomationWorkflowDraftImporter.dryRun(document)
        let workflow = try #require(result.workflow)
        let task = try #require(workflow.tasks.first)

        #expect(result.isImportable)
        #expect(result.validationIssues.contains {
            $0.severity == .warning &&
            $0.code == .unresolvedRegionRef &&
            $0.taskKey == "watch"
        })
        #expect(task.resourceRequirement == .backgroundReadOnly)
        if case .condition(let spec) = task.kind,
           case .visual(let condition) = spec.kind {
            #expect(condition.type == .regionChanged)
            #expect(condition.regionRef == "battle_result_area")
            #expect(spec.timeout == 30)
        } else {
            Issue.record("Expected visual condition to import as a core visual condition")
        }
    }

    @Test("Draft visual assets materialize region refs during import")
    func draftVisualAssetsMaterializeRegionRefsDuringImport() throws {
        let region = AutomationWorkflowDraftVisualRegion(
            key: "battle_result_area",
            label: "Battle Result",
            bounds: RectValue(x: 0.15, y: 0.25, width: 0.4, height: 0.2),
            space: .displayNormalized
        )
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Watch region",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "watch",
                        type: "condition",
                        condition: AutomationWorkflowDraftCondition(
                            type: "regionChanged",
                            regionRef: "battle_result_area",
                            baselineRef: "battle_start"
                        ),
                        timeoutSeconds: 30
                    )
                ]
            ),
            visualAssets: AutomationWorkflowDraftVisualAssets(
                regions: [region],
                baselines: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "battle_start",
                        path: "assets/battle-start.png"
                    )
                ]
            )
        )

        let result = AutomationWorkflowDraftImporter.dryRun(document)
        let workflow = try #require(result.workflow)
        let task = try #require(workflow.tasks.first)

        #expect(result.isImportable)
        #expect(workflow.visualAssets == document.visualAssets)
        #expect(!result.validationIssues.contains { $0.code == .unresolvedRegionRef })
        if case .condition(let spec) = task.kind,
           case .visual(let condition) = spec.kind {
            #expect(condition.regionRef == "battle_result_area")
            #expect(condition.searchRegion == region.bounds)
            #expect(condition.searchRegionSpace == .displayNormalized)
            #expect(condition.baselineRef == "battle_start")
        } else {
            Issue.record("Expected visual condition to import with materialized region bounds")
        }

        let exportResult = AutomationWorkflowDraftExporter.export(workflow)
        let exportedTask = try #require(exportResult.document.workflow.tasks.first)
        #expect(exportResult.isExportable)
        #expect(exportedTask.condition?.regionRef == "battle_result_area")
        #expect(exportedTask.condition?.baselineRef == "battle_start")
        #expect(exportResult.document.visualAssets == document.visualAssets)
    }

    @Test("Draft validator checks visual asset registry")
    func draftValidatorChecksVisualAssetRegistry() {
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Bad visual assets",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "watch",
                        type: "condition",
                        condition: AutomationWorkflowDraftCondition(
                            type: "imageAppeared",
                            regionRef: "missing_region",
                            imageRef: "missing_image"
                        )
                    )
                ]
            ),
            visualAssets: AutomationWorkflowDraftVisualAssets(
                regions: [
                    AutomationWorkflowDraftVisualRegion(
                        key: "bad",
                        bounds: RectValue(x: 10, y: 10, width: 0, height: 20)
                    ),
                    AutomationWorkflowDraftVisualRegion(
                        key: "bad",
                        bounds: RectValue(x: 10, y: 10, width: 20, height: 20)
                    )
                ],
                images: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "unsafe_image",
                    path: "../outside.png",
                    sourceArtifactPath: "file:/tmp/source-frame.png"
                )
            ],
                baselines: [
                    AutomationWorkflowDraftVisualImageAsset(
                        key: "unsafe_baseline",
                        path: "file:/tmp/baseline.png"
                    )
                ]
            )
        )

        let issues = AutomationWorkflowDraftValidator.validate(document).issues

        #expect(issues.contains { $0.code == .duplicateVisualAssetKey })
        #expect(issues.contains { $0.code == .invalidVisualAsset })
        #expect(issues.contains {
            $0.code == .missingVisualAsset &&
            $0.taskKey == "watch" &&
            $0.path == "$.workflow.tasks[0].condition.regionRef"
        })
        #expect(issues.contains {
            $0.code == .missingVisualAsset &&
            $0.taskKey == "watch" &&
            $0.path == "$.workflow.tasks[0].condition.imageRef"
        })
        #expect(issues.contains {
            $0.code == .invalidVisualAsset &&
            $0.path == "$.visualAssets.images[0].path"
        })
        #expect(issues.contains {
            $0.code == .invalidVisualAsset &&
            $0.path == "$.visualAssets.images[0].sourceArtifactPath"
        })
        #expect(issues.contains {
            $0.code == .invalidVisualAsset &&
            $0.path == "$.visualAssets.baselines[0].path"
        })
    }

    @Test("Draft visual asset paths stay inside package")
    func draftVisualAssetPathsStayInsidePackage() {
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("assets/icon.png") == "assets/icon.png")
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("assets//icon.png") == "assets/icon.png")
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("../icon.png") == nil)
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("/tmp/icon.png") == nil)
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("~/icon.png") == nil)
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("file:/tmp/icon.png") == nil)
        #expect(AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath("assets\\icon.png") == nil)

        let assets = AutomationWorkflowDraftVisualAssets(
            images: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "spinner",
                    path: "assets/spinner.png"
                )
            ],
            baselines: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "battle_start",
                    path: "baselines/start.png"
                )
            ]
        )
        #expect(assets.imagePath(for: "spinner") == "assets/spinner.png")
        #expect(assets.baselinePath(for: "battle_start") == "baselines/start.png")
        #expect(assets.imagePath(for: "missing") == nil)
    }

    @Test("Draft validator checks visual condition references")
    func draftValidatorChecksVisualConditionReferences() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Watch pixels",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "missing_image",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(type: "imageAppeared", regionRef: "toolbar")
                ),
                AutomationWorkflowDraftTask(
                    key: "bad_pixel",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(
                        type: "pixelMatched",
                        colorHex: "orange",
                        pixelSampleRadius: 99,
                        threshold: 1.5
                    )
                )
            ]
        ))

        let issues = AutomationWorkflowDraftValidator.validate(document).issues

        #expect(issues.contains {
            $0.severity == .error &&
            $0.code == .missingVisualReference &&
            $0.taskKey == "missing_image"
        })
        #expect(issues.contains {
            $0.severity == .error &&
            $0.code == .invalidColor &&
            $0.taskKey == "bad_pixel"
        })
        #expect(issues.contains {
            $0.severity == .error &&
            $0.code == .invalidThreshold &&
            $0.taskKey == "bad_pixel"
        })
        #expect(issues.contains {
            $0.severity == .error &&
            $0.code == .invalidPixelSampleRadius &&
            $0.taskKey == "bad_pixel"
        })
        #expect(issues.contains {
            $0.severity == .error &&
            $0.code == .missingPixel &&
            $0.taskKey == "bad_pixel"
        })
    }

    @Test("Draft editor builds importable workflow incrementally")
    func draftEditorBuildsImportableWorkflowIncrementally() throws {
        var document = try AutomationWorkflowDraftEditor
            .makeDocument(name: "Battle exit")
            .document

        let placeholderCondition = try AutomationWorkflowDraftEditor.addTask(
            AutomationWorkflowDraftTask(key: "wait_exit", type: "condition"),
            to: document
        )
        let placeholderEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftEditPayload>
            .workflowDraftEdit(command: "workflow draft task add", result: placeholderCondition)

        #expect(placeholderEnvelope.ok)
        #expect(placeholderEnvelope.data?.isValid == false)
        #expect(placeholderEnvelope.errors.contains { $0.code == AutomationWorkflowDraftIssueCode.missingConditionText.rawValue })

        document = placeholderCondition.document
        document = try AutomationWorkflowDraftEditor.addTask(
            AutomationWorkflowDraftTask(
                key: "tap_screen",
                type: "macro",
                macroRef: AutomationWorkflowDraftMacroRef(name: "Tap Screen"),
                resource: .foregroundInput
            ),
            to: document
        ).document
        document = try AutomationWorkflowDraftEditor.setCondition(
            taskKey: "wait_exit",
            condition: AutomationWorkflowDraftCondition(
                type: "ocrText",
                text: "Leave",
                matchMode: .contains,
                regionRef: "battle_result_area",
                requireVisible: true
            ),
            in: document,
            timeoutSeconds: 120,
            pollingSeconds: 0.5
        ).document
        document = try AutomationWorkflowDraftEditor.addTask(
            AutomationWorkflowDraftTask(
                key: "click_exit",
                type: "macro",
                macroRef: AutomationWorkflowDraftMacroRef(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                    name: "Click Leave"
                ),
                resource: .foregroundInput
            ),
            to: document
        ).document
        document = try AutomationWorkflowDraftEditor.addTask(
            AutomationWorkflowDraftTask(
                key: "notify_timeout",
                type: "notification",
                notification: AutomationWorkflowDraftNotification(title: "Leave button did not appear")
            ),
            to: document
        ).document
        document = try AutomationWorkflowDraftEditor.addDependency(
            AutomationWorkflowDraftDependency(
                from: "tap_screen",
                to: "wait_exit",
                trigger: "success",
                delaySeconds: 1
            ),
            to: document
        ).document
        document = try AutomationWorkflowDraftEditor.addDependency(
            AutomationWorkflowDraftDependency(from: "wait_exit", to: "click_exit", trigger: "conditionMatched"),
            to: document
        ).document
        let finalEdit = try AutomationWorkflowDraftEditor.addDependency(
            AutomationWorkflowDraftDependency(from: "wait_exit", to: "notify_timeout", trigger: "timeout"),
            to: document
        )

        #expect(finalEdit.isValid)
        #expect(finalEdit.changedDependencyKeys == ["wait_exit->notify_timeout:timeout"])

        let importResult = AutomationWorkflowDraftImporter.compile(
            finalEdit.document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: battleExitCatalog()),
            options: AutomationWorkflowDraftImportOptions(importedAt: Date(timeIntervalSince1970: 3_000))
        )
        let workflow = try #require(importResult.workflow)
        let waitTask = try #require(workflow.tasks.first { $0.name == "Leave" })

        #expect(importResult.isImportable)
        if case .condition(let spec) = waitTask.kind {
            #expect(spec.timeout == 120)
            #expect(spec.pollingInterval == 0.5)
        } else {
            Issue.record("Expected wait_exit to import as a condition task")
        }
    }

    @Test("Draft editor rejects duplicate task keys before writing another task")
    func draftEditorRejectsDuplicateTaskKeysBeforeWritingAnotherTask() throws {
        let first = try AutomationWorkflowDraftEditor.addTask(
            AutomationWorkflowDraftTask(key: "tap", type: "delay", delaySeconds: 1),
            to: AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(name: "Duplicate"))
        )

        #expect(throws: AutomationWorkflowDraftEditError.self) {
            try AutomationWorkflowDraftEditor.addTask(
                AutomationWorkflowDraftTask(key: "tap", type: "delay", delaySeconds: 2),
                to: first.document
            )
        }
    }

    @Test("Draft editor updates dependencies, schedules, removes tasks, and normalizes")
    func draftEditorUpdatesDependenciesSchedulesRemovesTasksAndNormalizes() throws {
        let scheduledStart = Date(timeIntervalSince1970: 4_000)
        var document = battleExitDocument()

        let scheduled = try AutomationWorkflowDraftEditor.setSchedule(
            taskKey: "tap_screen",
            schedule: AutomationWorkflowDraftSchedule(
                type: "repeating",
                startAt: scheduledStart,
                every: 1,
                unit: "days",
                timeZone: "Asia/Shanghai"
            ),
            in: document
        )
        document = scheduled.document

        #expect(scheduled.isValid)
        #expect(document.workflow.tasks.first { $0.key == "tap_screen" }?.schedule?.startAt == scheduledStart)

        let changedDependency = try AutomationWorkflowDraftEditor.setDependency(
            matching: AutomationWorkflowDraftDependencySelector(
                from: "tap_screen",
                to: "wait_exit",
                trigger: "success"
            ),
            in: document,
            key: "tap_then_wait",
            delaySeconds: 2,
            enabled: false
        )
        document = changedDependency.document

        #expect(changedDependency.changedDependencyKeys == [
            "tap_screen->wait_exit:success",
            "tap_then_wait"
        ])
        #expect(document.workflow.dependencies.first { $0.key == "tap_then_wait" }?.delaySeconds == 2)
        #expect(document.workflow.dependencies.first { $0.key == "tap_then_wait" }?.enabled == false)

        let removedDependency = try AutomationWorkflowDraftEditor.removeDependency(
            matching: AutomationWorkflowDraftDependencySelector(
                from: "wait_exit",
                to: "notify_timeout",
                trigger: "timeout"
            ),
            from: document
        )
        document = removedDependency.document

        #expect(removedDependency.changedDependencyKeys == ["wait_exit->notify_timeout:timeout"])
        #expect(removedDependency.validation.issues.contains {
            $0.code == .missingTimeoutBranch &&
            $0.taskKey == "wait_exit"
        })

        let removedTask = try AutomationWorkflowDraftEditor.removeTask(
            key: "click_exit",
            from: document
        )
        document = removedTask.document

        #expect(!document.workflow.tasks.contains { $0.key == "click_exit" })
        #expect(!document.workflow.dependencies.contains {
            $0.from == "click_exit" || $0.to == "click_exit"
        })
        #expect(removedTask.changedDependencyKeys == ["wait_exit->click_exit:conditionMatched"])

        let normalized = AutomationWorkflowDraftEditor.normalize(document)

        #expect(normalized.document.schema == AutomationWorkflowDraftSchema.current)
        #expect(normalized.document.workflow.tasks.map(\.key) == ["notify_timeout", "tap_screen", "wait_exit"])
        #expect(normalized.document.workflow.dependencies.map(\.key) == ["tap_then_wait"])
    }

    @Test("Draft patch applies batch operations and returns merged changes")
    func draftPatchAppliesBatchOperationsAndReturnsMergedChanges() throws {
        let tapID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let scheduledStart = Date(timeIntervalSince1970: 5_000)
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(name: "Patch flow"))
        let patch = AutomationWorkflowDraftPatchDocument(ops: [
            AutomationWorkflowDraftPatchOperation(
                op: "addTask",
                key: "tap_screen",
                name: "Tap Screen",
                type: "macro",
                macroRef: AutomationWorkflowDraftMacroRef(name: "Tap Screen"),
                resource: .foregroundInput
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "addTask",
                key: "wait_exit",
                type: "condition"
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "setCondition",
                key: "wait_exit",
                condition: AutomationWorkflowDraftCondition(
                    type: "ocrText",
                    text: "Leave",
                    matchMode: .contains,
                    regionRef: "battle_result_area",
                    requireVisible: true
                ),
                timeoutSeconds: 120,
                pollingSeconds: 0.5
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "addTask",
                task: AutomationWorkflowDraftTask(
                    key: "notify_timeout",
                    type: "notification",
                    notification: AutomationWorkflowDraftNotification(
                        title: "Leave button did not appear",
                        severity: "warning"
                    )
                )
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "addDependency",
                key: "tap_then_wait",
                delaySeconds: 1,
                from: "tap_screen",
                to: "wait_exit",
                trigger: "success"
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "addDependency",
                dependency: AutomationWorkflowDraftDependency(
                    from: "wait_exit",
                    to: "notify_timeout",
                    trigger: "timeout"
                )
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "setSchedule",
                key: "tap_screen",
                schedule: AutomationWorkflowDraftSchedule(
                    type: "repeating",
                    startAt: scheduledStart,
                    every: 1,
                    unit: "days",
                    timeZone: "Asia/Shanghai"
                )
            ),
            AutomationWorkflowDraftPatchOperation(
                op: "setTask",
                key: "tap_screen",
                name: "Tap first",
                type: "macro",
                macroRef: AutomationWorkflowDraftMacroRef(id: tapID, name: "Tap Screen"),
                retryMaxAttempts: 2,
                graphPosition: AutomationGraphPoint(x: 40, y: 80)
            ),
            AutomationWorkflowDraftPatchOperation(op: "normalize")
        ])

        let result = try AutomationWorkflowDraftPatchApplier.apply(
            patch,
            to: document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: battleExitCatalog())
        )
        let tapTask = try #require(result.document.workflow.tasks.first { $0.key == "tap_screen" })
        let waitTask = try #require(result.document.workflow.tasks.first { $0.key == "wait_exit" })

        #expect(result.operation == "draft patch")
        #expect(result.isValid)
        #expect(result.changedTaskKeys == ["notify_timeout", "tap_screen", "wait_exit"])
        #expect(result.changedDependencyKeys == [
            "tap_then_wait",
            "wait_exit->notify_timeout:timeout"
        ])
        #expect(result.document.workflow.tasks.map { $0.key } == ["notify_timeout", "tap_screen", "wait_exit"])
        #expect(tapTask.name == "Tap first")
        #expect(tapTask.macroRef?.id == tapID)
        #expect(tapTask.schedule?.startAt == scheduledStart)
        #expect(tapTask.retry?.maxAttempts == 2)
        #expect(tapTask.graphPosition == AutomationGraphPoint(x: 40, y: 80))
        #expect(waitTask.condition?.text == "Leave")
        #expect(waitTask.timeoutSeconds == 120)
        #expect(waitTask.pollingSeconds == 0.5)
        #expect(result.document.workflow.dependencies.map { $0.key ?? "" } == [
            "tap_then_wait",
            "wait_exit->notify_timeout:timeout"
        ])
    }

    @Test("Draft editor and patch preserve visual condition fields")
    func draftEditorAndPatchPreserveVisualConditionFields() throws {
        var document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Visual flow",
            tasks: [
                AutomationWorkflowDraftTask(key: "watch_icon", type: "condition")
            ]
        ))

        let edited = try AutomationWorkflowDraftEditor.setCondition(
            taskKey: "watch_icon",
            condition: AutomationWorkflowDraftCondition(
                type: "imageAppeared",
                regionRef: "battle_result_area",
                requireVisible: true,
                imageRef: "leave_button_template",
                threshold: 0.88
            ),
            in: document,
            timeoutSeconds: 45,
            pollingSeconds: 0.25
        )
        document = edited.document

        let patch = AutomationWorkflowDraftPatchDocument(ops: [
            AutomationWorkflowDraftPatchOperation(
                op: "setCondition",
                key: "watch_icon",
                type: "pixelMatched",
                regionRef: "battle_result_area",
                colorHex: "#FFCC00",
                pixelSampleRadius: 2,
                threshold: 0.15
            )
        ])
        let patched = try AutomationWorkflowDraftPatchApplier.apply(patch, to: document)
        let task = try #require(patched.document.workflow.tasks.first)
        let condition = try #require(task.condition)

        #expect(edited.isValid)
        #expect(patched.isValid)
        #expect(condition.type == "pixelMatched")
        #expect(condition.regionRef == "battle_result_area")
        #expect(condition.colorHex == "#FFCC00")
        #expect(condition.pixelSampleRadius == 2)
        #expect(condition.threshold == 0.15)
        #expect(task.timeoutSeconds == 45)
        #expect(task.pollingSeconds == 0.25)
    }

    @Test("Draft patch rejects unsupported operations")
    func draftPatchRejectsUnsupportedOperations() {
        let document = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(name: "Patch flow"))
        let patch = AutomationWorkflowDraftPatchDocument(ops: [
            AutomationWorkflowDraftPatchOperation(op: "teleport")
        ])

        do {
            _ = try AutomationWorkflowDraftPatchApplier.apply(patch, to: document)
            Issue.record("Expected unsupported patch operation to throw")
        } catch let error as AutomationWorkflowDraftEditError {
            #expect(error.code == "unsupportedPatchOperation")
            #expect(error.path == "$.ops[0].op")
        } catch {
            Issue.record("Expected AutomationWorkflowDraftEditError, got \(error)")
        }
    }

    @Test("Workflow draft exporter converts internal workflow to AI draft")
    func workflowDraftExporterConvertsInternalWorkflowToAIDraft() throws {
        let workflowID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let macroID = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
        let tapTaskID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
        let waitTaskID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!
        let notifyTaskID = UUID(uuidString: "cccccccc-0000-0000-0000-000000000001")!
        let startAt = Date(timeIntervalSince1970: 10_000)
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Battle exit",
            tasks: [
                AutomationTask(
                    id: tapTaskID,
                    name: "Tap Screen",
                    kind: .macro(macroID: macroID),
                    schedule: .repeating(AutomationRepeatRule(
                        anchor: startAt,
                        interval: .days(1),
                        timeZoneIdentifier: "Asia/Shanghai"
                    )),
                    resourceRequirement: .foregroundInput,
                    timeout: 10
                ),
                AutomationTask(
                    id: waitTaskID,
                    name: "Wait Exit",
                    kind: .condition(AutomationConditionSpec(
                        name: "Wait Exit",
                        kind: .ocrText(AutomationOCRCondition(
                            text: "Leave",
                            matchMode: .contains,
                            searchRegion: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                            searchRegionSpace: .displayNormalized,
                            requireVisible: true
                        )),
                        timeout: 120,
                        pollingInterval: 0.5
                    )),
                    resourceRequirement: .backgroundReadOnly,
                    timeout: 120
                ),
                AutomationTask(
                    id: notifyTaskID,
                    name: "Notify Timeout",
                    kind: .notification(AutomationNotificationSpec(
                        title: "Leave button did not appear",
                        body: "Check the battle result screen.",
                        severity: .warning
                    )),
                    resourceRequirement: .none
                )
            ],
            dependencies: [
                AutomationDependency(
                    id: UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!,
                    fromTaskID: tapTaskID,
                    toTaskID: waitTaskID,
                    trigger: .onSuccess,
                    delay: 1
                ),
                AutomationDependency(
                    id: UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000001")!,
                    fromTaskID: waitTaskID,
                    toTaskID: notifyTaskID,
                    trigger: .onTimeout
                )
            ],
            createdAt: startAt,
            modifiedAt: startAt
        )

        let result = AutomationWorkflowDraftExporter.export(
            workflow,
            options: AutomationWorkflowDraftExportOptions(macroCatalog: [
                AutomationWorkflowDraftMacroCatalogEntry(id: macroID, name: "Tap Screen")
            ])
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload>
            .workflowDraftExport(command: "workflow export", result: result)
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(
            AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload>.self,
            from: encoded
        )

        #expect(result.isExportable)
        #expect(result.workflowID == workflowID)
        #expect(result.document.workflow.name == "Battle exit")
        #expect(result.taskIDToKey[tapTaskID] == "tap_screen_aaaaaaaa")
        #expect(result.taskIDToKey[waitTaskID] == "wait_exit_bbbbbbbb")
        #expect(result.document.workflow.tasks.map(\.key) == [
            "tap_screen_aaaaaaaa",
            "wait_exit_bbbbbbbb",
            "notify_timeout_cccccccc"
        ])

        let tapDraft = try #require(result.document.workflow.tasks.first { $0.key == "tap_screen_aaaaaaaa" })
        #expect(tapDraft.type == "macro")
        #expect(tapDraft.macroRef?.id == macroID)
        #expect(tapDraft.macroRef?.name == "Tap Screen")
        #expect(tapDraft.schedule?.type == "repeating")
        #expect(tapDraft.schedule?.startAt == startAt)
        #expect(tapDraft.schedule?.every == 1)
        #expect(tapDraft.schedule?.unit == "days")
        #expect(tapDraft.resource == .foregroundInput)

        let waitDraft = try #require(result.document.workflow.tasks.first { $0.key == "wait_exit_bbbbbbbb" })
        #expect(waitDraft.type == "condition")
        #expect(waitDraft.condition?.type == "ocrText")
        #expect(waitDraft.condition?.text == "Leave")
        #expect(waitDraft.condition?.regionRef == "wait_exit_bbbbbbbb_region")
        #expect(waitDraft.timeoutSeconds == 120)
        #expect(waitDraft.pollingSeconds == 0.5)
        #expect(result.document.visualAssets?.regions == [
            AutomationWorkflowDraftVisualRegion(
                key: "wait_exit_bbbbbbbb_region",
                label: "Wait Exit",
                bounds: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                space: .displayNormalized
            )
        ])

        #expect(result.document.workflow.dependencies.map(\.trigger) == ["success", "timeout"])
        #expect(envelope.ok)
        #expect(envelope.warnings.isEmpty)
        #expect(decoded == envelope)
    }

    @Test("Workflow list and show payloads summarize run history")
    func workflowListAndShowPayloadsSummarizeRunHistory() throws {
        let workflowID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
        let taskID = UUID(uuidString: "91000000-0000-0000-0000-000000000002")!
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Nightly",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Wait",
                    kind: .delay(1)
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let run = AutomationTaskRun(
            id: UUID(uuidString: "91000000-0000-0000-0000-000000000003")!,
            executionID: UUID(uuidString: "91000000-0000-0000-0000-000000000004")!,
            workflowID: workflowID,
            taskID: taskID,
            status: .running,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )

        let listEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowListPayload>
            .workflowList(command: "workflow list", workflows: [workflow], runHistory: [run])
        let showEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowShowPayload>
            .workflowShow(command: "workflow show", workflow: workflow, runHistory: [run])

        #expect(listEnvelope.ok)
        #expect(listEnvelope.data?.count == 1)
        #expect(listEnvelope.data?.workflows.first?.id == workflowID)
        #expect(listEnvelope.data?.workflows.first?.runCount == 1)
        #expect(listEnvelope.data?.workflows.first?.latestRunStatus == .running)
        #expect(showEnvelope.data?.workflow.id == workflowID)
        #expect(showEnvelope.data?.runHistory == [run])
        #expect(showEnvelope.nextActions.contains { $0.command.contains("workflow export") })
    }

    @Test("Workflow status payload summarizes runtime state for UI and AI")
    func workflowStatusPayloadSummarizesRuntimeState() throws {
        let workflowID = UUID(uuidString: "92000000-0000-0000-0000-000000000001")!
        let runningTaskID = UUID(uuidString: "92000000-0000-0000-0000-000000000002")!
        let waitingTaskID = UUID(uuidString: "92000000-0000-0000-0000-000000000003")!
        let failedTaskID = UUID(uuidString: "92000000-0000-0000-0000-000000000004")!
        let macroID = UUID(uuidString: "92000000-0000-0000-0000-000000000005")!
        let executionID = UUID(uuidString: "92000000-0000-0000-0000-000000000006")!
        let generatedAt = Date(timeIntervalSince1970: 4_000)
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Battle loop",
            tasks: [
                AutomationTask(
                    id: runningTaskID,
                    name: "Tap Screen",
                    kind: .macro(macroID: macroID)
                ),
                AutomationTask(
                    id: waitingTaskID,
                    name: "Wait Exit",
                    kind: .delay(1)
                ),
                AutomationTask(
                    id: failedTaskID,
                    name: "Notify",
                    kind: .notification(AutomationNotificationSpec(title: "Failed", body: "Check evidence."))
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let runs = [
            AutomationTaskRun(
                id: UUID(uuidString: "92000000-0000-0000-0000-000000000007")!,
                executionID: executionID,
                workflowID: workflowID,
                taskID: runningTaskID,
                macroID: macroID,
                actualStartTime: Date(timeIntervalSince1970: 3_000),
                status: .running,
                createdAt: Date(timeIntervalSince1970: 2_900)
            ),
            AutomationTaskRun(
                id: UUID(uuidString: "92000000-0000-0000-0000-000000000008")!,
                executionID: executionID,
                workflowID: workflowID,
                taskID: waitingTaskID,
                earliestStartTime: Date(timeIntervalSince1970: 3_100),
                status: .waitingForResource,
                createdAt: Date(timeIntervalSince1970: 3_050)
            ),
            AutomationTaskRun(
                id: UUID(uuidString: "92000000-0000-0000-0000-000000000009")!,
                executionID: executionID,
                workflowID: workflowID,
                taskID: failedTaskID,
                actualStartTime: Date(timeIntervalSince1970: 2_000),
                completedAt: Date(timeIntervalSince1970: 2_100),
                status: .completed,
                outcome: .failed(report: nil),
                createdAt: Date(timeIntervalSince1970: 1_900)
            )
        ]

        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowStatusPayload>
            .workflowStatus(
                command: "workflow status",
                workflows: [workflow],
                runHistory: runs,
                generatedAt: generatedAt
            )
        let payload = try #require(envelope.data)
        let status = try #require(payload.workflows.first)
        let runningTask = try #require(status.tasks.first { $0.taskID == runningTaskID })
        let waitingTask = try #require(status.tasks.first { $0.taskID == waitingTaskID })
        let failedTask = try #require(status.tasks.first { $0.taskID == failedTaskID })

        #expect(envelope.ok)
        #expect(payload.generatedAt == generatedAt)
        #expect(status.overallStatus == .running)
        #expect(status.statusLabel == "正在执行")
        #expect(status.activeRunCount == 1)
        #expect(status.waitingRunCount == 1)
        #expect(status.attentionRunCount == 1)
        #expect(status.latestRun?.id == waitingTask.latestRunID)
        #expect(runningTask.status == .running)
        #expect(waitingTask.status == .waitingForResource)
        #expect(waitingTask.statusDetail == "正在等待鼠标键盘空闲。")
        #expect(failedTask.status == .needsAttention)
        #expect(failedTask.statusDetail == "最近一次运行失败。")
        #expect(envelope.nextActions.contains { $0.command.contains("workflow show") })
    }

    private func battleExitDocument() -> AutomationWorkflowDraftDocument {
        let exitID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        return AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
            name: "Battle exit",
            tasks: [
                AutomationWorkflowDraftTask(
                    key: "tap_screen",
                    type: "macro",
                    macroRef: AutomationWorkflowDraftMacroRef(name: "Tap Screen")
                ),
                AutomationWorkflowDraftTask(
                    key: "wait_exit",
                    type: "condition",
                    condition: AutomationWorkflowDraftCondition(type: "ocrText", text: "Leave"),
                    timeoutSeconds: 120
                ),
                AutomationWorkflowDraftTask(
                    key: "click_exit",
                    type: "macro",
                    macroRef: AutomationWorkflowDraftMacroRef(id: exitID, name: "Click Leave")
                ),
                AutomationWorkflowDraftTask(
                    key: "notify_timeout",
                    type: "notification",
                    notification: AutomationWorkflowDraftNotification(title: "Leave button did not appear")
                )
            ],
            dependencies: [
                AutomationWorkflowDraftDependency(
                    from: "tap_screen",
                    to: "wait_exit",
                    trigger: "success",
                    delaySeconds: 1
                ),
                AutomationWorkflowDraftDependency(
                    from: "wait_exit",
                    to: "click_exit",
                    trigger: "conditionMatched"
                ),
                AutomationWorkflowDraftDependency(
                    from: "wait_exit",
                    to: "notify_timeout",
                    trigger: "timeout"
                )
            ]
        ))
    }

    private func battleExitCatalog() -> [AutomationWorkflowDraftMacroCatalogEntry] {
        [
            AutomationWorkflowDraftMacroCatalogEntry(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                name: "Tap Screen",
                durationSeconds: 2,
                eventCount: 2,
                clickCount: 1
            ),
            AutomationWorkflowDraftMacroCatalogEntry(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                name: "Click Leave",
                durationSeconds: 1,
                eventCount: 2,
                clickCount: 1
            )
        ]
    }
}
