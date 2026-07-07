import Foundation

public struct AutomationProductEvidenceAuditPayload: Codable, Equatable, Sendable {
    public var directory: String
    public var requiredCount: Int
    public var satisfiedRequiredCount: Int
    public var missingRequiredIDs: [String]
    public var allRequiredPresent: Bool
    public var items: [AutomationProductEvidenceAuditItem]

    public init(
        directory: String,
        requiredCount: Int,
        satisfiedRequiredCount: Int,
        missingRequiredIDs: [String],
        allRequiredPresent: Bool,
        items: [AutomationProductEvidenceAuditItem]
    ) {
        self.directory = directory
        self.requiredCount = requiredCount
        self.satisfiedRequiredCount = satisfiedRequiredCount
        self.missingRequiredIDs = missingRequiredIDs
        self.allRequiredPresent = allRequiredPresent
        self.items = items
    }
}

public struct AutomationProductEvidenceAuditItem: Codable, Equatable, Sendable {
    public var id: String
    public var category: String
    public var title: String
    public var required: Bool
    public var satisfied: Bool
    public var fileGroups: [[AutomationProductEvidenceAuditFile]]
    public var note: String

    public init(
        id: String,
        category: String,
        title: String,
        required: Bool,
        satisfied: Bool,
        fileGroups: [[AutomationProductEvidenceAuditFile]],
        note: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.required = required
        self.satisfied = satisfied
        self.fileGroups = fileGroups
        self.note = note
    }
}

public enum AutomationProductEvidenceClipContainer: String, Codable, Equatable, Sendable {
    case isoBaseMedia
    case unsupported
    case unknown

    public var isSupported: Bool {
        self == .isoBaseMedia
    }
}

public struct AutomationProductEvidenceAuditFile: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var byteCount: Int64?
    public var minimumByteCount: Int64?
    public var clipContainer: AutomationProductEvidenceClipContainer?
    public var requiresSupportedClipContainer: Bool
    public var missingRequiredPhrases: [String]

    public init(
        path: String,
        exists: Bool,
        byteCount: Int64? = nil,
        minimumByteCount: Int64? = nil,
        clipContainer: AutomationProductEvidenceClipContainer? = nil,
        requiresSupportedClipContainer: Bool = false,
        missingRequiredPhrases: [String] = []
    ) {
        self.path = path
        self.exists = exists
        self.byteCount = byteCount
        self.minimumByteCount = minimumByteCount
        self.clipContainer = clipContainer
        self.requiresSupportedClipContainer = requiresSupportedClipContainer
        self.missingRequiredPhrases = missingRequiredPhrases
    }

    public var meetsMinimumByteCount: Bool {
        guard let minimumByteCount else {
            return true
        }
        guard let byteCount else {
            return false
        }
        return byteCount >= minimumByteCount
    }

    public var hasSupportedClipContainer: Bool {
        guard requiresSupportedClipContainer else {
            return true
        }
        guard let clipContainer else {
            return false
        }
        return clipContainer.isSupported
    }

    public var satisfied: Bool {
        exists && missingRequiredPhrases.isEmpty && meetsMinimumByteCount && hasSupportedClipContainer
    }
}

public struct AutomationProductEvidenceAuditSpec: Equatable, Sendable {
    public var id: String
    public var category: String
    public var title: String
    public var fileGroups: [[String]]
    public var required: Bool
    public var note: String
    public var sidecarRequiredPhrases: [String]

    public init(
        id: String,
        category: String,
        title: String,
        fileGroups: [[String]],
        required: Bool,
        note: String,
        sidecarRequiredPhrases: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.fileGroups = fileGroups
        self.required = required
        self.note = note
        self.sidecarRequiredPhrases = sidecarRequiredPhrases
    }
}

