import Foundation

struct AutomationWorkflowGraphLevels: Sendable {
    static func levelsByTaskID(
        for workflow: AutomationWorkflow
    ) -> [UUID: Int] {
        let taskIDs = Set(workflow.tasks.map(\.id))
        guard !taskIDs.isEmpty else {
            return [:]
        }

        let dependencies = workflow.dependencies.filter { dependency in
            dependency.isEnabled
                && taskIDs.contains(dependency.fromTaskID)
                && taskIDs.contains(dependency.toTaskID)
        }

        var outgoing: [UUID: [UUID]] = [:]
        var indegree = Dictionary(uniqueKeysWithValues: workflow.tasks.map { ($0.id, 0) })
        var levels = Dictionary(uniqueKeysWithValues: workflow.tasks.map { ($0.id, 0) })

        for dependency in dependencies {
            outgoing[dependency.fromTaskID, default: []].append(dependency.toTaskID)
            indegree[dependency.toTaskID, default: 0] += 1
        }

        var queue = workflow.tasks.compactMap { task in
            indegree[task.id] == 0 ? task.id : nil
        }
        var readIndex = 0
        var processedCount = 0

        while readIndex < queue.count {
            let taskID = queue[readIndex]
            readIndex += 1
            processedCount += 1

            let sourceLevel = levels[taskID] ?? 0
            for targetTaskID in outgoing[taskID] ?? [] {
                levels[targetTaskID] = max(levels[targetTaskID] ?? 0, sourceLevel + 1)
                indegree[targetTaskID, default: 0] -= 1
                if indegree[targetTaskID] == 0 {
                    queue.append(targetTaskID)
                }
            }
        }

        guard processedCount < workflow.tasks.count else {
            return levels
        }

        // Persisted workflows are validated as DAGs. Keep corrupt/legacy cyclic
        // data renderable by falling back to the previous bounded relaxation only
        // for nodes Kahn traversal could not resolve. Valid workflows stay O(T + D).
        let unresolvedTaskIDs = Set(
            workflow.tasks.compactMap { task in
                (indegree[task.id] ?? 0) > 0 ? task.id : nil
            }
        )
        let maximumLevel = max(0, workflow.tasks.count - 1)

        for _ in 0..<unresolvedTaskIDs.count {
            var changed = false
            for dependency in dependencies where unresolvedTaskIDs.contains(dependency.toTaskID) {
                let nextLevel = min(
                    maximumLevel,
                    (levels[dependency.fromTaskID] ?? 0) + 1
                )
                if nextLevel > (levels[dependency.toTaskID] ?? 0) {
                    levels[dependency.toTaskID] = nextLevel
                    changed = true
                }
            }
            if !changed {
                break
            }
        }

        return levels
    }
}
