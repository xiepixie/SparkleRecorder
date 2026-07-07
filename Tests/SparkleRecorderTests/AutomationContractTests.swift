import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Core Contract Tests")
struct AutomationContractTests {
    @Test("Workflow contract round trips through Codable")
    func workflowContractRoundTrips() throws {
        let workflowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let macroID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let macroTaskID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let conditionTaskID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let dependencyID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let startsAt = Date(timeIntervalSince1970: 2_000)
        let visualAssets = AutomationWorkflowDraftVisualAssets(
            images: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "success_badge",
                    label: "Success badge",
                    path: "assets/success-badge.png"
                )
            ],
            baselines: [
                AutomationWorkflowDraftVisualImageAsset(
                    key: "checkout_start",
                    path: "baselines/checkout-start.png"
                )
            ]
        )

        let macroTask = AutomationTask(
            id: macroTaskID,
            name: "Checkout macro",
            kind: .macro(macroID: macroID),
            schedule: .once(startsAt),
            resourceRequirement: .foregroundInput,
            timeout: 30,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 3, backoff: .fixed(2))
        )
        let conditionTask = AutomationTask(
            id: conditionTaskID,
            name: "Verify success text",
            kind: .condition(AutomationConditionSpec(
                name: "Payment success",
                kind: .ocrText(AutomationOCRCondition(
                    text: "Payment complete",
                    matchMode: .contains,
                    searchRegion: RectValue(x: 0, y: 0, width: 400, height: 240)
                )),
                timeout: 5,
                pollingInterval: 0.2
            )),
            resourceRequirement: .backgroundReadOnly
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Nightly checkout",
            tasks: [macroTask, conditionTask],
            dependencies: [
                AutomationDependency(
                    id: dependencyID,
                    fromTaskID: macroTaskID,
                    toTaskID: conditionTaskID,
                    trigger: .onSuccess,
                    delay: 1.5
                )
            ],
            visualAssets: visualAssets,
            createdAt: startsAt,
            modifiedAt: startsAt
        )

        let encoded = try JSONEncoder().encode(workflow)
        let decoded = try JSONDecoder().decode(AutomationWorkflow.self, from: encoded)

        #expect(decoded == workflow)
        #expect(decoded.validationIssues().isEmpty)
        #expect(decoded.task(id: macroTaskID)?.kind.macroID == macroID)
        #expect(decoded.dependencies(from: macroTaskID).map(\.id) == [dependencyID])
        #expect(decoded.visualAssets == visualAssets)
    }

    @Test("OCR condition keeps legacy JSON compatible")
    func ocrConditionKeepsLegacyJSONCompatible() throws {
        let data = """
        {
          "text": "Ready",
          "matchMode": "contains",
          "searchRegion": {
            "x": 0.1,
            "y": 0.2,
            "width": 0.3,
            "height": 0.4
          },
          "requireVisible": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AutomationOCRCondition.self, from: data)

        #expect(decoded.text == "Ready")
        #expect(decoded.matchMode == .contains)
        #expect(decoded.searchRegion == RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        #expect(decoded.searchRegionSpace == .automatic)
        #expect(decoded.requireVisible)
    }

    @Test("Visual condition round trips through Codable")
    func visualConditionRoundTripsThroughCodable() throws {
        let condition = AutomationVisualCondition(
            type: .pixelMatched,
            regionRef: "battle_button",
            imageRef: "leave_button_template",
            baselineRef: "battle_result_baseline",
            pixel: AutomationGraphPoint(x: 0.5, y: 0.75),
            targetColorHex: "#FFCC00",
            pixelSampleRadius: 3,
            threshold: 0.82,
            requireVisible: true
        )
        let spec = AutomationConditionSpec(
            name: "Wait for button color",
            kind: .visual(condition),
            timeout: 30,
            pollingInterval: 0.5
        )

        let decoded = try JSONDecoder().decode(
            AutomationConditionSpec.self,
            from: try JSONEncoder().encode(spec)
        )

        #expect(decoded == spec)
    }

    @Test("Visual condition clamps pixel sample radius")
    func visualConditionClampsPixelSampleRadius() {
        #expect(AutomationVisualCondition(
            type: .pixelMatched,
            pixelSampleRadius: -1
        ).pixelSampleRadius == 0)
        #expect(AutomationVisualCondition(
            type: .pixelMatched,
            pixelSampleRadius: 99
        ).pixelSampleRadius == AutomationVisualCondition.maximumPixelSampleRadius)
    }

    @Test("OCR search region resolves display, window, and content spaces")
    func ocrSearchRegionResolvesCoordinateSpaces() {
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 800),
            windowFrame: RectValue(x: 100, y: 120, width: 500, height: 400),
            contentFrame: RectValue(x: 100, y: 160, width: 500, height: 360)
        )

        let automatic = AutomationOCRCondition(
            text: "Ready",
            searchRegion: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        )
        let windowLocal = AutomationOCRCondition(
            text: "Ready",
            searchRegion: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegionSpace: .windowLocal
        )
        let contentNormalized = AutomationOCRCondition(
            text: "Ready",
            searchRegion: RectValue(x: 0.2, y: 0.25, width: 0.4, height: 0.5),
            searchRegionSpace: .contentNormalized
        )
        let missingWindow = AutomationOCRCondition(
            text: "Ready",
            searchRegion: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegionSpace: .windowLocal
        )

        #expect(automatic.searchRegionResolution(in: context) == .resolved(
            RectValue(x: 100, y: 160, width: 300, height: 320)
        ))
        #expect(windowLocal.searchRegionResolution(in: context) == .resolved(
            RectValue(x: 110, y: 140, width: 30, height: 40)
        ))
        #expect(contentNormalized.searchRegionResolution(in: context) == .resolved(
            RectValue(x: 200, y: 250, width: 200, height: 180)
        ))
        #expect(missingWindow.searchRegionResolution(in: AutomationOCRSearchRegionContext(
            displayBounds: context.displayBounds
        )) == .unavailable)
    }

    @Test("Visual condition search region resolves using OCR coordinate spaces")
    func visualConditionSearchRegionResolvesCoordinateSpaces() {
        let context = AutomationOCRSearchRegionContext(
            displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 800),
            windowFrame: RectValue(x: 100, y: 120, width: 500, height: 400),
            contentFrame: RectValue(x: 100, y: 160, width: 500, height: 360)
        )

        let automatic = AutomationVisualCondition(
            type: .imageAppeared,
            searchRegion: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        )
        let windowLocal = AutomationVisualCondition(
            type: .regionChanged,
            searchRegion: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegionSpace: .windowLocal
        )
        let contentNormalized = AutomationVisualCondition(
            type: .pixelMatched,
            searchRegion: RectValue(x: 0.2, y: 0.25, width: 0.4, height: 0.5),
            searchRegionSpace: .contentNormalized
        )
        let missingWindow = AutomationVisualCondition(
            type: .imageDisappeared,
            searchRegion: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegionSpace: .windowLocal
        )

        #expect(automatic.searchRegionResolution(in: context) == .resolved(
            RectValue(x: 100, y: 160, width: 300, height: 320)
        ))
        #expect(windowLocal.searchRegionResolution(in: context) == .resolved(
            RectValue(x: 110, y: 140, width: 30, height: 40)
        ))
        #expect(contentNormalized.searchRegionResolution(in: context) == .resolved(
            RectValue(x: 200, y: 250, width: 200, height: 180)
        ))
        #expect(missingWindow.searchRegionResolution(in: AutomationOCRSearchRegionContext(
            displayBounds: context.displayBounds
        )) == .unavailable)
    }

    @Test("OCR condition editing preserves existing region bounds")
    func ocrConditionEditingPreservesExistingRegionBounds() {
        let existingRegion = RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let existing = AutomationOCRCondition(
            text: "Ready",
            matchMode: .contains,
            searchRegion: existingRegion,
            searchRegionSpace: .contentNormalized,
            requireVisible: true
        )

        let updated = existing.updatingTextMatchAndSpace(
            text: "Done",
            matchMode: .exact,
            searchRegionSpace: .windowNormalized,
            requireVisible: false
        )

        #expect(updated.text == "Done")
        #expect(updated.matchMode == .exact)
        #expect(updated.searchRegion == existingRegion)
        #expect(updated.searchRegionSpace == .windowNormalized)
        #expect(!updated.requireVisible)
    }

    @Test("OCR region picker selection writes display, window, and content bounds")
    func ocrRegionPickerSelectionWritesBoundsForCoordinateSpaces() {
        let selection = AutomationOCRSearchRegionSelection(
            displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 1_000),
            selectedDisplayRegion: RectValue(x: 250, y: 250, width: 100, height: 100),
            windowFrame: RectValue(x: 100, y: 100, width: 400, height: 400),
            contentFrame: RectValue(x: 200, y: 200, width: 200, height: 200)
        )

        #expect(selection.searchRegion(in: .automatic) == RectValue(x: 250, y: 250, width: 100, height: 100))
        #expect(selection.searchRegion(in: .displayAbsolute) == RectValue(x: 250, y: 250, width: 100, height: 100))
        #expect(selection.searchRegion(in: .displayNormalized) == RectValue(x: 0.25, y: 0.25, width: 0.1, height: 0.1))
        #expect(selection.searchRegion(in: .windowLocal) == RectValue(x: 150, y: 150, width: 100, height: 100))
        #expect(selection.searchRegion(in: .windowNormalized) == RectValue(x: 0.375, y: 0.375, width: 0.25, height: 0.25))
        #expect(selection.searchRegion(in: .contentLocal) == RectValue(x: 50, y: 50, width: 100, height: 100))
        #expect(selection.searchRegion(in: .contentNormalized) == RectValue(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test("OCR region picker selection reports unavailable window and content spaces")
    func ocrRegionPickerSelectionReportsMissingFrames() {
        let selection = AutomationOCRSearchRegionSelection(
            displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 1_000),
            selectedDisplayRegion: RectValue(x: 250, y: 250, width: 100, height: 100)
        )

        #expect(selection.searchRegion(in: .windowLocal) == nil)
        #expect(selection.searchRegion(in: .windowNormalized) == nil)
        #expect(selection.searchRegion(in: .contentLocal) == nil)
        #expect(selection.searchRegion(in: .contentNormalized) == nil)
    }

    @Test("Same saved macro creates independent task runs")
    func sameMacroCreatesIndependentRuns() {
        let workflowID = UUID()
        let macroID = UUID()
        let task = AutomationTask(
            name: "Reusable macro",
            kind: .macro(macroID: macroID),
            schedule: .manual
        )
        let firstTime = Date(timeIntervalSince1970: 10)
        let secondTime = Date(timeIntervalSince1970: 20)

        let firstRun = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            scheduledStartTime: firstTime
        )
        let secondRun = task.makeRun(
            workflowID: workflowID,
            runID: UUID(),
            scheduledStartTime: secondTime
        )

        #expect(firstRun.id != secondRun.id)
        #expect(firstRun.workflowID == workflowID)
        #expect(firstRun.taskID == secondRun.taskID)
        #expect(firstRun.macroID == macroID)
        #expect(secondRun.macroID == macroID)
        #expect(firstRun.scheduledStartTime == firstTime)
        #expect(secondRun.scheduledStartTime == secondTime)
        #expect(firstRun.status == .planned)
        #expect(firstRun.outcome == nil)
    }

    @Test("Batch resource lease action round trips through Codable")
    func batchResourceLeaseActionRoundTrips() throws {
        let runID = UUID()
        let acquiredAt = Date(timeIntervalSince1970: 25)
        let action = AutomationAction.resourceLeasesAcquired(
            runID: runID,
            leases: [
                AutomationResourceLease(
                    id: UUID(),
                    runID: runID,
                    resource: .foregroundInput,
                    acquiredAt: acquiredAt
                ),
                AutomationResourceLease(
                    id: UUID(),
                    runID: runID,
                    resource: .screenCapture,
                    acquiredAt: acquiredAt
                )
            ],
            at: acquiredAt
        )

        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)

        #expect(decoded == action)
    }

    @Test("Condition evaluation effect round trips previous outcomes through Codable")
    func conditionEvaluationEffectRoundTripsPreviousOutcomes() throws {
        let effect = AutomationEffect.evaluateCondition(
            runID: UUID(),
            workflowID: UUID(),
            taskID: UUID(),
            condition: AutomationConditionSpec(
                name: "Previous success",
                kind: .previousOutcome(.success)
            ),
            previousOutcomes: [
                .failed(report: nil),
                .succeeded(report: nil)
            ]
        )

        let encoded = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(AutomationEffect.self, from: encoded)

        #expect(decoded == effect)
    }

    @Test("Condition evaluation action round trips diagnostics through Codable")
    func conditionEvaluationActionRoundTripsDiagnostics() throws {
        let runID = UUID()
        let action = AutomationAction.conditionEvaluationCompleted(
            runID: runID,
            result: AutomationConditionEvaluationResult(
                outcome: .conditionNotMatched,
                evidence: AutomationConditionEvaluationEvidence(
                    runID: runID,
                    workflowID: UUID(),
                    taskID: UUID(),
                    conditionID: UUID(),
                    kind: .ocrText,
                    outcome: .conditionNotMatched,
                    evaluatedAt: Date(timeIntervalSince1970: 1_200),
                    sampleCount: 5,
                    displayBounds: RectValue(x: 0, y: 0, width: 800, height: 600),
                    resolvedSearchRegion: RectValue(x: 10, y: 20, width: 100, height: 50),
                    searchRegionSpace: .displayAbsolute,
                    targetDescription: "Leave",
                    observedSummary: "Detected text: Battle Complete",
                    fields: [
                        AutomationConditionDiagnosticField(id: "lastTexts", title: "Last texts", value: "Battle Complete")
                    ],
                    artifacts: [
                        AutomationConditionDiagnosticArtifact(
                            id: "regionSampleImage",
                            title: "Watched region",
                            kind: .regionSampleImage,
                            relativePath: "AutomationEvidence/\(runID.uuidString)/condition-region-sample.png",
                            pixelBounds: RectValue(x: 10, y: 20, width: 100, height: 50),
                            createdAt: Date(timeIntervalSince1970: 1_200)
                        )
                    ]
                )
            ),
            at: Date(timeIntervalSince1970: 1_205)
        )

        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)

        #expect(decoded == action)
    }

    @Test("Condition diagnostics decode old payloads without artifact references")
    func conditionDiagnosticsDecodeOldPayloadsWithoutArtifacts() throws {
        let runID = UUID()
        let workflowID = UUID()
        let taskID = UUID()
        let conditionID = UUID()
        let json = """
        {
          "runID": "\(runID.uuidString)",
          "workflowID": "\(workflowID.uuidString)",
          "taskID": "\(taskID.uuidString)",
          "conditionID": "\(conditionID.uuidString)",
          "kind": "ocrText",
          "outcome": {
            "conditionNotMatched": {}
          },
          "evaluatedAt": 1200,
          "sampleCount": 2,
          "targetDescription": "Leave",
          "observedSummary": "Detected text: Battle Complete",
          "fields": []
        }
        """

        let decoded = try JSONDecoder().decode(
            AutomationConditionEvaluationEvidence.self,
            from: Data(json.utf8)
        )

        #expect(decoded.runID == runID)
        #expect(decoded.artifacts.isEmpty)
        #expect(decoded.sampleCount == 2)
        #expect(decoded.targetDescription == "Leave")
    }

    @Test("Condition diagnostic artifact paths stay relative to the evidence directory")
    func conditionDiagnosticArtifactPathsStayRelative() {
        let artifact = AutomationConditionDiagnosticArtifact(
            id: "sample",
            title: "Last sample",
            kind: .displaySampleImage,
            relativePath: "AutomationEvidence//run-id/condition-last-sample.png"
        )
        let baseURL = URL(fileURLWithPath: "/tmp/SparkleRecorder", isDirectory: true)

        #expect(artifact.normalizedRelativePath == "AutomationEvidence/run-id/condition-last-sample.png")
        #expect(artifact.resolvedURL(relativeTo: baseURL)?.path == "/tmp/SparkleRecorder/AutomationEvidence/run-id/condition-last-sample.png")
        #expect(AutomationConditionDiagnosticArtifact.normalizedRelativePath("../outside.png") == nil)
        #expect(AutomationConditionDiagnosticArtifact.normalizedRelativePath("/tmp/outside.png") == nil)
        #expect(AutomationConditionDiagnosticArtifact.normalizedRelativePath("~/outside.png") == nil)
        #expect(AutomationConditionDiagnosticArtifact.normalizedRelativePath("file:/tmp/outside.png") == nil)
        #expect(AutomationConditionDiagnosticArtifact.normalizedRelativePath("AutomationEvidence\\sample.png") == nil)
        #expect(AutomationConditionDiagnosticArtifact.normalizedRelativePath("AutomationEvidence/./sample.png") == nil)
    }

    @Test("Resource requirement max wait stays Codable compatible")
    func resourceRequirementMaxWaitStaysCodableCompatible() throws {
        let json = """
        {
          "resources": [
            "foregroundInput"
          ],
          "priority": "high",
          "leaseTimeout": 10
        }
        """
        let decoded = try JSONDecoder().decode(
            AutomationResourceRequirement.self,
            from: Data(json.utf8)
        )
        let requirement = AutomationResourceRequirement(
            resources: [.foregroundInput],
            priority: .high,
            leaseTimeout: -2,
            maxWaitDuration: -5
        )

        let roundTripped = try JSONDecoder().decode(
            AutomationResourceRequirement.self,
            from: JSONEncoder().encode(requirement)
        )

        #expect(decoded.resources == [.foregroundInput])
        #expect(decoded.priority == .high)
        #expect(decoded.leaseTimeout == 10)
        #expect(decoded.maxWaitDuration == nil)
        #expect(roundTripped.leaseTimeout == 0)
        #expect(roundTripped.maxWaitDuration == 0)
    }

    @Test("View intent round trips task movement through Codable")
    func viewIntentRoundTripsTaskMovement() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let position = AutomationGraphPoint(x: 144, y: 96)
        let movedAt = Date(timeIntervalSince1970: 30)
        let intent = AutomationViewIntent.moveTask(
            workflowID: workflowID,
            taskID: taskID,
            position: position
        )

        let encoded = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(AutomationViewIntent.self, from: encoded)

        #expect(decoded == intent)
        #expect(decoded.reducerAction(at: movedAt) == .moveTask(
            workflowID: workflowID,
            taskID: taskID,
            position: position,
            at: movedAt
        ))
    }

    @Test("View intent maps task start to manual start action")
    func viewIntentMapsTaskStartToManualStartAction() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let requestedAt = Date(timeIntervalSince1970: 31)
        let intent = AutomationViewIntent.startTask(workflowID: workflowID, taskID: taskID)

        let encoded = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(AutomationViewIntent.self, from: encoded)

        #expect(decoded == intent)
        #expect(decoded.reducerAction(at: requestedAt) == .manualStart(
            workflowID: workflowID,
            taskID: taskID,
            requestedAt: requestedAt
        ))
    }

    @Test("Dependency triggers match terminal outcomes")
    func dependencyTriggersMatchTerminalOutcomes() {
        let success = AutomationOutcome.succeeded(report: nil)
        let failed = AutomationOutcome.failed(report: nil)
        let denied = AutomationOutcome.permissionDenied(permission: .accessibility, message: "Need permission")
        let timeout = AutomationOutcome.timedOut(deadline: Date(timeIntervalSince1970: 30))
        let cancelled = AutomationOutcome.cancelled(reason: "User stopped")

        #expect(AutomationDependencyTrigger.onSuccess.matches(success))
        #expect(!AutomationDependencyTrigger.onSuccess.matches(failed))
        #expect(AutomationDependencyTrigger.onFailure.matches(failed))
        #expect(AutomationDependencyTrigger.onFailure.matches(denied))
        #expect(AutomationDependencyTrigger.onTimeout.matches(timeout))
        #expect(AutomationDependencyTrigger.onCancelled.matches(cancelled))
        #expect(AutomationDependencyTrigger.onConditionMatched.matches(.conditionMatched))
        #expect(AutomationDependencyTrigger.onConditionNotMatched.matches(.conditionNotMatched))
        #expect(AutomationDependencyTrigger.always.matches(success))
        #expect(AutomationDependencyTrigger.onOutcome(.anyTerminal).matches(.missingMacro(macroID: UUID())))
    }

    @Test("Workflow validation catches broken edges and cycles")
    func workflowValidationCatchesBrokenEdgesAndCycles() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let missingTaskID = UUID()
        let selfDependencyID = UUID()
        let brokenDependencyID = UUID()
        let first = AutomationTask(id: firstTaskID, name: "A", kind: .delay(1), resourceRequirement: .none)
        let second = AutomationTask(id: secondTaskID, name: "B", kind: .delay(1), resourceRequirement: .none)
        let workflow = AutomationWorkflow(
            name: "Invalid",
            tasks: [first, second],
            dependencies: [
                AutomationDependency(id: selfDependencyID, fromTaskID: firstTaskID, toTaskID: firstTaskID, trigger: .always),
                AutomationDependency(id: brokenDependencyID, fromTaskID: secondTaskID, toTaskID: missingTaskID, trigger: .always),
                AutomationDependency(fromTaskID: firstTaskID, toTaskID: secondTaskID, trigger: .always),
                AutomationDependency(fromTaskID: secondTaskID, toTaskID: firstTaskID, trigger: .always)
            ]
        )

        let issues = workflow.validationIssues()

        #expect(issues.contains(.selfDependency(dependencyID: selfDependencyID, taskID: firstTaskID)))
        #expect(issues.contains(.missingDependencyTarget(dependencyID: brokenDependencyID, taskID: missingTaskID)))
        #expect(issues.contains { issue in
            if case .cycleDetected = issue {
                return true
            }
            return false
        })
    }

    @Test("Run lifecycle helpers keep evidence and outcome separate from SavedMacro")
    func runLifecycleHelpersKeepRuntimeStateInRun() {
        let runID = UUID()
        let leaseID = UUID()
        let evidenceID = UUID()
        let conditionEvidence = AutomationConditionEvaluationEvidence(
            runID: runID,
            workflowID: UUID(),
            taskID: UUID(),
            conditionID: UUID(),
            kind: .imageAppeared,
            outcome: .conditionNotMatched,
            evaluatedAt: Date(timeIntervalSince1970: 54),
            sampleCount: 3,
            displayBounds: RectValue(x: 0, y: 0, width: 1_440, height: 900),
            resolvedSearchRegion: RectValue(x: 100, y: 120, width: 240, height: 160),
            searchRegionSpace: .displayAbsolute,
            targetDescription: "leave_button_template",
            observedSummary: "Template similarity 0.61",
            score: 0.61,
            threshold: 0.92,
            fields: [
                AutomationConditionDiagnosticField(id: "score", title: "Best similarity", value: "0.61")
            ],
            artifacts: [
                AutomationConditionDiagnosticArtifact(
                    id: "lastSampleImage",
                    title: "Last sample",
                    kind: .displaySampleImage,
                    relativePath: "AutomationEvidence/\(runID.uuidString)/condition-last-sample.png",
                    pixelBounds: RectValue(x: 0, y: 0, width: 1_440, height: 900)
                )
            ]
        )
        let task = AutomationTask(name: "Macro", kind: .macro(macroID: UUID()))
        let run = task.makeRun(workflowID: UUID(), runID: runID)
        let started = run.started(at: Date(timeIntervalSince1970: 50), leaseID: leaseID)
        let completed = started.completed(
            with: .failed(report: RunReport(
                runID: runID,
                startTime: Date(timeIntervalSince1970: 50),
                duration: 4,
                isSuccess: false,
                failedEventIndex: 2,
                errorMessage: "OCR did not find success text"
            )),
            at: Date(timeIntervalSince1970: 54),
            evidenceID: evidenceID,
            conditionEvidence: conditionEvidence
        )
        let decoded = try? JSONDecoder().decode(
            AutomationTaskRun.self,
            from: JSONEncoder().encode(completed)
        )

        #expect(started.status == .running)
        #expect(started.leaseID == leaseID)
        #expect(completed.status == .completed)
        #expect(completed.isTerminal)
        #expect(completed.evidenceID == evidenceID)
        #expect(completed.conditionEvidence == conditionEvidence)
        #expect(completed.outcome != nil)
        #expect(decoded?.conditionEvidence == conditionEvidence)
    }
}