public struct AutomationProductEvidenceSidecarTemplatePayload: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var sidecarPath: String
    public var clipPathCandidates: [String]
    public var requiredLabels: [String]
    public var template: String

    public init(
        id: String,
        title: String,
        sidecarPath: String,
        clipPathCandidates: [String],
        requiredLabels: [String],
        template: String
    ) {
        self.id = id
        self.title = title
        self.sidecarPath = sidecarPath
        self.clipPathCandidates = clipPathCandidates
        self.requiredLabels = requiredLabels
        self.template = template
    }
}

public struct AutomationProductEvidenceSidecarCompletion: Equatable, Sendable {
    public var clipPath: String
    public var captureDate: String
    public var worktreeNote: String
    public var appBuildRunSource: String
    public var workflowPackage: String
    public var userAction: String
    public var knownGaps: String
    public var evidenceSource: String

    public init(
        clipPath: String,
        captureDate: String,
        worktreeNote: String,
        appBuildRunSource: String,
        workflowPackage: String,
        userAction: String,
        knownGaps: String,
        evidenceSource: String
    ) {
        self.clipPath = clipPath
        self.captureDate = captureDate
        self.worktreeNote = worktreeNote
        self.appBuildRunSource = appBuildRunSource
        self.workflowPackage = workflowPackage
        self.userAction = userAction
        self.knownGaps = knownGaps
        self.evidenceSource = evidenceSource
    }
}

public struct AutomationProductEvidenceCompletedSidecarPayload: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var sidecarPath: String
    public var clipPath: String
    public var requiredLabels: [String]
    public var content: String

    public init(
        id: String,
        title: String,
        sidecarPath: String,
        clipPath: String,
        requiredLabels: [String],
        content: String
    ) {
        self.id = id
        self.title = title
        self.sidecarPath = sidecarPath
        self.clipPath = clipPath
        self.requiredLabels = requiredLabels
        self.content = content
    }
}

public struct AutomationProductEvidenceCapturePlanPayload: Codable, Equatable, Sendable {
    public var directory: String
    public var missingLiveCount: Int
    public var allLiveSatisfied: Bool
    public var items: [AutomationProductEvidenceCapturePlanItem]

    public init(
        directory: String,
        missingLiveCount: Int,
        allLiveSatisfied: Bool,
        items: [AutomationProductEvidenceCapturePlanItem]
    ) {
        self.directory = directory
        self.missingLiveCount = missingLiveCount
        self.allLiveSatisfied = allLiveSatisfied
        self.items = items
    }
}

public struct AutomationProductEvidenceCapturePlanItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var satisfied: Bool
    public var note: String
    public var options: [AutomationProductEvidenceCapturePlanOption]

    public init(
        id: String,
        title: String,
        satisfied: Bool,
        note: String,
        options: [AutomationProductEvidenceCapturePlanOption]
    ) {
        self.id = id
        self.title = title
        self.satisfied = satisfied
        self.note = note
        self.options = options
    }
}

public struct AutomationProductEvidenceCapturePlanOption: Codable, Equatable, Sendable {
    public var sidecarPath: String
    public var clipPathCandidates: [String]
    public var missingPaths: [String]
    public var undersizedPaths: [String]
    public var invalidClipContainerPaths: [String]
    public var incompleteSidecarLabels: [String]
    public var sidecarTemplateCommand: String
    public var sidecarCompletionCommand: String
    public var acceptanceFocus: String

    public init(
        sidecarPath: String,
        clipPathCandidates: [String],
        missingPaths: [String],
        undersizedPaths: [String] = [],
        invalidClipContainerPaths: [String] = [],
        incompleteSidecarLabels: [String],
        sidecarTemplateCommand: String,
        sidecarCompletionCommand: String,
        acceptanceFocus: String
    ) {
        self.sidecarPath = sidecarPath
        self.clipPathCandidates = clipPathCandidates
        self.missingPaths = missingPaths
        self.undersizedPaths = undersizedPaths
        self.invalidClipContainerPaths = invalidClipContainerPaths
        self.incompleteSidecarLabels = incompleteSidecarLabels
        self.sidecarTemplateCommand = sidecarTemplateCommand
        self.sidecarCompletionCommand = sidecarCompletionCommand
        self.acceptanceFocus = acceptanceFocus
    }
}

