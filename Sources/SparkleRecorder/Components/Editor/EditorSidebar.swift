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
    let recorder: Recorder
    let surfaces: [String: PlaybackSurface]
    let onLoadInspector: () -> Void
    let onUpdatePreview: () -> Void
    let onPickCoordinate: (Bool) -> Void
    let onAddClickPoint: () -> Void
    let onPickText: () -> Void
    let onRefreshRows: () -> [ActionRow]

    @State private var insertWaitMs: Double = 1000
    @State private var confirmClearAll = false
    @Environment(\.undoManager) private var undoManager

    struct ActionInsertionPlacement {
        var eventIndex: Int
        var explicitStartTime: TimeInterval?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
		                // Section 1: Action setup (target, playback strategy, and position)
		                section(NSLocalizedString("Selected action", comment: ""), icon: "slider.horizontal.3") {
	                    if selection.count == 1, let id = selection.first,
	                       let row = rows.first(where: { $0.id == id }) {
	                        let grp = row.group
	                        let firstEvent = firstEvent(for: grp)
	                        HStack {
                            Image(systemName: actionKindIcon(grp.kind))
                                .foregroundStyle(actionKindColor(grp.kind))
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 0) {
                                let actionNumber = (rows.firstIndex(where: { $0.id == id }) ?? 0) + 1
                                Text(String(format: NSLocalizedString("Action #%d", comment: ""), actionNumber))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(humanActionKindName(grp.kind))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
	                            }
	                        }
                            workflowHint(for: grp, event: firstEvent)
	 
		                        inspectorGrid {
			                            labeledField(grp.kind.isPassiveWait ? NSLocalizedString("Wait Duration (s)", comment: "") : NSLocalizedString("Time (s)", comment: ""), text: $inspTime)
		                        
		                            if grp.kind == .waitForText {
		                                labeledDoubleField(NSLocalizedString("Timeout (s)", comment: ""), value: $inspTimeout)
		                            }
		                        
			                            if grp.kind.canUseLocatorStrategy {
		                                gridField(NSLocalizedString("Strategy", comment: "")) {
		                                    Picker("", selection: Binding(
		                                        get: { inspStrategy },
		                                        set: { inspStrategy = $0; applyInspector() }
		                                    )) {
		                                        Text(NSLocalizedString("Offset", comment: "")).tag(CoordinateStrategy.windowLocalPreferred)
		                                        Text(NSLocalizedString("Proportional", comment: "")).tag(CoordinateStrategy.normalizedPreferred)
		                                        Text(NSLocalizedString("Absolute", comment: "")).tag(CoordinateStrategy.absoluteOnly)
		                                        Text(NSLocalizedString("Text (OCR)", comment: "")).tag(CoordinateStrategy.locatorOnly)
		                                    }
		                                    .pickerStyle(.segmented)
		                                    .labelsHidden()
		                                    .controlSize(.small)
		                                }
		                                
		                                if inspStrategy == .locatorOnly {
		                                    labeledDoubleField(NSLocalizedString("Timeout (s)", comment: ""), value: $inspTimeout)
		                                    gridField(NSLocalizedString("Target Text", comment: "")) {
		                                        TargetTextEditorInnerView(text: Binding(get: { inspOCRText }, set: { inspOCRText = $0; applyInspector() }), onPick: onPickText)
		                                    }
		                                    gridField(NSLocalizedString("Fallback", comment: "")) {
		                                        locatorPlaybackPolicyView()
		                                    }
		                                } else {
		                                    labeledField("X", text: $inspX)
		                                    labeledField("Y", text: $inspY)
		                                }
			                            } else if grp.kind.editsPathTarget {
		                                gridField(NSLocalizedString("Start", comment: "")) { Text("") }
		                                labeledField("X", text: $inspX)
		                                labeledField("Y", text: $inspY)
		                                gridField(NSLocalizedString("End", comment: "")) { Text("") }
		                                labeledField("X", text: $inspEndX)
		                                labeledField("Y", text: $inspEndY)
		                            }
		                        
			                            if grp.kind.editsKeyboardInput {
		                                gridField(NSLocalizedString("Key code", comment: "")) {
		                                    ShortcutRecorderField(
		                                        currentBinding: keyboardShortcutBinding(for: grp),
		                                        allHotkeys: [],
		                                        allowsClear: false,
		                                        recordingPrompt: NSLocalizedString("Press any key…", comment: ""),
		                                        emptyPrompt: NSLocalizedString("Click to record shortcut", comment: ""),
		                                        onRecord: applyRecordedShortcut
		                                    )
		                                }
		                                labeledField(NSLocalizedString("Raw Code", comment: ""), text: $inspKey)
			                            } else if grp.kind.editsSemanticTextTarget {
			                                gridField(NSLocalizedString("Target Text", comment: "")) {
			                                    TargetTextEditorInnerView(text: Binding(get: { inspOCRText }, set: { inspOCRText = $0; applyInspector() }), onPick: onPickText)
			                                }
                                if grp.kind == .waitForText || grp.kind == .waitForTextGone || grp.kind == .verifyText {
			                                    gridField(NSLocalizedString("Must Exist", comment: "")) {
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

                                if grp.kind == .multiPointClick {
                                    multiPointClickEditor(for: grp)
                                }

                                if grp.kind.canConvertClickType {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(NSLocalizedString("Action Type", comment: ""))
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Picker("", selection: Binding(
                                            get: { grp.kind },
                                            set: { convertClickType(grp: grp, newKind: $0) }
                                        )) {
                                            Text(NSLocalizedString("Click", comment: "")).tag(ActionGroupKind.click)
                                            Text(NSLocalizedString("Double", comment: "")).tag(ActionGroupKind.doubleClick)
                                            Text(NSLocalizedString("Triple+", comment: "")).tag(ActionGroupKind.repeatedClick)
                                            Text(NSLocalizedString("Long Press", comment: "")).tag(ActionGroupKind.longPress)
                                        }
                                        .pickerStyle(.segmented)
                                        .labelsHidden()
                                        .controlSize(.small)
                                    }
                                }

                                if grp.kind.canRetargetCoordinate && inspStrategy != .locatorOnly {
                                    Button(action: { onPickCoordinate(false) }) {
                                        Label(NSLocalizedString("Retarget Coordinate", comment: ""), systemImage: "scope")
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
                                    Button {
                                        insertClickTextAfterSelectedWait(grp)
                                    } label: {
                                        Label(NSLocalizedString("Add Click Text", comment: ""), systemImage: "cursorarrow.click")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(NSLocalizedString("Reuse this wait target for the next text click.", comment: ""))

                                    Button {
                                        convertWaitToClickText(grp)
                                    } label: {
                                        Label(NSLocalizedString("Convert to Click Text", comment: ""), systemImage: "cursorarrow.click")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(NSLocalizedString("Replace this wait with a text click using the same target.", comment: ""))
                                }
                    } else if selection.count > 1 {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(String(format: NSLocalizedString("Batch edit %d actions", comment: ""), selection.count))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Brand.sigBlue)

                            if !selectedTextTargetGroups().isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NSLocalizedString("Shared Text Target", comment: ""))
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    TargetTextEditorInnerView(
                                        text: Binding(
                                            get: { inspOCRText },
                                            set: { inspOCRText = $0 }
                                        ),
                                        onPick: onPickText
                                    )
                                    HStack(spacing: 6) {
                                        labeledInlineDoubleField(NSLocalizedString("Timeout", comment: ""), value: $inspTimeout)
                                        Button(NSLocalizedString("Apply to Selected", comment: "")) { applyBatchTextTarget() }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NSLocalizedString("Align Coordinates", comment: ""))
                                     .font(.system(size: 9.5, weight: .semibold))
                                     .foregroundStyle(.secondary)
                                HStack {
                                     Button(NSLocalizedString("Align X to First", comment: "")) { alignSelectedCoordinates(axis: .x) }
                                     Button(NSLocalizedString("Align Y to First", comment: "")) { alignSelectedCoordinates(axis: .y) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NSLocalizedString("Standardize Timeout", comment: ""))
                                     .font(.system(size: 9.5, weight: .semibold))
                                     .foregroundStyle(.secondary)
                                HStack {
                                     TextField("s", text: Binding(
                                         get: { String(format: "%.2f", inspTimeout) },
                                         set: { if let v = Double($0) { inspTimeout = v } }
                                     ))
                                     .textFieldStyle(.roundedBorder)
                                     .font(.system(.callout, design: .monospaced))
                                     .controlSize(.small)
                                     .frame(width: 60)
                                     
                                     Button(NSLocalizedString("Apply to Selected", comment: "")) { applyBatchTimeout() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        emptyInspector(
                            icon: "hand.tap",
                            title: NSLocalizedString("No selection", comment: ""),
                            subtitle: NSLocalizedString("Click a row to inspect or edit", comment: "")
                        )
                    }
                }

                // Section 2: Selection / Edit Actions
                section(NSLocalizedString("Selection", comment: ""), icon: "checklist") {
                    HStack(spacing: 6) {
                        Button(action: deleteSelected) {
                            Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(.delete, modifiers: [])

                        Button(action: duplicateSelected) {
                            Label(NSLocalizedString("Duplicate", comment: ""), systemImage: "plus.square.on.square")
                                .frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut("d", modifiers: .command)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selection.isEmpty)
                    
                    HStack(spacing: 6) {
                        Button(action: bindSelectedBehavior) {
                            Label(NSLocalizedString("Bind behavior", comment: ""), systemImage: "square.stack.3d.down.right")
                        }
                        .frame(maxWidth: .infinity)
                        .help(NSLocalizedString("Show selected actions as one behavior block", comment: ""))
                        .disabled(!canBindSelection)
                        
                        Button(action: unbindSelectedBehavior) {
                            Label(NSLocalizedString("Unbind", comment: ""), systemImage: "square.stack.3d.down.forward")
                        }
                        .frame(maxWidth: .infinity)
                        .help(NSLocalizedString("Show behavior events as separate actions again", comment: ""))
                        .disabled(!canUnbindSelection)
                    }
                    .controlSize(.small)

                    HStack(spacing: 6) {
                        Button(action: trimBefore) {
                            Label(NSLocalizedString("Trim before", comment: ""), systemImage: "arrow.left.to.line")
                        }
                        .frame(maxWidth: .infinity)
                        .help(NSLocalizedString("Delete every event before the selected one", comment: ""))

                        Button(action: trimAfter) {
                            Label(NSLocalizedString("Trim after", comment: ""), systemImage: "arrow.right.to.line")
                        }
                        .frame(maxWidth: .infinity)
                        .help(NSLocalizedString("Delete every event after the selected one", comment: ""))
                    }
                    .controlSize(.small)
                    .disabled(selection.count != 1)

                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Label(NSLocalizedString("Clear all", comment: ""), systemImage: "trash.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(rows.isEmpty)
                    .confirmationDialog(
                        NSLocalizedString("Remove all events from this macro?", comment: ""),
                        isPresented: $confirmClearAll,
                        titleVisibility: .visible
                    ) {
                        Button(NSLocalizedString("Clear All Events", comment: ""), role: .destructive) { clearAll() }
                        Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
                    } message: {
                        Text(NSLocalizedString("You can undo this with ⌘Z while the editor is open.", comment: ""))
                    }
                }

                // Section 3: Insert Action
                section(NSLocalizedString("Insert action", comment: ""), icon: "plus.square") {
                    insertionTargetView()
                    
                    HStack(spacing: 6) {
                        Stepper(value: $insertWaitMs, in: 50...60000, step: 100) {
                            Text("\(Int(insertWaitMs)) ms")
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        }
                        .controlSize(.small)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        // Row 1: Basic Input
                        insertActionButton(
                            title: NSLocalizedString("Click", comment: ""),
                            subtitle: NSLocalizedString("Fixed point", comment: ""),
                            icon: "hand.point.up.left",
                            tint: Brand.sigGreen
                        ) { insertAction(.click) }
                        
                        insertActionButton(
                            title: NSLocalizedString("Key", comment: ""),
                            subtitle: NSLocalizedString("Keyboard", comment: ""),
                            icon: "keyboard",
                            tint: Brand.sigBlue
                        ) { insertAction(.keyPress) }

                        // Row 2: Extended Mouse
                        insertActionButton(
                            title: NSLocalizedString("Double Click", comment: ""),
                            subtitle: NSLocalizedString("Fixed point", comment: ""),
                            icon: "cursorarrow.click.2",
                            tint: Brand.sigGreen
                        ) { insertAction(.doubleClick) }

                        insertActionButton(
                            title: NSLocalizedString("Drag", comment: ""),
                            subtitle: NSLocalizedString("Path", comment: ""),
                            icon: "hand.draw",
                            tint: Brand.sigBlue
                        ) { insertAction(.drag) }

                        // Row 3: Navigation & Timing
                        insertActionButton(
                            title: NSLocalizedString("Scroll", comment: ""),
                            subtitle: NSLocalizedString("Wheel", comment: ""),
                            icon: "arrow.up.and.down",
                            tint: Brand.sigBlue
                        ) { insertAction(.scroll) }

                        insertActionButton(
                            title: NSLocalizedString("Wait", comment: ""),
                            subtitle: NSLocalizedString("Delay", comment: ""),
                            icon: "hourglass",
                            tint: .secondary
                        ) { insertAction(.wait) }

                        // Row 4: Vision & OCR Clicks
                        insertActionButton(
                            title: NSLocalizedString("Click Text", comment: ""),
                            subtitle: NSLocalizedString("Wait then click", comment: ""),
                            icon: "text.cursor",
                            tint: Brand.sigTeal
                        ) { insertTextClick() }

                        insertActionButton(
                            title: NSLocalizedString("Reveal & Click", comment: ""),
                            subtitle: NSLocalizedString("Vision flow", comment: ""),
                            icon: "sparkles.rectangle.stack",
                            tint: Brand.sigTeal
                        ) { insertRevealAndClickTextFlow() }

                        // Row 5: Vision Waits
                        insertActionButton(
                            title: NSLocalizedString("Wait Text", comment: ""),
                            subtitle: NSLocalizedString("Wait to appear", comment: ""),
                            icon: "text.magnifyingglass",
                            tint: Brand.sigViolet
                        ) { insertAction(.waitForText) }

                        insertActionButton(
                            title: NSLocalizedString("Wait Text Gone", comment: ""),
                            subtitle: NSLocalizedString("Wait to disappear", comment: ""),
                            icon: "text.badge.minus",
                            tint: Brand.sigAmber
                        ) { insertAction(.waitForTextGone) }

                        // Row 6: Verification & Misc
                        insertActionButton(
                            title: NSLocalizedString("Verify Text", comment: ""),
                            subtitle: NSLocalizedString("Checkpoint", comment: ""),
                            icon: "checkmark.seal",
                            tint: Brand.sigAmber
                        ) { insertAction(.verifyText) }

                        insertActionButton(
                            title: NSLocalizedString("Multi Click", comment: ""),
                            subtitle: NSLocalizedString("Several points", comment: ""),
                            icon: "point.3.connected.trianglepath.dotted",
                            tint: Brand.sigPink
                        ) { insertAction(.multiPointClick) }
                    }
                }

                // Section 4: Time Adjustments (Merged Shift & Stretch)
                section(NSLocalizedString("Time Adjustments", comment: ""), icon: "timer") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Shift Selected", comment: ""))
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
                                .disabled(selection.isEmpty)

                                Button(action: { shiftSelection(by: shiftMs / 1000.0) }) {
                                    Image(systemName: "goforward")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .disabled(selection.isEmpty)
                            }
                            .controlGroupStyle(.navigation)
                            .controlSize(.small)
                        }
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(NSLocalizedString("Time Stretch", comment: ""))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f×", stretchFactor))
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        }
                        Slider(value: $stretchFactor, in: 0.25...4.0, step: 0.05)
                            .controlSize(.small)
                        HStack {
                            Button(NSLocalizedString("Reset", comment: "")) { stretchFactor = 1.0 }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            Spacer()
                            Button(NSLocalizedString("Apply", comment: "")) { applyStretch() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(rows.isEmpty || abs(stretchFactor - 1.0) < 0.001)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
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
                if let parsed = Double(newValue) {
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
                    if let parsed = Double(newValue) {
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
            Text(NSLocalizedString("Playback if text is missing", comment: ""))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { inspFallbackPolicy },
                set: { inspFallbackPolicy = $0; applyInspector() }
            )) {
                Text(NSLocalizedString("Pause", comment: "")).tag(LocatorFallbackPolicy.fail)
                Text(NSLocalizedString("Use fallback point", comment: "")).tag(LocatorFallbackPolicy.allowCoordinateFallback)
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
            return NSLocalizedString("No target text", comment: "")
        case .missingAnchor, .notTextTarget:
            return NSLocalizedString("No text target", comment: "")
        case .ready:
            return NSLocalizedString("Text target ready", comment: "")
        }
    }

    func textTargetReadinessDetail(_ readiness: TextTargetReadiness) -> String {
        switch readiness {
        case .missingText:
            return NSLocalizedString("Pick text or type a non-empty target.", comment: "")
        case .missingAnchor, .notTextTarget:
            return NSLocalizedString("Pick text to create a searchable target.", comment: "")
        case .ready:
            return NSLocalizedString("Playback will use the matched text target.", comment: "")
        }
    }

    @ViewBuilder
    func multiPointClickEditor(for group: ActionGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Click Points", comment: ""))
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

            HStack(spacing: 6) {
                Button {
                    onAddClickPoint()
                } label: {
                    Label(NSLocalizedString("Add Point", comment: ""), systemImage: "plus")
                }
                .frame(maxWidth: .infinity)

                Button {
                    removeLastMultiClickPoint(group)
                } label: {
                    Label(NSLocalizedString("Remove Last", comment: ""), systemImage: "minus")
                }
                .frame(maxWidth: .infinity)
                .disabled(points.count <= 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    @ViewBuilder
    func insertionTargetView() -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.sigGreen)
            Text(insertionTargetLabel())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(.rect(cornerRadius: 7))
    }
    
    func insertionTargetLabel() -> String {
        guard let anchor = insertionAnchor() else {
            return NSLocalizedString("Append at end", comment: "")
        }
        if selection.count > 1 {
            return String(format: NSLocalizedString("Insert after selection, ending at #%d", comment: ""), anchor.order + 1)
        }
        return String(format: NSLocalizedString("Insert after #%d", comment: ""), anchor.order + 1)
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
    
    func selectedEventIndices() -> [Int] {
        selectionSnapshot.eventIndices
    }
    
    func nextBehaviorName() -> String {
        let existing = recorder.events.compactMap(\.behaviorGroupID).reduce(into: Set<BehaviorGroupID>()) { partial, id in
            partial.insert(id)
        }
        return String(format: NSLocalizedString("Behavior %d", comment: ""), existing.count + 1)
    }
    
    func bindSelectedBehavior() {
        let indices = selectedEventIndices()
        guard indices.count >= 2 else { return }
        let id = BehaviorGroupID()
        let name = nextBehaviorName()
        
        withUndo(NSLocalizedString("Bind Behavior", comment: "")) {
            recorder.events.bindBehavior(at: indices, id: id, name: name)
        }
        
        selectBehavior(id)
    }
    
    func unbindSelectedBehavior() {
        let indices = selectedEventIndices()
        guard !indices.isEmpty, canUnbindSelection else { return }
        
        withUndo(NSLocalizedString("Unbind Behavior", comment: "")) {
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
        let snapshot = recorder.events
        let snapshotDur = recorder.liveDuration
        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] r in
            let redoSnapshot = r.events
            let redoDur = r.liveDuration
            r.loadEvents(snapshot, duration: snapshotDur)
            undoManager?.registerUndo(withTarget: r) { r2 in
                r2.loadEvents(redoSnapshot, duration: redoDur)
            }
        }
        undoManager?.setActionName(name)
        mutate()
        recorder.recalculateStats()
    }

    func duplicateSelected() {
        let selectedGroups = selection.compactMap { groupID -> ActionGroup? in
            rows.first(where: { $0.id == groupID })?.group
        }
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
        
        withUndo(NSLocalizedString("Duplicate Action", comment: "")) {
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
            selectInsertedEvents(in: copiesRange)
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
        let plan = ActionGroupDeletionPlanner.plan(
            for: selectedGroups,
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        guard !plan.isEmpty else { return }
        
        selection.removeAll()
        withUndo(NSLocalizedString("Delete Actions", comment: "")) {
            recorder.events.applyActionGroupDeletionPlan(plan)
            if let liveDuration = plan.liveDurationAfterDeletion {
                recorder.liveDuration = liveDuration
            }
        }
    }

    func trimBefore() {
        guard selection.count == 1, let id = selection.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        let grp = row.group
        let cutoff = max(0, grp.startTime)
        guard cutoff > 0 else { return }
        withUndo(NSLocalizedString("Trim Before", comment: "")) {
            recorder.events.removeAll { $0.time < cutoff }
            for idx in recorder.events.indices {
                recorder.events[idx].time = max(0, recorder.events[idx].time - cutoff)
            }
            recorder.liveDuration = max(0, recorder.liveDuration - cutoff)
        }
        selection = []
    }

    func trimAfter() {
        guard selection.count == 1, let id = selection.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        let grp = row.group
        let cutoff = max(0, grp.endTime)
        let epsilon: TimeInterval = 0.000_001
        let shouldRemove: (RecordedEvent) -> Bool = { event in
            if grp.kind.isPassiveWait {
                return event.time >= cutoff - epsilon
            }
            return event.time > cutoff + epsilon
        }
        guard recorder.events.contains(where: shouldRemove) || recorder.liveDuration > cutoff + epsilon else { return }
        withUndo(NSLocalizedString("Trim After", comment: "")) {
            recorder.events.removeAll(where: shouldRemove)
            recorder.liveDuration = cutoff
        }
        selection = []
    }

    func clearAll() {
        selection.removeAll()
        withUndo(NSLocalizedString("Clear All Events", comment: "")) {
            recorder.clearAll()
        }
    }

    func removeLastMultiClickPoint(_ group: ActionGroup) {
        guard group.kind == .multiPointClick, group.eventIndices.count > 2 else { return }
        withUndo(NSLocalizedString("Remove Click Point", comment: "")) {
            recorder.events.removeLastMultiPointClick(at: group.eventIndices)
        }
        onLoadInspector()
        onUpdatePreview()
    }

	    func insertAction(_ kind: ActionGroupKind) {
	        let placement = insertionPlacementAfterSelection()
	        let idx = placement.eventIndex
	        let clampedIndex = max(0, min(idx, recorder.events.count))
        let insertedCount = kind.insertedEventCount
        let waitDelta = max(0, insertWaitMs / 1000.0)
        let waitStart = clampedIndex > 0 ? recorder.events[clampedIndex - 1].time : 0
        let waitEnd: TimeInterval = {
            if clampedIndex < recorder.events.count {
                return recorder.events[clampedIndex].time + waitDelta
            }
            return max(recorder.liveDuration, recorder.events.last?.time ?? 0) + waitDelta
        }()
        
        withUndo(String(format: NSLocalizedString("Insert %@", comment: ""), humanActionKindName(kind))) {
            switch kind {
            case .wait:
                recorder.events.insertWait(at: clampedIndex, milliseconds: insertWaitMs)
                if clampedIndex >= recorder.events.count, waitDelta > 0 {
                    recorder.liveDuration = max(recorder.liveDuration, recorder.events.last?.time ?? 0) + waitDelta
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
                retimeInsertedEvents(in: clampedIndex..<(clampedIndex + insertedCount), toStartTime: explicitStartTime)
            }
        }
        
        if kind.isPassiveWait {
            selectInsertedWait(start: waitStart, end: waitEnd)
	        } else if insertedCount > 0 {
	            selectInsertedEvents(in: clampedIndex..<(clampedIndex + insertedCount))
	        }
	    }
    
    func insertTextClick() {
        let placement = insertionPlacementAfterSelection()
        let idx = placement.eventIndex
        let clampedIndex = max(0, min(idx, recorder.events.count))
        
        withUndo(NSLocalizedString("Insert Click Text", comment: "")) {
            recorder.events.insertTextClick(at: clampedIndex)
            if let explicitStartTime = placement.explicitStartTime {
                retimeInsertedEvents(in: clampedIndex..<(clampedIndex + 2), toStartTime: explicitStartTime)
            }
        }
        
        selectInsertedEvents(in: clampedIndex..<(clampedIndex + 2))
    }

    func insertClickTextAfterSelectedWait(_ group: ActionGroup) {
        guard group.kind == .waitForText,
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
        var insertedRange = insertionIndex..<insertionIndex

        withUndo(NSLocalizedString("Add Click Text After Wait", comment: "")) {
            insertedRange = recorder.events.insertTextClick(
                at: insertionIndex,
                textAnchor: anchor,
                textTimeout: timeout,
                fallbackPolicy: fallbackPolicy,
                surfaceId: sourceEvent.surfaceId
            )
        }

        selectWaitAndInsertedTextClick(waitEventIndices: group.eventIndices, insertedRange: insertedRange)
    }

    func convertWaitToClickText(_ group: ActionGroup) {
        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: group,
            events: recorder.events,
            liveDuration: recorder.liveDuration,
            fallbackPolicy: firstEvent(for: group)?.locatorFallbackPolicy ?? inspFallbackPolicy
        )
        guard !plan.isEmpty else { return }

        let insertedEvents = plan.insertedEvents
        withUndo(NSLocalizedString("Convert Wait to Click Text", comment: "")) {
            recorder.events.applyTextClickConversionPlan(plan)
            if let liveDuration = plan.liveDurationAfterConversion {
                recorder.liveDuration = liveDuration
            }
        }

        selectEvents(matching: insertedEvents)
    }

    func selectWaitAndInsertedTextClick(waitEventIndices: [Int], insertedRange: Range<Int>) {
        DispatchQueue.main.async {
            let waitIndexSet = Set(waitEventIndices)
            let groups = self.onRefreshRows().map(\.group)
            let targets = groups.filter { group in
                let isSourceWait = group.eventIndices.contains { waitIndexSet.contains($0) }
                let isInsertedClick = group.eventIndices.contains { insertedRange.contains($0) }
                return (isSourceWait || isInsertedClick) && self.isTextTargetGroup(group)
            }
            if !targets.isEmpty {
                self.selection = Set(targets.map(\.id))
                DispatchQueue.main.async {
                    self.onLoadInspector()
                    self.onUpdatePreview()
                }
            } else {
                self.selectInsertedEvents(in: insertedRange)
            }
        }
    }

    func selectEvents(matching eventsToSelect: [RecordedEvent]) {
        guard !eventsToSelect.isEmpty else { return }

        DispatchQueue.main.async {
            var remaining = eventsToSelect
            var matchedEventIndices = Set<Int>()

            for (index, event) in self.recorder.events.enumerated() {
                guard let matchIndex = remaining.firstIndex(of: event) else { continue }
                matchedEventIndices.insert(index)
                remaining.remove(at: matchIndex)
                if remaining.isEmpty { break }
            }

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
        var insertedRange = clampedIndex..<clampedIndex

        withUndo(NSLocalizedString("Insert Reveal and Click Text", comment: "")) {
            insertedRange = recorder.events.insertRevealAndClickTextFlow(at: clampedIndex, preDelay: delay)
            if let explicitStartTime = placement.explicitStartTime {
                retimeInsertedEvents(in: insertedRange, toStartTime: explicitStartTime)
            }
        }

        selectInsertedTextTargets(in: insertedRange)
    }

    func retimeInsertedEvents(in range: Range<Int>, toStartTime startTime: TimeInterval) {
        guard startTime.isFinite,
              range.lowerBound >= 0,
              range.upperBound <= recorder.events.count,
              range.lowerBound < range.upperBound else {
            return
        }
        let baseTime = recorder.events[range.lowerBound].time
        let delta = startTime - baseTime
        guard delta != 0 else { return }

        for index in range {
            recorder.events[index].time += delta
        }
        recorder.events.sortByTimePreservingOrder()
        if let lastTime = recorder.events.last?.time {
            recorder.liveDuration = max(recorder.liveDuration, lastTime)
        }
    }

    func applyStretch() {
        let factor = stretchFactor
        withUndo(NSLocalizedString("Time Stretch", comment: "")) {
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
        var allIndices: [Int] = []
        for groupID in selection {
            if let row = rows.first(where: { $0.id == groupID }) {
                allIndices.append(contentsOf: row.group.eventIndices)
            }
        }
        guard !allIndices.isEmpty else { return }
        withUndo(NSLocalizedString("Shift Actions", comment: "")) {
            recorder.events.shiftTime(of: IndexSet(allIndices), by: delta)
        }
    }

    func applyInspector() {
        guard selection.count == 1, let selectId = selection.first,
              let row = rows.first(where: { $0.id == selectId }) else { return }
        let grp = row.group
        var editedWaitTargets: [(start: TimeInterval, end: TimeInterval)] = []
        
        withUndo(NSLocalizedString("Edit Action", comment: "")) {
            if grp.kind.isPassiveWait {
                if let t = TimeInterval(inspTime) {
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
                if let t = TimeInterval(inspTime) {
                    let delta = t - grp.startTime
                    recorder.events.shiftTime(of: IndexSet(grp.eventIndices), by: delta)
                }
            }
            
            // Only point-target actions expose playback strategy. Keyboard,
            // wait, path, and behavior rows should not receive coordinate
            // strategy metadata as a side effect of editing their timing.
            if grp.kind.editsSemanticTextTarget {
                let anchor = updatedAnchor(for: grp, text: inspOCRText)
                recorder.events.updateSemanticAction(
                    at: grp.eventIndices,
                    textAnchor: anchor,
                    timeout: inspTimeout,
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
                    textTimeout: inspStrategy == .locatorOnly ? inspTimeout : nil
                )
            }
            
            if (grp.kind.editsPointTarget || grp.kind.editsPathTarget), let sp = grp.startPoint {
                if inspStrategy != .locatorOnly, let newX = Double(inspX), let newY = Double(inspY) {
                    let deltaStart = CGPoint(x: CGFloat(newX) - sp.x, y: CGFloat(newY) - sp.y)
                    
                    var deltaEnd = deltaStart
                    if grp.kind.editsPathTarget, let ep = grp.endPoint,
                       let newEndX = Double(inspEndX), let newEndY = Double(inspEndY) {
                        deltaEnd = CGPoint(x: CGFloat(newEndX) - ep.x, y: CGFloat(newEndY) - ep.y)
                    }
                    
                    recorder.events.translateEventsLinear(at: grp.eventIndices, startDelta: deltaStart, endDelta: deltaEnd, surfaces: surfaces)
                }
            }
            
            if grp.kind.editsKeyboardInput, let k = UInt16(inspKey) {
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
        withUndo(NSLocalizedString("Convert Action Type", comment: "")) {
            let indices = grp.eventIndices
            guard !indices.isEmpty else { return }
            
            switch newKind {
            case .click:
                recorder.events.updateClickType(at: indices, to: 1)
                if grp.kind == .longPress, indices.count >= 2, let lastIdx = indices.last {
                    let first = recorder.events[indices[0]]
                    let currentLast = recorder.events[lastIdx]
                    let desiredTime = first.time + 0.1
                    if currentLast.time > desiredTime {
                        recorder.events.shiftTime(of: IndexSet([lastIdx]), by: desiredTime - currentLast.time)
                    }
                }
            case .doubleClick:
                recorder.events.updateClickType(at: indices, to: 2)
            case .repeatedClick:
                recorder.events.updateClickType(at: indices, to: 3)
            case .longPress:
                recorder.events.updateClickType(at: indices, to: 1)
                if indices.count >= 2, let lastIdx = indices.last {
                    let first = recorder.events[indices[0]]
                    let currentLast = recorder.events[lastIdx]
                    let desiredTime = first.time + 1.0
                    if currentLast.time < desiredTime {
                        recorder.events.shiftTime(of: IndexSet([lastIdx]), by: desiredTime - currentLast.time)
                    }
                }
            default:
                break
            }
        }
        onLoadInspector()
        onUpdatePreview()
    }
    
    enum Axis { case x, y }
    
    func alignSelectedCoordinates(axis: Axis) {
        let selectedGroups = selectedGroups()
        guard let firstGrp = selectedGroups.first, let sp = firstGrp.startPoint else { return }
        
        let targetVal = axis == .x ? sp.x : sp.y
        var didChange = false
        
        withUndo(NSLocalizedString("Align Coordinates", comment: "")) {
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
        withUndo(NSLocalizedString("Batch Set Timeout", comment: "")) {
            for grp in selectedGroups {
                if grp.kind.editsSemanticTextTarget {
                    let anchor = firstEvent(for: grp)?.textAnchor ?? grp.textAnchor
                    recorder.events.updateSemanticAction(
                        at: grp.eventIndices,
                        textAnchor: anchor,
                        timeout: inspTimeout,
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
                        textTimeout: inspTimeout
                    )
                }
            }
        }
        onLoadInspector()
        onUpdatePreview()
    }

    func applyBatchTextTarget() {
        let targetGroups = selectedTextTargetGroups()
        guard !targetGroups.isEmpty else { return }

        withUndo(NSLocalizedString("Batch Set Text Target", comment: "")) {
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
            TextField(NSLocalizedString("e.g. Confirm", comment: ""), text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .controlSize(.small)
            
            Button(action: onPick) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(NSLocalizedString("Pick text from screen", comment: ""))
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
                Text(hasContentLock ? NSLocalizedString("Content-locked target", comment: "") : NSLocalizedString("Screen target", comment: ""))
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text(fallbackPolicy == .allowCoordinateFallback ? NSLocalizedString("Fallback on", comment: "") : NSLocalizedString("Pause on miss", comment: ""))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Detected Text", comment: ""))
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(anchor.text)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
            
            Divider()
            
            positionRow(color: Brand.sigGreen, title: NSLocalizedString("Text box", comment: ""), value: rectSummary(anchor.observedFrame))
            if let normalized = anchor.observedContentNormalizedFrame {
                positionRow(color: Brand.sigBlue, title: NSLocalizedString("Content lock", comment: ""), value: normalizedRectSummary(normalized))
            }
            if let search = anchor.searchRegion {
                positionRow(color: Brand.sigAmber, title: NSLocalizedString("Search region", comment: ""), value: rectSummary(search))
            }
            if let fallback = anchor.coordinateFallback {
                positionRow(color: Brand.sigViolet, title: NSLocalizedString("Fallback point", comment: ""), value: pointSummary(fallback))
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
