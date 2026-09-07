import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Task Inspector Draft Tests")
struct AutomationTaskInspectorDraftTests {
    @Test("Schedule draft round trips manual once and every repeat unit")
    func scheduleDraftRoundTrips() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let schedules: [AutomationSchedule] = [
            .manual,
            .once(anchor),
            .repeating(AutomationRepeatRule(anchor: anchor, interval: .minutes(3))),
            .repeating(AutomationRepeatRule(anchor: anchor, interval: .hours(4))),
            .repeating(AutomationRepeatRule(anchor: anchor, interval: .days(5))),
            .repeating(AutomationRepeatRule(anchor: anchor, interval: .weeks(2)))
        ]

        for schedule in schedules {
            let draft = AutomationTaskScheduleDraft(schedule: schedule, referenceDate: anchor)
            #expect(draft.schedule == schedule)
        }
    }

    @Test("Schedule draft clamps repeating count before materializing")
    func scheduleDraftClampsRepeatingCount() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = AutomationTaskScheduleDraft(
            mode: .repeating,
            onceDate: anchor,
            repeatStart: anchor,
            repeatEvery: 0,
            repeatUnit: .days
        )

        #expect(
            draft.schedule == .repeating(
                AutomationRepeatRule(anchor: anchor, interval: .days(1))
            )
        )
    }

    @Test("Execution draft preserves task policy and normalizes edited limits")
    func executionDraftAppliesNormalizedPolicy() {
        let task = AutomationTask(
            name: "Export",
            kind: .delay(1),
            timeout: 45,
            retryPolicy: AutomationRetryPolicy(maxAttempts: 3),
            joinPolicy: .any,
            targetApplicationPolicy: .launchIfNeeded,
            targetApplicationReadyDelay: 5
        )
        var draft = AutomationTaskExecutionDraft(task: task)

        #expect(draft.targetApplicationPolicy == .launchIfNeeded)
        #expect(draft.targetApplicationReadyDelay == 5)
        #expect(draft.hasTimeout)
        #expect(draft.timeout == 45)
        #expect(draft.retryAttempts == 3)
        #expect(draft.joinPolicy == .any)

        draft.timeout = -4
        draft.retryAttempts = 0
        draft.joinPolicy = .firstMatched

        var updated = task
        draft.apply(to: &updated)

        #expect(updated.timeout == 0)
        #expect(updated.retryPolicy.maxAttempts == 1)
        #expect(updated.joinPolicy == .firstMatched)
    }

    @Test("Resource draft preserves lease timeout and unions required resources")
    func resourceDraftBuildsEffectiveRequirement() {
        let base = AutomationResourceRequirement(
            resources: [.network],
            priority: .low,
            leaseTimeout: 22,
            maxWaitDuration: 15
        )
        var draft = AutomationTaskResourceDraft(requirement: base)
        draft.resources = [.foregroundInput]
        draft.priority = .high
        draft.maxWaitDuration = -3

        let requirement = draft.requirement(
            preserving: base,
            requiredResources: [.screenCapture]
        )

        #expect(requirement.resources == [.foregroundInput, .screenCapture])
        #expect(requirement.priority == .high)
        #expect(requirement.leaseTimeout == 22)
        #expect(requirement.maxWaitDuration == 0)
    }

    @Test("Resource draft drops max wait when no resource remains")
    func resourceDraftDropsMaxWaitWithoutResources() {
        let base = AutomationResourceRequirement(
            resources: [.network],
            priority: .normal,
            leaseTimeout: 12,
            maxWaitDuration: 9
        )
        var draft = AutomationTaskResourceDraft(requirement: base)
        draft.resources = []

        let requirement = draft.requirement(preserving: base)

        #expect(requirement.resources.isEmpty)
        #expect(requirement.maxWaitDuration == nil)
        #expect(requirement.leaseTimeout == 12)
    }

    @Test("Condition draft round trips OCR authoring fields")
    func conditionDraftRoundTripsOCR() throws {
        let region = RectValue(x: 10, y: 20, width: 300, height: 80)
        let ocr = AutomationOCRCondition(
            text: "Ready",
            matchMode: .exact,
            searchRegion: region,
            searchRegionSpace: .contentLocal,
            requireVisible: false
        )
        let condition = AutomationConditionSpec(
            name: "Wait for ready",
            kind: .ocrText(ocr),
            timeout: 12,
            pollingInterval: 0.5
        )

        let draft = AutomationTaskConditionDraft(condition: condition)
        let materialized = draft.conditionSpec(
            taskName: "Fallback",
            preserving: AutomationOCRCondition(text: "old")
        )
        guard case .ocrText(let materializedOCR) = materialized.kind else {
            Issue.record("Expected OCR condition")
            return
        }

        #expect(draft.mode == .ocrText)
        #expect(draft.requiredResources == [.screenCapture])
        #expect(materialized.name == "Wait for ready")
        #expect(materialized.timeout == 12)
        #expect(materialized.pollingInterval == 0.5)
        #expect(materializedOCR == ocr)
    }

    @Test("Condition draft round trips visual pixel intent")
    func conditionDraftRoundTripsVisualPixel() throws {
        let visual = AutomationVisualCondition(
            type: .pixelMatched,
            regionRef: " status ",
            searchRegion: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            searchRegionSpace: .windowNormalized,
            pixel: AutomationGraphPoint(x: 0.4, y: 0.6),
            targetColorHex: "#AABBCC",
            pixelSampleRadius: 4,
            threshold: 0.85,
            requireVisible: false
        )
        let condition = AutomationConditionSpec(
            name: "Pixel ready",
            kind: .visual(visual)
        )

        let draft = AutomationTaskConditionDraft(condition: condition)
        let materialized = draft.conditionSpec(
            taskName: "Fallback",
            preserving: AutomationOCRCondition(text: "")
        )
        guard case .visual(let materializedVisual) = materialized.kind else {
            Issue.record("Expected visual condition")
            return
        }

        #expect(draft.mode == .visual)
        #expect(draft.requiredResources == [.screenCapture])
        #expect(materializedVisual == visual)
    }

    @Test("Condition draft normalizes fallback name timeout polling and external signal")
    func conditionDraftNormalizesMaterialization() throws {
        var draft = AutomationTaskConditionDraft()
        draft.name = "   "
        draft.mode = .externalSignal
        draft.signalName = "  build-finished  "
        draft.hasTimeout = true
        draft.timeout = -5
        draft.pollingInterval = 0

        let condition = draft.conditionSpec(
            taskName: "Wait for build",
            preserving: AutomationOCRCondition(text: "")
        )
        guard case .externalSignal(let signalName) = condition.kind else {
            Issue.record("Expected external signal condition")
            return
        }

        #expect(condition.name == "Wait for build")
        #expect(condition.timeout == 0)
        #expect(condition.pollingInterval == 0.05)
        #expect(signalName == "build-finished")
    }

    @Test("Rect draft keeps OCR clamping separate from visual positive-size semantics")
    func rectDraftPreservesGeometrySemantics() {
        let draft = AutomationTaskRectDraft(
            isEnabled: true,
            x: -4,
            y: -3,
            width: -2,
            height: 8
        )

        #expect(draft.nonnegativeRect == RectValue(x: 0, y: 0, width: 0, height: 8))
        #expect(draft.positiveSizeRect == nil)
    }
}
