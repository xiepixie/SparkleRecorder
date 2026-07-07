import Foundation

public extension AutomationOverviewProjection {
    static func ownerCFixture(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> AutomationOverviewProjection {
        AutomationViewProjection.overview(from: .ownerCFixture(now: now))
    }
}

public extension AutomationRunState {
    static func ownerCFixture(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> AutomationRunState {
        let workflowID = fixedUUID("00000000-0000-0000-0000-00000000c001")
        let macroA = fixedUUID("00000000-0000-0000-0000-00000000c101")
        let macroB = fixedUUID("00000000-0000-0000-0000-00000000c102")
        let missingMacro = fixedUUID("00000000-0000-0000-0000-00000000c103")

        let taskLogin = fixedUUID("00000000-0000-0000-0000-00000000c201")
        let taskVerify = fixedUUID("00000000-0000-0000-0000-00000000c202")
        let taskExport = fixedUUID("00000000-0000-0000-0000-00000000c203")
        let taskAlert = fixedUUID("00000000-0000-0000-0000-00000000c204")
        let taskCleanup = fixedUUID("00000000-0000-0000-0000-00000000c205")
        let taskTimeout = fixedUUID("00000000-0000-0000-0000-00000000c206")
        let taskBlocked = fixedUUID("00000000-0000-0000-0000-00000000c207")
        let taskScheduled = fixedUUID("00000000-0000-0000-0000-00000000c208")
        let taskResourceWait = fixedUUID("00000000-0000-0000-0000-00000000c209")
        let taskRetry = fixedUUID("00000000-0000-0000-0000-00000000c20a")
        let taskVisualWait = fixedUUID("00000000-0000-0000-0000-00000000c20b")
        let conditionVisualSpinner = fixedUUID("00000000-0000-0000-0000-00000000c60b")

        let tasks = [
            AutomationTask(
                id: taskLogin,
                name: "Open nightly workspace",
                kind: .macro(macroID: macroA),
                schedule: .once(now.addingTimeInterval(-900)),
                resourceRequirement: .foregroundInput,
                timeout: 120
            ),
            AutomationTask(
                id: taskVerify,
                name: "Verify dashboard text",
                kind: .condition(AutomationConditionSpec(
                    name: "Dashboard ready",
                    kind: .ocrText(AutomationOCRCondition(text: "Ready")),
                    timeout: 30
                )),
                resourceRequirement: .backgroundReadOnly,
                timeout: 30
            ),
            AutomationTask(
                id: taskExport,
                name: "Export report",
                kind: .macro(macroID: macroB),
                resourceRequirement: .foregroundInput
            ),
            AutomationTask(
                id: taskAlert,
                name: "Send failure notice",
                kind: .notification(AutomationNotificationSpec(
                    title: "Report failed",
                    body: "The nightly report could not complete.",
                    severity: .error
                )),
                resourceRequirement: .none,
                joinPolicy: .any
            ),
            AutomationTask(
                id: taskCleanup,
                name: "Cleanup after cancel",
                kind: .delay(5),
                resourceRequirement: .none
            ),
            AutomationTask(
                id: taskTimeout,
                name: "Wait for SLA window",
                kind: .delay(60),
                resourceRequirement: .none,
                timeout: 60
            ),
            AutomationTask(
                id: taskBlocked,
                name: "Run archived macro",
                kind: .macro(macroID: missingMacro),
                resourceRequirement: .foregroundInput
            ),
            AutomationTask(
                id: taskScheduled,
                name: "Tomorrow health check",
                kind: .notification(AutomationNotificationSpec(
                    title: "Health check",
                    body: "Review automation status."
                )),
                schedule: .once(now.addingTimeInterval(86_400)),
                resourceRequirement: .none
            ),
            AutomationTask(
                id: taskResourceWait,
                name: "Wait for mouse handoff",
                kind: .macro(macroID: macroB),
                resourceRequirement: .foregroundInput
            ),
            AutomationTask(
                id: taskRetry,
                name: "Retry upload receipt",
                kind: .macro(macroID: macroB),
                resourceRequirement: .backgroundReadOnly,
                retryPolicy: AutomationRetryPolicy(maxAttempts: 3, backoff: .fixed(120))
            ),
            AutomationTask(
                id: taskVisualWait,
                name: "Watch spinner disappearance",
                kind: .condition(AutomationConditionSpec(
                    id: conditionVisualSpinner,
                    name: "Spinner disappears",
                    kind: .visual(AutomationVisualCondition(
                        type: .imageDisappeared,
                        regionRef: "battle_result_area",
                        imageRef: "loading_spinner_template",
                        baselineRef: "battle_start",
                        threshold: 0.91
                    )),
                    timeout: 45,
                    pollingInterval: 0.5
                )),
                resourceRequirement: .backgroundReadOnly
            )
        ]

        let dependencies = [
            AutomationDependency(
                id: fixedUUID("00000000-0000-0000-0000-00000000c301"),
                fromTaskID: taskLogin,
                toTaskID: taskVerify,
                trigger: .onSuccess,
                delay: 1
            ),
            AutomationDependency(
                id: fixedUUID("00000000-0000-0000-0000-00000000c302"),
                fromTaskID: taskVerify,
                toTaskID: taskExport,
                trigger: .onConditionMatched,
                delay: 3
            ),
            AutomationDependency(
                id: fixedUUID("00000000-0000-0000-0000-00000000c30a"),
                fromTaskID: taskVerify,
                toTaskID: taskAlert,
                trigger: .onConditionNotMatched
            ),
            AutomationDependency(
                id: fixedUUID("00000000-0000-0000-0000-00000000c30b"),
                fromTaskID: taskTimeout,
                toTaskID: taskAlert,
                trigger: .onTimeout
            ),
            AutomationDependency(
                id: fixedUUID("00000000-0000-0000-0000-00000000c303"),
                fromTaskID: taskAlert,
                toTaskID: taskCleanup,
                trigger: .onFailure
            ),
            AutomationDependency(
                id: fixedUUID("00000000-0000-0000-0000-00000000c304"),
                fromTaskID: taskTimeout,
                toTaskID: taskBlocked,
                trigger: .onSuccess
            )
        ]

        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Nightly operations",
            tasks: tasks,
            dependencies: dependencies,
            createdAt: now.addingTimeInterval(-7_200),
            modifiedAt: now.addingTimeInterval(-300)
        )

        let runs = [
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c401"),
                workflowID: workflowID,
                taskID: taskLogin,
                macroID: macroA,
                scheduledStartTime: now.addingTimeInterval(-900),
                earliestStartTime: now.addingTimeInterval(-900),
                actualStartTime: now.addingTimeInterval(-890),
                completedAt: now.addingTimeInterval(-830),
                status: .completed,
                outcome: .succeeded(report: RunReport(
                    runID: fixedUUID("00000000-0000-0000-0000-00000000c401"),
                    startTime: now.addingTimeInterval(-890),
                    duration: 60,
                    isSuccess: true
                )),
                evidenceID: fixedUUID("00000000-0000-0000-0000-00000000c501"),
                createdAt: now.addingTimeInterval(-900)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c402"),
                workflowID: workflowID,
                taskID: taskVerify,
                scheduledStartTime: now.addingTimeInterval(-829),
                earliestStartTime: now.addingTimeInterval(-829),
                actualStartTime: now.addingTimeInterval(-820),
                status: .running,
                createdAt: now.addingTimeInterval(-829)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c403"),
                workflowID: workflowID,
                taskID: taskExport,
                macroID: macroB,
                earliestStartTime: now.addingTimeInterval(-760),
                status: .waitingForDependencies,
                createdAt: now.addingTimeInterval(-760)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c404"),
                workflowID: workflowID,
                taskID: taskAlert,
                actualStartTime: now.addingTimeInterval(-640),
                completedAt: now.addingTimeInterval(-638),
                status: .completed,
                outcome: .failed(report: RunReport(
                    runID: fixedUUID("00000000-0000-0000-0000-00000000c404"),
                    startTime: now.addingTimeInterval(-640),
                    duration: 2,
                    isSuccess: false,
                    errorMessage: "Notification service rejected the payload"
                )),
                createdAt: now.addingTimeInterval(-641)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c405"),
                workflowID: workflowID,
                taskID: taskCleanup,
                actualStartTime: now.addingTimeInterval(-600),
                completedAt: now.addingTimeInterval(-599),
                status: .completed,
                outcome: .cancelled(reason: "User stopped the cleanup branch"),
                createdAt: now.addingTimeInterval(-601)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c406"),
                workflowID: workflowID,
                taskID: taskTimeout,
                actualStartTime: now.addingTimeInterval(-500),
                completedAt: now.addingTimeInterval(-440),
                status: .completed,
                outcome: .timedOut(deadline: now.addingTimeInterval(-440)),
                createdAt: now.addingTimeInterval(-501),
                branchEvidence: [
                    AutomationBranchDecisionEvidence(
                        sourceRunID: fixedUUID("00000000-0000-0000-0000-00000000c406"),
                        sourceTaskID: taskTimeout,
                        dependencyID: fixedUUID("00000000-0000-0000-0000-00000000c30b"),
                        trigger: .onTimeout,
                        status: .triggered,
                        targetTaskID: taskAlert,
                        targetRunID: fixedUUID("00000000-0000-0000-0000-00000000c404"),
                        executionID: fixedUUID("00000000-0000-0000-0000-00000000c406"),
                        sourceOutcome: .timedOut(deadline: now.addingTimeInterval(-440)),
                        decidedAt: now.addingTimeInterval(-440),
                        targetJoinPolicy: .any,
                        reason: "Source timed out, so the timeout branch triggered."
                    ),
                    AutomationBranchDecisionEvidence(
                        sourceRunID: fixedUUID("00000000-0000-0000-0000-00000000c406"),
                        sourceTaskID: taskTimeout,
                        dependencyID: fixedUUID("00000000-0000-0000-0000-00000000c304"),
                        trigger: .onSuccess,
                        status: .skipped,
                        targetTaskID: taskBlocked,
                        executionID: fixedUUID("00000000-0000-0000-0000-00000000c406"),
                        sourceOutcome: .timedOut(deadline: now.addingTimeInterval(-440)),
                        decidedAt: now.addingTimeInterval(-440),
                        reason: "Source outcome was Timeout, so the success branch was skipped."
                    )
                ]
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c407"),
                workflowID: workflowID,
                taskID: taskBlocked,
                macroID: missingMacro,
                actualStartTime: now.addingTimeInterval(-360),
                completedAt: now.addingTimeInterval(-360),
                status: .completed,
                outcome: .missingMacro(macroID: missingMacro),
                createdAt: now.addingTimeInterval(-361)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c408"),
                workflowID: workflowID,
                taskID: taskResourceWait,
                macroID: macroB,
                earliestStartTime: now.addingTimeInterval(-250),
                status: .waitingForResource,
                createdAt: now.addingTimeInterval(-251)
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c409"),
                executionID: fixedUUID("00000000-0000-0000-0000-00000000c409"),
                workflowID: workflowID,
                taskID: taskRetry,
                macroID: macroB,
                actualStartTime: now.addingTimeInterval(-180),
                completedAt: now.addingTimeInterval(-160),
                status: .completed,
                outcome: .failed(report: RunReport(
                    runID: fixedUUID("00000000-0000-0000-0000-00000000c409"),
                    startTime: now.addingTimeInterval(-180),
                    duration: 20,
                    isSuccess: false,
                    failedEventIndex: 2,
                    errorMessage: "Upload receipt was not visible"
                )),
                evidenceID: fixedUUID("00000000-0000-0000-0000-00000000c409"),
                createdAt: now.addingTimeInterval(-181),
                attempt: 1
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c40a"),
                executionID: fixedUUID("00000000-0000-0000-0000-00000000c409"),
                workflowID: workflowID,
                taskID: taskRetry,
                macroID: macroB,
                earliestStartTime: now.addingTimeInterval(120),
                status: .planned,
                createdAt: now.addingTimeInterval(-160),
                attempt: 2
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c40c"),
                workflowID: workflowID,
                taskID: taskVisualWait,
                earliestStartTime: now.addingTimeInterval(-120),
                actualStartTime: now.addingTimeInterval(-118),
                completedAt: now.addingTimeInterval(-94),
                status: .completed,
                outcome: .conditionMatched,
                createdAt: now.addingTimeInterval(-121),
                conditionEvidence: AutomationConditionEvaluationEvidence(
                    runID: fixedUUID("00000000-0000-0000-0000-00000000c40c"),
                    workflowID: workflowID,
                    taskID: taskVisualWait,
                    conditionID: conditionVisualSpinner,
                    kind: .imageDisappeared,
                    outcome: .conditionMatched,
                    evaluatedAt: now.addingTimeInterval(-94),
                    firstSampleAt: now.addingTimeInterval(-118),
                    lastSampleAt: now.addingTimeInterval(-95),
                    sampleCount: 8,
                    displayBounds: RectValue(x: 0, y: 0, width: 1440, height: 900),
                    resolvedSearchRegion: RectValue(x: 520, y: 284, width: 360, height: 220),
                    searchRegionSpace: .displayAbsolute,
                    targetDescription: "loading_spinner_template in battle_result_area",
                    observedSummary: "Spinner template similarity fell to 0.12, below the 0.91 disappearance threshold.",
                    score: 0.12,
                    threshold: 0.91,
                    fields: [
                        AutomationConditionDiagnosticField(
                            id: "regionRef",
                            title: "Region",
                            value: "battle_result_area"
                        ),
                        AutomationConditionDiagnosticField(
                            id: "imageRef",
                            title: "Image",
                            value: "loading_spinner_template"
                        ),
                        AutomationConditionDiagnosticField(
                            id: "baselineRef",
                            title: "Baseline",
                            value: "battle_start"
                        ),
                        AutomationConditionDiagnosticField(
                            id: "samples",
                            title: "Samples",
                            value: "8 frames over 23s"
                        )
                    ],
                    artifacts: [
                        AutomationConditionDiagnosticArtifact(
                            id: "lastSampleImage",
                            title: "Last sample",
                            kind: .displaySampleImage,
                            relativePath: "fixture-artifacts/visual-condition/condition-last-sample.png",
                            pixelBounds: RectValue(x: 0, y: 0, width: 960, height: 540),
                            createdAt: now.addingTimeInterval(-95)
                        ),
                        AutomationConditionDiagnosticArtifact(
                            id: "regionSampleImage",
                            title: "Watched region",
                            kind: .regionSampleImage,
                            relativePath: "fixture-artifacts/visual-condition/condition-region-sample.png",
                            pixelBounds: RectValue(x: 520, y: 284, width: 360, height: 220),
                            createdAt: now.addingTimeInterval(-95)
                        )
                    ]
                )
            ),
            AutomationTaskRun(
                id: fixedUUID("00000000-0000-0000-0000-00000000c40b"),
                workflowID: workflowID,
                taskID: taskVisualWait,
                earliestStartTime: now.addingTimeInterval(-40),
                actualStartTime: now.addingTimeInterval(-30),
                status: .running,
                createdAt: now.addingTimeInterval(-41)
            )
        ]

        return AutomationRunState(
            workflows: [workflow],
            runs: runs,
            leases: [],
            now: now
        )
    }
}

private func fixedUUID(_ value: String) -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        fatalError("Invalid fixture UUID: \(value)")
    }
    return uuid
}