public struct AutomationProductEvidenceSidecarDraftsPayload: Codable, Equatable, Sendable {
    public var directory: String
    public var includeSatisfied: Bool
    public var drafts: [AutomationProductEvidenceSidecarTemplatePayload]

    public init(
        directory: String,
        includeSatisfied: Bool,
        drafts: [AutomationProductEvidenceSidecarTemplatePayload]
    ) {
        self.directory = directory
        self.includeSatisfied = includeSatisfied
        self.drafts = drafts
    }
}

public enum AutomationProductEvidenceAudit {
    public static let defaultDirectory = "docs/workflow-page-productization/product-evidence"
    public static let minimumLiveClipByteCount: Int64 = 1

    public static let liveSidecarRequiredPhrases: [String] = [
        "Capture date:",
        "Worktree note:",
        "App build/run source:",
        "Workflow/package:",
        "User action:",
        "Checklist item:",
        "Known gaps:",
        "Evidence source:",
        "Clip file:"
    ]

    public static let defaultSpecs: [AutomationProductEvidenceAuditSpec] = [
        AutomationProductEvidenceAuditSpec(
            id: "fixture-idle-workflow",
            category: "fixture",
            title: "Idle Workflow Fixture",
            fileGroups: [["idle-workflow.png", "idle-workflow.md"]],
            required: true,
            note: "Fixture proof for the restrained idle Workflow surface."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-running-workflow",
            category: "fixture",
            title: "Running Workflow Fixture",
            fileGroups: [["running-workflow.png", "running-workflow.md"]],
            required: true,
            note: "Fixture proof for projection-driven running state."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-visual-diagnostics",
            category: "fixture",
            title: "Visual Diagnostics Fixture",
            fileGroups: [["visual-diagnostics-drill-in.png", "visual-diagnostics-drill-in.md"]],
            required: true,
            note: "Fixture proof for condition evidence rendering and artifact affordances."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-template-baseline-preview-refs",
            category: "fixture",
            title: "Template/Baseline Preview Refs Fixture",
            fileGroups: [["template-baseline-preview-refs.png", "template-baseline-preview-refs.md"]],
            required: true,
            note: "Fixture proof that source reference, runtime sample and comparison decision render together."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-branch-evidence",
            category: "fixture",
            title: "Branch Evidence Fixture",
            fileGroups: [["branch-evidence-drill-in.png", "branch-evidence-drill-in.md"]],
            required: true,
            note: "Fixture proof for durable branch decision drill-in."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-failed-run-detail",
            category: "fixture",
            title: "Failed Run Detail Fixture",
            fileGroups: [["failed-run-detail.png", "failed-run-detail.md"]],
            required: true,
            note: "Fixture proof for per-run manifest/report/screenshot binding."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-failed-run-preview-unavailable",
            category: "fixture",
            title: "Failed Run Preview-Unavailable Fixture",
            fileGroups: [["failed-run-preview-unavailable.png", "failed-run-preview-unavailable.md"]],
            required: true,
            note: "Fixture proof for unreadable screenshot fallback."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-drag-link",
            category: "fixture",
            title: "Drag Link Authoring Fixture",
            fileGroups: [["drag-link-authoring.png", "drag-link-authoring.md"]],
            required: true,
            note: "Fixture proof for connector preview state."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "fixture-task-reorder",
            category: "fixture",
            title: "Task Reorder Authoring Fixture",
            fileGroups: [["task-reorder-authoring.png", "task-reorder-authoring.md"]],
            required: true,
            note: "Fixture proof for task reorder visual state."
        ),
        AutomationProductEvidenceAuditSpec(
            id: "live-visual-diagnostics-open-reveal",
            category: "live",
            title: "Live Visual Diagnostics Open/Reveal",
            fileGroups: [
                ["live-visual-diagnostics-open-reveal.mov", "live-visual-diagnostics-open-reveal.md"],
                ["live-visual-diagnostics-open-reveal.mp4", "live-visual-diagnostics-open-reveal.md"]
            ],
            required: true,
            note: "Required S0 live evidence for App Support artifact preview/open/reveal.",
            sidecarRequiredPhrases: liveSidecarRequiredPhrases
        ),
        AutomationProductEvidenceAuditSpec(
            id: "live-macro-evidence-open-reveal",
            category: "live",
            title: "Live Macro Evidence Open/Reveal",
            fileGroups: [
                ["live-macro-evidence-open-reveal.mov", "live-macro-evidence-open-reveal.md"],
                ["live-macro-evidence-open-reveal.mp4", "live-macro-evidence-open-reveal.md"]
            ],
            required: true,
            note: "Required S0 live evidence for Reveal Report / Open Screenshot.",
            sidecarRequiredPhrases: liveSidecarRequiredPhrases
        ),
        AutomationProductEvidenceAuditSpec(
            id: "live-branch-evidence-consistency",
            category: "live",
            title: "Live Branch Evidence Consistency",
            fileGroups: [
                ["live-branch-evidence-consistency.mov", "live-branch-evidence-consistency.md"],
                ["live-branch-evidence-consistency.mp4", "live-branch-evidence-consistency.md"]
            ],
            required: true,
            note: "Required S0 live evidence for FlowGraph edge, selected run and Run Detail agreement.",
            sidecarRequiredPhrases: liveSidecarRequiredPhrases
        ),
        AutomationProductEvidenceAuditSpec(
            id: "live-authoring-wysiwyg",
            category: "live",
            title: "Live Authoring WYSIWYG",
            fileGroups: [
                ["live-task-reorder-wysiwyg.mov", "live-task-reorder-wysiwyg.md"],
                ["live-task-reorder-wysiwyg.mp4", "live-task-reorder-wysiwyg.md"],
                ["live-drag-link-wysiwyg.mov", "live-drag-link-wysiwyg.md"],
                ["live-drag-link-wysiwyg.mp4", "live-drag-link-wysiwyg.md"]
            ],
            required: true,
            note: "Required S0 live evidence for either real task reorder or real drag-link mutation.",
            sidecarRequiredPhrases: liveSidecarRequiredPhrases
        )
    ]

