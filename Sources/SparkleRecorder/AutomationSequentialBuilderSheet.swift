import Foundation
import SparkleRecorderCore
import SwiftUI

enum AutomationLinearContinuation: String, CaseIterable, Identifiable, Equatable {
  case immediate
  case delay
  case screenText

  var id: Self { self }

  var title: String {
    switch self {
    case .immediate:
      return String(localized: "Continue immediately", table: "Automation")
    case .delay:
      return String(localized: "Wait for a duration", table: "Automation")
    case .screenText:
      return String(localized: "Wait for screen text", table: "Automation")
    }
  }
}

enum AutomationLinearScheduleMode: String, CaseIterable, Identifiable, Equatable {
  case manual
  case daily
  case weekly
  case once
  case interval

  var id: Self { self }

  var title: String {
    switch self {
    case .manual:
      return String(localized: "Manual only", table: "Automation")
    case .daily:
      return String(localized: "Every day", table: "Automation")
    case .weekly:
      return String(localized: "Every week", table: "Automation")
    case .once:
      return String(localized: "Once", table: "Common")
    case .interval:
      return String(localized: "Interval", table: "Automation")
    }
  }
}

enum AutomationLinearSequenceSaveIntent: Equatable {
  case save
  case saveAndTest
  case advancedEdit

  var opensWorkflow: Bool { self == .advancedEdit }
  var runsAfterSaving: Bool { self == .saveAndTest }
}

enum AutomationLinearSequenceMoveDirection: Equatable {
  case earlier
  case later
}

struct AutomationLinearSequenceStep: Identifiable, Equatable {
  var id: UUID
  var macroID: UUID
  var macroName: String
  var duration: TimeInterval
  var continuation: AutomationLinearContinuation
  var delaySeconds: TimeInterval
  var screenText: String
  var conditionTimeout: TimeInterval
  var ocrMatchMode: TextMatchMode
  var ocrSearchRegion: RectValue?
  var ocrSearchRegionSpace: AutomationOCRSearchRegionSpace
  var ocrRequireVisible: Bool

  init(
    id: UUID = UUID(),
    macro: SavedMacro,
    continuation: AutomationLinearContinuation = .immediate,
    delaySeconds: TimeInterval = 2,
    screenText: String = "",
    conditionTimeout: TimeInterval = 30,
    ocrMatchMode: TextMatchMode = .contains,
    ocrSearchRegion: RectValue? = nil,
    ocrSearchRegionSpace: AutomationOCRSearchRegionSpace = .automatic,
    ocrRequireVisible: Bool = true
  ) {
    self.id = id
    self.macroID = macro.id
    self.macroName = macro.name
    self.duration = macro.duration
    self.continuation = continuation
    self.delaySeconds = delaySeconds
    self.screenText = screenText
    self.conditionTimeout = conditionTimeout
    self.ocrMatchMode = ocrMatchMode
    self.ocrSearchRegion = ocrSearchRegion
    self.ocrSearchRegionSpace = ocrSearchRegionSpace
    self.ocrRequireVisible = ocrRequireVisible
  }

  var ocrCondition: AutomationOCRCondition {
    AutomationOCRCondition(
      text: screenText,
      matchMode: ocrMatchMode,
      searchRegion: ocrSearchRegion,
      searchRegionSpace: ocrSearchRegionSpace,
      requireVisible: ocrRequireVisible
    )
  }

  mutating func apply(_ condition: AutomationOCRCondition) {
    screenText = condition.text
    ocrMatchMode = condition.matchMode
    ocrSearchRegion = condition.searchRegion
    ocrSearchRegionSpace = condition.searchRegionSpace
    ocrRequireVisible = condition.requireVisible
  }
}

struct AutomationLinearSequenceDraft: Equatable {
  var name: String
  var steps: [AutomationLinearSequenceStep]
  var targetApplicationReadyDelay: TimeInterval
  var scheduleMode: AutomationLinearScheduleMode
  var startAt: Date
  var repeatEvery: Int
  var repeatUnit: AutomationTimelineRepeatUnit
  var weeklyWeekday: Int

