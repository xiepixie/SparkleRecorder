import Cocoa
import SwiftUI
import SparkleRecorderCore

struct EditorSidebar: View {
    @Binding var selection: Set<UUID>
    let rows: [ActionRow]
    @Binding var stretchFactor: Double
    @Binding var shiftMs: Double
    @Binding var inspTime: String
    @Binding var inspX: String
    @Binding var inspY: String
    @Binding var inspEndX: String
    @Binding var inspEndY: String
    @Binding var inspKey: String
    @Binding var inspFlags: UInt64
    @Binding var inspStrategy: CoordinateStrategy
    @Binding var inspOCRText: String
    @Binding var inspFallbackPolicy: LocatorFallbackPolicy
    @Binding var inspTimeout: Double
    @Binding var inspVerifyMustExist: Bool
    @Binding var inspBehaviorName: String
    let recorder: Recorder
    let surfaces: [String: PlaybackSurface]
    let onLoadInspector: () -> Void
    let onUpdatePreview: () -> Void
    let onPickCoordinate: (Bool) -> Void
    let onAddClickPoint: () -> Void
    let onPickText: () -> Void
    let onRefreshRows: () -> [ActionRow]
    let onCreateRepeatUntilDraft: (Int, TimeInterval, TimeInterval, String) -> Void

    @State private var insertWaitMs: Double = 1000
    @State private var confirmClearAll = false
    @State private var loopMaxAttempts: Int = 10
    @State private var loopTimeoutSeconds: Double = 30.0
    @State private var loopPollingSeconds: Double = 1.0
    @State private var loopFailurePolicy: String = "failRun"
    @Environment(\.undoManager) private var undoManager

    enum SidebarTab: String, CaseIterable, Identifiable {
        case inspector = "Inspector"
        case orchestrate = "Orchestrate"
        case insert = "Insert"
        var id: String { rawValue }
    }
    @State private var currentTab: SidebarTab = .inspector