    public static func evaluate(
        directory: String,
        existingPaths: Set<String>,
        sidecarContents: [String: String] = [:],
        fileByteCounts: [String: Int64] = [:],
        clipContainers: [String: AutomationProductEvidenceClipContainer] = [:],
        specs: [AutomationProductEvidenceAuditSpec] = defaultSpecs
    ) -> AutomationProductEvidenceAuditPayload {
        let items = specs.map { spec -> AutomationProductEvidenceAuditItem in
            let fileGroups: [[AutomationProductEvidenceAuditFile]] = spec.fileGroups.map { group in
                let groupClipPaths = group.filter { isLiveClipPath($0) }
                return group.map { path in
                    let exists = existingPaths.contains(path)
                    let minimumByteCount = minimumByteCount(for: path, in: spec)
                    let requiresSupportedClipContainer = requiresSupportedClipContainer(
                        for: path,
                        in: spec
                    )
                    let missingRequiredPhrases = Self.missingRequiredPhrases(
                        path: path,
                        exists: exists,
                        contents: sidecarContents[path],
                        requiredPhrases: spec.sidecarRequiredPhrases,
                        validClipPaths: groupClipPaths,
                        expectedChecklistTitle: spec.title,
                        expectedChecklistID: spec.id
                    )
                    return AutomationProductEvidenceAuditFile(
                        path: path,
                        exists: exists,
                        byteCount: exists ? fileByteCounts[path] : nil,
                        minimumByteCount: minimumByteCount,
                        clipContainer: exists ? clipContainers[path] : nil,
                        requiresSupportedClipContainer: requiresSupportedClipContainer,
                        missingRequiredPhrases: missingRequiredPhrases
                    )
                }
            }
            let satisfied = fileGroups.contains { group in
                group.allSatisfy { $0.satisfied }
            }
            return AutomationProductEvidenceAuditItem(
                id: spec.id,
                category: spec.category,
                title: spec.title,
                required: spec.required,
                satisfied: satisfied,
                fileGroups: fileGroups,
                note: spec.note
            )
        }
        let requiredItems = items.filter { $0.required }
        let missingRequiredIDs = requiredItems
            .filter { !$0.satisfied }
            .map { $0.id }
        return AutomationProductEvidenceAuditPayload(
            directory: directory,
            requiredCount: requiredItems.count,
            satisfiedRequiredCount: requiredItems.count - missingRequiredIDs.count,
            missingRequiredIDs: missingRequiredIDs,
            allRequiredPresent: missingRequiredIDs.isEmpty,
            items: items
        )
    }