  init(
    name: String,
    macros: [SavedMacro],
    targetApplicationReadyDelay: TimeInterval = 2,
    scheduleMode: AutomationLinearScheduleMode = .daily,
    startAt: Date,
    repeatEvery: Int = 1,
    repeatUnit: AutomationTimelineRepeatUnit = .days,
    weeklyWeekday: Int? = nil
  ) {
    self.name = name
    self.steps = macros.map { AutomationLinearSequenceStep(macro: $0) }
    self.targetApplicationReadyDelay = min(60, max(0, targetApplicationReadyDelay))
    self.scheduleMode = scheduleMode
    self.startAt = startAt
    self.repeatEvery = repeatEvery
    self.repeatUnit = repeatUnit
    self.weeklyWeekday = weeklyWeekday ?? Calendar.current.component(.weekday, from: startAt)
  }

  init?(workflow: AutomationWorkflow, macros: [SavedMacro]) {
    guard AutomationCatalogProjection.tier(for: workflow) == .linearSequence else { return nil }
    let macroByID = Dictionary(uniqueKeysWithValues: macros.map { ($0.id, $0) })
    let dependencies = workflow.dependencies.filter(\.isEnabled)
    let incomingTaskIDs = Set(dependencies.map(\.toTaskID))
    guard let entryTask = workflow.tasks.first(where: { !incomingTaskIDs.contains($0.id) }) else {
      return nil
    }
    let taskByID = Dictionary(uniqueKeysWithValues: workflow.tasks.map { ($0.id, $0) })
    let outgoingByTaskID = Dictionary(grouping: dependencies, by: \.fromTaskID)
    let scheduleDraft = AutomationQuickScheduleDraft(
      workflowName: workflow.name,
      task: entryTask
    )
    let scheduleMode: AutomationLinearScheduleMode
    switch entryTask.schedule {
    case .manual, nil:
      scheduleMode = .manual
    case .once, .repeating:
      scheduleMode = Self.linearScheduleMode(scheduleDraft.mode)
    }

    self.init(
      name: workflow.name,
      macros: [],
      targetApplicationReadyDelay: entryTask.targetApplicationReadyDelay,
      scheduleMode: scheduleMode,
      startAt: scheduleDraft.startAt,
      repeatEvery: scheduleDraft.repeatEvery,
      repeatUnit: scheduleDraft.repeatUnit,
      weeklyWeekday: scheduleDraft.weeklyWeekday
    )

    var cursorID: UUID? = entryTask.id
    var visited: Set<UUID> = []
    while let currentID = cursorID {
      guard visited.insert(currentID).inserted,
        let task = taskByID[currentID],
        case .macro(let macroID) = task.kind,
        let macro = macroByID[macroID]
      else {
        return nil
      }
      var step = AutomationLinearSequenceStep(macro: macro)
      guard let dependency = outgoingByTaskID[currentID]?.first else {
        steps.append(step)
        cursorID = nil
        continue
      }
      guard let nextTask = taskByID[dependency.toTaskID] else { return nil }

      switch nextTask.kind {
      case .macro:
        if dependency.delay > 0 {
          step.continuation = .delay
          step.delaySeconds = dependency.delay
        }
        cursorID = nextTask.id
      case .delay(let duration):
        guard let nextDependency = outgoingByTaskID[nextTask.id]?.first else { return nil }
        step.continuation = .delay
        step.delaySeconds = duration + dependency.delay + nextDependency.delay
        visited.insert(nextTask.id)
        cursorID = nextDependency.toTaskID
      case .condition(let condition):
        guard case .ocrText(let ocr) = condition.kind,
          let nextDependency = outgoingByTaskID[nextTask.id]?.first
        else {
          return nil
        }
        step.continuation = .screenText
        step.conditionTimeout = nextTask.timeout ?? condition.timeout ?? 30
        step.apply(ocr)
        visited.insert(nextTask.id)
        cursorID = nextDependency.toTaskID
      case .notification:
        return nil
      }
      steps.append(step)
    }

    guard steps.count >= 2 else { return nil }
  }

  private static func linearScheduleMode(
    _ mode: AutomationQuickScheduleMode
  ) -> AutomationLinearScheduleMode {
    switch mode {
    case .daily: .daily
    case .weekly: .weekly
    case .once: .once
    case .custom: .interval
    }
  }

  var normalizedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  mutating func add(_ macro: SavedMacro) {
    steps.append(AutomationLinearSequenceStep(macro: macro))
  }

