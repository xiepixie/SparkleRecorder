import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("App Automation Resource Arbiter Tests")
struct AppAutomationResourceArbiterTests {
    @Test("Foreground input waits while the App owns recording or manual playback input")
    func foregroundInputRespectsAppOwnership() async {
        let availability = MutableForegroundInputAvailability(false)
        let client = AppAutomationResourceArbiter.make(
            foregroundInputAvailable: { await availability.value() }
        )
        let runID = UUID()
        let request = AutomationResourceRequest(
            runID: runID,
            resource: .foregroundInput,
            requestedAt: Date()
        )

        #expect(await client.acquire(request) == .denied(resource: .foregroundInput))

        await availability.set(true)
        let acquired = await client.acquire(request)
        #expect(acquired.lease?.runID == runID)
        #expect(acquired.lease?.resource == .foregroundInput)
    }

    @Test("Non-foreground resources are not blocked by App foreground ownership")
    func nonForegroundResourcesRemainIndependent() async {
        let availability = MutableForegroundInputAvailability(false)
        let client = AppAutomationResourceArbiter.make(
            foregroundInputAvailable: { await availability.value() }
        )
        let request = AutomationResourceRequest(
            runID: UUID(),
            resource: .screenCapture,
            requestedAt: Date()
        )

        #expect((await client.acquire(request)).lease?.resource == .screenCapture)
    }

    @Test("Automation-vs-Automation lease conflicts remain owned by the core arbiter")
    func preservesCoreLeaseConflicts() async {
        let availability = MutableForegroundInputAvailability(true)
        let client = AppAutomationResourceArbiter.make(
            foregroundInputAvailable: { await availability.value() }
        )
        let now = Date()
        let first = AutomationResourceRequest(
            runID: UUID(),
            resource: .foregroundInput,
            requestedAt: now
        )
        let second = AutomationResourceRequest(
            runID: UUID(),
            resource: .foregroundInput,
            requestedAt: now.addingTimeInterval(1)
        )

        #expect((await client.acquire(first)).lease != nil)
        #expect(await client.acquire(second) == .denied(resource: .foregroundInput))
    }
}

private actor MutableForegroundInputAvailability {
    private var available: Bool

    init(_ available: Bool) {
        self.available = available
    }

    func value() -> Bool { available }
    func set(_ available: Bool) { self.available = available }
}
