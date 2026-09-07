import Foundation

public enum AutomationTaskScheduleMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case manual
    case once
    case repeating
}

public enum AutomationTaskRepeatUnit: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case minutes
    case hours
    case days
    case weeks
}

public struct AutomationTaskScheduleDraft: Equatable, Sendable {
    public var mode: AutomationTaskScheduleMode
    public var onceDate: Date
    public var repeatStart: Date
    public var repeatEvery: Int
    public var repeatUnit: AutomationTaskRepeatUnit

    public init(
        mode: AutomationTaskScheduleMode = .manual,
        onceDate: Date = .now,
        repeatStart: Date = .now,
        repeatEvery: Int = 1,
        repeatUnit: AutomationTaskRepeatUnit = .hours
    ) {
        self.mode = mode
        self.onceDate = onceDate
        self.repeatStart = repeatStart
        self.repeatEvery = repeatEvery
        self.repeatUnit = repeatUnit
    }

    public init(schedule: AutomationSchedule?, referenceDate: Date = .now) {
        self.init(onceDate: referenceDate, repeatStart: referenceDate)

        switch schedule {
        case .manual, nil:
            mode = .manual
        case .once(let date):
            mode = .once
            onceDate = date
        case .repeating(let rule):
            mode = .repeating
            repeatStart = rule.anchor
            switch rule.interval {
            case .minutes(let count):
                repeatEvery = count
                repeatUnit = .minutes
            case .hours(let count):
                repeatEvery = count
                repeatUnit = .hours
            case .days(let count):
                repeatEvery = count
                repeatUnit = .days
            case .weeks(let count):
                repeatEvery = count
                repeatUnit = .weeks
            }
        }
    }

    public var schedule: AutomationSchedule {
        switch mode {
        case .manual:
            return .manual
        case .once:
            return .once(onceDate)
        case .repeating:
            return .repeating(
                AutomationRepeatRule(
                    anchor: repeatStart,
                    interval: repeatInterval
                )
            )
        }
    }

    private var repeatInterval: AutomationRepeatInterval {
        let count = max(1, repeatEvery)
        switch repeatUnit {
        case .minutes:
            return .minutes(count)
        case .hours:
            return .hours(count)
        case .days:
            return .days(count)
        case .weeks:
            return .weeks(count)
        }
    }
}

public struct AutomationTaskExecutionDraft: Equatable, Sendable {
    public var targetApplicationPolicy: AutomationTargetApplicationPolicy
    public var targetApplicationReadyDelay: TimeInterval
    public var hasTimeout: Bool
    public var timeout: TimeInterval
    public var retryAttempts: Int
    public var joinPolicy: AutomationJoinPolicy

    public init(
        targetApplicationPolicy: AutomationTargetApplicationPolicy = .activateIfRunning,
        targetApplicationReadyDelay: TimeInterval = 0,
        hasTimeout: Bool = false,
        timeout: TimeInterval = 60,
        retryAttempts: Int = 1,
        joinPolicy: AutomationJoinPolicy = .all
    ) {
        self.targetApplicationPolicy = targetApplicationPolicy
        self.targetApplicationReadyDelay = targetApplicationReadyDelay
        self.hasTimeout = hasTimeout
        self.timeout = timeout
        self.retryAttempts = retryAttempts
        self.joinPolicy = joinPolicy
    }

    public init(task: AutomationTask) {
        self.init(
            targetApplicationPolicy: task.targetApplicationPolicy,
            targetApplicationReadyDelay: task.targetApplicationReadyDelay,
            hasTimeout: task.timeout != nil,
            timeout: task.timeout ?? 60,
            retryAttempts: task.retryPolicy.maxAttempts,
            joinPolicy: task.joinPolicy
        )
    }

    public func apply(to task: inout AutomationTask) {
        task.targetApplicationPolicy = targetApplicationPolicy
        task.targetApplicationReadyDelay = targetApplicationReadyDelay
        task.timeout = hasTimeout ? max(0, timeout) : nil
        task.retryPolicy = AutomationRetryPolicy(maxAttempts: max(1, retryAttempts))
        task.joinPolicy = joinPolicy
    }
}

public struct AutomationTaskResourceDraft: Equatable, Sendable {
    public var resources: Set<AutomationResource>
    public var priority: AutomationResourcePriority
    public var hasMaxWaitDuration: Bool
    public var maxWaitDuration: TimeInterval

    public init(
        resources: Set<AutomationResource> = [],
        priority: AutomationResourcePriority = .normal,
        hasMaxWaitDuration: Bool = false,
        maxWaitDuration: TimeInterval = 10
    ) {
        self.resources = resources
        self.priority = priority
        self.hasMaxWaitDuration = hasMaxWaitDuration
        self.maxWaitDuration = maxWaitDuration
    }