  mutating func addPreparationMacro(_ macro: SavedMacro) {
    steps.insert(AutomationLinearSequenceStep(macro: macro), at: 0)
  }

  mutating func removeStep(id: UUID) {
    steps.removeAll { $0.id == id }
  }

  mutating func moveStep(id: UUID, direction: AutomationLinearSequenceMoveDirection) {
    guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
    let destination = direction == .earlier ? index - 1 : index + 1
    guard steps.indices.contains(destination) else { return }
    steps.swapAt(index, destination)
  }

  func validationMessage(onOrAfter referenceDate: Date = Date()) -> String? {
    if normalizedName.isEmpty {
      return String(localized: "Give the sequence a name.", table: "Automation")
    }
    if steps.isEmpty {
      return String(localized: "Add at least one macro.", table: "Automation")
    }
    if scheduleMode == .once, startAt <= referenceDate {
      return String(localized: "Choose a future time for a one-time run.", table: "Automation")
    }
    if scheduleMode == .interval, repeatEvery < 1 {
      return String(localized: "The interval must be at least 1.", table: "Automation")
    }
    for step in steps.dropLast() {
      if step.continuation == .delay, step.delaySeconds <= 0 {
        return String(localized: "Wait durations must be greater than zero.", table: "Automation")
      }
      if step.continuation == .screenText {
        if step.screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return String(localized: "Enter the screen text to wait for.", table: "Automation")
        }
        if step.conditionTimeout <= 0 {
          return String(
            localized: "Text wait timeouts must be greater than zero.", table: "Automation")
        }
      }
    }
    return nil
  }

  func resolvedSchedule(onOrAfter referenceDate: Date) -> AutomationSchedule {
    guard scheduleMode != .manual else { return .manual }
    let quickMode: AutomationQuickScheduleMode
    switch scheduleMode {
    case .manual:
      return .manual
    case .daily:
      quickMode = .daily
    case .weekly:
      quickMode = .weekly
    case .once:
      quickMode = .once
    case .interval:
      quickMode = .custom
    }
    return AutomationQuickScheduleDraft(
      workflowName: normalizedName,
      mode: quickMode,
      startAt: startAt,
      repeatEvery: repeatEvery,
      repeatUnit: repeatUnit,
      weeklyWeekday: weeklyWeekday
    ).resolvedSchedule(onOrAfter: referenceDate)
  }

  func nextRun(onOrAfter referenceDate: Date = Date()) -> Date? {
    resolvedSchedule(onOrAfter: referenceDate)
      .nextOccurrence(onOrAfter: referenceDate)?
      .scheduledAt
  }

  func makeDocument(onOrAfter referenceDate: Date = Date()) -> AutomationWorkflowDraftDocument {
    var tasks: [AutomationWorkflowDraftTask] = []
    var dependencies: [AutomationWorkflowDraftDependency] = []
    var regions: [AutomationWorkflowDraftVisualRegion] = []
    let schedule = draftSchedule(onOrAfter: referenceDate)

    for (index, step) in steps.enumerated() {
      let macroKey = "macro_\(index + 1)"
      tasks.append(
        AutomationWorkflowDraftTask(
          key: macroKey,
          type: "macro",
          name: step.macroName,
          macroRef: AutomationWorkflowDraftMacroRef(id: step.macroID, name: step.macroName),
          schedule: index == 0 ? schedule : nil,
          resource: .foregroundInput,
          targetApplicationPolicy: AutomationTargetApplicationPolicy.launchIfNeeded.rawValue,
          targetApplicationReadyDelay: index == 0 ? targetApplicationReadyDelay : nil,
          targetApplicationCleanupPolicy: AutomationTargetApplicationCleanupPolicy.keepOpen
            .rawValue,
          playbackLoops: 1,
          missedRunPolicy: AutomationMissedRunPolicy.latestOnly.rawValue,
          graphPosition: AutomationGraphPoint(x: Double(index * 260), y: 0)
        ))

      guard index < steps.count - 1 else { continue }
      let nextMacroKey = "macro_\(index + 2)"
      switch step.continuation {
      case .immediate:
        dependencies.append(
          AutomationWorkflowDraftDependency(
            from: macroKey,
            to: nextMacroKey,
            trigger: "success"
          ))
      case .delay:
        dependencies.append(
          AutomationWorkflowDraftDependency(
            from: macroKey,
            to: nextMacroKey,
            trigger: "success",
            delaySeconds: max(0, step.delaySeconds)
          ))
      case .screenText:
        let conditionKey = "gate_\(index + 1)"
        let regionKey: String?
        if let region = step.ocrSearchRegion {
          let key = "gate_\(index + 1)_region"
          regions.append(
            AutomationWorkflowDraftVisualRegion(
              key: key,
              label: step.screenText,
              bounds: region,
              space: step.ocrSearchRegionSpace
            ))
          regionKey = key
        } else {
          regionKey = nil
        }
        tasks.append(
          AutomationWorkflowDraftTask(
            key: conditionKey,
            type: "condition",
            name: String(localized: "Wait for screen text", table: "Automation"),
            condition: AutomationWorkflowDraftCondition(
              type: "ocrText",
              text: step.screenText.trimmingCharacters(in: .whitespacesAndNewlines),
              matchMode: step.ocrMatchMode,
              regionRef: regionKey,
              requireVisible: step.ocrRequireVisible
            ),
            resource: .screenCapture,
            timeoutSeconds: max(0, step.conditionTimeout),
            pollingSeconds: 0.5,
            graphPosition: AutomationGraphPoint(x: Double(index * 260 + 130), y: 90)
          ))
        dependencies.append(
          AutomationWorkflowDraftDependency(
            from: macroKey,
            to: conditionKey,
            trigger: "success"
          ))
        dependencies.append(
          AutomationWorkflowDraftDependency(
            from: conditionKey,
            to: nextMacroKey,
            trigger: "conditionMatched"
          ))
      }
    }

    return AutomationWorkflowDraftDocument(
      workflow: AutomationWorkflowDraft(
        name: normalizedName,
        tasks: tasks,
        dependencies: dependencies
      ),
      visualAssets: regions.isEmpty ? nil : AutomationWorkflowDraftVisualAssets(regions: regions)
    )
  }

  private func draftSchedule(onOrAfter referenceDate: Date) -> AutomationWorkflowDraftSchedule {
    switch resolvedSchedule(onOrAfter: referenceDate) {
    case .manual:
      return AutomationWorkflowDraftSchedule(type: "manual")
    case .once(let date):
      return AutomationWorkflowDraftSchedule(type: "once", startAt: date)
    case .repeating(let rule):
      let values: (Int, String)
      switch rule.interval {
      case .minutes(let count): values = (count, "minutes")
      case .hours(let count): values = (count, "hours")
      case .days(let count): values = (count, "days")
      case .weeks(let count): values = (count, "weeks")
      }
      return AutomationWorkflowDraftSchedule(
        type: "repeating",
        startAt: rule.anchor,
        every: values.0,
        unit: values.1,
        timeZone: rule.timeZoneIdentifier
      )
    }
  }
}