    public static func liveSidecarTemplate(
        id: String,
        sidecarPath requestedSidecarPath: String? = nil,
        specs: [AutomationProductEvidenceAuditSpec] = defaultSpecs
    ) -> AutomationProductEvidenceSidecarTemplatePayload? {
        guard let spec = specs.first(where: { $0.id == id }),
              !spec.sidecarRequiredPhrases.isEmpty else {
            return nil
        }

        let sidecarPath = requestedSidecarPath ?? spec.fileGroups
            .flatMap { $0 }
            .first { $0.hasSuffix(".md") }
        guard let sidecarPath else {
            return nil
        }

        let matchingGroups = spec.fileGroups.filter { $0.contains(sidecarPath) }
        guard !matchingGroups.isEmpty else {
            return nil
        }

        let clipPathCandidates = matchingGroups
            .flatMap { $0 }
            .filter { !$0.hasSuffix(".md") }
            .sorted()
        guard !clipPathCandidates.isEmpty else {
            return nil
        }

        let template = liveSidecarTemplateText(
            title: spec.title,
            id: spec.id,
            sidecarPath: sidecarPath,
            clipPathCandidates: clipPathCandidates
        )
        return AutomationProductEvidenceSidecarTemplatePayload(
            id: spec.id,
            title: spec.title,
            sidecarPath: sidecarPath,
            clipPathCandidates: clipPathCandidates,
            requiredLabels: spec.sidecarRequiredPhrases,
            template: template
        )
    }

    public static func completedLiveSidecar(
        id: String,
        sidecarPath requestedSidecarPath: String? = nil,
        completion: AutomationProductEvidenceSidecarCompletion,
        specs: [AutomationProductEvidenceAuditSpec] = defaultSpecs
    ) -> AutomationProductEvidenceCompletedSidecarPayload? {
        guard let template = liveSidecarTemplate(
            id: id,
            sidecarPath: requestedSidecarPath,
            specs: specs
        ), template.clipPathCandidates.contains(completion.clipPath) else {
            return nil
        }

        let content = completedLiveSidecarText(
            title: template.title,
            id: template.id,
            sidecarPath: template.sidecarPath,
            completion: completion
        )
        return AutomationProductEvidenceCompletedSidecarPayload(
            id: template.id,
            title: template.title,
            sidecarPath: template.sidecarPath,
            clipPath: completion.clipPath,
            requiredLabels: template.requiredLabels,
            content: content
        )
    }

