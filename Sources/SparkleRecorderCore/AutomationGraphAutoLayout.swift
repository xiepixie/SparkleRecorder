import Foundation

public struct AutomationGraphAutoLayout: Sendable {
    public static func computeLayout(
        for workflow: AutomationWorkflow,
        nodeSize: AutomationGraphSize,
        gapX: Double = 60,
        gapY: Double = 80
    ) -> [UUID: AutomationGraphPoint] {
        var adj = [UUID: [UUID]]()
        var inDegree = [UUID: Int]()
        
        for task in workflow.tasks {
            adj[task.id] = []
            inDegree[task.id] = 0
        }
        
        for dep in workflow.dependencies {
            adj[dep.fromTaskID, default: []].append(dep.toTaskID)
            inDegree[dep.toTaskID, default: 0] += 1
        }
        
        var roots = [UUID]()
        for task in workflow.tasks {
            if inDegree[task.id] == 0 {
                let outDegree = adj[task.id]?.count ?? 0
                if outDegree > 0 {
                    roots.append(task.id)
                }
                // If outDegree == 0, it's an isolated node. We don't add it to roots.
                // It will be handled in the unvisited pass at the end, placing it on the far right.
            }
        }
        
        var levels = [[UUID]]()
        var currentLevel = roots
        
        while !currentLevel.isEmpty {
            levels.append(currentLevel)
            var nextLevel = [UUID]()
            for node in currentLevel {
                for neighbor in adj[node] ?? [] {
                    inDegree[neighbor, default: 0] -= 1
                    if inDegree[neighbor] == 0 {
                        nextLevel.append(neighbor)
                    }
                }
            }
            currentLevel = nextLevel
        }
        
        var positions = [UUID: AutomationGraphPoint]()
        var currentX: Double = 32
        
        for level in levels {
            var currentY: Double = 32
            for node in level {
                positions[node] = AutomationGraphPoint(x: currentX, y: currentY)
                currentY += nodeSize.height + gapY
            }
            currentX += nodeSize.width + gapX
        }
        
        // Ensure any disconnected cycles or isolated nodes get a layout on the far right
        var unvisitedY: Double = 32
        var unvisitedCount = 0
        for task in workflow.tasks {
            if positions[task.id] == nil {
                positions[task.id] = AutomationGraphPoint(x: currentX, y: unvisitedY)
                unvisitedCount += 1
                if unvisitedCount % 5 == 0 {
                    currentX += nodeSize.width + gapX
                    unvisitedY = 32
                } else {
                    unvisitedY += nodeSize.height + gapY
                }
            }
        }
        
        return positions
    }
}
