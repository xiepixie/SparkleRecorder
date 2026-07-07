import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation View Projection Tests")
struct AutomationViewProjectionTests {
    @Test("Macro Review source presentation exposes saved macro scope")
    func macroReviewSourcePresentationExposesSavedMacroScope() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let recordingID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Review flow",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Upload report",
                    kind: .macro(macroID: macroID)
                )
            ]
        )
        let reference = MacroSemanticRecordingReference(
            recordingID: recordingID,
            bundleRelativePath: "SemanticRecordings/demo",
            manifestRelativePath: "SemanticRecordings/demo/manifest.json",
            capturedAt: capturedAt,
            eventCount: 4
        )
        let macro = SavedMacro(
            id: macroID,
            name: "Upload report",
            events: [TestFixtures.clickEvent()],
            semanticRecording: reference
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID
        )

        let presentation = AutomationMacroReviewSourcePresentation.make(
            run: run,
            workflow: workflow,
            macros: [macro]
        )

        #expect(presentation.sourceKind == .savedMacro)
        #expect(presentation.macroID == macroID)
        #expect(presentation.macroName == "Upload report")
        #expect(presentation.recordingReference == reference)
        #expect(presentation.canRevealLinkedBundle)
        #expect(presentation.buttonTitle(isOpening: false) == "Open Linked Review")
        #expect(presentation.buttonTitle(isOpening: true) == "Opening")
        #expect(presentation.summary == "Open the semantic recording captured with Upload report. It includes 4 timeline events; this run does not carry a separate semantic bundle yet.")
        #expect(presentation.readinessBadges == [
            .init(title: "Source", value: "Saved Macro"),
            .init(title: "Scope", value: "Macro-level"),
            .init(title: "Run", value: "Not bound"),
            .init(title: "Fallback", value: "Bundle Picker")
        ])
        #expect(presentation.decisionRows == [
            .init(
                title: "Next step",
                value: "Open linked review",
                detail: "Uses the semantic recording attached to the saved macro and preselects the closest event or condition evidence when the run outcome provides a target.",
                tone: .ready
            ),
            .init(
                title: "Evidence binding",
                value: "Macro-level",
                detail: "This run does not yet carry a per-run semantic bundle, so review evidence is useful for repair but not accepted as live run proof.",
                tone: .needsInput
            ),
            .init(
                title: "Mutation boundary",
                value: "Review only",
                detail: "Opening Macro Review never mutates the workflow; reviewed changes still need Draft Preview and confirmed import.",
                tone: .reviewOnly
            )
        ])
    }

    @Test("Macro Review source presentation resolves macro from workflow task")
    func macroReviewSourcePresentationResolvesMacroFromWorkflowTask() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Review flow",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Upload report",
                    kind: .macro(macroID: macroID)
                )
            ]
        )
        let reference = MacroSemanticRecordingReference(
            recordingID: UUID(),
            bundleRelativePath: "SemanticRecordings/demo",
            manifestRelativePath: "SemanticRecordings/demo/manifest.json",
            eventCount: 2
        )
        let macro = SavedMacro(
            id: macroID,
            name: "Upload report",
            events: [TestFixtures.clickEvent()],
            semanticRecording: reference
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID
        )

        let presentation = AutomationMacroReviewSourcePresentation.make(
            run: run,
            workflow: workflow,
            macros: [macro]
        )

        #expect(presentation.sourceKind == .savedMacro)
        #expect(presentation.macroID == macroID)
        #expect(presentation.recordingReference == reference)
    }

    @Test("Macro Review source presentation keeps manual fallback explicit")
    func macroReviewSourcePresentationKeepsManualFallbackExplicit() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Review flow",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Upload report",
                    kind: .macro(macroID: macroID)
                )
            ]
        )
        let macro = SavedMacro(
            id: macroID,
            name: "Upload report",
            events: [TestFixtures.clickEvent()]
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID
        )

        let presentation = AutomationMacroReviewSourcePresentation.make(
            run: run,
            workflow: workflow,
            macros: [macro]
        )

        #expect(presentation.sourceKind == .manualBundle)
        #expect(presentation.macroID == macroID)
        #expect(presentation.macroName == "Upload report")
        #expect(presentation.recordingReference == nil)
        #expect(!presentation.canRevealLinkedBundle)
        #expect(presentation.buttonTitle(isOpening: false) == "Open Review")
        #expect(presentation.summary == "Open a semantic recording bundle for frame timeline, visual evidence, region selection, and review-only draft patch generation.")
        #expect(presentation.readinessBadges == [
            .init(title: "Source", value: "Manual"),
            .init(title: "Scope", value: "User-picked"),
            .init(title: "Run", value: "Not bound"),
            .init(title: "Fallback", value: "Bundle Picker")
        ])
        #expect(presentation.decisionRows == [
            .init(
                title: "Next step",
                value: "Choose bundle",
                detail: "No semantic recording link was found for this macro or run; choose a bundle before reviewing frames, OCR, or visual evidence.",
                tone: .needsInput
            ),
            .init(
                title: "Evidence binding",
                value: "Manual selection",
                detail: "The selected bundle is not proven to belong to this run, so use it for local review until S2 provides a saved-macro-linked live bundle.",
                tone: .needsInput
            ),
            .init(
                title: "Mutation boundary",
                value: "Review only",
                detail: "Opening Macro Review never mutates the workflow; reviewed changes still need Draft Preview and confirmed import.",
                tone: .reviewOnly
            )
        ])
    }

    @Test("Macro Review source presentation copy has localized catalog entries")
    func macroReviewSourcePresentationCopyHasLocalizedCatalogEntries() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Review flow",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Upload report",
                    kind: .macro(macroID: macroID)
                )
            ]
        )
        let reference = MacroSemanticRecordingReference(
            recordingID: UUID(),
            bundleRelativePath: "SemanticRecordings/demo",
            manifestRelativePath: "SemanticRecordings/demo/manifest.json",
            eventCount: 4
        )
        let linkedMacro = SavedMacro(
            id: macroID,
            name: "Upload report",
            events: [TestFixtures.clickEvent()],
            semanticRecording: reference
        )
        let manualMacro = SavedMacro(
            id: macroID,
            name: "Upload report",
            events: [TestFixtures.clickEvent()]
        )
        let runs = [
            AutomationTaskRun(workflowID: workflowID, taskID: taskID, macroID: macroID),
            AutomationTaskRun(
                workflowID: workflowID,
                taskID: taskID,
                macroID: macroID,
                outcome: .failed(report: nil)
            ),
            AutomationTaskRun(
                workflowID: workflowID,
                taskID: taskID,
                macroID: macroID,
                outcome: .timedOut(deadline: Date(timeIntervalSince1970: 2_000))
            ),
            AutomationTaskRun(
                workflowID: workflowID,
                taskID: taskID,
                macroID: macroID,
                outcome: .conditionNotMatched
            )
        ]
        let presentations = runs.flatMap { run in
            [
                AutomationMacroReviewSourcePresentation.make(
                    run: run,
                    workflow: workflow,
                    macros: [linkedMacro]
                ),
                AutomationMacroReviewSourcePresentation.make(
                    run: run,
                    workflow: workflow,
                    macros: [manualMacro]
                )
            ]
        }
        let summaryFormat = "Open the semantic recording captured with %@. It includes %d timeline events; this run does not carry a separate semantic bundle yet."
        let keys = presentations.reduce(into: Set([summaryFormat])) { keys, presentation in
            if presentation.sourceKind == .manualBundle {
                keys.insert(presentation.summary)
            }
            keys.insert(presentation.buttonTitle(isOpening: false))
            keys.insert(presentation.buttonTitle(isOpening: true))
            for badge in presentation.readinessBadges {
                keys.insert(badge.title)
                if !badge.value.hasPrefix("Event #") {
                    keys.insert(badge.value)
                }
            }
            for row in presentation.decisionRows {
                keys.insert(row.title)
                keys.insert(row.value)
                keys.insert(row.detail)
            }
        }
        let catalog = try localizationCatalog()

        var missingEntries: [String] = []
        var missingEnglish: [String] = []
        var missingSimplifiedChinese: [String] = []
        for key in keys.sorted() {
            guard let entry = catalog[key] as? [String: Any] else {
                missingEntries.append(key)
                continue
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            if localizations["en"] == nil {
                missingEnglish.append(key)
            }
            if localizations["zh-Hans"] == nil {
                missingSimplifiedChinese.append(key)
            }
        }

        #expect(missingEntries.isEmpty, "Missing Localizable.xcstrings entries: \(missingEntries)")
        #expect(missingEnglish.isEmpty, "Missing English localizations: \(missingEnglish)")
        #expect(missingSimplifiedChinese.isEmpty, "Missing Simplified Chinese localizations: \(missingSimplifiedChinese)")
    }

    @Test("Macro Review source presentation exposes failed event target")
    func macroReviewSourcePresentationExposesFailedEventTarget() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let reference = MacroSemanticRecordingReference(
            recordingID: UUID(),
            bundleRelativePath: "SemanticRecordings/demo",
            manifestRelativePath: "SemanticRecordings/demo/manifest.json",
            eventCount: 4
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Review flow",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Upload report",
                    kind: .macro(macroID: macroID)
                )
            ]
        )
        let macro = SavedMacro(
            id: macroID,
            name: "Upload report",
            events: [TestFixtures.clickEvent()],
            semanticRecording: reference
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            outcome: .failed(report: RunReport(
                runID: UUID(),
                startTime: Date(timeIntervalSince1970: 1_800_000_000),
                duration: 12,
                isSuccess: false,
                failedEventIndex: 2,
                errorMessage: "Upload receipt was not visible"
            ))
        )

        let presentation = AutomationMacroReviewSourcePresentation.make(
            run: run,
            workflow: workflow,
            macros: [macro]
        )

        #expect(presentation.readinessBadges == [
            .init(title: "Source", value: "Saved Macro"),
            .init(title: "Scope", value: "Macro-level"),
            .init(title: "Run", value: "Not bound"),
            .init(title: "Target", value: "Event #3"),
            .init(title: "Evidence", value: "Failure report"),
            .init(title: "Fallback", value: "Bundle Picker")
        ])
    }

    @Test("Macro Review source presentation exposes condition evidence target")
    func macroReviewSourcePresentationExposesConditionEvidenceTarget() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Review flow",
            tasks: [
                AutomationTask(
                    id: taskID,
                    name: "Wait for receipt",
                    kind: .macro(macroID: macroID)
                )
            ]
        )
        let macro = SavedMacro(
            id: macroID,
            name: "Wait for receipt",
            events: [TestFixtures.clickEvent()]
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            outcome: .conditionNotMatched
        )

        let presentation = AutomationMacroReviewSourcePresentation.make(
            run: run,
            workflow: workflow,
            macros: [macro]
        )

        #expect(presentation.readinessBadges == [
            .init(title: "Source", value: "Manual"),
            .init(title: "Scope", value: "User-picked"),
            .init(title: "Run", value: "Not bound"),
            .init(title: "Target", value: "Condition"),
            .init(title: "Evidence", value: "Else branch"),
            .init(title: "Fallback", value: "Bundle Picker")
        ])
    }

    @Test("Owner C fixture exposes all first milestone statuses")
    func ownerCFixtureExposesAllFirstMilestoneStatuses() {
        let projection = AutomationOverviewProjection.ownerCFixture()
        let statuses = Set(projection.workflows.flatMap { $0.nodes.map(\.status) })

        #expect(statuses.contains(.scheduled))
        #expect(statuses.contains(.waiting))
        #expect(statuses.contains(.running))
        #expect(statuses.contains(.failed))
        #expect(statuses.contains(.cancelled))
        #expect(statuses.contains(.timedOut))
        #expect(statuses.contains(.blocked))
    }

    @Test("Owner C fixture exposes resource waiting and retry review states")
    func ownerCFixtureExposesResourceWaitingAndRetryReviewStates() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let projection = AutomationOverviewProjection.ownerCFixture(now: now)
        let workflow = try #require(projection.workflows.first)
        let nodesByTitle = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.title, $0) })

        let resourceWaitNode = try #require(nodesByTitle["Wait for mouse handoff"])
        #expect(resourceWaitNode.status == .waiting)
        #expect(resourceWaitNode.statusDetail == "Waiting for mouse and keyboard")
        let resourceWaiting = try #require(resourceWaitNode.resourceWaiting)
        #expect(resourceWaiting.detail == "Waiting for mouse and keyboard")
        #expect(resourceWaiting.resources == [.foregroundInput])
        #expect(resourceWaiting.resourceLabels == ["Needs mouse and keyboard"])
        #expect(resourceWaiting.priority == .normal)
        #expect(resourceWaiting.priorityLabel == "Normal priority")
        #expect(resourceWaiting.waitingSince == now.addingTimeInterval(-250))
        #expect(resourceWaiting.waitedDuration == 250)
        #expect(resourceWaiting.blockers.isEmpty)

        let resourceWaitTimeline = try #require(projection.timelineItems.first {
            $0.title == "Wait for mouse handoff"
        })
        #expect(resourceWaitTimeline.status == .waiting)
        #expect(resourceWaitTimeline.lane == .foregroundInput)
        #expect(resourceWaitTimeline.resourceWaiting == resourceWaiting)

        let retryNode = try #require(nodesByTitle["Retry upload receipt"])
        let retrySummary = try #require(retryNode.retryAttemptSummary)
        #expect(retrySummary.currentAttempt == 2)
        #expect(retrySummary.maxAttempts == 3)
        #expect(retrySummary.remainingAttempts == 1)
        #expect(retrySummary.nextRetryAt == now.addingTimeInterval(120))

        let retryTimeline = try #require(projection.timelineItems.first {
            $0.title == "Retry upload receipt" && $0.retryAttemptSummary != nil
        })
        #expect(retryTimeline.retryAttemptSummary == retrySummary)
    }

    @Test("Owner C fixture exposes join policy review state")
    func ownerCFixtureExposesJoinPolicyReviewState() throws {
        let projection = AutomationOverviewProjection.ownerCFixture()
        let workflow = try #require(projection.workflows.first)
        let nodesByTitle = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.title, $0) })

        let joinNode = try #require(nodesByTitle["Send failure notice"])

        #expect(joinNode.joinPolicy == .any)
        #expect(joinNode.joinPolicyLabel == "Any incoming branch")
        #expect(joinNode.incomingDependencyCount == 2)
    }

    @Test("Owner C fixture exposes visual condition progress state")
    func ownerCFixtureExposesVisualConditionProgressState() throws {
        let projection = AutomationOverviewProjection.ownerCFixture()
        let workflow = try #require(projection.workflows.first)
        let nodesByTitle = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.title, $0) })

        let visualNode = try #require(nodesByTitle["Watch spinner disappearance"])
        let progress = try #require(visualNode.conditionProgress)

        #expect(visualNode.status == .running)
        #expect(progress.kind == .imageDisappeared)
        #expect(progress.kindLabel == "Image disappeared")
        #expect(progress.targetLabel == "loading_spinner_template")
        #expect(progress.regionRef == "battle_result_area")
        #expect(progress.imageRef == "loading_spinner_template")
        #expect(progress.isActivelyPolling)
        #expect(projection.timelineItems.contains { item in
            item.title == "Watch spinner disappearance" &&
                item.conditionProgress == progress &&
                item.lane == .screenCapture
        })
    }

    @Test("Owner C fixture exposes visual diagnostics artifact evidence")
    func ownerCFixtureExposesVisualDiagnosticsArtifactEvidence() throws {
        let state = AutomationRunState.ownerCFixture()
        let run = try #require(state.runs.first {
            $0.id.uuidString == "00000000-0000-0000-0000-00000000C40C"
        })
        let evidence = try #require(run.conditionEvidence)

        #expect(evidence.kind == .imageDisappeared)
        #expect(evidence.outcome == .conditionMatched)
        #expect(evidence.sampleCount == 8)
        #expect(evidence.resolvedSearchRegion == RectValue(x: 520, y: 284, width: 360, height: 220))
        #expect(evidence.artifacts.map(\.kind) == [.displaySampleImage, .regionSampleImage])
        #expect(evidence.artifacts.map(\.relativePath) == [
            "fixture-artifacts/visual-condition/condition-last-sample.png",
            "fixture-artifacts/visual-condition/condition-region-sample.png"
        ])
    }

    @Test("Owner C fixture exposes failed run evidence binding")
    func ownerCFixtureExposesFailedRunEvidenceBinding() throws {
        let state = AutomationRunState.ownerCFixture()
        let run = try #require(state.runs.first {
            $0.id.uuidString == "00000000-0000-0000-0000-00000000C409"
        })

        #expect(run.status == .completed)
        #expect(run.evidenceID == run.id)
        guard case .failed(let report) = run.outcome else {
            Issue.record("Expected failed run outcome")
            return
        }
        #expect(report?.runID == run.id)
        #expect(report?.failedEventIndex == 2)
        #expect(report?.errorMessage == "Upload receipt was not visible")
    }

    @Test("Condition diagnostics mark graph and timeline evidence")
    func conditionDiagnosticsMarkGraphAndTimelineEvidence() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let conditionID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let task = AutomationTask(
            id: taskID,
            name: "Watch visual state",
            kind: .condition(AutomationConditionSpec(
                id: conditionID,
                name: "Spinner gone",
                kind: .visual(AutomationVisualCondition(type: .imageDisappeared, imageRef: "spinner"))
            )),
            resourceRequirement: .backgroundReadOnly
        )
        let evidence = AutomationConditionEvaluationEvidence(
            runID: UUID(),
            workflowID: workflowID,
            taskID: taskID,
            conditionID: conditionID,
            kind: .imageDisappeared,
            outcome: .conditionMatched,
            evaluatedAt: completedAt,
            sampleCount: 3,
            targetDescription: "spinner",
            observedSummary: "Template absent 0.12",
            score: 0.12,
            threshold: 0.92
        )
        let run = AutomationTaskRun(
            id: evidence.runID,
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: completedAt.addingTimeInterval(-2),
            completedAt: completedAt,
            status: .completed,
            outcome: .conditionMatched,
            createdAt: completedAt.addingTimeInterval(-2),
            conditionEvidence: evidence
        )
        let state = AutomationRunState(
            workflows: [AutomationWorkflow(id: workflowID, name: "Visual", tasks: [task])],
            runs: [run]
        )

        let projection = AutomationViewProjection.overview(from: state)
        let node = try #require(projection.workflows.first?.nodes.first)
        let timelineItem = try #require(projection.timelineItems.first)

        #expect(node.hasEvidence)
        #expect(timelineItem.hasEvidence)
    }

    @Test("Dependency edges contain precomputed Canvas endpoints")
    func dependencyEdgesContainPrecomputedCanvasEndpoints() throws {
        let projection = AutomationOverviewProjection.ownerCFixture()
        let workflow = try #require(projection.workflows.first)

        #expect(!workflow.edges.isEmpty)
        #expect(workflow.edges.allSatisfy { edge in
            edge.start.x < edge.end.x || edge.status == .blocked
        })
        #expect(workflow.edges.allSatisfy { edge in
            edge.start.y >= 0 && edge.end.y >= 0
        })
    }

    @Test("Timeline labels stay user-facing")
    func timelineLabelsStayUserFacing() {
        let projection = AutomationOverviewProjection.ownerCFixture()
        let labels = projection.timelineItems.map(\.lane.displayName) + projection.timelineItems.map(\.resourceLabel)

        #expect(!labels.contains { $0.localizedStandardContains("Channel") })
        #expect(labels.contains("Needs mouse and keyboard"))
        #expect(labels.contains("Screen capture"))
        #expect(labels.contains("Completed"))
    }

    @Test("Latest run decides task status")
    func latestRunDecidesTaskStatus() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let task = AutomationTask(id: taskID, name: "Retryable", kind: .delay(1), resourceRequirement: .none)
        let workflow = AutomationWorkflow(id: workflowID, name: "Retries", tasks: [task])
        let older = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            completedAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            outcome: .failed(report: nil),
            createdAt: Date(timeIntervalSince1970: 90)
        )
        let newer = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: Date(timeIntervalSince1970: 200),
            status: .running,
            createdAt: Date(timeIntervalSince1970: 190)
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [older, newer],
            now: Date(timeIntervalSince1970: 201)
        ))
        let node = try #require(projection.workflows.first?.nodes.first)

        #expect(node.runID == newer.id)
        #expect(node.status == .running)
    }

    @Test("Workflow status summary is projected outside SwiftUI")
    func workflowStatusSummaryIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let runningTaskID = UUID()
        let waitingTaskID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Runtime summary",
            tasks: [
                AutomationTask(id: runningTaskID, name: "Run", kind: .delay(1), resourceRequirement: .none),
                AutomationTask(id: waitingTaskID, name: "Wait", kind: .delay(1), resourceRequirement: .foregroundInput)
            ]
        )
        let runs = [
            AutomationTaskRun(
                workflowID: workflowID,
                taskID: runningTaskID,
                actualStartTime: Date(timeIntervalSince1970: 10),
                status: .running,
                createdAt: Date(timeIntervalSince1970: 9)
            ),
            AutomationTaskRun(
                workflowID: workflowID,
                taskID: waitingTaskID,
                earliestStartTime: Date(timeIntervalSince1970: 11),
                status: .waitingForResource,
                createdAt: Date(timeIntervalSince1970: 10)
            )
        ]

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: runs
        ))
        let workflowProjection = try #require(projection.workflows.first)

        #expect(workflowProjection.status == .running)
        #expect(workflowProjection.statusDetail == "1 running, 1 waiting")
    }

    @Test("Resource waiting reason is projected with active lease blocker")
    func resourceWaitingReasonIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let holderTaskID = UUID()
        let waitingTaskID = UUID()
        let holderRunID = UUID()
        let waitingRunID = UUID()
        let leaseID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let waitingSince = now.addingTimeInterval(-12)
        let leaseExpiresAt = now.addingTimeInterval(30)
        let holderTask = AutomationTask(
            id: holderTaskID,
            name: "Holding input",
            kind: .delay(60),
            resourceRequirement: .foregroundInput
        )
        let waitingTask = AutomationTask(
            id: waitingTaskID,
            name: "Needs input next",
            kind: .macro(macroID: UUID()),
            resourceRequirement: AutomationResourceRequirement(
                resources: [.foregroundInput, .screenCapture],
                priority: .high,
                maxWaitDuration: 20
            )
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Resource wait",
            tasks: [holderTask, waitingTask]
        )
        let holderRun = AutomationTaskRun(
            id: holderRunID,
            workflowID: workflowID,
            taskID: holderTaskID,
            actualStartTime: now.addingTimeInterval(-30),
            status: .running,
            createdAt: now.addingTimeInterval(-31)
        )
        let waitingRun = AutomationTaskRun(
            id: waitingRunID,
            workflowID: workflowID,
            taskID: waitingTaskID,
            earliestStartTime: waitingSince,
            status: .waitingForResource,
            createdAt: waitingSince.addingTimeInterval(-1)
        )
        let foregroundLease = AutomationResourceLease(
            id: leaseID,
            runID: holderRunID,
            resource: .foregroundInput,
            acquiredAt: now.addingTimeInterval(-30),
            expiresAt: leaseExpiresAt
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [holderRun, waitingRun],
            leases: [foregroundLease],
            now: now
        ))
        let workflowProjection = try #require(projection.workflows.first)
        let waitingNode = try #require(workflowProjection.nodes.first { $0.taskID == waitingTaskID })
        let waitingReason = try #require(waitingNode.resourceWaiting)
        let blocker = try #require(waitingReason.blockers.first)
        let timelineReason = try #require(projection.timelineItems.first {
            $0.runID == waitingRunID
        }?.resourceWaiting)

        #expect(waitingReason.detail == "Waiting for mouse and keyboard held by Holding input")
        #expect(waitingReason.resources == [.foregroundInput, .screenCapture])
        #expect(waitingReason.resourceLabels == ["Needs mouse and keyboard", "Screen capture"])
        #expect(waitingReason.priority == .high)
        #expect(waitingReason.priorityLabel == "High priority")
        #expect(waitingReason.waitingSince == waitingSince)
        #expect(waitingReason.waitedDuration == 12)
        #expect(waitingReason.maxWaitDuration == 20)
        #expect(waitingReason.deadline == waitingSince.addingTimeInterval(20))
        #expect(waitingReason.remainingDuration == 8)
        #expect(abs((waitingReason.elapsedFraction ?? 0) - 0.6) < 0.0001)
        #expect(blocker.resource == .foregroundInput)
        #expect(blocker.resourceLabel == "Needs mouse and keyboard")
        #expect(blocker.runID == holderRunID)
        #expect(blocker.taskID == holderTaskID)
        #expect(blocker.taskTitle == "Holding input")
        #expect(blocker.leaseExpiresAt == leaseExpiresAt)
        #expect(timelineReason == waitingReason)
    }

    @Test("Next scheduled occurrence is projected outside SwiftUI")
    func nextScheduledOccurrenceIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let onceTaskID = UUID()
        let repeatingTaskID = UUID()
        let now = Date(timeIntervalSince1970: 12_000)
        let onceDate = now.addingTimeInterval(600)
        let repeatingAnchor = now.addingTimeInterval(-3_600)
        let representedRepeatingDate = now
        let nextRepeatingDate = now.addingTimeInterval(1_800)
        let onceTask = AutomationTask(
            id: onceTaskID,
            name: "Once",
            kind: .delay(0),
            schedule: .once(onceDate),
            resourceRequirement: .none
        )
        let repeatingTask = AutomationTask(
            id: repeatingTaskID,
            name: "Repeating",
            kind: .delay(0),
            schedule: .repeating(AutomationRepeatRule(
                anchor: repeatingAnchor,
                interval: .minutes(30)
            )),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Schedule projection",
            tasks: [onceTask, repeatingTask]
        )
        let representedRun = repeatingTask.makeRun(
            workflowID: workflowID,
            scheduledStartTime: representedRepeatingDate,
            earliestStartTime: representedRepeatingDate,
            createdAt: representedRepeatingDate
        )
        .completed(with: .succeeded(report: nil), at: representedRepeatingDate)

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [representedRun],
            now: now
        ))
        let workflowProjection = try #require(projection.workflows.first)
        let nodesByID = Dictionary(uniqueKeysWithValues: workflowProjection.nodes.map { ($0.taskID, $0) })

        #expect(nodesByID[onceTaskID]?.nextScheduledOccurrence == onceDate)
        #expect(nodesByID[repeatingTaskID]?.nextScheduledOccurrence == nextRepeatingDate)
        #expect(workflowProjection.nextScheduledOccurrence == onceDate)
        #expect(workflowProjection.nextScheduledTaskID == onceTaskID)
    }

    @Test("Join policy is projected outside SwiftUI")
    func joinPolicyIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let upstreamAID = UUID()
        let upstreamBID = UUID()
        let taskID = UUID()
        let upstreamA = AutomationTask(
            id: upstreamAID,
            name: "A",
            kind: .delay(1),
            resourceRequirement: .none
        )
        let upstreamB = AutomationTask(
            id: upstreamBID,
            name: "B",
            kind: .delay(1),
            resourceRequirement: .none
        )
        let task = AutomationTask(
            id: taskID,
            name: "Join",
            kind: .delay(1),
            resourceRequirement: .none,
            joinPolicy: .firstMatched
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Join policy",
            tasks: [upstreamA, upstreamB, task],
            dependencies: [
                AutomationDependency(fromTaskID: upstreamAID, toTaskID: taskID, trigger: .onSuccess),
                AutomationDependency(fromTaskID: upstreamBID, toTaskID: taskID, trigger: .onFailure)
            ]
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(workflows: [workflow]))
        let workflowProjection = try #require(projection.workflows.first)
        let node = try #require(workflowProjection.nodes.first { $0.taskID == taskID })

        #expect(node.joinPolicy == .firstMatched)
        #expect(node.joinPolicyLabel == "First matching branch")
        #expect(node.incomingDependencyCount == 2)
    }

    @Test("Timeout countdown is projected for queued and running tasks")
    func timeoutCountdownIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 104)
        let task = AutomationTask(
            id: taskID,
            name: "Wait for text",
            kind: .condition(AutomationConditionSpec(
                name: "Text",
                kind: .ocrText(AutomationOCRCondition(text: "Ready"))
            )),
            resourceRequirement: .backgroundReadOnly,
            timeout: 10
        )
        let workflow = AutomationWorkflow(id: workflowID, name: "Countdown", tasks: [task])
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: startedAt,
            status: .running,
            createdAt: startedAt
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [run],
            now: now
        ))
        let nodeCountdown = try #require(projection.workflows.first?.nodes.first?.timeoutCountdown)
        let timelineCountdown = try #require(projection.timelineItems.first?.timeoutCountdown)

        #expect(nodeCountdown.startedAt == startedAt)
        #expect(nodeCountdown.deadline == startedAt.addingTimeInterval(10))
        #expect(nodeCountdown.timeout == 10)
        #expect(nodeCountdown.remaining == 6)
        #expect(abs(nodeCountdown.elapsedFraction - 0.4) < 0.0001)
        #expect(timelineCountdown == nodeCountdown)
    }

    @Test("Retry attempt summary is projected for planned retry runs")
    func retryAttemptSummaryIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let firstRunID = UUID()
        let retryRunID = UUID()
        let failedAt = Date(timeIntervalSince1970: 200)
        let retryAt = Date(timeIntervalSince1970: 215)
        let now = Date(timeIntervalSince1970: 210)
        let task = AutomationTask(
            id: taskID,
            name: "Retryable macro",
            kind: .macro(macroID: UUID()),
            resourceRequirement: .none,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 3, backoff: .fixed(15))
        )
        let workflow = AutomationWorkflow(id: workflowID, name: "Retry projection", tasks: [task])
        let failedRun = AutomationTaskRun(
            id: firstRunID,
            executionID: firstRunID,
            workflowID: workflowID,
            taskID: taskID,
            completedAt: failedAt,
            status: .completed,
            outcome: .failed(report: nil),
            createdAt: failedAt.addingTimeInterval(-10),
            attempt: 1
        )
        let retryRun = AutomationTaskRun(
            id: retryRunID,
            executionID: firstRunID,
            workflowID: workflowID,
            taskID: taskID,
            earliestStartTime: retryAt,
            status: .planned,
            createdAt: failedAt,
            attempt: 2
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [failedRun, retryRun],
            now: now
        ))
        let node = try #require(projection.workflows.first?.nodes.first)
        let nodeRetry = try #require(node.retryAttemptSummary)
        let timelineRetry = try #require(projection.timelineItems.first { $0.runID == retryRunID }?.retryAttemptSummary)

        #expect(node.runID == retryRunID)
        #expect(nodeRetry.currentAttempt == 2)
        #expect(nodeRetry.maxAttempts == 3)
        #expect(nodeRetry.remainingAttempts == 1)
        #expect(nodeRetry.nextRetryAt == retryAt)
        #expect(nodeRetry.label == "Attempt 2 of 3")
        #expect(timelineRetry == nodeRetry)
    }

    @Test("Visual condition progress is projected outside SwiftUI")
    func visualConditionProgressIsProjectedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let startedAt = Date(timeIntervalSince1970: 300)
        let now = Date(timeIntervalSince1970: 306)
        let condition = AutomationConditionSpec(
            name: "Spinner gone",
            kind: .visual(AutomationVisualCondition(
                type: .imageDisappeared,
                regionRef: "battle_result_area",
                imageRef: "loading_spinner_template",
                baselineRef: "battle_start",
                threshold: 0.91
            )),
            timeout: 20,
            pollingInterval: 0.5
        )
        let task = AutomationTask(
            id: taskID,
            name: "Wait spinner gone",
            kind: .condition(condition),
            resourceRequirement: .backgroundReadOnly
        )
        let workflow = AutomationWorkflow(id: workflowID, name: "Visual wait", tasks: [task])
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: startedAt,
            status: .running,
            createdAt: startedAt
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [run],
            now: now
        ))
        let nodeProgress = try #require(projection.workflows.first?.nodes.first?.conditionProgress)
        let timelineProgress = try #require(projection.timelineItems.first?.conditionProgress)
        let countdown = try #require(nodeProgress.timeoutCountdown)

        #expect(nodeProgress.kind == .imageDisappeared)
        #expect(nodeProgress.kindLabel == "Image disappeared")
        #expect(nodeProgress.targetLabel == "loading_spinner_template")
        #expect(nodeProgress.detail.contains("Region battle_result_area"))
        #expect(nodeProgress.detail.contains("Image loading_spinner_template"))
        #expect(nodeProgress.pollingInterval == 0.5)
        #expect(nodeProgress.isActivelyPolling)
        #expect(nodeProgress.regionRef == "battle_result_area")
        #expect(nodeProgress.imageRef == "loading_spinner_template")
        #expect(nodeProgress.baselineRef == "battle_start")
        #expect(nodeProgress.threshold == 0.91)
        #expect(countdown.startedAt == startedAt)
        #expect(countdown.deadline == startedAt.addingTimeInterval(20))
        #expect(countdown.remaining == 14)
        #expect(abs(countdown.elapsedFraction - 0.3) < 0.0001)
        #expect(timelineProgress == nodeProgress)
        #expect(projection.workflows.first?.nodes.first?.timeoutCountdown == nil)
    }

    @Test("Pixel condition progress includes sample radius")
    func pixelConditionProgressIncludesSampleRadius() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let condition = AutomationConditionSpec(
            name: "Status color",
            kind: .visual(AutomationVisualCondition(
                type: .pixelMatched,
                regionRef: "status_light",
                targetColorHex: "#00FF00",
                pixelSampleRadius: 2,
                threshold: 0.93
            )),
            pollingInterval: 0.25
        )
        let task = AutomationTask(
            id: taskID,
            name: "Wait status color",
            kind: .condition(condition),
            resourceRequirement: .backgroundReadOnly
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: Date(timeIntervalSince1970: 300),
            status: .running,
            createdAt: Date(timeIntervalSince1970: 300)
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [AutomationWorkflow(id: workflowID, name: "Pixel wait", tasks: [task])],
            runs: [run],
            now: Date(timeIntervalSince1970: 301)
        ))
        let progress = try #require(projection.workflows.first?.nodes.first?.conditionProgress)

        #expect(progress.kind == .pixelMatched)
        #expect(progress.targetLabel == "#00FF00")
        #expect(progress.detail.contains("Sample radius 2"))
        #expect(progress.pixelSampleRadius == 2)
        #expect(progress.threshold == 0.93)
    }

    @Test("Dependency status is computed outside SwiftUI")
    func dependencyStatusIsComputedOutsideSwiftUI() throws {
        let workflowID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let dependencyID = UUID()
        let first = AutomationTask(id: firstID, name: "First", kind: .delay(1), resourceRequirement: .none)
        let second = AutomationTask(id: secondID, name: "Second", kind: .delay(1), resourceRequirement: .none)
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Edges",
            tasks: [first, second],
            dependencies: [
                AutomationDependency(id: dependencyID, fromTaskID: firstID, toTaskID: secondID, trigger: .onSuccess)
            ]
        )
        let run = AutomationTaskRun(
            workflowID: workflowID,
            taskID: firstID,
            completedAt: Date(timeIntervalSince1970: 10),
            status: .completed,
            outcome: .failed(report: nil),
            createdAt: Date(timeIntervalSince1970: 9)
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(workflows: [workflow], runs: [run]))
        let edge = try #require(projection.workflows.first?.edges.first)

        #expect(edge.id == dependencyID)
        #expect(edge.status == .blocked)
    }

    @Test("Dependency edge label projects recognized dynamic delay")
    func dependencyEdgeLabelProjectsRecognizedDynamicDelay() throws {
        let workflowID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let runID = UUID()
        let conditionID = UUID()
        let dependencyID = UUID()
        let condition = AutomationConditionSpec(
            id: conditionID,
            name: "Read timer",
            kind: .ocrText(AutomationOCRCondition(text: "mature"))
        )
        let first = AutomationTask(id: firstID, name: "Read timer", kind: .condition(condition), resourceRequirement: .none)
        let second = AutomationTask(id: secondID, name: "Harvest", kind: .delay(1), resourceRequirement: .none)
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Edges",
            tasks: [first, second],
            dependencies: [
                AutomationDependency(
                    id: dependencyID,
                    fromTaskID: firstID,
                    toTaskID: secondID,
                    trigger: .onConditionMatched,
                    delay: 30,
                    dynamicDelay: AutomationDependencyDynamicDelay(fallbackDelay: 30, maximumDelay: 7_200)
                )
            ]
        )
        let evidence = AutomationConditionEvaluationEvidence(
            runID: runID,
            workflowID: workflowID,
            taskID: firstID,
            conditionID: conditionID,
            kind: .ocrText,
            outcome: .conditionMatched,
            evaluatedAt: Date(timeIntervalSince1970: 10),
            targetDescription: "Timer",
            observedSummary: "Detected text: 1h 30m"
        )
        let run = AutomationTaskRun(
            id: runID,
            workflowID: workflowID,
            taskID: firstID,
            completedAt: Date(timeIntervalSince1970: 10),
            status: .completed,
            outcome: .conditionMatched,
            createdAt: Date(timeIntervalSince1970: 9),
            conditionEvidence: evidence
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(workflows: [workflow], runs: [run]))
        let edge = try #require(projection.workflows.first?.edges.first)

        #expect(edge.id == dependencyID)
        #expect(edge.delayLabel == "Observed 1h 30m")
    }

    @Test("Branch decisions are projected on dependency edges")
    func branchDecisionsAreProjectedOnDependencyEdges() throws {
        let workflowID = UUID()
        let sourceID = UUID()
        let successID = UUID()
        let failureID = UUID()
        let successDependencyID = UUID()
        let failureDependencyID = UUID()
        let sourceRunID = UUID()
        let failureRunID = UUID()
        let executionID = UUID()
        let completedAt = Date(timeIntervalSince1970: 50)
        let source = AutomationTask(id: sourceID, name: "Check", kind: .delay(1), resourceRequirement: .none)
        let success = AutomationTask(id: successID, name: "Then", kind: .delay(1), resourceRequirement: .none)
        let failure = AutomationTask(id: failureID, name: "Else", kind: .delay(1), resourceRequirement: .none)
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Branch decisions",
            tasks: [source, success, failure],
            dependencies: [
                AutomationDependency(
                    id: successDependencyID,
                    fromTaskID: sourceID,
                    toTaskID: successID,
                    trigger: .onSuccess
                ),
                AutomationDependency(
                    id: failureDependencyID,
                    fromTaskID: sourceID,
                    toTaskID: failureID,
                    trigger: .onFailure
                )
            ]
        )
        var sourceRun = AutomationTaskRun(
            id: sourceRunID,
            executionID: executionID,
            workflowID: workflowID,
            taskID: sourceID,
            completedAt: completedAt,
            status: .completed,
            outcome: .failed(report: nil),
            createdAt: Date(timeIntervalSince1970: 45)
        )
        sourceRun.branchEvidence = [
            AutomationBranchDecisionEvidence(
                sourceRunID: sourceRunID,
                sourceTaskID: sourceID,
                dependencyID: failureDependencyID,
                trigger: .onFailure,
                status: .triggered,
                targetTaskID: failureID,
                executionID: executionID,
                sourceOutcome: .failed(report: nil),
                decidedAt: completedAt,
                targetJoinPolicy: .all,
                reason: "Durable branch payload"
            )
        ]
        let failureRun = AutomationTaskRun(
            id: failureRunID,
            executionID: executionID,
            workflowID: workflowID,
            taskID: failureID,
            earliestStartTime: completedAt,
            status: .planned,
            createdAt: completedAt,
            upstreamRunIDs: [sourceRunID]
        )

        let projection = AutomationViewProjection.overview(from: AutomationRunState(
            workflows: [workflow],
            runs: [sourceRun, failureRun]
        ))
        let workflowProjection = try #require(projection.workflows.first)
        let edges = Dictionary(uniqueKeysWithValues: workflowProjection.edges.map { ($0.id, $0) })
        let successEdge = try #require(edges[successDependencyID])
        let failureEdge = try #require(edges[failureDependencyID])
        let successDecision = try #require(successEdge.branchDecision)
        let failureDecision = try #require(failureEdge.branchDecision)

        #expect(successEdge.status == .blocked)
        #expect(successDecision.status == .skipped)
        #expect(successDecision.sourceRunID == sourceRunID)
        #expect(successDecision.targetRunID == nil)
        #expect(successDecision.executionID == executionID)
        #expect(successDecision.decidedAt == completedAt)
        #expect(successDecision.outcomeLabel == "Failure")

        #expect(failureEdge.status == .satisfied)
        #expect(failureDecision.status == .triggered)
        #expect(failureDecision.sourceRunID == sourceRunID)
        #expect(failureDecision.targetRunID == failureRunID)
        #expect(failureDecision.executionID == executionID)
        #expect(failureDecision.decidedAt == completedAt)
        #expect(failureDecision.outcomeLabel == "Failure")
        #expect(failureDecision.detail == "Durable branch payload")
    }

    @Test("Task graph position is read from reducer projection")
    func taskGraphPositionIsReadFromReducerProjection() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let position = AutomationGraphPoint(x: 240, y: 120)
        let task = AutomationTask(
            id: taskID,
            name: "Moved",
            kind: .delay(1),
            resourceRequirement: .none,
            graphPosition: position
        )
        let workflow = AutomationWorkflow(id: workflowID, name: "Layout", tasks: [task])

        let projection = AutomationViewProjection.overview(from: AutomationRunState(workflows: [workflow]))
        let node = try #require(projection.workflows.first?.nodes.first)

        #expect(node.position == position)
    }

    private func localizationCatalog() throws -> [String: Any] {
        let url = repositoryRoot()
            .appendingPathComponent("Sources/SparkleRecorder/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(rootObject["strings"] as? [String: Any])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
