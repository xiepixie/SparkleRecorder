import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Workflow Runtime CLI Payload Tests")
struct AutomationWorkflowRuntimeCLITests {
    @Test("Workflow run payload identifies created execution runs")
    func workflowRunPayloadIdentifiesCreatedExecutionRuns() throws {
        let workflowID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let taskID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
        let runID = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
        let requestedAt = Date(timeIntervalSince1970: 6_000)
        let completedAt = requestedAt.addingTimeInterval(1)
        let task = AutomationTask(
            id: taskID,
            name: "Start",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Runtime smoke",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let completedRun = task.makeRun(
            workflowID: workflowID,
            runID: runID,
            scheduledStartTime: requestedAt,
            earliestStartTime: requestedAt,
            createdAt: requestedAt
        )
        .started(at: requestedAt, leaseID: nil)
        .completed(with: .succeeded(report: nil), at: completedAt)

        let payload = AutomationWorkflowRunPayload(
            workflow: workflow,
            requestedTaskID: taskID,
            requestedAt: requestedAt,
            beforeRuns: [],
            afterState: AutomationRunState(workflows: [workflow], runs: [completedRun]),
            timedOut: false
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowRunPayload>
            .workflowRun(command: "workflow run", payload: payload)

        #expect(payload.startedRunID == runID)
        #expect(payload.executionID == runID)
        #expect(payload.isComplete)
        #expect(payload.workflowStatus.overallStatus == .completed)
        #expect(payload.executionRuns.map(\.id) == [runID])
        #expect(envelope.ok)
        #expect(envelope.nextActions.contains { $0.command.contains("workflow runs") })
    }

    @Test("Workflow cancel payload reports terminal cancellation")
    func workflowCancelPayloadReportsTerminalCancellation() throws {
        let workflowID = UUID(uuidString: "60000000-0000-0000-0000-000000000011")!
        let taskID = UUID(uuidString: "60000000-0000-0000-0000-000000000012")!
        let runID = UUID(uuidString: "60000000-0000-0000-0000-000000000013")!
        let requestedAt = Date(timeIntervalSince1970: 6_100)
        let task = AutomationTask(
            id: taskID,
            name: "Long task",
            kind: .delay(30),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Cancelable runtime",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let beforeRun = task.makeRun(
            workflowID: workflowID,
            runID: runID,
            scheduledStartTime: requestedAt,
            earliestStartTime: requestedAt,
            createdAt: requestedAt
        )
        let afterRun = beforeRun.completed(with: .cancelled(reason: "User cancelled"), at: requestedAt)

        let payload = AutomationWorkflowCancelPayload(
            runID: runID,
            requestedAt: requestedAt,
            beforeRun: beforeRun,
            afterState: AutomationRunState(workflows: [workflow], runs: [afterRun])
        )
        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowCancelPayload>
            .workflowCancel(command: "workflow cancel", payload: payload)

        #expect(payload.cancelled)
        #expect(payload.run?.outcome == .cancelled(reason: "User cancelled"))
        #expect(payload.workflowStatus?.overallStatus == .needsAttention)
        #expect(envelope.ok)
        #expect(envelope.warnings.isEmpty)
    }

    @Test("Workflow handoff payload reports queued App host command")
    func workflowHandoffPayloadReportsQueuedAppHostCommand() throws {
        let workflowID = UUID(uuidString: "60000000-0000-0000-0000-000000000031")!
        let taskID = UUID(uuidString: "60000000-0000-0000-0000-000000000032")!
        let commandID = UUID(uuidString: "60000000-0000-0000-0000-000000000033")!
        let requestedAt = Date(timeIntervalSince1970: 6_300)
        let command = AutomationRuntimeHandoffCommand(
            id: commandID,
            kind: .manualStart(workflowID: workflowID, taskID: taskID),
            requestedAt: requestedAt,
            source: "test"
        )
        let payload = AutomationRuntimeHandoffPayload(
            command: command,
            enqueuedAt: requestedAt,
            pendingCommandCount: 1
        )
        let envelope = AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload>
            .workflowHandoff(command: "workflow run", payload: payload)

        #expect(payload.target == .appHost)
        #expect(payload.command.id == commandID)
        #expect(payload.pendingCommandCount == 1)
        #expect(envelope.ok)
        #expect(envelope.nextActions.contains { $0.command.contains("workflow status") })
        #expect(envelope.nextActions.contains { $0.command.contains("workflow runs") })
    }

    @Test("Workflow handoff status payload reports receipt state")
    func workflowHandoffStatusPayloadReportsReceiptState() throws {
        let workflowID = UUID(uuidString: "60000000-0000-0000-0000-000000000034")!
        let taskID = UUID(uuidString: "60000000-0000-0000-0000-000000000035")!
        let commandID = UUID(uuidString: "60000000-0000-0000-0000-000000000036")!
        let runID = UUID(uuidString: "60000000-0000-0000-0000-000000000037")!
        let requestedAt = Date(timeIntervalSince1970: 6_310)
        let handledAt = Date(timeIntervalSince1970: 6_311)
        let task = AutomationTask(
            id: taskID,
            name: "Handoff task",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Handoff workflow",
            tasks: [task],
            createdAt: requestedAt,
            modifiedAt: requestedAt
        )
        let run = task.makeRun(
            workflowID: workflowID,
            runID: runID,
            scheduledStartTime: requestedAt,
            earliestStartTime: requestedAt,
            createdAt: requestedAt
        )
        .started(at: handledAt, leaseID: nil)
        let receipt = AutomationRuntimeHandoffReceipt(
            commandID: commandID,
            commandKind: .manualStart(workflowID: workflowID, taskID: taskID),
            requestedAt: requestedAt,
            handledAt: handledAt,
            status: .dispatched,
            runIDs: [runID],
            message: "Dispatched by App host",
            source: "test"
        )
        let payload = AutomationRuntimeHandoffStatusPayload(
            commandID: commandID,
            command: nil,
            receipt: receipt,
            workflowStatus: AutomationWorkflowStatus(workflow: workflow, runHistory: [run]),
            runs: [run],
            pendingCommandCount: 0,
            receiptCount: 1,
            checkedAt: handledAt
        )
        let envelope = AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload>
            .workflowHandoffStatus(command: "workflow handoff status", payload: payload)

        #expect(payload.state == .dispatched)
        #expect(payload.receipt?.runIDs == [runID])
        #expect(payload.runs.map(\.id) == [runID])
        #expect(payload.runs.first?.status == .running)
        #expect(payload.workflowStatus?.summary.id == workflowID)
        #expect(payload.workflowStatus?.overallStatus == .running)
        #expect(envelope.ok)
        #expect(envelope.nextActions.contains { $0.command.contains("workflow status \(workflowID.uuidString)") })

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AutomationRuntimeHandoffStatusPayload.self, from: encoded)
        #expect(decoded == payload)

        let legacyJSON = """
        {
          "target": "appHost",
          "commandID": "\(commandID.uuidString)",
          "state": "dispatched",
          "receipt": {
            "commandID": "\(commandID.uuidString)",
            "commandKind": {
              "manualStart": {
                "workflowID": "\(workflowID.uuidString)",
                "taskID": "\(taskID.uuidString)"
              }
            },
            "requestedAt": 6310,
            "handledAt": 6311,
            "status": "dispatched",
            "runIDs": [
              "\(runID.uuidString)"
            ],
            "source": "test"
          },
          "pendingCommandCount": 0,
          "receiptCount": 1,
          "checkedAt": 6311
        }
        """
        let legacyPayload = try JSONDecoder().decode(
            AutomationRuntimeHandoffStatusPayload.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(legacyPayload.runs.isEmpty)
        #expect(legacyPayload.workflowStatus == nil)
        #expect(legacyPayload.state == .dispatched)

        let missingPayload = AutomationRuntimeHandoffStatusPayload(
            commandID: UUID(uuidString: "60000000-0000-0000-0000-000000000038")!,
            command: nil,
            receipt: nil,
            pendingCommandCount: 0,
            receiptCount: 1,
            checkedAt: handledAt
        )
        let missingEnvelope = AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload>
            .workflowHandoffStatus(command: "workflow handoff status", payload: missingPayload)

        #expect(missingPayload.state == .missing)
        #expect(!missingEnvelope.ok)
    }

    @Test("Workflow runs payload sorts latest run first")
    func workflowRunsPayloadSortsLatestRunFirst() throws {
        let workflowID = UUID(uuidString: "60000000-0000-0000-0000-000000000021")!
        let taskID = UUID(uuidString: "60000000-0000-0000-0000-000000000022")!
        let olderRunID = UUID(uuidString: "60000000-0000-0000-0000-000000000023")!
        let newerRunID = UUID(uuidString: "60000000-0000-0000-0000-000000000024")!
        let start = Date(timeIntervalSince1970: 6_200)
        let task = AutomationTask(
            id: taskID,
            name: "Repeatable",
            kind: .delay(0),
            resourceRequirement: .none
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Run history",
            tasks: [task],
            createdAt: start,
            modifiedAt: start
        )
        let olderRun = task.makeRun(
            workflowID: workflowID,
            runID: olderRunID,
            createdAt: start
        )
        .completed(with: .succeeded(report: nil), at: start.addingTimeInterval(1))
        let newerRun = task.makeRun(
            workflowID: workflowID,
            runID: newerRunID,
            createdAt: start.addingTimeInterval(10)
        )
        .completed(with: .failed(report: nil), at: start.addingTimeInterval(11))

        let payload = AutomationWorkflowRunsPayload(
            workflow: workflow,
            runHistory: [olderRun, newerRun]
        )

        #expect(payload.count == 2)
        #expect(payload.runs.map(\.id) == [newerRunID, olderRunID])
        #expect(payload.status.overallStatus == .needsAttention)
    }
}
