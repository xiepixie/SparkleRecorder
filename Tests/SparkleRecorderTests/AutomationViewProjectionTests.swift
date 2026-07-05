import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation View Projection Tests")
struct AutomationViewProjectionTests {
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
}