struct AutomationSequentialBuilderSheet: View {
  @Environment(\.dismiss) private var dismiss

  let availableMacros: [SavedMacro]
  let onCreate: @MainActor (AutomationWorkflowDraftDocument, Bool, Bool) async throws -> Void

  @State private var draft: AutomationLinearSequenceDraft
  @State private var isPreviewActive = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    initialMacros: [SavedMacro],
    availableMacros: [SavedMacro],
    initialDraft: AutomationLinearSequenceDraft? = nil,
    onCreate: @escaping @MainActor (AutomationWorkflowDraftDocument, Bool, Bool) async throws -> Void
  ) {
    let firstName =
      initialMacros.first?.name ?? String(localized: "New sequence", table: "Automation")
    _draft = State(
      initialValue: initialDraft
        ?? AutomationLinearSequenceDraft(
          name: String(format: String(localized: "%@ sequence", table: "Automation"), firstName),
          macros: initialMacros,
          startAt: Date().addingTimeInterval(3_600)
        ))
    self.availableMacros = availableMacros
    self.onCreate = onCreate
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))

      Divider().opacity(0.35)

      ScrollView {
        VStack(spacing: 18) {
          readinessSection
          sequenceSection
          scheduleSection
          summarySection
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
      }
      .background(Color.primary.opacity(0.015))

      Divider().opacity(0.35)

      footer
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(width: 880, height: 700)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(Brand.libraryBlue)
        .frame(width: 28, height: 28)

      Text("Quick sequence", tableName: "Automation")
        .font(.headline)

      TextField(String(localized: "Sequence name", table: "Automation"), text: $draft.name)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)

      Spacer(minLength: 12)

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .help(String(localized: "Cancel", table: "Common"))
    }
  }

  private var readinessSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(
          String(localized: "Start preparation", table: "Automation"),
          systemImage: "macwindow.badge.plus"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        Spacer()
      }

      HStack(spacing: 16) {
        HStack(spacing: 8) {
          Text(String(localized: "Wait after window appears", table: "Automation"))
            .font(.callout)
            .foregroundStyle(.secondary)

          Picker("", selection: $draft.targetApplicationReadyDelay) {
            Text(String(localized: "No wait", table: "Automation")).tag(TimeInterval(0))
            Text("2s").tag(TimeInterval(2))
            Text("5s").tag(TimeInterval(5))
            Text("10s").tag(TimeInterval(10))
            Text("20s").tag(TimeInterval(20))
          }
          .labelsHidden()
          .frame(width: 100)
        }

        Spacer(minLength: 12)

        Menu {
          ForEach(availableMacros) { macro in
            Button(macro.name) {
              draft.addPreparationMacro(macro)
            }
          }
        } label: {
          Label(
            String(localized: "Add login or navigation macro", table: "Automation"),
            systemImage: "person.badge.key"
          )
          .font(.callout)
        }
        .menuStyle(.borderlessButton)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )
    }
  }

  private var sequenceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(
          String(localized: "Steps", table: "Automation"),
          systemImage: "square.stack.3d.up"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

        Text("\(draft.steps.count)")
          .font(.caption2.weight(.bold).monospacedDigit())
          .padding(.horizontal, 6)
          .padding(.vertical, 1.5)
          .background(Capsule().fill(Brand.libraryBlue.opacity(0.12)))
          .foregroundStyle(Brand.libraryBlue)

        Spacer()

        Menu {
          ForEach(availableMacros) { macro in
            Button(macro.name) {
              draft.add(macro)
            }
          }
        } label: {
          Label(String(localized: "Add macro", table: "Automation"), systemImage: "plus.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(Brand.libraryBlue)
        }
        .menuStyle(.borderlessButton)
      }

      VStack(spacing: 0) {
        ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
          stepCard(step: step, index: index)

          if index < draft.steps.count - 1 {
            stepConnector(index: index)
          }
        }
      }
    }
  }

  private func stepCard(step: AutomationLinearSequenceStep, index: Int) -> some View {
    let isLast = index == draft.steps.count - 1
    return HStack(spacing: 12) {
      Text("\(index + 1)")
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(Brand.libraryBlue)
        .frame(width: 22, height: 22)
        .background(Circle().fill(Brand.libraryBlue.opacity(0.12)))

      Image(systemName: "play.rectangle.fill")
        .font(.system(size: 14))
        .foregroundStyle(Brand.libraryBlue)

      VStack(alignment: .leading, spacing: 2) {
        Text(step.macroName)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Text(durationText(step.duration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 16)

      HStack(spacing: 2) {
        stepButton(
          "arrow.up", help: String(localized: "Move earlier", table: "Automation"),
          disabled: index == 0
        ) {
          draft.moveStep(id: step.id, direction: .earlier)
        }
        stepButton(
          "arrow.down", help: String(localized: "Move later", table: "Automation"),
          disabled: isLast
        ) {
          draft.moveStep(id: step.id, direction: .later)
        }
        stepButton(
          "trash", help: String(localized: "Remove step", table: "Automation"),
          role: .destructive
        ) {
          draft.removeStep(id: step.id)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
  }

  private func stepConnector(index: Int) -> some View {
    let step = draft.steps[index]
    return VStack(spacing: 2) {
      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(width: 1.5, height: 7)

      HStack(spacing: 6) {
        Menu {
          ForEach(AutomationLinearContinuation.allCases) { continuation in
            Button(continuation.title) {
              draft.steps[index].continuation = continuation
            }
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: connectorIcon(for: step.continuation))
              .font(.system(size: 9.5, weight: .semibold))
            Text(connectorSummary(for: step))
              .font(.system(size: 11, weight: .medium))
            Image(systemName: "chevron.up.chevron.down")
              .font(.system(size: 8))
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 9)
          .padding(.vertical, 3.5)
          .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
          .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }

      if step.continuation == .delay {
        HStack(spacing: 6) {
          Text(String(localized: "Wait", table: "Automation") + ":")
            .font(.caption2)
            .foregroundStyle(.secondary)
          TextField(
            "", value: $draft.steps[index].delaySeconds,
            format: .number.precision(.fractionLength(0...1))
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 58)
          .controlSize(.small)
          Text(String(localized: "seconds", table: "Common"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
      } else if step.continuation == .screenText {
        ocrInlineConfig(index: index)
      }

      VStack(spacing: -3) {
        Rectangle()
          .fill(Color.primary.opacity(0.12))
          .frame(width: 1.5, height: 7)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(Color.primary.opacity(0.28))
      }
    }
    .padding(.vertical, 1)
  }

  private func connectorIcon(for continuation: AutomationLinearContinuation) -> String {
    switch continuation {
    case .immediate: return "arrow.down"
    case .delay: return "timer"
    case .screenText: return "text.viewfinder"
    }
  }

  private func connectorSummary(for step: AutomationLinearSequenceStep) -> String {
    switch step.continuation {
    case .immediate:
      return String(localized: "Continue immediately", table: "Automation")
    case .delay:
      return String(
        format: String(localized: "Wait %.1fs", table: "Automation"),
        step.delaySeconds
      )
    case .screenText:
      let trimmed = step.screenText.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? String(localized: "Wait for screen text", table: "Automation")
        : String(format: String(localized: "Wait for “%@”", table: "Automation"), trimmed)
    }
  }

  @ViewBuilder
  private func ocrInlineConfig(index: Int) -> some View {
    let stepID = draft.steps[index].id
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        TextField(
          String(localized: "Text to find", table: "Automation"),
          text: $draft.steps[index].screenText
        )
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)

        Button {
          pickOCRText(stepID: stepID)
        } label: {
          Label(
            String(localized: "Pick from screen", table: "Automation"),
            systemImage: "text.viewfinder"
          )
          .font(.caption2)
        }
        .controlSize(.small)

        Button {
          drawOCRRegion(stepID: stepID)
        } label: {
          Label(
            String(localized: "Draw area", table: "Automation"),
            systemImage: "viewfinder.rectangular"
          )
          .font(.caption2)
        }
        .controlSize(.small)
      }

      HStack(spacing: 10) {
        Picker(
          "",
          selection: $draft.steps[index].ocrMatchMode
        ) {
          Text(String(localized: "Contains", table: "Common")).tag(TextMatchMode.contains)
          Text(String(localized: "Exact", table: "Common")).tag(TextMatchMode.exact)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 130)
        .controlSize(.small)

        if draft.steps[index].ocrSearchRegion != nil {
          Label(
            draft.steps[index].ocrSearchRegionSpace.titleForVisualCondition,
            systemImage: "rectangle.dashed"
          )
          .font(.caption2)
          .foregroundStyle(Brand.libraryGreen)

          Button {
            clearOCRRegion(stepID: stepID)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.caption2)
          }
          .buttonStyle(.plain)
          .help(String(localized: "Clear OCR area", table: "Automation"))
        } else {
          Label(
            String(localized: "Entire target screen", table: "Automation"),
            systemImage: "display"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }

        Spacer(minLength: 6)

        Text(String(localized: "Timeout", table: "Common") + ":")
          .font(.caption2)
          .foregroundStyle(.secondary)

        Picker("", selection: $draft.steps[index].conditionTimeout) {
          Text("10s").tag(TimeInterval(10))
          Text("30s").tag(TimeInterval(30))
          Text("60s").tag(TimeInterval(60))
          Text("120s").tag(TimeInterval(120))
        }
        .labelsHidden()
        .frame(width: 75)
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
    )
  }

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        String(localized: "Timing", table: "Automation"),
        systemImage: "calendar.badge.clock"
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.secondary)

      VStack(spacing: 10) {
        HStack(spacing: 12) {
          Text(String(localized: "Run", table: "Common"))
            .font(.callout)
            .foregroundStyle(.secondary)

          Picker("", selection: $draft.scheduleMode) {
            ForEach(AutomationLinearScheduleMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .frame(width: 140)

          switch draft.scheduleMode {
          case .manual:
            Text(String(localized: "Manual only", table: "Automation"))
              .font(.callout)
              .foregroundStyle(.secondary)
          case .daily:
            DatePicker(
              String(localized: "At", table: "Common"),
              selection: $draft.startAt,
              displayedComponents: [.hourAndMinute]
            )
          case .weekly:
            Picker(String(localized: "Day", table: "Common"), selection: $draft.weeklyWeekday) {
              ForEach(1...7, id: \.self) { weekday in
                Text(weekdayTitle(weekday)).tag(weekday)
              }
            }
            .frame(width: 120)
            DatePicker(
              String(localized: "At", table: "Common"),
              selection: $draft.startAt,
              displayedComponents: [.hourAndMinute]
            )
          case .once:
            DatePicker(
              String(localized: "Start", table: "Common"),
              selection: $draft.startAt,
              displayedComponents: [.date, .hourAndMinute]
            )
          case .interval:
            DatePicker(
              String(localized: "Start", table: "Common"),
              selection: $draft.startAt,
              displayedComponents: [.date, .hourAndMinute]
            )
            HStack(spacing: 6) {
              Text(String(localized: "Every", table: "Common"))
              TextField("", value: $draft.repeatEvery, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
              Picker("", selection: $draft.repeatUnit) {
                ForEach(AutomationTimelineRepeatUnit.allCases) { unit in
                  Text(unit.title).tag(unit)
                }
              }
              .labelsHidden()
              .frame(width: 90)
            }
          }
          Spacer(minLength: 0)
        }

        Divider().opacity(0.35)

        HStack(spacing: 12) {
          HStack(spacing: 6) {
            Image(systemName: "calendar")
              .foregroundStyle(.secondary)
            Text(String(localized: "Next run", table: "Automation") + ":")
              .foregroundStyle(.secondary)
            if let nextRun = draft.nextRun() {
              Text(nextRun, format: .dateTime.month(.abbreviated).day().weekday().hour().minute())
                .monospacedDigit()
                .fontWeight(.medium)
            } else {
              Text(String(localized: "Manual only", table: "Automation"))
            }
          }
          .font(.caption)

          Spacer(minLength: 16)

          Label(
            String(localized: "Each macro once", table: "Automation"),
            systemImage: "play.square.stack"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )
    }
  }

  private var summarySection: some View {
    HStack(spacing: 8) {
      Image(
        systemName: validationMessage == nil
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(validationMessage == nil ? Brand.libraryGreen : Color.red)

      if let validationMessage {
        Text(validationMessage)
          .foregroundStyle(.red)
          .lineLimit(2)
      } else {
        Text(
          String(
            format: String(localized: "%d macros · %@", table: "Automation"),
            draft.steps.count,
            estimatedDurationText
          )
        )
        .fontWeight(.medium)
        .foregroundStyle(.secondary)

        Spacer(minLength: 0)

        Text("Applications remain open after the sequence", tableName: "Automation")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .font(.caption)
    .padding(.horizontal, 2)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Button(String(localized: "Cancel", table: "Common")) { dismiss() }
        .keyboardShortcut(.cancelAction)
        .disabled(isSaving)

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Spacer(minLength: 0)
      }

      Button(String(localized: "Advanced edit…", table: "Automation")) {
        create(intent: .advancedEdit)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .font(.callout)
      .disabled(validationMessage != nil || isPreviewActive || isSaving)

      AutomationLinearSequencePreviewButton(
        isDisabled: validationMessage != nil || isSaving,
        onActivityChange: { isPreviewActive = $0 },
        onRun: { create(intent: .saveAndTest) }
      )
      .buttonStyle(.bordered)

      Button {
        create(intent: .save)
      } label: {
        if isSaving {
          ProgressView().controlSize(.small)
        } else {
          Text("Save sequence", tableName: "Automation")
        }
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
      .disabled(validationMessage != nil || isPreviewActive || isSaving)
    }
  }

  private var validationMessage: String? {
    draft.validationMessage()
  }

  private var estimatedDurationText: String {
    let macroDuration = draft.steps.reduce(0) { $0 + $1.duration }
    let delays = draft.steps.dropLast().reduce(0) { partial, step in
      partial + (step.continuation == .delay ? max(0, step.delaySeconds) : 0)
    }
    let total = max(0, Int((macroDuration + delays).rounded()))
    if total >= 3_600 {
      return "\(total / 3_600)h \((total % 3_600) / 60)m"
    }
    return "\(total / 60)m \(total % 60)s"
  }

  private func sectionHeader(title: String, value: String?) -> some View {
    HStack {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      if let value {
        Text(value)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 38)
    .background(Color.primary.opacity(0.018))
  }

  private func stepButton(
    _ systemImage: String,
    help: String,
    disabled: Bool = false,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Image(systemName: systemImage)
        .frame(width: 24, height: 22)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .help(help)
    .accessibilityLabel(help)
  }

  private func pickOCRText(stepID: UUID) {
    guard let index = draft.steps.firstIndex(where: { $0.id == stepID }) else { return }
    let currentCondition = draft.steps[index].ocrCondition
    let targetSurface =
      availableMacros
      .first(where: { $0.id == draft.steps[index].macroID })?
      .surfaces.values.first
    AutomationOCRRegionPicker.pick(
      currentCondition: currentCondition,
      targetSurface: targetSurface,
      onFailure: { message in errorMessage = message }
    ) { condition in
      guard let refreshedIndex = draft.steps.firstIndex(where: { $0.id == stepID }) else { return }
      draft.steps[refreshedIndex].apply(condition)
    }
  }

  private func drawOCRRegion(stepID: UUID) {
    guard let index = draft.steps.firstIndex(where: { $0.id == stepID }) else { return }
    let currentCondition = draft.steps[index].ocrCondition
    AutomationOCRRegionPicker.pickArea(
      currentCondition: currentCondition,
      searchRegionSpace: currentCondition.searchRegionSpace
    ) { condition in
      guard let refreshedIndex = draft.steps.firstIndex(where: { $0.id == stepID }) else { return }
      draft.steps[refreshedIndex].apply(condition)
    }
  }

  private func clearOCRRegion(stepID: UUID) {
    guard let index = draft.steps.firstIndex(where: { $0.id == stepID }) else { return }
    draft.steps[index].ocrSearchRegion = nil
    draft.steps[index].ocrSearchRegionSpace = .automatic
  }

  private func create(intent: AutomationLinearSequenceSaveIntent) {
    guard validationMessage == nil, !isSaving else { return }
    let document = draft.makeDocument()
    isSaving = true
    errorMessage = nil
    Task { @MainActor in
      do {
        try await onCreate(document, intent.opensWorkflow, intent.runsAfterSaving)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }

  private func durationText(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private func weekdayTitle(_ weekday: Int) -> String {
    let symbols = Calendar.current.weekdaySymbols
    return symbols[min(7, max(1, weekday)) - 1]
  }
}

private struct AutomationLinearSequencePreviewButton: View {
  let isDisabled: Bool
  let onActivityChange: (Bool) -> Void
  let onRun: () -> Void

  @State private var countdown: Int?
  @State private var task: Task<Void, Never>?

  var body: some View {
    Button {
      countdown == nil ? start() : cancel()
    } label: {
      Label(title, systemImage: countdown == nil ? "play.fill" : "xmark")
    }
    .disabled(isDisabled)
    .onDisappear(perform: cancel)
  }

  private var title: String {
    guard let countdown else {
      return String(localized: "Save & test in 5 seconds", table: "Automation")
    }
    return countdown > 0
      ? String(format: String(localized: "Cancel test (%d)", table: "Automation"), countdown)
      : String(localized: "Starting test…", table: "Automation")
  }

  private func start() {
    task?.cancel()
    onActivityChange(true)
    task = Task { @MainActor in
      for remaining in stride(from: 5, through: 1, by: -1) {
        guard !Task.isCancelled else { return }
        countdown = remaining
        try? await Task.sleep(for: .seconds(1))
      }
      guard !Task.isCancelled else { return }
      countdown = 0
      onRun()
      task = nil
      countdown = nil
      onActivityChange(false)
    }
  }

  private func cancel() {
    let wasActive = task != nil || countdown != nil
    task?.cancel()
    task = nil
    countdown = nil
    if wasActive { onActivityChange(false) }
  }
}
