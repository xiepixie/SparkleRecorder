import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Workflow Activation Projection Tests")
struct AutomationWorkflowActivationProjectionTests {
    @Test("Empty workflow is blocked")
    func emptyWorkflowIsBlocked() {
        let activation = AutomationWorkflowActivationProjection(workflow: workflow(nodes: []))

        #expect(activation.state == .blocked)
        #expect(activation.checks.map(\.id) == ["missing-task"])
    }

    @Test("Workflow without a schedule is explicitly manual only")
    func workflowWithoutScheduleIsManualOnly() {
        let activation = AutomationWorkflowActivationProjection(
            workflow: workflow(nodes: [node(nextOccurrence: nil)])
        )

        #expect(activation.state == .manualOnly)
        #expect(activation.scheduledTaskCount == 0)
        #expect(activation.checks.map(\.id) == ["manual-only"])
    }

    @Test("Scheduled workflow warns that the app must remain open")
    func scheduledWorkflowWarnsAboutAppLifecycle() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let activation = AutomationWorkflowActivationProjection(
            workflow: workflow(nodes: [node(nextOccurrence: date)], nextOccurrence: date)
        )

        #expect(activation.state == .scheduled)
        #expect(activation.nextOccurrence == date)
        #expect(activation.scheduledTaskCount == 1)
        #expect(activation.checks.map(\.id) == ["app-online", "schedule-ready"])
    }

    @Test("Running status takes precedence over schedule readiness")
    func runningStatusTakesPrecedence() {
        let activation = AutomationWorkflowActivationProjection(
            workflow: workflow(status: .running, nodes: [node(nextOccurrence: nil)])
        )

        #expect(activation.state == .running)
        #expect(activation.checks.map(\.id) == ["running"])
    }

    private func workflow(
        status: AutomationDisplayStatus = .scheduled,
        nodes: [AutomationTaskNodeProjection],
        nextOccurrence: Date? = nil
    ) -> AutomationWorkflowProjection {
        AutomationWorkflowProjection(
            id: UUID(),
            name: "Morning workflow",
            status: status,
            statusDetail: "Ready",
            nextScheduledOccurrence: nextOccurrence,
            nodes: nodes,
            edges: [],
            graphSize: .init(width: 800, height: 600),
            nodeSize: .init(width: 250, height: 120)
        )
    }

    private func node(nextOccurrence: Date?) -> AutomationTaskNodeProjection {
        AutomationTaskNodeProjection(
            workflowID: UUID(),
            taskID: UUID(),
            runID: nil,
            title: "Open report",
            kindLabel: "Macro",
            scheduleLabel: "Manual",
            nextScheduledOccurrence: nextOccurrence,
            resourceLabel: "Foreground input",
            incomingDependencyCount: 0,
            joinPolicy: .all,
            joinPolicyLabel: "All",
            status: .scheduled,
            statusDetail: "Ready",
            hasEvidence: false,
            position: .init(x: 0, y: 0)
        )
    }
}
