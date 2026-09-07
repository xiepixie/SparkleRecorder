import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Overview Model Tests")
@MainActor
struct AutomationOverviewModelTests {
    @Test("Runtime polling ignores snapshots whose revision has not changed")
    func runtimePollingSkipsUnchangedRevision() async {
        let firstTask = AutomationTask(name: "First", kind: .delay(1))
        let firstWorkflow = AutomationWorkflow(name: "First workflow", tasks: [firstTask])
        let firstState = AutomationRunState(workflows: [firstWorkflow])

        let secondTask = AutomationTask(name: "Second", kind: .delay(2))
        let secondWorkflow = AutomationWorkflow(name: "Second workflow", tasks: [secondTask])
        let secondState = AutomationRunState(workflows: [secondWorkflow])

        var snapshot = AutomationRuntimeSnapshot(state: firstState, revision: 7)
        let model = AutomationOverviewModel(runtimeSnapshotLoader: { snapshot })

        await model.refreshRuntimeState()
        #expect(model.state == firstState)
        let firstProjection = model.projection
        let firstCatalog = model.catalogProjection
        let firstRunCenter = model.runCenterProjection

        snapshot = AutomationRuntimeSnapshot(state: secondState, revision: 7)
        await model.refreshRuntimeState()

        #expect(model.state == firstState)
        #expect(model.projection == firstProjection)
        #expect(model.catalogProjection == firstCatalog)
        #expect(model.runCenterProjection == firstRunCenter)
    }

    @Test("Runtime polling publishes a new revision")
    func runtimePollingPublishesChangedRevision() async {
        let firstState = AutomationRunState(
            workflows: [AutomationWorkflow(name: "First", tasks: [])]
        )
        let secondState = AutomationRunState(
            workflows: [AutomationWorkflow(name: "Second", tasks: [])]
        )

        var snapshot = AutomationRuntimeSnapshot(state: firstState, revision: 1)
        let model = AutomationOverviewModel(runtimeSnapshotLoader: { snapshot })
        await model.refreshRuntimeState()

        snapshot = AutomationRuntimeSnapshot(state: secondState, revision: 2)
        await model.refreshRuntimeState()

        #expect(model.state == secondState)
    }
}