    public static func liveCapturePlan(
        directory: String,
        existingPaths: Set<String>,
        sidecarContents: [String: String] = [:],
        fileByteCounts: [String: Int64] = [:],
        clipContainers: [String: AutomationProductEvidenceClipContainer] = [:],
        specs: [AutomationProductEvidenceAuditSpec] = defaultSpecs
    ) -> AutomationProductEvidenceCapturePlanPayload {
        let audit = evaluate(
            directory: directory,
            existingPaths: existingPaths,
            sidecarContents: sidecarContents,
            fileByteCounts: fileByteCounts,
            clipContainers: clipContainers,
            specs: specs
        )
        let liveSpecs = specs.filter { !$0.sidecarRequiredPhrases.isEmpty }
        let liveItems = liveSpecs.map { spec -> AutomationProductEvidenceCapturePlanItem in
            let auditItem = audit.items.first { $0.id == spec.id }
            let sidecarPaths = orderedUnique(
                spec.fileGroups.flatMap { $0 }.filter { $0.hasSuffix(".md") }
            )
            let options = sidecarPaths.compactMap { sidecarPath -> AutomationProductEvidenceCapturePlanOption? in
                guard let template = liveSidecarTemplate(
                    id: spec.id,
                    sidecarPath: sidecarPath,
                    specs: specs
                ) else {
                    return nil
                }
                let groupFiles = orderedUnique(spec.fileGroups
                    .filter { $0.contains(sidecarPath) }
                    .flatMap { $0 })
                let missingPaths = groupFiles
                    .filter { !existingPaths.contains($0) }
                    .sorted()
                let undersizedPaths = groupFiles
                    .filter { path in
                        guard existingPaths.contains(path),
                              let minimumByteCount = minimumByteCount(for: path, in: spec) else {
                            return false
                        }
                        guard let byteCount = fileByteCounts[path] else {
                            return true
                        }
                        return byteCount < minimumByteCount
                    }
                    .sorted()
                let invalidClipContainerPaths = groupFiles
                    .filter { path in
                        guard existingPaths.contains(path),
                              requiresSupportedClipContainer(for: path, in: spec) else {
                            return false
                        }
                        return clipContainers[path]?.isSupported != true
                    }
                    .sorted()
                let incompleteLabels = missingRequiredPhrases(
                    path: sidecarPath,
                    exists: existingPaths.contains(sidecarPath),
                    contents: sidecarContents[sidecarPath],
                    requiredPhrases: spec.sidecarRequiredPhrases,
                    validClipPaths: template.clipPathCandidates,
                    expectedChecklistTitle: spec.title,
                    expectedChecklistID: spec.id
                )
                return AutomationProductEvidenceCapturePlanOption(
                    sidecarPath: sidecarPath,
                    clipPathCandidates: template.clipPathCandidates,
                    missingPaths: missingPaths,
                    undersizedPaths: undersizedPaths,
                    invalidClipContainerPaths: invalidClipContainerPaths,
                    incompleteSidecarLabels: incompleteLabels,
                    sidecarTemplateCommand: sidecarTemplateCommand(
                        id: spec.id,
                        sidecarPath: sidecarPaths.count > 1 ? sidecarPath : nil
                    ),
                    sidecarCompletionCommand: sidecarCompletionCommand(
                        id: spec.id,
                        sidecarPath: sidecarPaths.count > 1 ? sidecarPath : nil,
                        clipPath: template.clipPathCandidates.first ?? "<clip>"
                    ),
                    acceptanceFocus: spec.note
                )
            }
            return AutomationProductEvidenceCapturePlanItem(
                id: spec.id,
                title: spec.title,
                satisfied: auditItem?.satisfied == true,
                note: spec.note,
                options: options
            )
        }
        let missingLiveCount = liveItems.filter { !$0.satisfied }.count
        return AutomationProductEvidenceCapturePlanPayload(
            directory: directory,
            missingLiveCount: missingLiveCount,
            allLiveSatisfied: missingLiveCount == 0,
            items: liveItems
        )
    }

