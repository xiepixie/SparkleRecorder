import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Workflow Graph Levels Tests")
struct AutomationWorkflowGraphLevelsTests {
    @Test("DAG levels use the longest enabled dependency path")
    func dagUsesLongestDependencyPath() {
        let root = AutomationTask(name: "Root", kind: .delay(0))
        let left = AutomationTask(name: "Left", kind: .delay(0))
        let right = AutomationTask(name: "Right", kind: .delay(0))
        let leaf = AutomationTask(name: "Leaf", kind: .delay(0))
        let workflow = AutomationWorkflow(
            name: "Diamond",
            tasks: [root, left, right, leaf],
            dependencies: [
                AutomationDependency(fromTaskID: root.id, toTaskID: left.id, trigger: .onSuccess),
                AutomationDependency(fromTaskID: root.id, toTaskID: right.id, trigger: .onSuccess),
                AutomationDependency(fromTaskID: left.id, toTaskID: leaf.id, trigger: .onSuccess),
                AutomationDependency(fromTaskID: right.id, toTaskID: leaf.id, trigger: .onSuccess),
            ]
        )

        let levels = AutomationWorkflowGraphLevels.levelsByTaskID(for: workflow)

        #expect(levels[root.id] == 0)
        #expect(levels[left.id] == 1)
        #expect(levels[right.id] == 1)
        #expect(levels[leaf.id] == 2)
    }

    @Test("Disabled and broken dependencies do not move tasks")
    func disabledAndBrokenDependenciesAreIgnored() {
        let first = AutomationTask(name: "First", kind: .delay(0))
        let second = AutomationTask(name: "Second", kind: .delay(0))
        let workflow = AutomationWorkflow(
            name: "Ignored edges",
            tasks: [first, second],
            dependencies: [
                AutomationDependency(
                    fromTaskID: first.id,
                    toTaskID: second.id,
                    trigger: .onSuccess,
                    isEnabled: false
                ),
                AutomationDependency(
                    fromTaskID: UUID(),
                    toTaskID: second.id,
                    trigger: .onSuccess
                ),
            ]
        )

        let levels = AutomationWorkflowGraphLevels.levelsByTaskID(for: workflow)

        #expect(levels[first.id] == 0)
        #expect(levels[second.id] == 0)
    }

    @Test("Cyclic persisted data stays bounded and renderable")
    func cycleFallbackIsBounded() {
        let first = AutomationTask(name: "First", kind: .delay(0))
        let second = AutomationTask(name: "Second", kind: .delay(0))
        let third = AutomationTask(name: "Third", kind: .delay(0))
        let workflow = AutomationWorkflow(
            name: "Corrupt cycle",
            tasks: [first, second, third],
            dependencies: [
                AutomationDependency(fromTaskID: first.id, toTaskID: second.id, trigger: .onSuccess),
                AutomationDependency(fromTaskID: second.id, toTaskID: third.id, trigger: .onSuccess),
                AutomationDependency(fromTaskID: third.id, toTaskID: first.id, trigger: .onSuccess),
            ]
        )

        let levels = AutomationWorkflowGraphLevels.levelsByTaskID(for: workflow)

        #expect(levels.count == 3)
        #expect(levels.values.allSatisfy { (0..<3).contains($0) })
        #expect(levels.values.contains(2))
    }

    @Test("Large linear DAG projects levels without repeated graph relaxation")
    func largeLinearDAG() {
        let taskCount = 1_000
        let tasks = (0..<taskCount).map { index in
            AutomationTask(name: "Task \(index)", kind: .delay(0))
        }
        let dependencies = zip(tasks, tasks.dropFirst()).map { source, target in
            AutomationDependency(fromTaskID: source.id, toTaskID: target.id, trigger: .onSuccess)
        }
        let workflow = AutomationWorkflow(
            name: "Large chain",
            tasks: tasks,
            dependencies: dependencies
        )

        let levels = AutomationWorkflowGraphLevels.levelsByTaskID(for: workflow)

        #expect(levels.count == taskCount)
        #expect(levels[tasks.first!.id] == 0)
        #expect(levels[tasks.last!.id] == taskCount - 1)
    }
}