    public init(requirement: AutomationResourceRequirement) {
        self.init(
            resources: requirement.resources,
            priority: requirement.priority,
            hasMaxWaitDuration: requirement.maxWaitDuration != nil,
            maxWaitDuration: requirement.maxWaitDuration ?? 10
        )
    }

    public func requirement(
        preserving base: AutomationResourceRequirement,
        requiredResources: Set<AutomationResource> = []
    ) -> AutomationResourceRequirement {
        let effectiveResources = resources.union(requiredResources)
        return AutomationResourceRequirement(
            resources: effectiveResources,
            priority: priority,
            leaseTimeout: base.leaseTimeout,
            maxWaitDuration: effectiveResources.isEmpty || !hasMaxWaitDuration
                ? nil
                : max(0, maxWaitDuration)
        )
    }
}

public enum AutomationTaskConditionMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case manualApproval
    case externalSignal
    case ocrText
    case visual
    case previousOutcome

    public var requiresScreenCapture: Bool {
        switch self {
        case .ocrText, .visual:
            return true
        case .manualApproval, .externalSignal, .previousOutcome:
            return false
        }
    }
}

public struct AutomationTaskRectDraft: Equatable, Sendable {
    public var isEnabled: Bool
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        isEnabled: Bool = false,
        x: Double = 0,
        y: Double = 0,
        width: Double = 0,
        height: Double = 0
    ) {
        self.isEnabled = isEnabled
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: RectValue?) {
        guard let rect else {
            self.init()
            return
        }
        self.init(
            isEnabled: true,
            x: Double(rect.x),
            y: Double(rect.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    public var nonnegativeRect: RectValue? {
        guard isEnabled else { return nil }
        return RectValue(
            x: CGFloat(max(0, x)),
            y: CGFloat(max(0, y)),
            width: CGFloat(max(0, width)),
            height: CGFloat(max(0, height))
        )
    }

    public var positiveSizeRect: RectValue? {
        guard isEnabled, width > 0, height > 0 else { return nil }
        return RectValue(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

public struct AutomationTaskConditionDraft: Equatable, Sendable {
    public var name: String
    public var mode: AutomationTaskConditionMode
    public var signalName: String

    public var ocrText: String
    public var ocrMatchMode: TextMatchMode
    public var ocrSearchRegionSpace: AutomationOCRSearchRegionSpace
    public var ocrRequiresVisible: Bool
    public var ocrRegion: AutomationTaskRectDraft

    public var visualType: AutomationVisualConditionType
    public var visualRegionRef: String
    public var visualSearchRegionSpace: AutomationOCRSearchRegionSpace
    public var visualRegion: AutomationTaskRectDraft
    public var visualImageRef: String
    public var visualBaselineRef: String
    public var hasVisualPixel: Bool
    public var visualPixelX: Double
    public var visualPixelY: Double
    public var visualColorHex: String
    public var visualPixelSampleRadius: Int
    public var hasVisualThreshold: Bool
    public var visualThreshold: Double
    public var visualRequiresVisible: Bool

    public var outcomePredicate: String
    public var hasTimeout: Bool
    public var timeout: TimeInterval
    public var pollingInterval: TimeInterval

    public init() {
        name = ""
        mode = .manualApproval
        signalName = ""
        ocrText = ""
        ocrMatchMode = .contains
        ocrSearchRegionSpace = .automatic
        ocrRequiresVisible = true
        ocrRegion = AutomationTaskRectDraft()
        visualType = .regionChanged
        visualRegionRef = ""
        visualSearchRegionSpace = .automatic
        visualRegion = AutomationTaskRectDraft()
        visualImageRef = ""
        visualBaselineRef = ""
        hasVisualPixel = false
        visualPixelX = 0
        visualPixelY = 0
        visualColorHex = ""
        visualPixelSampleRadius = AutomationVisualCondition.defaultPixelSampleRadius
        hasVisualThreshold = false
        visualThreshold = 0.9
        visualRequiresVisible = true
        outcomePredicate = AutomationOutcomePredicate.anyTerminal.rawValue
        hasTimeout = false
        timeout = 30
        pollingInterval = 0.25
    }

    public init(condition: AutomationConditionSpec?) {
        self.init()
        guard let condition else { return }

        name = condition.name
        hasTimeout = condition.timeout != nil
        timeout = condition.timeout ?? 30
        pollingInterval = condition.pollingInterval

        switch condition.kind {
        case .manualApproval:
            mode = .manualApproval
        case .externalSignal(let signalName):
            mode = .externalSignal
            self.signalName = signalName
        case .ocrText(let ocr):
            mode = .ocrText
            apply(ocrCondition: ocr)
        case .visual(let visual):
            mode = .visual
            visualType = visual.type
            visualRegionRef = visual.regionRef ?? ""
            visualSearchRegionSpace = visual.searchRegionSpace
            visualRegion = AutomationTaskRectDraft(rect: visual.searchRegion)
            visualImageRef = visual.imageRef ?? ""
            visualBaselineRef = visual.baselineRef ?? ""
            if let pixel = visual.pixel {
                hasVisualPixel = true
                visualPixelX = pixel.x
                visualPixelY = pixel.y
            }
            visualColorHex = visual.targetColorHex ?? ""
            visualPixelSampleRadius = visual.pixelSampleRadius
                ?? AutomationVisualCondition.defaultPixelSampleRadius
            hasVisualThreshold = visual.threshold != nil
            visualThreshold = visual.threshold ?? 0.9
            visualRequiresVisible = visual.requireVisible
        case .previousOutcome(let predicate):
            mode = .previousOutcome
            outcomePredicate = predicate.rawValue
        }
    }

    public mutating func apply(ocrCondition: AutomationOCRCondition) {
        ocrText = ocrCondition.text
        ocrMatchMode = ocrCondition.matchMode
        ocrSearchRegionSpace = ocrCondition.searchRegionSpace
        ocrRequiresVisible = ocrCondition.requireVisible
        ocrRegion = AutomationTaskRectDraft(rect: ocrCondition.searchRegion)
    }

    public var requiredResources: Set<AutomationResource> {
        mode.requiresScreenCapture ? [.screenCapture] : []
    }

    public func ocrCondition(preserving base: AutomationOCRCondition) -> AutomationOCRCondition {
        base.updatingTextMatchRegionAndSpace(
            text: ocrText.trimmingCharacters(in: .whitespacesAndNewlines),
            matchMode: ocrMatchMode,
            searchRegion: ocrRegion.nonnegativeRect,
            searchRegionSpace: ocrSearchRegionSpace,
            requireVisible: ocrRequiresVisible
        )
    }

    public var visualCondition: AutomationVisualCondition {
        AutomationVisualCondition(
            type: visualType,
            regionRef: visualRegionRef,
            searchRegion: visualRegion.positiveSizeRect,
            searchRegionSpace: visualSearchRegionSpace,
            imageRef: materializedVisualImageRef,
            baselineRef: visualType == .regionChanged ? visualBaselineRef : nil,
            pixel: visualType == .pixelMatched && hasVisualPixel
                ? AutomationGraphPoint(x: visualPixelX, y: visualPixelY)
                : nil,
            targetColorHex: visualType == .pixelMatched ? visualColorHex : nil,
            pixelSampleRadius: visualType == .pixelMatched ? visualPixelSampleRadius : nil,
            threshold: hasVisualThreshold ? visualThreshold : nil,
            requireVisible: visualRequiresVisible
        )
    }

    private var materializedVisualImageRef: String? {
        switch visualType {
        case .imageAppeared, .imageDisappeared:
            return visualImageRef
        case .regionChanged, .pixelMatched:
            return nil
        }
    }

    public func conditionSpec(
        taskName: String,
        preserving baseOCRCondition: AutomationOCRCondition,
        ocrConditionOverride: AutomationOCRCondition? = nil
    ) -> AutomationConditionSpec {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return AutomationConditionSpec(
            name: trimmedName.isEmpty ? taskName : trimmedName,
            kind: conditionKind(
                preserving: baseOCRCondition,
                ocrConditionOverride: ocrConditionOverride
            ),
            timeout: hasTimeout ? max(0, timeout) : nil,
            pollingInterval: max(0.05, pollingInterval)
        )
    }

    private func conditionKind(
        preserving baseOCRCondition: AutomationOCRCondition,
        ocrConditionOverride: AutomationOCRCondition?
    ) -> AutomationConditionKind {
        switch mode {
        case .manualApproval:
            return .manualApproval
        case .externalSignal:
            return .externalSignal(signalName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .ocrText:
            return .ocrText(ocrConditionOverride ?? ocrCondition(preserving: baseOCRCondition))
        case .visual:
            return .visual(visualCondition)
        case .previousOutcome:
            let predicate = AutomationOutcomePredicate(rawValue: outcomePredicate) ?? .anyTerminal
            return .previousOutcome(predicate)
        }
    }
}