    public static func liveSidecarDrafts(
        directory: String,
        existingPaths: Set<String>,
        sidecarContents: [String: String] = [:],
        fileByteCounts: [String: Int64] = [:],
        clipContainers: [String: AutomationProductEvidenceClipContainer] = [:],
        includeSatisfied: Bool = false,
        specs: [AutomationProductEvidenceAuditSpec] = defaultSpecs
    ) -> AutomationProductEvidenceSidecarDraftsPayload {
        let plan = liveCapturePlan(
            directory: directory,
            existingPaths: existingPaths,
            sidecarContents: sidecarContents,
            fileByteCounts: fileByteCounts,
            clipContainers: clipContainers,
            specs: specs
        )
        var seenSidecars = Set<String>()
        var drafts: [AutomationProductEvidenceSidecarTemplatePayload] = []

        for item in plan.items where includeSatisfied || !item.satisfied {
            for option in item.options where !seenSidecars.contains(option.sidecarPath) {
                guard let draft = liveSidecarTemplate(
                    id: item.id,
                    sidecarPath: option.sidecarPath,
                    specs: specs
                ) else {
                    continue
                }
                seenSidecars.insert(option.sidecarPath)
                drafts.append(draft)
            }
        }

        return AutomationProductEvidenceSidecarDraftsPayload(
            directory: directory,
            includeSatisfied: includeSatisfied,
            drafts: drafts
        )
    }

    private static func missingRequiredPhrases(
        path: String,
        exists: Bool,
        contents: String?,
        requiredPhrases: [String],
        validClipPaths: [String] = [],
        expectedChecklistTitle: String? = nil,
        expectedChecklistID: String? = nil
    ) -> [String] {
        guard exists, path.hasSuffix(".md"), !requiredPhrases.isEmpty else {
            return []
        }
        let contents = contents ?? ""
        return requiredPhrases.filter { label in
            guard let value = sidecarValue(for: label, in: contents) else {
                return true
            }
            guard !isPlaceholderSidecarValue(value) else {
                return true
            }
            switch label {
            case "Checklist item:":
                return !sidecarChecklistValue(
                    value,
                    matchesTitle: expectedChecklistTitle,
                    id: expectedChecklistID
                )
            case "Clip file:":
                return !sidecarClipValue(value, matchesOneOf: validClipPaths)
            case "Evidence source:":
                return !isLiveEvidenceSource(value)
            default:
                return false
            }
        }
    }

    private static func minimumByteCount(
        for path: String,
        in spec: AutomationProductEvidenceAuditSpec
    ) -> Int64? {
        guard requiresSupportedClipContainer(for: path, in: spec) else {
            return nil
        }
        return minimumLiveClipByteCount
    }

    private static func requiresSupportedClipContainer(
        for path: String,
        in spec: AutomationProductEvidenceAuditSpec
    ) -> Bool {
        !spec.sidecarRequiredPhrases.isEmpty && isLiveClipPath(path)
    }

    private static func isLiveClipPath(_ path: String) -> Bool {
        path.hasSuffix(".mov") || path.hasSuffix(".mp4")
    }