    struct ActionInsertionPlacement {
        var eventIndex: Int
        var explicitStartTime: TimeInterval?
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $currentTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Text(NSLocalizedString(tab.rawValue, comment: "")).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch currentTab {
                    case .inspector:
                        inspectorTabContent()
                    case .orchestrate:
                        orchestrateTabContent()
                    case .insert:
                        insertTabContent()
                    }
                }
                .padding(14)
            }
        }
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
    }

    @ViewBuilder
    func inspectorTabContent() -> some View {
        Group {
            if selection.count == 1 {
                section(String(localized: "Selected action", table: "EditorUX"), icon: "slider.horizontal.3") {
                    selectedActionInspector()
                }
            } else if selection.count > 1 {
                section(String(localized: "Batch edit", table: "Common"), icon: "slider.horizontal.3") {
                    batchEditInspector()
                }
            }
            
            editorReviewSection()
        }
    }

    @ViewBuilder
    func orchestrateTabContent() -> some View {
        if selection.isEmpty {
            section(String(localized: "Global actions", table: "EditorUX"), icon: "globe") {
                clearAllButton()
            }
        } else {
            section(String(localized: "Selection", table: "Common"), icon: "checklist") {
                selectionActionsContent()
            }
            
            if selectedBehaviorGroup() != nil || selection.count > 1 {
                behaviorSection()
            }
            
            repeatUntilSection()
            
            section(String(localized: "Time Adjustments", table: "Common"), icon: "timer") {
                timeAdjustmentsContent()
            }
        }
    }

    @ViewBuilder
    func insertTabContent() -> some View {
        section(String(localized: "Insert action", table: "EditorUX"), icon: "plus.square") {
            insertActionContent()
        }
        
        let behaviors = boundBehaviors
        if !behaviors.isEmpty {
            section(String(localized: "Reusable Behaviors", table: "Common"), icon: "rectangle.stack") {
                VStack(spacing: 6) {
                    ForEach(behaviors, id: \.id) { behavior in
                        Button {
                            insertBehaviorCopy(behavior)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.stack.3d.down.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Brand.sigAmber)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(behavior.behaviorGroupName ?? String(localized: "Behavior", table: "Common"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(String(format: String(localized: "%d actions", table: "EditorUX"), behavior.containedActionCount ?? 1))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    func selectedActionInspector() -> some View {
        if let id = selection.first, let row = rows.first(where: { $0.id == id }) {
            let grp = row.group
            let firstEvent = firstEvent(for: grp)
            	                        HStack {
                                        Image(systemName: actionKindIcon(grp.kind))
                                            .foregroundStyle(actionKindColor(grp.kind))
                                            .font(.system(size: 12))
                                        VStack(alignment: .leading, spacing: 0) {
                                            let actionNumber = (rows.firstIndex(where: { $0.id == id }) ?? 0) + 1
                                            Text(String(format: String(localized: "Action #%d", table: "EditorUX"), actionNumber))
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(humanActionKindName(grp.kind))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
            	                            }
            	                        }
                                        workflowHint(for: grp, event: firstEvent)
                                        let inspectorWarning = actionInspectorInputWarning(
                                            for: grp,
                                            timeText: inspTime,
                                            xText: inspX,
                                            yText: inspY,
                                            endXText: inspEndX,
                                            endYText: inspEndY,
                                            keyText: inspKey,
                                            strategy: inspStrategy,
                                            timeout: inspTimeout
                                        )

            		                        inspectorGrid {
            			                            labeledField(grp.kind.isPassiveWait ? String(localized: "Wait Duration (s)", table: "EditorUX") : String(localized: "Time (s)", table: "Common"), text: $inspTime)

            		                            if grp.kind == .waitForText || grp.kind == .waitForTextGone {
            		                                labeledDoubleField(String(localized: "Timeout (s)", table: "Common"), value: $inspTimeout)
            		                            }

            			                            if grp.kind.canUseLocatorStrategy {
            		                                gridField(String(localized: "Strategy", table: "Common")) {
            		                                    Picker("", selection: Binding(
            		                                        get: { inspStrategy },
            		                                        set: { inspStrategy = $0; applyInspector() }
            		                                    )) {
            		                                        Text("Offset", tableName: "Common").tag(CoordinateStrategy.windowLocalPreferred)
            		                                        Text("Proportional", tableName: "Common").tag(CoordinateStrategy.normalizedPreferred)
            		                                        Text("Absolute", tableName: "Common").tag(CoordinateStrategy.absoluteOnly)
            		                                        Text("Text (OCR)", tableName: "EditorUX").tag(CoordinateStrategy.locatorOnly)
            		                                    }
            		                                    .pickerStyle(.segmented)
            		                                    .labelsHidden()
            		                                    .controlSize(.small)
            		                                }

            		                                if inspStrategy == .locatorOnly {
            		                                    labeledDoubleField(String(localized: "Timeout (s)", table: "Common"), value: $inspTimeout)
            		                                    gridField(String(localized: "Target Text", table: "EditorUX")) {
            		                                        TargetTextEditorInnerView(text: Binding(get: { inspOCRText }, set: { inspOCRText = $0; applyInspector() }), onPick: onPickText)
            		                                    }
            		                                    gridField(String(localized: "Fallback", table: "Common")) {
            		                                        locatorPlaybackPolicyView()
            		                                    }
            		                                } else {
            		                                    labeledField("X", text: $inspX)
            		                                    labeledField("Y", text: $inspY)
            		                                }
            			                            } else if grp.kind.editsPathTarget {
            		                                gridField(String(localized: "Start", table: "Common")) { Text("") }
            		                                labeledField("X", text: $inspX)
            		                                labeledField("Y", text: $inspY)
            		                                gridField(String(localized: "End", table: "Common")) { Text("") }
            		                                labeledField("X", text: $inspEndX)
            		                                labeledField("Y", text: $inspEndY)
            		                            }

            			                            if grp.kind.editsKeyboardInput {
            		                                gridField(String(localized: "Key code", table: "Common")) {
            		                                    ShortcutRecorderField(
            		                                        currentBinding: keyboardShortcutBinding(for: grp),
            		                                        allHotkeys: [],
            		                                        allowsClear: false,
            		                                        recordingPrompt: String(localized: "Press any key…", table: "Common"),
            		                                        emptyPrompt: String(localized: "Click to record shortcut", table: "Recording"),
            		                                        onRecord: applyRecordedShortcut
            		                                    )
            		                                }
            		                                labeledField(String(localized: "Raw Code", table: "Common"), text: $inspKey)
            			                            } else if grp.kind.editsSemanticTextTarget {
            			                                gridField(String(localized: "Target Text", table: "EditorUX")) {
            			                                    TargetTextEditorInnerView(text: Binding(get: { inspOCRText }, set: { inspOCRText = $0; applyInspector() }), onPick: onPickText)
            			                                }
                                            if grp.kind == .waitForText || grp.kind == .waitForTextGone || grp.kind == .verifyText {
            			                                    gridField(String(localized: "Must Exist", table: "Common")) {
            			                                    Toggle("", isOn: Binding(
            			                                        get: { inspVerifyMustExist },
            			                                        set: { inspVerifyMustExist = $0; applyInspector() }
            			                                    ))
            			                                    .labelsHidden()
            			                                    .controlSize(.small)
            			                                    }
            			                                }
            			                            }
            			                        }

                                            if inspectorWarning.isWarning {
                                                HStack(alignment: .top, spacing: 6) {
                                                    Image(systemName: "exclamationmark.triangle")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(Brand.sigAmber)
                                                        .frame(width: 14)
                                                    Text(actionInspectorInputWarningHelp(inspectorWarning))
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                                .padding(.vertical, 2)
                                            }

                                            if grp.kind == .multiPointClick {
                                                multiPointClickEditor(for: grp)
                                            }

                                            if grp.kind.canConvertClickType {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("Action Type", tableName: "EditorUX")
                                                        .font(.system(size: 9.5, weight: .semibold))
                                                        .foregroundStyle(.secondary)
                                                    Picker("", selection: Binding(
                                                        get: { grp.kind },
                                                        set: { convertClickType(grp: grp, newKind: $0) }
                                                    )) {
                                                        Text("Click", tableName: "EditorUX").tag(ActionGroupKind.click)
                                                        Text("Double", tableName: "Common").tag(ActionGroupKind.doubleClick)
                                                        Text("Triple+", tableName: "Common").tag(ActionGroupKind.repeatedClick)
                                                        Text("Long Press", tableName: "Common").tag(ActionGroupKind.longPress)
                                                    }
                                                    .pickerStyle(.segmented)
                                                    .labelsHidden()
                                                    .controlSize(.small)
                                                }
                                            }

                                            if grp.kind.canRetargetCoordinate && inspStrategy != .locatorOnly {
                                                Button(action: { onPickCoordinate(false) }) {
                                                    Label(String(localized: "Retarget Coordinate", table: "Common"), systemImage: "scope")
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }

            		                        if grp.kind.editsSemanticTextTarget || (grp.kind.canUseLocatorStrategy && inspStrategy == .locatorOnly) {
                                                let textReadiness = ActionGroupProjection.textTargetReadiness(for: grp, events: recorder.events)
                                                let anchor = ActionGroupProjection.firstTextAnchor(for: grp, events: recorder.events)
            		                            if textReadiness.isReady, let anchor {
            		                                AnchorPositionCard(anchor: anchor, fallbackPolicy: firstEvent?.locatorFallbackPolicy ?? .fail)
            		                            } else {
            		                                visionEmptyState(readiness: textReadiness)
            		                            }
                                            }

                                            if grp.kind == .waitForText {
                                                let conversionReadiness = textClickConversionReadiness(for: grp)
                                                Button {
                                                    insertClickTextAfterSelectedWait(grp)
                                                } label: {
                                                    Label(String(localized: "Add Click Text", table: "EditorUX"), systemImage: "cursorarrow.click")
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .disabled(!conversionReadiness.canConvert)
                                                .help(textClickFollowUpInsertionReadinessHelp(conversionReadiness))

                                                Button {
                                                    convertWaitToClickText(grp)
                                                } label: {
                                                    Label(String(localized: "Convert to Click Text", table: "EditorUX"), systemImage: "cursorarrow.click")
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .disabled(!conversionReadiness.canConvert)
                                                .help(textClickConversionReadinessHelp(conversionReadiness))

                                                if !conversionReadiness.canConvert {
                                                    Text(textClickFollowUpInsertionReadinessHelp(conversionReadiness))
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }

        }
    }

    @ViewBuilder
    func batchEditInspector() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: String(localized: "Batch edit %d actions", table: "EditorUX"), selection.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.sigBlue)

            let textTargetGroups = selectedTextTargetGroups()
            if !textTargetGroups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shared Text Target", tableName: "EditorUX")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    let textTargetReadiness = batchTextTargetReadiness(for: textTargetGroups, targetText: inspOCRText)
                    TargetTextEditorInnerView(
                        text: Binding(
                            get: { inspOCRText },
                            set: { inspOCRText = $0 }
                        ),
                        onPick: onPickText
                    )
                    HStack(spacing: 6) {
                        labeledInlineDoubleField(String(localized: "Timeout", table: "Common"), value: $inspTimeout)
                        Button(String(localized: "Apply to Selected", table: "Common")) { applyBatchTextTarget() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!textTargetReadiness.canApply)
                            .help(batchTextTargetReadinessHelp(textTargetReadiness))
                    }
                    if !textTargetReadiness.canApply {
                        Text(batchTextTargetReadinessHelp(textTargetReadiness))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Align Coordinates", tableName: "Common")
                     .font(.system(size: 9.5, weight: .semibold))
                     .foregroundStyle(.secondary)
                let alignXReadiness = coordinateAlignmentReadiness(axis: .x)
                let alignYReadiness = coordinateAlignmentReadiness(axis: .y)
                HStack {
                     Button(String(localized: "Align X to First", table: "Common")) { alignSelectedCoordinates(axis: .x) }
                        .disabled(!alignXReadiness.canAlign)
                        .help(batchCoordinateAlignmentReadinessHelp(alignXReadiness))
                     Button(String(localized: "Align Y to First", table: "Common")) { alignSelectedCoordinates(axis: .y) }
                        .disabled(!alignYReadiness.canAlign)
                        .help(batchCoordinateAlignmentReadinessHelp(alignYReadiness))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if !alignXReadiness.canAlign && !alignYReadiness.canAlign {
                    let message = batchCoordinateAlignmentReadinessHelp(alignXReadiness)
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Standardize Timeout", tableName: "Common")
                     .font(.system(size: 9.5, weight: .semibold))
                     .foregroundStyle(.secondary)
                let timeoutReadiness = batchTimeoutReadiness(
                    for: selectedGroups(),
                    events: recorder.events,
                    timeout: inspTimeout
                )
                HStack {
                     TextField("s", text: Binding(
                         get: { String(format: "%.2f", inspTimeout) },
                         set: { if let v = Double($0) { inspTimeout = v } }
                     ))
                     .textFieldStyle(.roundedBorder)
                     .font(.system(.callout, design: .monospaced))
                     .controlSize(.small)
                     .frame(width: 60)

                     Button(String(localized: "Apply to Selected", table: "Common")) { applyBatchTimeout() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!timeoutReadiness.canApply)
                        .help(batchTimeoutReadinessHelp(timeoutReadiness))
                }
                if !timeoutReadiness.canApply {
                    Text(batchTimeoutReadinessHelp(timeoutReadiness))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)

    }

    @ViewBuilder
    func selectionActionsContent() -> some View {
        let selectionGroups = selectedGroups()
        let deletionReadiness = actionSelectionDeletionReadiness(
            for: selectionGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        let duplicationReadiness = actionSelectionDuplicationReadiness(
            for: selectionGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )

        HStack(spacing: 6) {
            Button(action: deleteSelected) {
                Label(String(localized: "Delete", table: "Common"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!deletionReadiness.canDelete)
            .help(actionSelectionDeletionReadinessHelp(deletionReadiness))

            Button(action: duplicateSelected) {
                Label(
                    selectionSnapshot.containsBehavior
                        ? String(localized: "Duplicate Behavior", table: "Common")
                        : String(localized: "Duplicate", table: "Common"),
                    systemImage: "plus.square.on.square"
                )
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!duplicationReadiness.canDuplicate)
            .help(actionSelectionDuplicationReadinessHelp(duplicationReadiness))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        HStack(spacing: 6) {
            let trimBeforeReadiness = actionTrimReadiness(
                for: selectionGroups,
                events: recorder.events,
                liveDuration: recorder.liveDuration,
                direction: .before
            )
            let trimAfterReadiness = actionTrimReadiness(
                for: selectionGroups,
                events: recorder.events,
                liveDuration: recorder.liveDuration,
                direction: .after
            )
            Button(action: trimBefore) {
                Label(String(localized: "Trim before", table: "Common"), systemImage: "arrow.left.to.line")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!trimBeforeReadiness.canTrim)
            .help(actionTrimReadinessHelp(trimBeforeReadiness, direction: .before))

            Button(action: trimAfter) {
                Label(String(localized: "Trim after", table: "Common"), systemImage: "arrow.right.to.line")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!trimAfterReadiness.canTrim)
            .help(actionTrimReadinessHelp(trimAfterReadiness, direction: .after))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)


    }

    @ViewBuilder
    func clearAllButton() -> some View {
        Button(role: .destructive) {
            confirmClearAll = true
        } label: {
            Label(String(localized: "Clear all", table: "Common"), systemImage: "trash.slash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(rows.isEmpty)
        .confirmationDialog(
            String(localized: "Remove all events from this macro?", table: "EditorUX"),
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear All Events", table: "EditorUX"), role: .destructive) { clearAll() }
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
        } message: {
            Text("You can undo this with ⌘Z while the editor is open.", tableName: "EditorUX")
        }

    }

    @ViewBuilder
    func insertActionContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            insertionTargetView()
            
            Divider().opacity(0.3)
            
            HStack {
                Text("Default Delay", tableName: "EditorUX")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    TextField("", value: $insertWaitMs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                    
                    Text("ms", tableName: "Common")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Stepper("", value: $insertWaitMs, in: 50...60000, step: 100)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.bottom, 6)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            // Row 1: Basic Input
            insertActionButton(
                title: String(localized: "Click", table: "EditorUX"),
                subtitle: String(localized: "Fixed point", table: "Common"),
                icon: "hand.point.up.left",
                tint: Brand.sigGreen
            ) { insertAction(.click) }

            insertActionButton(
                title: String(localized: "Key", table: "Common"),
                subtitle: String(localized: "Keyboard", table: "Common"),
                icon: "keyboard",
                tint: Brand.sigBlue
            ) { insertAction(.keyPress) }

            // Row 2: Extended Mouse
            insertActionButton(
                title: String(localized: "Double Click", table: "EditorUX"),
                subtitle: String(localized: "Fixed point", table: "Common"),
                icon: "cursorarrow.click.2",
                tint: Brand.sigGreen
            ) { insertAction(.doubleClick) }

            insertActionButton(
                title: String(localized: "Drag", table: "EditorUX"),
                subtitle: String(localized: "Path", table: "Common"),
                icon: "hand.draw",
                tint: Brand.sigBlue
            ) { insertAction(.drag) }

            // Row 3: Navigation & Timing
            insertActionButton(
                title: String(localized: "Scroll", table: "Common"),
                subtitle: String(localized: "Wheel", table: "Common"),
                icon: "arrow.up.and.down",
                tint: Brand.sigBlue
            ) { insertAction(.scroll) }

            insertActionButton(
                title: String(localized: "Wait", table: "EditorUX"),
                subtitle: String(localized: "Delay", table: "EditorUX"),
                icon: "hourglass",
                tint: .secondary
            ) { insertAction(.wait) }

            // Row 4: Vision & OCR Clicks
            insertActionButton(
                title: String(localized: "Click Text", table: "EditorUX"),
                subtitle: String(localized: "Wait then click", table: "EditorUX"),
                icon: "text.cursor",
                tint: Brand.sigTeal
            ) { insertTextClick() }

            insertActionButton(
                title: String(localized: "Reveal & Click", table: "EditorUX"),
                subtitle: String(localized: "Vision flow", table: "Common"),
                icon: "sparkles.rectangle.stack",
                tint: Brand.sigTeal
            ) { insertRevealAndClickTextFlow() }

            // Row 5: Vision Waits
            insertActionButton(
                title: String(localized: "Wait Text", table: "EditorUX"),
                subtitle: String(localized: "Wait to appear", table: "EditorUX"),
                icon: "text.magnifyingglass",
                tint: Brand.sigViolet
            ) { insertAction(.waitForText) }

            insertActionButton(
                title: String(localized: "Wait Text Gone", table: "EditorUX"),
                subtitle: String(localized: "Wait to disappear", table: "EditorUX"),
                icon: "text.badge.minus",
                tint: Brand.sigAmber
            ) { insertAction(.waitForTextGone) }

            // Row 6: Verification & Misc
            insertActionButton(
                title: String(localized: "Verify Text", table: "EditorUX"),
                subtitle: String(localized: "Checkpoint", table: "Common"),
                icon: "checkmark.seal",
                tint: Brand.sigAmber
            ) { insertAction(.verifyText) }

            insertActionButton(
                title: String(localized: "Multi Click", table: "EditorUX"),
                subtitle: String(localized: "Several points", table: "Common"),
                icon: "point.3.connected.trianglepath.dotted",
                tint: Brand.sigPink
            ) { insertAction(.multiPointClick) }
        }

    }

    @ViewBuilder
    func timeAdjustmentsContent() -> some View {
        let shiftGroups = selectedGroups()
        let shiftEarlierReadiness = actionShiftReadiness(for: shiftGroups, direction: .earlier)
        let shiftLaterReadiness = actionShiftReadiness(for: shiftGroups, direction: .later)

        VStack(alignment: .leading, spacing: 6) {
            Text("Shift Selected", tableName: "Common")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack {
                Stepper(value: $shiftMs, in: 10...5000, step: 50) {
                    Text("\(Int(shiftMs)) ms")
                        .font(.system(size: 10, design: .monospaced).weight(.semibold))
                }
                .controlSize(.small)
                Spacer()
                ControlGroup {
                    Button(action: { shiftSelection(by: -shiftMs / 1000.0) }) {
                        Image(systemName: "gobackward")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .disabled(!shiftEarlierReadiness.canShift)
                    .help(actionShiftReadinessHelp(shiftEarlierReadiness, direction: .earlier))

                    Button(action: { shiftSelection(by: shiftMs / 1000.0) }) {
                        Image(systemName: "goforward")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .disabled(!shiftLaterReadiness.canShift)
                    .help(actionShiftReadinessHelp(shiftLaterReadiness, direction: .later))
                }
                .controlGroupStyle(.navigation)
                .controlSize(.small)
            }

            if !shiftEarlierReadiness.canShift && !shiftLaterReadiness.canShift {
                Text(actionShiftReadinessHelp(shiftEarlierReadiness, direction: .earlier))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Divider().padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 6) {
            let stretchReadiness = actionTimeStretchReadiness(
                hasActions: !rows.isEmpty,
                factor: stretchFactor
            )
            HStack {
                Text("Time Stretch", tableName: "Common")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f×", stretchFactor))
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
            }
            Slider(value: $stretchFactor, in: 0.25...4.0, step: 0.05)
                .controlSize(.small)
            HStack {
                Button(String(localized: "Reset", table: "Common")) { stretchFactor = 1.0 }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Spacer()
                Button(String(localized: "Apply", table: "Common")) { applyStretch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!stretchReadiness.canApply)
                    .help(actionTimeStretchReadinessHelp(stretchReadiness))
            }
            if !stretchReadiness.canApply {
                Text(actionTimeStretchReadinessHelp(stretchReadiness))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

    }

    @ViewBuilder
    func editorReviewSection() -> some View {
        let groups = rows.map(\.group)
        let health = macroEditorHealthSummary(for: groups, events: recorder.events)
        let repeatUntilReadiness = MacroEditorRepeatUntilDraftBuilder.readiness(
            events: recorder.events,
            groups: groups,
            selectedGroupIDs: selection
        )
        let guidanceItems = macroEditorGuidanceItems(
            for: groups,
            events: recorder.events,
            selectedGroupIDs: selection,
            repeatUntilReadiness: repeatUntilReadiness
        )

        section(String(localized: "Review", table: "Common"), icon: "checklist.checked") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: macroEditorSidebarHealthIcon(health))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(macroEditorSidebarHealthTint(health))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(macroEditorHealthTitle(health))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(macroEditorHealthDetail(health))
                            .font(.system(size: 9.8))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 6) {
                    reviewMetric(
                        value: health.recordedActionCount,
                        label: String(localized: "actions", table: "EditorUX"),
                        tint: Brand.sigBlue
                    )
                    reviewMetric(
                        value: health.textTargetCount,
                        label: String(localized: "targets", table: "Common"),
                        tint: Brand.sigAmber
                    )
                    reviewMetric(
                        value: health.behaviorCount,
                        label: String(localized: "blocks", table: "Common"),
                        tint: Brand.sigViolet
                    )
                }

                VStack(spacing: 6) {
                    ForEach(guidanceItems.prefix(3)) { item in
                        guidanceRow(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func reviewMetric(value: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    func guidanceRow(_ item: MacroEditorGuidanceItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(guidanceTint(item.priority))
                .frame(width: 20)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(LocalizedStringKey(item.detail))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let actionTitle = item.actionTitle {
                Button(actionTitle) {
                    applyGuidanceAction(item.action)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .buttonBorderShape(.capsule)
                .help(item.detail)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func applyGuidanceAction(_ action: MacroEditorGuidanceAction) {
        switch action {
        case .none:
            break
        case .selectGroups(let ids):
            selectGuidanceGroups(ids)
        case .pickText(let ids):
            selectGuidanceGroups(ids)
            DispatchQueue.main.async {
                onPickText()
            }
        case .createBehavior:
            bindSelectedBehavior()
        case .createRepeatUntil:
            onCreateRepeatUntilDraft(
                loopMaxAttempts,
                loopTimeoutSeconds,
                loopPollingSeconds,
                loopFailurePolicy
            )
        }
    }

    func selectGuidanceGroups(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        selection = Set(ids)
        DispatchQueue.main.async {
            onLoadInspector()
            onUpdatePreview()
        }
    }

    func macroEditorSidebarHealthIcon(_ summary: MacroEditorHealthSummary) -> String {
        switch summary.state {
        case .empty:
            return "record.circle"
        case .needsTargets:
            return "text.viewfinder"
        case .reviewReliability:
            return "wrench.and.screwdriver"
        case .ready:
            return "checkmark.seal"
        }
    }

    func macroEditorSidebarHealthTint(_ summary: MacroEditorHealthSummary) -> Color {
        switch summary.state {
        case .empty:
            return .secondary
        case .needsTargets:
            return Brand.sigAmber
        case .reviewReliability:
            return Brand.sigTeal
        case .ready:
            return Brand.libraryGreen
        }
    }

    func guidanceTint(_ priority: MacroEditorGuidancePriority) -> Color {
        switch priority {
        case .blocking:
            return Brand.sigAmber
        case .next:
            return Brand.sigBlue
        case .improve:
            return Brand.sigTeal
        case .done:
            return Brand.libraryGreen
        }
    }


    func keyboardShortcutBinding(for group: ActionGroup) -> Binding<HotkeyBinding?> {
        Binding(
            get: {
                guard let keyCode = UInt16(inspKey) ?? group.keyCode else { return nil }
                let flags = inspFlags
                return HotkeyBinding(
                    keyCode: UInt32(keyCode),
                    name: shortcutName(keyCode: keyCode, flags: flags)
                )
            },
            set: { _ in }
        )
    }

    func applyRecordedShortcut(_ recording: ShortcutRecording) {
        inspKey = String(recording.keyCode)
        inspFlags = recording.eventFlags
        applyInspector()
    }

    @ViewBuilder
    func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(.rect(cornerRadius: 10))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    func behaviorSection() -> some View {
        section(String(localized: "Behavior", table: "Common"), icon: "square.stack.3d.down.right") {
            VStack(alignment: .leading, spacing: 8) {
                let bindReadiness = selectionSnapshot.behaviorBindReadiness
                let selectedBehavior = selectedBehaviorGroup()
                if let selectedBehavior {
                    let renameReadiness = behaviorRenameReadiness(
                        for: selectedBehavior,
                        proposedName: inspBehaviorName
                    )
                    Label(String(localized: "Selected Behavior", table: "Common"), systemImage: "checkmark.rectangle.stack")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Brand.sigAmber)
                    Text("Rename or split this behavior without changing the actions inside it.", tableName: "EditorUX")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(String(localized: "Behavior name", table: "Common"), text: $inspBehaviorName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .controlSize(.small)
                        .onSubmit { submitBehaviorName() }
                    Button {
                        duplicateSelected()
                    } label: {
                        Label(String(localized: "Duplicate Behavior", table: "Common"), systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(String(localized: "Copy this behavior as a new reusable behavior block.", table: "Automation"))

                    HStack(spacing: 6) {
                        Button {
                            renameSelectedBehavior()
                        } label: {
                            Label(String(localized: "Rename Behavior", table: "Common"), systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!renameReadiness.canRename)
                        .help(behaviorRenameReadinessHelp(renameReadiness))

                        Button {
                            unbindSelectedBehavior()
                        } label: {
                            Label(String(localized: "Unbind", table: "Common"), systemImage: "square.stack.3d.down.forward")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !renameReadiness.canRename {
                        Text(behaviorRenameReadinessHelp(renameReadiness))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Label(String(localized: "New Behavior", table: "Common"), systemImage: "plus.square.on.square")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Brand.sigAmber)
                    Text("Select a continuous set of recorded actions, name it, then create one behavior block.", tableName: "Recording")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(String(localized: "Behavior name", table: "Common"), text: $inspBehaviorName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .controlSize(.small)
                        .onSubmit { submitBehaviorName() }
                    HStack(spacing: 6) {
                        Button {
                            bindSelectedBehavior()
                        } label: {
                            Label(String(localized: "Create Behavior", table: "Common"), systemImage: "square.stack.3d.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .help(behaviorBindReadinessHelp(bindReadiness))
                        .disabled(!canBindSelection)

                        Button {
                            unbindSelectedBehavior()
                        } label: {
                            Label(String(localized: "Unbind", table: "Common"), systemImage: "square.stack.3d.down.forward")
                                .frame(maxWidth: .infinity)
                        }
                        .help(String(localized: "Show behavior events as separate actions again", table: "EditorUX"))
                        .disabled(!canUnbindSelection)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !bindReadiness.canBind {
                        Text(behaviorBindReadinessHelp(bindReadiness))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func repeatUntilSection() -> some View {
        let repeatUntilReadiness = MacroEditorRepeatUntilDraftBuilder.readiness(
            events: recorder.events,
            groups: rows.map(\.group),
            selectedGroupIDs: selection
        )
        
        if selection.count > 1 {
            section(String(localized: "Repeat Until Loop", table: "Common"), icon: "arrow.triangle.2.circlepath") {
                VStack(alignment: .leading, spacing: 8) {
                    // Loop Configuration Form
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Max Attempts", tableName: "Common")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(loopMaxAttempts) " + String(localized: "times", table: "Common"))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Stepper("", value: $loopMaxAttempts, in: 1...100)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Divider().opacity(0.3)

                        HStack(spacing: 6) {
                            Text("Timeout", tableName: "Common")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(loopTimeoutSeconds))s")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Stepper("", value: $loopTimeoutSeconds, in: 5...300, step: 5)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Divider().opacity(0.3)

                        HStack(spacing: 6) {
                            Text("Polling Interval", tableName: "Common")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1fs", loopPollingSeconds))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Stepper("", value: $loopPollingSeconds, in: 0.5...10.0, step: 0.5)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Divider().opacity(0.3)

                        HStack(spacing: 6) {
                            Text("On Failure", tableName: "Common")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Picker("", selection: $loopFailurePolicy) {
                                Text("Abort Macro", tableName: "EditorUX").tag("failRun")
                                Text("Pause & Approve", tableName: "Common").tag("requireManualApproval")
                                Text("Continue next", tableName: "Common").tag("continueWorkflow")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 125)
                        }
                    }
                    .padding(8)
                    .background(Color(.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(6)

                    Button {
                        onCreateRepeatUntilDraft(
                            loopMaxAttempts,
                            loopTimeoutSeconds,
                            loopPollingSeconds,
                            loopFailurePolicy
                        )
                    } label: {
                        Label(String(localized: "Preview Repeat Until", table: "Common"), systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!repeatUntilReadiness.canCreate)
                    .help(repeatUntilReadinessHelp(repeatUntilReadiness))
                    
                    Text("Save the selected body as a behavior macro, then open a draft-only Repeat-Until preview.", tableName: "EditorUX")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !repeatUntilReadiness.canCreate {
                        Text(repeatUntilReadinessHelp(repeatUntilReadiness))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Brand.sigAmber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func emptyInspector(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    func workflowHint(for group: ActionGroup, event: RecordedEvent?) -> some View {
        let message = actionWorkflowMessage(for: group, event: event)
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(actionKindColor(group.kind))
                .frame(width: 14)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(.rect(cornerRadius: 7))
    }
    
    @ViewBuilder
    func insertActionButton(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(subtitle)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }


    @ViewBuilder
    func inspectorGrid(@ViewBuilder content: () -> some View) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            content()
        }
    }

    @ViewBuilder
    func gridField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            content()
        }
    }

    @ViewBuilder
    func labeledField(_ title: String, text: Binding<String>) -> some View {
        gridField(title) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .controlSize(.small)
                .onSubmit { applyInspector() }
        }
    }
    
    @ViewBuilder
    func labeledDoubleField(_ title: String, value: Binding<Double>) -> some View {
        labeledField(title, text: Binding(
            get: { String(format: "%.2f", value.wrappedValue) },
            set: { newValue in
                if let parsed = finiteInspectorDouble(newValue) {
                    value.wrappedValue = parsed
                    applyInspector()
                }
            }
        ))
    }

    @ViewBuilder
    func labeledInlineDoubleField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(title, text: Binding(
                get: { String(format: "%.2f", value.wrappedValue) },
                set: { newValue in
                    if let parsed = finiteInspectorDouble(newValue) {
                        value.wrappedValue = parsed
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.callout, design: .monospaced))
            .controlSize(.small)
            .frame(width: 64)
        }
    }
    
    func firstEvent(for group: ActionGroup) -> RecordedEvent? {
        guard let first = group.eventIndices.first, recorder.events.indices.contains(first) else { return nil }
        return recorder.events[first]
    }
    
    @ViewBuilder
    func locatorPlaybackPolicyView() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playback if text is missing", tableName: "EditorUX")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { inspFallbackPolicy },
                set: { inspFallbackPolicy = $0; applyInspector() }
            )) {
                Text("Pause", tableName: "Common").tag(LocatorFallbackPolicy.fail)
                Text("Use fallback point", tableName: "Common").tag(LocatorFallbackPolicy.allowCoordinateFallback)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
    }
    
    @ViewBuilder
    func visionEmptyState(readiness: TextTargetReadiness = .missingAnchor) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: readiness == .missingText ? "exclamationmark.triangle" : "text.viewfinder")
                .foregroundStyle(Brand.sigAmber)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(textTargetReadinessTitle(readiness))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(textTargetReadinessDetail(readiness))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(.rect(cornerRadius: 7))
    }

    func textTargetReadinessTitle(_ readiness: TextTargetReadiness) -> String {
        switch readiness {
        case .missingText:
            return String(localized: "No target text", table: "EditorUX")
        case .missingAnchor, .notTextTarget:
            return String(localized: "No text target", table: "EditorUX")
        case .ready:
            return String(localized: "Text target ready", table: "EditorUX")
        }
    }

    func textTargetReadinessDetail(_ readiness: TextTargetReadiness) -> String {
        switch readiness {
        case .missingText:
            return String(localized: "Pick text or type a non-empty target.", table: "EditorUX")
        case .missingAnchor, .notTextTarget:
            return String(localized: "Pick text to create a searchable target.", table: "EditorUX")
        case .ready:
            return String(localized: "Playback will use the matched text target.", table: "EditorUX")
        }
    }

    @ViewBuilder
    func multiPointClickEditor(for group: ActionGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Click Points", tableName: "EditorUX")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)

            let points = group.path.isEmpty ? group.eventIndices.compactMap { index -> CGPoint? in
                guard recorder.events.indices.contains(index),
                      recorder.events[index].kind == .leftMouseDown else { return nil }
                return CGPoint(x: recorder.events[index].x, y: recorder.events[index].y)
            } : group.path

            VStack(spacing: 4) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Brand.sigPink))
                        Text("(\(Int(point.x)), \(Int(point.y)))")
                            .font(.system(size: 10.5, design: .monospaced))
                        Spacer()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(.rect(cornerRadius: 6))
                }
            }

            let removalReadiness = multiPointClickPointRemovalReadiness(for: group)
            HStack(spacing: 6) {
                Button {
                    onAddClickPoint()
                } label: {
                    Label(String(localized: "Add Point", table: "Common"), systemImage: "plus")
                }
                .frame(maxWidth: .infinity)

                Button {
                    removeLastMultiClickPoint(group)
                } label: {
                    Label(String(localized: "Remove Last", table: "Common"), systemImage: "minus")
                }
                .frame(maxWidth: .infinity)
                .disabled(!removalReadiness.canRemove)
                .help(multiPointClickPointRemovalReadinessHelp(removalReadiness))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !removalReadiness.canRemove {
                Text(multiPointClickPointRemovalReadinessHelp(removalReadiness))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var insertionIndexBinding: Binding<Int> {
        Binding<Int>(
            get: {
                if let anchor = insertionAnchor() {
                    return anchor.order + 1
                }
                return rows.count + 1
            },
            set: { newValue in
                let clamped = max(1, min(newValue, rows.count + 1))
                if clamped > rows.count {
                    selection.removeAll()
                } else {
                    let index = clamped - 1
                    if rows.indices.contains(index) {
                        selection = [rows[index].id]
                    }
                }
            }
        )
    }

    @ViewBuilder
    func insertionTargetView() -> some View {
        HStack(spacing: 8) {
            Text("Insert Position", tableName: "Common")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if rows.isEmpty {
                Text("Empty Timeline", tableName: "EditorUX")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    let val = insertionIndexBinding.wrappedValue
                    if val > rows.count {
                        Text("Append at end", tableName: "Common")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("After Action #", tableName: "EditorUX")
                            .font(.system(size: 11))
                        
                        TextField("", value: insertionIndexBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 45)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Stepper("", value: insertionIndexBinding, in: 1...(rows.count + 1))
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
        }
    }
    
    func insertionAnchor() -> (order: Int, row: ActionRow)? {
        var anchor: (order: Int, row: ActionRow)?
        for (index, row) in rows.enumerated() where selection.contains(row.id) {
            anchor = (index, row)
        }
        return anchor
    }
    
    func insertionPlacementAfterSelection() -> ActionInsertionPlacement {
        guard let anchor = insertionAnchor()?.row else {
            return ActionInsertionPlacement(eventIndex: recorder.events.count, explicitStartTime: nil)
        }
        
        let group = anchor.group
        if let lastEventIndex = group.eventIndices.last {
            return ActionInsertionPlacement(eventIndex: min(lastEventIndex + 1, recorder.events.count), explicitStartTime: nil)
        }
        
        let index = recorder.events.firstIndex { event in
            event.time >= group.endTime
        } ?? recorder.events.count
        let explicitStartTime = group.kind.isPassiveWait ? group.endTime : nil
        return ActionInsertionPlacement(eventIndex: index, explicitStartTime: explicitStartTime)
    }

    func insertionIndexAfterSelection() -> Int {
        insertionPlacementAfterSelection().eventIndex
    }
    
    func selectInsertedEvents(in range: Range<Int>) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            if let inserted = ActionGroupProjection.firstGroup(containingEventIn: range, groups: groups) {
                self.selection = [inserted.id]
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            }
        }
    }

    func selectCopiedEvents(
        in range: Range<Int>,
        excludingBehaviorIDs sourceBehaviorIDs: Set<BehaviorGroupID>
    ) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            let copiedEventIndices = Set(range)
            let copiedBehaviors = ActionGroupProjection.behaviorGroups(
                containingEventIndices: copiedEventIndices,
                excluding: sourceBehaviorIDs,
                groups: groups
            )
            let targets = copiedBehaviors.isEmpty
                ? groups.filter { group in
                    group.eventIndices.contains { copiedEventIndices.contains($0) }
                }
                : copiedBehaviors

            if !targets.isEmpty {
                self.selection = Set(targets.map(\.id))
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            }
        }
    }

    func selectInsertedEvents(matching insertedEvents: [RecordedEvent], fallback range: Range<Int>) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            let target = ActionGroupProjection.firstGroup(
                matching: insertedEvents,
                in: self.recorder.events,
                groups: groups
            ) ?? ActionGroupProjection.firstGroup(containingEventIn: range, groups: groups)

            if let target {
                self.selection = [target.id]
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            }
        }
    }

    func selectInsertedTextTargets(in range: Range<Int>) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            let textGroups = groups.filter { group in
                group.eventIndices.contains { range.contains($0) } && self.isTextTargetGroup(group)
            }
            if !textGroups.isEmpty {
                self.selection = Set(textGroups.map(\.id))
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            } else if let inserted = ActionGroupProjection.firstGroup(containingEventIn: range, groups: groups) {
                self.selection = [inserted.id]
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            }
        }
    }

    func selectInsertedTextTargets(matching insertedEvents: [RecordedEvent], fallback range: Range<Int>) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            let matchedIndices = ActionGroupProjection.eventIndices(
                matching: insertedEvents,
                in: self.recorder.events
            )
            let textGroups = groups.filter { group in
                group.eventIndices.contains { matchedIndices.contains($0) } &&
                self.isTextTargetGroup(group)
            }

            if !textGroups.isEmpty {
                self.selection = Set(textGroups.map(\.id))
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            } else {
                self.selectInsertedEvents(matching: insertedEvents, fallback: range)
            }
        }
    }

    func events(in range: Range<Int>) -> [RecordedEvent] {
        guard range.lowerBound >= 0,
              range.upperBound <= recorder.events.count,
              range.lowerBound < range.upperBound else {
            return []
        }
        return Array(recorder.events[range])
    }
    
    func selectInsertedWait(start: TimeInterval, end: TimeInterval) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            if let wait = ActionGroupProjection.firstWaitGroup(start: start, end: end, groups: groups) {
                self.selection = [wait.id]
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            }
        }
    }
    
    var selectionSnapshot: ActionGroupSelectionSnapshot {
        ActionGroupProjection.selectionSnapshot(
            groups: rows.map(\.group),
            selectedGroupIDs: selection,
            events: recorder.events
        )
    }

    func selectedGroups() -> [ActionGroup] {
        rows.compactMap { row in
            selection.contains(row.id) ? row.group : nil
        }
    }

    func isTextTargetGroup(_ group: ActionGroup) -> Bool {
        ActionGroupProjection.isTextTargetGroup(group, events: recorder.events)
    }

    func selectedTextTargetGroups() -> [ActionGroup] {
        ActionGroupProjection.textTargetGroups(
            groups: rows.map(\.group),
            selectedGroupIDs: selection,
            events: recorder.events
        )
    }

    var canBindSelection: Bool {
        selectionSnapshot.canBindBehavior
    }

    var canUnbindSelection: Bool {
        selectionSnapshot.containsBehavior
    }

    var behaviorNameDraft: String {
        inspBehaviorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canRenameSelectedBehavior: Bool {
        behaviorRenameReadiness(
            for: selectedBehaviorGroup(),
            proposedName: inspBehaviorName
        ).canRename
    }
    
    func selectedEventIndices() -> [Int] {
        selectionSnapshot.eventIndices
    }

    func selectedBehaviorGroup() -> ActionGroup? {
        let groups = selectedGroups()
        guard groups.count == 1 else { return nil }
        guard let group = groups.first, group.behaviorGroupID != nil else { return nil }
        return group
    }

    func repeatUntilReadinessHelp(_ readiness: MacroEditorRepeatUntilDraftReadiness) -> String {
        switch readiness {
        case .ready:
            return String(localized: "Create a reusable behavior macro and preview the Repeat-Until workflow draft.", table: "Automation")
        case .noSelection:
            return String(localized: "Select a behavior body and one text wait condition.", table: "Automation")
        case .missingBody:
            return String(localized: "Select at least one recorded action as the Repeat-Until body.", table: "Recording")
        case .multipleUntilConditions:
            return String(localized: "Select only one Wait Text, Wait Text Gone, or Verify Text condition.", table: "Automation")
        case .missingUntilCondition:
            return String(localized: "Select one Wait Text, Wait Text Gone, or Verify Text condition as the Until check.", table: "Automation")
        case .missingUntilText:
            return String(localized: "Pick or type target text before creating Repeat Until.", table: "EditorUX")
        }
    }
    
    func nextBehaviorName() -> String {
        let existing = recorder.events.compactMap(\.behaviorGroupID).reduce(into: Set<BehaviorGroupID>()) { partial, id in
            partial.insert(id)
        }
        return String(format: String(localized: "Behavior %d", table: "Common"), existing.count + 1)
    }

    func behaviorNameForNewBinding() -> String {
        behaviorNameDraft.isEmpty ? nextBehaviorName() : behaviorNameDraft
    }

    func submitBehaviorName() {
        if selectedBehaviorGroup() != nil {
            renameSelectedBehavior()
        } else {
            bindSelectedBehavior()
        }
    }
    
    func bindSelectedBehavior() {
        let indices = selectedEventIndices()
        guard canBindSelection else { return }
        let id = BehaviorGroupID()
        let name = behaviorNameForNewBinding()
        
        withUndo(String(localized: "Create Behavior", table: "Common")) {
            recorder.events.bindBehavior(at: indices, id: id, name: name)
        }
        
        selectBehavior(id)
    }

    func renameSelectedBehavior() {
        guard let group = selectedBehaviorGroup(),
              let id = group.behaviorGroupID,
              behaviorRenameReadiness(for: group, proposedName: inspBehaviorName).canRename else {
            return
        }

        withUndo(String(localized: "Rename Behavior", table: "Common")) {
            recorder.events.renameBehavior(id: id, name: behaviorNameDraft)
        }

        selectBehavior(id)
    }
    
    func unbindSelectedBehavior() {
        let indices = selectedEventIndices()
        guard !indices.isEmpty, canUnbindSelection else { return }
        
        withUndo(String(localized: "Unbind Behavior", table: "Common")) {
            recorder.events.unbindBehavior(at: indices)
        }
        
        DispatchQueue.main.async {
            self.selection = []
            self.onLoadInspector()
            self.onUpdatePreview()
        }
    }
    
    func selectBehavior(_ id: BehaviorGroupID) {
        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            if let bound = ActionGroupProjection.firstBehaviorGroup(id: id, groups: groups) {
                self.selection = [bound.id]
                self.onLoadInspector()
                self.onUpdatePreview()
            }
        }
    }

    // MARK: - Actions

    func withUndo(_ name: String, _ mutate: () -> Void) {
        let before = MacroEditMutationSnapshot(
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        mutate()
        let after = MacroEditMutationSnapshot(
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        guard after.differs(from: before) else { return }

        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] r in
            r.loadEvents(before.events, duration: before.liveDuration)
            undoManager?.registerUndo(withTarget: r) { r2 in
                r2.loadEvents(after.events, duration: after.liveDuration)
            }
        }
        undoManager?.setActionName(name)
        recorder.recalculateStats()
    }

    func duplicateSelected() {
        let selectedGroups = selection.compactMap { groupID -> ActionGroup? in
            rows.first(where: { $0.id == groupID })?.group
        }
        let sourceBehaviorIDs = Set(selectedGroups.compactMap(\.behaviorGroupID))
        guard actionSelectionDuplicationReadiness(
            for: selectedGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        ).canDuplicate else { return }

        let waitPlan = ActionGroupPassiveWaitDuplicationPlanner.plan(
            for: selectedGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        let waitTargets = duplicatedWaitTargets(for: selectedGroups)
        var allIndices: [Int] = []
        for grp in selectedGroups {
            allIndices.append(contentsOf: grp.eventIndices)
        }
        guard !allIndices.isEmpty || !waitPlan.isEmpty else { return }
        
        let sorted = allIndices.sorted()
        let copiesRange: Range<Int>? = {
            guard let last = sorted.last else { return nil }
            let afterIdx = last + 1
            return afterIdx ..< (afterIdx + sorted.count)
        }()
        
        withUndo(String(localized: "Duplicate Action", table: "EditorUX")) {
            recorder.events.applyPassiveWaitDuplicationPlan(waitPlan)
            if let liveDuration = waitPlan.liveDurationAfterDuplication {
                recorder.liveDuration = liveDuration
            }
            if !allIndices.isEmpty {
                recorder.events.duplicateEvents(at: allIndices)
            }
            if let lastTime = recorder.events.last?.time {
                recorder.liveDuration = max(recorder.liveDuration, lastTime)
            }
        }

        if let copiesRange {
            selectCopiedEvents(in: copiesRange, excludingBehaviorIDs: sourceBehaviorIDs)
        } else {
            selectWaits(matching: waitTargets)
        }
    }

    func duplicatedWaitTargets(for groups: [ActionGroup]) -> [(start: TimeInterval, end: TimeInterval)] {
        let waits = groups
            .filter { $0.kind == .wait && $0.duration > 0 }
            .sorted { $0.startTime < $1.startTime }

        return waits.map { group in
            let startOffset = waits.reduce(TimeInterval(0)) { partial, wait in
                wait.endTime <= group.startTime ? partial + wait.duration : partial
            }
            let endOffset = waits.reduce(TimeInterval(0)) { partial, wait in
                wait.endTime <= group.endTime ? partial + wait.duration : partial
            }
            return (
                start: group.startTime + startOffset,
                end: group.endTime + endOffset
            )
        }
    }

    func selectWaits(matching targets: [(start: TimeInterval, end: TimeInterval)]) {
        guard !targets.isEmpty else { return }

        DispatchQueue.main.async {
            let groups = self.onRefreshRows().map(\.group)
            let matched = groups.filter { group in
                guard group.kind == .wait else { return false }
                return targets.contains { target in
                    abs(group.startTime - target.start) <= 0.02 &&
                    abs(group.endTime - target.end) <= 0.02
                }
            }
            self.selection = Set(matched.map(\.id))
            self.onLoadInspector()
            self.onUpdatePreview()
        }
    }

    func deleteSelected() {
        let selectedGroups = selection.compactMap { groupID -> ActionGroup? in
            rows.first(where: { $0.id == groupID })?.group
        }
        guard actionSelectionDeletionReadiness(
            for: selectedGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        ).canDelete else { return }

        let plan = ActionGroupDeletionPlanner.plan(
            for: selectedGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        guard !plan.isEmpty else { return }
        
        selection.removeAll()
        withUndo(String(localized: "Delete Actions", table: "EditorUX")) {
            recorder.events.applyActionGroupDeletionPlan(plan)
            if let liveDuration = plan.liveDurationAfterDeletion {
                recorder.liveDuration = liveDuration
            }
        }
    }

    func trimBefore() {
        let trimGroups = selectedGroups()
        guard actionTrimReadiness(
            for: trimGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration,
            direction: .before
        ).canTrim, let grp = trimGroups.first else { return }
        let cutoff = max(0, grp.startTime)
        withUndo(String(localized: "Trim Before", table: "Common")) {
            recorder.events.removeAll { $0.time < cutoff }
            for idx in recorder.events.indices {
                recorder.events[idx].time = max(0, recorder.events[idx].time - cutoff)
            }
            recorder.liveDuration = max(0, recorder.liveDuration - cutoff)
        }
        selection = []
    }

    func trimAfter() {
        let trimGroups = selectedGroups()
        guard actionTrimReadiness(
            for: trimGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration,
            direction: .after
        ).canTrim, let grp = trimGroups.first else { return }
        let cutoff = max(0, grp.endTime)
        let epsilon: TimeInterval = 0.000_001
        let shouldRemove: (RecordedEvent) -> Bool = { event in
            if grp.kind.isPassiveWait {
                return event.time >= cutoff - epsilon
            }
            return event.time > cutoff + epsilon
        }
        withUndo(String(localized: "Trim After", table: "Common")) {
            recorder.events.removeAll(where: shouldRemove)
            recorder.liveDuration = cutoff
        }
        selection = []
    }

    func clearAll() {
        selection.removeAll()
        withUndo(String(localized: "Clear All Events", table: "EditorUX")) {
            recorder.clearAll()
        }
    }

    func removeLastMultiClickPoint(_ group: ActionGroup) {
        guard multiPointClickPointRemovalReadiness(for: group).canRemove else { return }
        withUndo(String(localized: "Remove Click Point", table: "EditorUX")) {
            recorder.events.removeLastMultiPointClick(at: group.eventIndices)
        }
        onLoadInspector()
        onUpdatePreview()
    }

    func insertAction(_ kind: ActionGroupKind) {
        let placement = insertionPlacementAfterSelection()
        let idx = placement.eventIndex
        let clampedIndex = max(0, min(idx, recorder.events.count))
        let previousEventCount = recorder.events.count
        let previousLiveDuration = recorder.liveDuration
        let previousLastEventTime = recorder.events.last?.time
        let insertedCount = kind.insertedEventCount
        let waitDelta = max(0, insertWaitMs / 1000.0)
        let waitStart = clampedIndex > 0 ? recorder.events[clampedIndex - 1].time : 0
        var insertedEventsAfterMutation: [RecordedEvent] = []
        let waitEnd: TimeInterval = {
            if clampedIndex < recorder.events.count {
                return recorder.events[clampedIndex].time + waitDelta
            }
            return max(recorder.liveDuration, recorder.events.last?.time ?? 0) + waitDelta
        }()
        
        withUndo(String(format: String(localized: "Insert %@", table: "Common"), humanActionKindName(kind))) {
            var insertedEvents: [RecordedEvent] = []
            switch kind {
            case .wait:
                recorder.events.insertWait(at: clampedIndex, milliseconds: insertWaitMs)
                if waitDelta > 0 {
                    recorder.liveDuration = recorder.events.liveDurationAfterPassiveWaitInsertion(
                        previousLiveDuration: previousLiveDuration,
                        previousLastEventTime: previousLastEventTime,
                        previousEventCount: previousEventCount,
                        insertionIndex: clampedIndex,
                        waitDelta: waitDelta
                    )
                }
            case .click: recorder.events.insertClick(at: clampedIndex)
            case .doubleClick: recorder.events.insertDoubleClick(at: clampedIndex)
            case .multiPointClick: recorder.events.insertMultiPointClick(at: clampedIndex)
            case .drag: recorder.events.insertDrag(at: clampedIndex)
            case .scroll: recorder.events.insertScroll(at: clampedIndex)
            case .keyPress: recorder.events.insertKeystroke(at: clampedIndex)
            case .waitForText: recorder.events.insertWaitForText(at: clampedIndex)
            case .waitForTextGone: recorder.events.insertWaitForTextGone(at: clampedIndex)
            case .verifyText: recorder.events.insertVerifyText(at: clampedIndex)
            default: break
            }
            if !kind.isPassiveWait, insertedCount > 0, let explicitStartTime = placement.explicitStartTime {
                insertedEvents = retimeInsertedEvents(
                    in: clampedIndex..<(clampedIndex + insertedCount),
                    toStartTime: explicitStartTime
                )
            } else if !kind.isPassiveWait, insertedCount > 0 {
                insertedEvents = events(in: clampedIndex..<(clampedIndex + insertedCount))
            }
            if !kind.isPassiveWait {
                recorder.liveDuration = recorder.events.liveDurationPreservingTrailingWait(
                    previousLiveDuration: previousLiveDuration,
                    previousLastEventTime: previousLastEventTime
                )
            }
            insertedEventsAfterMutation = insertedEvents
        }
        
        if kind.isPassiveWait {
            selectInsertedWait(start: waitStart, end: waitEnd)
        } else if insertedCount > 0 {
            selectInsertedEvents(
                matching: insertedEventsAfterMutation,
                fallback: clampedIndex..<(clampedIndex + insertedCount)
            )
        }
    }
    
    func insertTextClick() {
        let placement = insertionPlacementAfterSelection()
        let idx = placement.eventIndex
        let clampedIndex = max(0, min(idx, recorder.events.count))
        let previousLiveDuration = recorder.liveDuration
        let previousLastEventTime = recorder.events.last?.time
        var insertedEvents: [RecordedEvent] = []
        
        withUndo(String(localized: "Insert Click Text", table: "EditorUX")) {
            recorder.events.insertTextClick(at: clampedIndex)
            if let explicitStartTime = placement.explicitStartTime {
                insertedEvents = retimeInsertedEvents(
                    in: clampedIndex..<(clampedIndex + 2),
                    toStartTime: explicitStartTime
                )
            } else {
                insertedEvents = events(in: clampedIndex..<(clampedIndex + 2))
            }
            recorder.liveDuration = recorder.events.liveDurationPreservingTrailingWait(
                previousLiveDuration: previousLiveDuration,
                previousLastEventTime: previousLastEventTime
            )
        }
        
        selectInsertedEvents(matching: insertedEvents, fallback: clampedIndex..<(clampedIndex + 2))
    }

    func insertBehaviorCopy(_ group: ActionGroup) {
        guard let behaviorID = group.behaviorGroupID else { return }
        
        let placement = insertionPlacementAfterSelection()
        let insertIndex = placement.eventIndex
        let clampedIndex = max(0, min(insertIndex, recorder.events.count))
        
        let behaviorEvents = recorder.events.filter { $0.behaviorGroupID == behaviorID }
        guard !behaviorEvents.isEmpty else { return }
        
        let sortedEvents = behaviorEvents.sorted { $0.time < $1.time }
        let srcBaseTime = sortedEvents[0].time
        let srcDuration = (sortedEvents.last!.time - srcBaseTime) + 0.1
        
        let previousLiveDuration = recorder.liveDuration
        let previousLastEventTime = recorder.events.last?.time
        
        let newBehaviorID = BehaviorGroupID()
        let newBehaviorName = String(
            format: String(localized: "Copy of %@", table: "Common"),
            group.behaviorGroupName ?? String(localized: "Behavior", table: "Common")
        )
        
        let insertionTime: TimeInterval = {
            if let explicit = placement.explicitStartTime {
                return explicit
            }
            if clampedIndex > 0 {
                return recorder.events[clampedIndex - 1].time + 0.1
            }
            return 0
        }()
        
        var copies: [RecordedEvent] = []
        for ev in sortedEvents {
            var copy = ev
            copy.time = insertionTime + (ev.time - srcBaseTime)
            copy.behaviorGroupID = newBehaviorID
            copy.behaviorGroupName = newBehaviorName
            copies.append(copy)
        }
        
        withUndo(String(format: String(localized: "Insert Behavior: %@", table: "Common"), newBehaviorName)) {
            for i in clampedIndex..<recorder.events.count {
                recorder.events[i].time += srcDuration
            }
            recorder.events.insert(contentsOf: copies, at: clampedIndex)
            recorder.liveDuration = recorder.events.liveDurationPreservingTrailingWait(
                previousLiveDuration: previousLiveDuration + srcDuration,
                previousLastEventTime: previousLastEventTime
            )
            if let lastTime = recorder.events.last?.time {
                recorder.liveDuration = max(recorder.liveDuration, lastTime)
            }
        }
        
        selectInsertedEvents(matching: copies, fallback: clampedIndex..<(clampedIndex + copies.count))
    }

    private var boundBehaviors: [ActionGroup] {
        var seen = Set<BehaviorGroupID>()
        var list = [ActionGroup]()
        for row in rows {
            if let bid = row.group.behaviorGroupID, !seen.contains(bid) {
                seen.insert(bid)
                list.append(row.group)
            }
        }
        return list
    }

    func insertClickTextAfterSelectedWait(_ group: ActionGroup) {
        guard group.kind == .waitForText,
              textClickConversionReadiness(for: group).canConvert,
              let sourceEventIndex = group.eventIndices.last,
              recorder.events.indices.contains(sourceEventIndex) else {
            return
        }

        let sourceEvent = recorder.events[sourceEventIndex]
        let insertionIndex = min(sourceEventIndex + 1, recorder.events.count)
        let trimmedInspectorText = inspOCRText.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = !trimmedInspectorText.isEmpty
            ? updatedAnchor(for: group, text: inspOCRText)
            : (sourceEvent.textAnchor
               ?? group.textAnchor
               ?? TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)))
        let timeout = sourceEvent.textTimeout ?? group.textTimeout ?? inspTimeout
        let fallbackPolicy = sourceEvent.locatorFallbackPolicy ?? inspFallbackPolicy
        let previousLiveDuration = recorder.liveDuration
        let previousLastEventTime = recorder.events.last?.time
        var insertedRange = insertionIndex..<insertionIndex
        var insertedEvents: [RecordedEvent] = []

        withUndo(String(localized: "Add Click Text After Wait", table: "EditorUX")) {
            insertedRange = recorder.events.insertTextClick(
                at: insertionIndex,
                textAnchor: anchor,
                textTimeout: timeout,
                fallbackPolicy: fallbackPolicy,
                surfaceId: sourceEvent.surfaceId
            )
            insertedEvents = events(in: insertedRange)
            recorder.liveDuration = recorder.events.liveDurationPreservingTrailingWait(
                previousLiveDuration: previousLiveDuration,
                previousLastEventTime: previousLastEventTime
            )
        }

        selectWaitAndInsertedTextClick(
            waitEventIndices: group.eventIndices,
            insertedEvents: insertedEvents,
            fallback: insertedRange
        )
    }

    func convertWaitToClickText(_ group: ActionGroup) {
        let textOverride = inspOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : updatedAnchor(for: group, text: inspOCRText)
        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: group,
            events: recorder.events,
            liveDuration: recorder.liveDuration,
            textAnchorOverride: textOverride,
            textTimeoutOverride: inspTimeout,
            fallbackPolicy: firstEvent(for: group)?.locatorFallbackPolicy ?? inspFallbackPolicy
        )
        guard !plan.isEmpty else { return }

        let insertedEvents = plan.insertedEvents
        withUndo(String(localized: "Convert Wait to Click Text", table: "EditorUX")) {
            recorder.events.applyTextClickConversionPlan(plan)
            if let liveDuration = plan.liveDurationAfterConversion {
                recorder.liveDuration = liveDuration
            }
        }

        selectEvents(matching: insertedEvents)
    }

    func textClickConversionReadiness(for group: ActionGroup) -> TextClickConversionReadiness {
        ActionGroupTextClickConversionPlanner.readiness(
            for: group,
            events: recorder.events
        )
    }

    func selectWaitAndInsertedTextClick(
        waitEventIndices: [Int],
        insertedEvents: [RecordedEvent],
        fallback insertedRange: Range<Int>
    ) {
        DispatchQueue.main.async {
            let waitIndexSet = Set(waitEventIndices)
            let insertedIndexSet = ActionGroupProjection.eventIndices(
                matching: insertedEvents,
                in: self.recorder.events
            )
            let groups = self.onRefreshRows().map(\.group)
            let targets = groups.filter { group in
                let isSourceWait = group.eventIndices.contains { waitIndexSet.contains($0) }
                let isInsertedClick = group.eventIndices.contains {
                    insertedIndexSet.contains($0) || insertedRange.contains($0)
                }
                return (isSourceWait || isInsertedClick) && self.isTextTargetGroup(group)
            }
            if !targets.isEmpty {
                self.selection = Set(targets.map(\.id))
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            } else {
                self.selectInsertedEvents(matching: insertedEvents, fallback: insertedRange)
            }
        }
    }

    func selectEvents(matching eventsToSelect: [RecordedEvent]) {
        guard !eventsToSelect.isEmpty else { return }

        DispatchQueue.main.async {
            let matchedEventIndices = ActionGroupProjection.eventIndices(
                matching: eventsToSelect,
                in: self.recorder.events
            )

            let groups = self.onRefreshRows().map(\.group)
            let targets = groups.filter { group in
                group.eventIndices.contains { matchedEventIndices.contains($0) }
            }
            if !targets.isEmpty {
                self.selection = Set(targets.map(\.id))
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            }
        }
    }

    func insertRevealAndClickTextFlow() {
        let placement = insertionPlacementAfterSelection()
        let clampedIndex = max(0, min(placement.eventIndex, recorder.events.count))
        let delay = placement.explicitStartTime == nil ? max(0, insertWaitMs / 1000.0) : 0
        let previousLiveDuration = recorder.liveDuration
        let previousLastEventTime = recorder.events.last?.time
        var insertedRange = clampedIndex..<clampedIndex
        var insertedEvents: [RecordedEvent] = []

        withUndo(String(localized: "Insert Reveal and Click Text", table: "EditorUX")) {
            insertedRange = recorder.events.insertRevealAndClickTextFlow(at: clampedIndex, preDelay: delay)
            if let explicitStartTime = placement.explicitStartTime {
                insertedEvents = retimeInsertedEvents(in: insertedRange, toStartTime: explicitStartTime)
            } else {
                insertedEvents = events(in: insertedRange)
            }
            recorder.liveDuration = recorder.events.liveDurationPreservingTrailingWait(
                previousLiveDuration: previousLiveDuration,
                previousLastEventTime: previousLastEventTime
            )
        }

        selectInsertedTextTargets(matching: insertedEvents, fallback: insertedRange)
    }

    @discardableResult
    func retimeInsertedEvents(in range: Range<Int>, toStartTime startTime: TimeInterval) -> [RecordedEvent] {
        guard startTime.isFinite,
              range.lowerBound >= 0,
              range.upperBound <= recorder.events.count,
              range.lowerBound < range.upperBound else {
            return []
        }
        let baseTime = recorder.events[range.lowerBound].time
        let delta = startTime - baseTime
        guard delta != 0 else { return events(in: range) }

        for index in range {
            recorder.events[index].time += delta
        }
        let retimedEvents = events(in: range)
        recorder.events.sortByTimePreservingOrder()
        if let lastTime = recorder.events.last?.time {
            recorder.liveDuration = max(recorder.liveDuration, lastTime)
        }
        return retimedEvents
    }

    func applyStretch() {
        let factor = stretchFactor
        guard actionTimeStretchReadiness(
            hasActions: !rows.isEmpty,
            factor: factor
        ).canApply else { return }

        withUndo(String(localized: "Time Stretch", table: "Common")) {
            let liveDuration = recorder.events.liveDurationAfterStretching(
                recorder.liveDuration,
                by: factor
            )
            recorder.events.scaleTime(by: factor)
            recorder.liveDuration = liveDuration
        }
        stretchFactor = 1.0
        _ = onRefreshRows()
        onLoadInspector()
        onUpdatePreview()
    }

    func shiftSelection(by delta: TimeInterval) {
        guard delta != 0 else { return }
        let selectedGroups = selectedGroups()
        let direction: ActionShiftDirection = delta < 0 ? .earlier : .later
        guard actionShiftReadiness(for: selectedGroups, direction: direction).canShift else { return }

        let allIndices = selectedGroups.flatMap(\.eventIndices)
        let indexSet = IndexSet(allIndices)
        let shiftPlan = recorder.events.timeShiftPlan(
            liveDuration: recorder.liveDuration,
            indices: indexSet,
            requestedDelta: delta
        )
        guard shiftPlan.canApply else { return }

        withUndo(String(localized: "Shift Actions", table: "EditorUX")) {
            recorder.events.shiftTime(of: indexSet, by: shiftPlan.delta)
            recorder.liveDuration = shiftPlan.liveDurationAfterShift
        }
    }

    func applyInspector() {
        guard selection.count == 1, let selectId = selection.first,
              let row = rows.first(where: { $0.id == selectId }) else { return }
        let grp = row.group
        var editedWaitTargets: [(start: TimeInterval, end: TimeInterval)] = []
        
        withUndo(String(localized: "Edit Action", table: "EditorUX")) {
            if grp.kind.isPassiveWait {
                if let t = finiteInspectorDouble(inspTime), t >= 0 {
                    let plan = ActionGroupPassiveWaitDurationEditPlanner.plan(
                        for: grp,
                        events: recorder.events,
                        liveDuration: recorder.liveDuration,
                        newDuration: t
                    )
                    recorder.events.applyPassiveWaitDurationEditPlan(plan)
                    if let liveDuration = plan.liveDurationAfterEdit {
                        recorder.liveDuration = liveDuration
                    }
                    if let start = plan.editedWaitStartTime,
                       let end = plan.editedWaitEndTime {
                        editedWaitTargets = [(start: start, end: end)]
                    }
                }
            } else {
                if let t = finiteInspectorDouble(inspTime), t >= 0 {
                    let indexSet = IndexSet(grp.eventIndices)
                    let shiftPlan = recorder.events.timeShiftPlan(
                        liveDuration: recorder.liveDuration,
                        indices: indexSet,
                        requestedDelta: t - grp.startTime
                    )
                    if shiftPlan.canApply {
                        recorder.events.shiftTime(of: indexSet, by: shiftPlan.delta)
                        recorder.liveDuration = shiftPlan.liveDurationAfterShift
                    }
                }
            }
            
            // Only point-target actions expose playback strategy. Keyboard,
            // wait, path, and behavior rows should not receive coordinate
            // strategy metadata as a side effect of editing their timing.
            let safeTimeout = nonNegativeInspectorDouble(inspTimeout)
            if grp.kind.editsSemanticTextTarget {
                let anchor = updatedAnchor(for: grp, text: inspOCRText)
                recorder.events.updateSemanticAction(
                    at: grp.eventIndices,
                    textAnchor: anchor,
                    timeout: safeTimeout,
                    verifyMustExist: inspVerifyMustExist,
                    fallbackPolicy: inspFallbackPolicy
                )
            } else if grp.kind.canUseLocatorStrategy {
                let anchor = inspStrategy == .locatorOnly && !inspOCRText.isEmpty
                    ? updatedAnchor(for: grp, text: inspOCRText)
                    : nil
                recorder.events.updateCoordinateStrategy(
                    at: grp.eventIndices,
                    strategy: inspStrategy,
                    textAnchor: anchor,
                    fallbackPolicy: inspFallbackPolicy,
                    textTimeout: inspStrategy == .locatorOnly ? safeTimeout : nil
                )
            }
            
            if (grp.kind.editsPointTarget || grp.kind.editsPathTarget), let sp = grp.startPoint {
                if inspStrategy != .locatorOnly,
                   let newX = finiteInspectorDouble(inspX),
                   let newY = finiteInspectorDouble(inspY) {
                    let deltaStart = CGPoint(x: CGFloat(newX) - sp.x, y: CGFloat(newY) - sp.y)
                    
                    var deltaEnd = deltaStart
                    if grp.kind.editsPathTarget, let ep = grp.endPoint,
                       let newEndX = finiteInspectorDouble(inspEndX),
                       let newEndY = finiteInspectorDouble(inspEndY) {
                        deltaEnd = CGPoint(x: CGFloat(newEndX) - ep.x, y: CGFloat(newEndY) - ep.y)
                    }
                    
                    recorder.events.translateEventsLinear(at: grp.eventIndices, startDelta: deltaStart, endDelta: deltaEnd, surfaces: surfaces)
                }
            }
            
            if grp.kind.editsKeyboardInput, let k = inspectorKeyCode(inspKey) {
                recorder.events.updateKeyStroke(at: grp.eventIndices, keyCode: k, flags: inspFlags)
            }
        }
        if !editedWaitTargets.isEmpty {
            selectWaits(matching: editedWaitTargets)
        } else {
            onLoadInspector()
            onUpdatePreview()
        }
    }

    func updatedAnchor(for group: ActionGroup, text: String) -> TextAnchor {
        TextTargetAnchorFactory.anchor(
            existing: firstEvent(for: group)?.textAnchor ?? group.textAnchor,
            text: text,
            fallbackEvent: firstEvent(for: group)
        )
    }

    func convertClickType(grp: ActionGroup, newKind: ActionGroupKind) {
        guard grp.kind != newKind else { return }
        let previousLiveDuration = recorder.liveDuration
        let previousLastEventTime = recorder.events.last?.time
        withUndo(String(localized: "Convert Action Type", table: "EditorUX")) {
            let indices = grp.eventIndices
            guard !indices.isEmpty else { return }

            recorder.events.convertClickType(at: indices, from: grp.kind, to: newKind)
            recorder.liveDuration = recorder.events.liveDurationPreservingTrailingWait(
                previousLiveDuration: previousLiveDuration,
                previousLastEventTime: previousLastEventTime
            )
        }
        onLoadInspector()
        onUpdatePreview()
    }
    
    enum Axis { case x, y }

    func coordinateAlignmentReadiness(axis: Axis) -> BatchCoordinateAlignmentReadiness {
        batchCoordinateAlignmentReadiness(
            for: selectedGroups(),
            alignsXCoordinate: axis == .x
        )
    }
    
    func alignSelectedCoordinates(axis: Axis) {
        let selectedGroups = selectedGroups()
        guard coordinateAlignmentReadiness(axis: axis).canAlign,
              let firstGrp = selectedGroups.first,
              let sp = firstGrp.startPoint else {
            return
        }
        
        let targetVal = axis == .x ? sp.x : sp.y
        var didChange = false
        
        withUndo(String(localized: "Align Coordinates", table: "Common")) {
            for grp in selectedGroups.dropFirst() {
                guard let cp = grp.startPoint else { continue }
                let deltaX = axis == .x ? (targetVal - cp.x) : 0
                let deltaY = axis == .y ? (targetVal - cp.y) : 0
                if deltaX != 0 || deltaY != 0 {
                    recorder.events.translateEventsLinear(
                        at: grp.eventIndices,
                        startDelta: CGPoint(x: deltaX, y: deltaY),
                        endDelta: CGPoint(x: deltaX, y: deltaY),
                        surfaces: surfaces
                    )
                    didChange = true
                }
            }
        }
        if didChange {
            onLoadInspector()
            onUpdatePreview()
        }
    }
    
    func applyBatchTimeout() {
        let selectedGroups = selectedGroups()
        guard batchTimeoutReadiness(
            for: selectedGroups,
            events: recorder.events,
            timeout: inspTimeout
        ).canApply, let timeout = nonNegativeInspectorDouble(inspTimeout) else {
            return
        }
        let editableGroups = batchTimeoutEditableGroups(for: selectedGroups, events: recorder.events)
        withUndo(String(localized: "Batch Set Timeout", table: "Common")) {
            for grp in editableGroups {
                if grp.kind.editsSemanticTextTarget {
                    let anchor = firstEvent(for: grp)?.textAnchor ?? grp.textAnchor
                    recorder.events.updateSemanticAction(
                        at: grp.eventIndices,
                        textAnchor: anchor,
                        timeout: timeout,
                        verifyMustExist: firstEvent(for: grp)?.verifyMustExist,
                        fallbackPolicy: firstEvent(for: grp)?.locatorFallbackPolicy
                    )
                } else if ActionGroupProjection.isTextTargetGroup(
                    grp,
                    events: recorder.events,
                    includesCoordinateClickCandidates: false
                ) {
                    let anchor = firstEvent(for: grp)?.textAnchor ?? grp.textAnchor
                    recorder.events.updateCoordinateStrategy(
                        at: grp.eventIndices,
                        strategy: .locatorOnly,
                        textAnchor: anchor,
                        fallbackPolicy: firstEvent(for: grp)?.locatorFallbackPolicy,
                        textTimeout: timeout
                    )
                }
            }
        }
        onLoadInspector()
        onUpdatePreview()
    }

    func applyBatchTextTarget() {
        let targetGroups = selectedTextTargetGroups()
        guard batchTextTargetReadiness(for: targetGroups, targetText: inspOCRText).canApply else {
            return
        }

        withUndo(String(localized: "Batch Set Text Target", table: "EditorUX")) {
            for group in targetGroups {
                let anchor = updatedAnchor(for: group, text: inspOCRText)
                if group.kind.editsSemanticTextTarget {
                    recorder.events.updateSemanticAction(
                        at: group.eventIndices,
                        textAnchor: anchor,
                        timeout: inspTimeout,
                        verifyMustExist: group.verifyMustExist ?? true,
                        fallbackPolicy: firstEvent(for: group)?.locatorFallbackPolicy
                    )
                } else {
                    recorder.events.updateCoordinateStrategy(
                        at: group.eventIndices,
                        strategy: .locatorOnly,
                        textAnchor: anchor,
                        fallbackPolicy: firstEvent(for: group)?.locatorFallbackPolicy ?? inspFallbackPolicy,
                        textTimeout: inspTimeout
                    )
                }
            }
        }
        onLoadInspector()
        onUpdatePreview()
    }
}

struct TargetTextEditorInnerView: View {
    @Binding var text: String
    let onPick: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            TextField(String(localized: "e.g. Confirm", table: "Common"), text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .controlSize(.small)
            
            Button(action: onPick) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(localized: "Pick text from screen", table: "Recording"))
        }
    }
}

struct TargetTextEditorView: View {
    @Binding var text: String
    let onPick: () -> Void
    var body: some View {
        TargetTextEditorInnerView(text: $text, onPick: onPick)
    }
}

struct AnchorPositionCard: View {
    let anchor: TextAnchor
    let fallbackPolicy: LocatorFallbackPolicy
    
    private var hasContentLock: Bool {
        anchor.observedContentNormalizedFrame != nil || anchor.searchContentNormalizedRegion != nil || anchor.coordinateFallbackContentNormalized != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: hasContentLock ? "rectangle.inset.filled.and.person.filled" : "display")
                    .foregroundStyle(Brand.sigAmber)
                Text(hasContentLock ? String(localized: "Content-locked target", table: "Common") : String(localized: "Screen target", table: "Recording"))
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text(fallbackPolicy == .allowCoordinateFallback ? String(localized: "Fallback on", table: "Common") : String(localized: "Pause on miss", table: "Common"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Detected Text", tableName: "EditorUX")
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(anchor.text)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
            
            Divider()
            
            positionRow(color: Brand.sigGreen, title: String(localized: "Text box", table: "EditorUX"), value: rectSummary(anchor.observedFrame))
            if let normalized = anchor.observedContentNormalizedFrame {
                positionRow(color: Brand.sigBlue, title: String(localized: "Content lock", table: "Common"), value: normalizedRectSummary(normalized))
            }
            if let search = anchor.searchRegion {
                positionRow(color: Brand.sigAmber, title: String(localized: "Search region", table: "EditorUX"), value: rectSummary(search))
            }
            if let fallback = anchor.coordinateFallback {
                positionRow(color: Brand.sigViolet, title: String(localized: "Fallback point", table: "Common"), value: pointSummary(fallback))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(.rect(cornerRadius: 7))
    }
    
    @ViewBuilder
    private func positionRow(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9.8, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 9.8, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
    
    private func rectSummary(_ rect: RectValue) -> String {
        "\(Int(rect.x)),\(Int(rect.y))  \(Int(rect.width))×\(Int(rect.height))"
    }
    
    private func normalizedRectSummary(_ rect: RectValue) -> String {
        "\(Int((rect.x * 100).rounded()))%,\(Int((rect.y * 100).rounded()))%  \(Int((rect.width * 100).rounded()))%×\(Int((rect.height * 100).rounded()))%"
    }
    
    private func pointSummary(_ point: PointValue) -> String {
        "\(Int(point.x)),\(Int(point.y))"
    }
}