    private static func isPlaceholderSidecarValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("<") || trimmed.hasSuffix(">")
    }

    private static func sidecarClipValue(
        _ value: String,
        matchesOneOf validClipPaths: [String]
    ) -> Bool {
        guard !validClipPaths.isEmpty else {
            return true
        }
        let clips = filenames(in: value, allowedExtensions: ["mov", "mp4"])
        guard clips.count == 1 else {
            return false
        }
        return validClipPaths.contains(clips[0])
    }

    private static func isLiveEvidenceSource(_ value: String) -> Bool {
        let normalized = value.lowercased()
        guard normalized.contains("live"),
              normalized.contains("recording") || normalized.contains("capture") else {
            return false
        }
        return !["fixture", "mock", "synthetic", "placeholder"].contains { disallowed in
            normalized.contains(disallowed)
        }
    }

    private static func sidecarChecklistValue(
        _ value: String,
        matchesTitle expectedTitle: String?,
        id expectedID: String?
    ) -> Bool {
        guard let expectedTitle, let expectedID else {
            return true
        }
        let normalized = value.lowercased()
        return normalized.contains(expectedTitle.lowercased()) &&
            normalized.contains(expectedID.lowercased())
    }

    private static func filenames(
        in value: String,
        allowedExtensions: Set<String>
    ) -> [String] {
        value.split { character in
            !(character.isLetter || character.isNumber || character == "." || character == "-" || character == "_")
        }
        .map(String.init)
        .filter { token in
            guard let fileExtension = token.split(separator: ".").last else {
                return false
            }
            return allowedExtensions.contains(fileExtension.lowercased())
        }
    }

    private static func sidecarValue(for label: String, in contents: String) -> String? {
        let lines = contents.split(whereSeparator: \.isNewline).map(String.init)
        guard let line = lines.first(where: { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("- \(label)") ||
                line.trimmingCharacters(in: .whitespaces).hasPrefix(label)
        }) else {
            return nil
        }
        guard let range = line.range(of: label) else {
            return nil
        }
        return String(line[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func liveSidecarTemplateText(
        title: String,
        id: String,
        sidecarPath: String,
        clipPathCandidates: [String]
    ) -> String {
        let clipCandidates = clipPathCandidates.map { "`\($0)`" }.joined(separator: " or ")
        return """
        # \(title)

        - Capture date: <YYYY-MM-DD>
        - Worktree note: <branch, commit, and whether the tree was dirty>
        - App build/run source: <installed app path, local swift run, or signed build identifier>
        - Workflow/package: <workflow id/name and package or repository source>
        - User action: <exact interaction captured in the clip>
        - Checklist item: \(title) (`\(id)`)
        - Evidence source: <live App recording, not fixture>
        - Clip file: \(clipCandidates)
        - Sidecar file: `\(sidecarPath)`
        - Known gaps: <remaining limitations after this capture, or "none for this gate">

        ## Acceptance Notes

        - Keep this sidecar next to the clip in `docs/workflow-page-productization/product-evidence/`.
        - Do not leave angle-bracket placeholders in the final sidecar; strict audit treats placeholders as incomplete.
        - Re-run `swift run SparkleRecorder workflow product-evidence audit --require-live --json` before marking S0 complete.
        """
    }

    private static func completedLiveSidecarText(
        title: String,
        id: String,
        sidecarPath: String,
        completion: AutomationProductEvidenceSidecarCompletion
    ) -> String {
        """
        # \(title)

        - Capture date: \(completion.captureDate)
        - Worktree note: \(completion.worktreeNote)
        - App build/run source: \(completion.appBuildRunSource)
        - Workflow/package: \(completion.workflowPackage)
        - User action: \(completion.userAction)
        - Checklist item: \(title) (`\(id)`)
        - Evidence source: \(completion.evidenceSource)
        - Clip file: `\(completion.clipPath)`
        - Sidecar file: `\(sidecarPath)`
        - Known gaps: \(completion.knownGaps)

        ## Acceptance Notes

        - This sidecar was completed from reviewed live capture metadata.
        - Keep this sidecar next to the clip in `docs/workflow-page-productization/product-evidence/`.
        - Re-run `swift run SparkleRecorder workflow product-evidence audit --require-live --json` before marking S0 complete.
        """
    }

    private static func sidecarTemplateCommand(id: String, sidecarPath: String?) -> String {
        var command = "SparkleRecorder workflow product-evidence sidecar-template \(id)"
        if let sidecarPath {
            command += " --sidecar \(sidecarPath)"
        }
        return command
    }

    private static func sidecarCompletionCommand(
        id: String,
        sidecarPath: String?,
        clipPath: String
    ) -> String {
        var command = "SparkleRecorder workflow product-evidence complete-sidecar \(id)"
        if let sidecarPath {
            command += " --sidecar \(sidecarPath)"
        }
        command += " --clip \(clipPath)"
        command += " --capture-date YYYY-MM-DD"
        command += " --worktree-note \"branch, commit, dirty-state\""
        command += " --app-build \"installed app path or local build\""
        command += " --workflow \"workflow id/name and package\""
        command += " --user-action \"captured user action\""
        command += " --known-gaps \"none or remaining limitation\""
        command += " --evidence-source \"live App recording\""
        return command
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
