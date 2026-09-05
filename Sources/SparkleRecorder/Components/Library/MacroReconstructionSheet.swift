import AVKit
import SparkleRecorderCore
import SwiftUI
import UniformTypeIdentifiers

struct MacroReconstructionSheet: View {
    @StateObject var model: MacroReconstructionReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDraggingOver = false
    @State private var isInitialLoading = true

    init(model: @autoclosure @escaping () -> MacroReconstructionReviewModel) {
        // Keep model construction inside StateObject's retained initialization thunk.
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView
            if isInitialLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                workflowPipelineBar
                HSplitView {
                    sourceMacroPane
                        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.trailing, 6)
                    candidateReviewPane
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.leading, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footerView
            }
        }
        .padding(18)
        .frame(minWidth: 900, idealWidth: 1020, minHeight: 700, idealHeight: 820)
        .interactiveDismissDisabled(model.isBusy && !isInitialLoading)
        .task {
            await model.reload()
            // A detached repository/projection load can finish after dismissal.
            // Dispose any player observer it installed after onDisappear ran.
            guard !Task.isCancelled else { model.close(); return }
            isInitialLoading = false
        }
        .onDisappear { model.close() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("AI-assisted reconstruction", tableName: "EditorUX")
                        .font(.title3.bold())
                    if let source = model.source {
                        Text(source.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                Text("Export the recording package for your AI tool, then import its complete candidate. Review and test every version before accepting it.", tableName: "EditorUX")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isBusy {
                ProgressView().controlSize(.small)
            }

            Button {
                model.close()
                dismiss()
            } label: {
                Text("Close", tableName: "Common")
            }
            .disabled(model.isBusy && !isInitialLoading)
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Workflow Pipeline Bar

    private var workflowPipelineBar: some View {
        HStack(spacing: 8) {
            // Step 1: Prepare & export
            HStack(spacing: 8) {
                stepBadge(1, active: model.selectedCandidate == nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prepare package", tableName: "EditorUX")
                        .font(.caption.weight(model.selectedCandidate == nil ? .bold : .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Button {
                            model.chooseExportDirectory()
                        } label: {
                            Label(String(localized: "Export AI package…", table: "EditorUX"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isBusy)

                        Toggle(isOn: $model.includeVisualEvidence) {
                            Text("Frames", tableName: "EditorUX")
                                .font(.caption2)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(model.isBusy)
                        .help(String(localized: "Include permitted video and frames", table: "EditorUX"))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(model.selectedCandidate == nil ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Step 2: Compare & refine
            HStack(spacing: 8) {
                stepBadge(2, active: model.selectedCandidate != nil && model.testedCandidateID == nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare & refine", tableName: "EditorUX")
                        .font(.caption.weight(model.selectedCandidate != nil && model.testedCandidateID == nil ? .bold : .medium))
                        .lineLimit(1)
                    if model.selectedCandidate == nil {
                        Button {
                            model.chooseCandidateFile()
                        } label: {
                            Label(String(localized: "Import candidate…", table: "EditorUX"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isBusy)
                    } else {
                        Button {
                            model.chooseCandidateFile()
                        } label: {
                            Label(String(localized: "Import candidate…", table: "EditorUX"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isBusy)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(model.selectedCandidate != nil && model.testedCandidateID == nil ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Step 3: Test & accept
            HStack(spacing: 8) {
                stepBadge(3, active: model.isTesting || model.testedCandidateID != nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Test & accept", tableName: "EditorUX")
                        .font(.caption.weight(model.isTesting || model.testedCandidateID != nil ? .bold : .medium))
                        .lineLimit(1)
                    if model.testedCandidateID != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("Test completed", tableName: "EditorUX")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    } else if model.isTesting {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Testing…", tableName: "EditorUX")
                                .font(.caption2)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Text("Verify in target app & accept", tableName: "EditorUX")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background((model.isTesting || model.testedCandidateID != nil) ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 2)
    }

    private func stepBadge(_ number: Int, active: Bool) -> some View {
        Text("\(number)")
            .font(.caption.bold())
            .frame(width: 20, height: 20)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.18), in: Circle())
            .foregroundStyle(active ? Color.white : Color.secondary)
    }

    // MARK: - Left Pane: Current Macro

    private var sourceMacroPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("Current macro", tableName: "EditorUX").font(.headline)
                } icon: {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: String(localized: "Actions: %d", table: "EditorUX"), model.sourceActions.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }

            if let player = model.videoPlayer {
                VideoPlayer(player: player)
                    .frame(minHeight: 160, idealHeight: 200, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if let marker = model.videoMarker {
                            GeometryReader { geometry in
                                let scale = min(geometry.size.width / Double(marker.size.width), geometry.size.height / Double(marker.size.height))
                                Circle().stroke(.yellow, lineWidth: 3).frame(width: 20, height: 20)
                                    .position(x: (geometry.size.width - Double(marker.size.width) * scale) / 2 + marker.point.x * scale,
                                              y: (geometry.size.height - Double(marker.size.height) * scale) / 2 + marker.point.y * scale)
                            }.allowsHitTesting(false)
                        }
                    }

                if !model.hasAlignedVideo {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle")
                        Text("Precise video alignment is unavailable. Action times below belong to the macro; they are not video seek times.", tableName: "EditorUX")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("No visual evidence recorded · Action times reflect macro playback timing.", tableName: "EditorUX")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.sourceRows) { row in
                        actionRow(row.action, number: row.number, candidate: false)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Right Pane: Candidate & Review

    private var candidateReviewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("Candidate", tableName: "EditorUX").font(.headline)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                }

                if !model.candidates.isEmpty {
                    Picker("", selection: Binding(get: { model.selectedCandidateID }, set: { id in Task { await model.selectCandidate(id) } })) {
                        Text("Select a candidate", tableName: "EditorUX").tag(Optional<UUID>.none)
                        ForEach(model.candidates) { candidate in
                            Text(candidate.createdAt.formatted(date: .abbreviated, time: .standard))
                                .tag(Optional(candidate.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(model.isBusy)
                }

                Spacer()

                if let candidate = model.selectedCandidate, model.testedCandidateID == candidate.id {
                    Label(String(localized: "Test completed", table: "EditorUX"), systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            if let candidate = model.selectedCandidate {
                candidateDetailView(candidate)
            } else {
                emptyCandidateView
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func candidateDetailView(_ candidate: MacroStoredCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Metrics and summary
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(format: String(localized: "Actions · %d → %d", table: "EditorUX"), model.sourceActions.count, model.candidateActions.count))
                        .font(.subheadline.bold())
                        .monospacedDigit()

                    let originalCount = model.sourceActions.count
                    let candidateCount = model.candidateActions.count
                    if originalCount > candidateCount && originalCount > 0 {
                        let diff = originalCount - candidateCount
                        let pct = Int(round(Double(diff) / Double(originalCount) * 100))
                        Text("-\(pct)% (↓\(diff))")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Text(candidate.document.model)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }

                if !candidate.document.summary.isEmpty {
                    Text(candidate.document.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.candidateRows) { row in
                        actionRow(row.action, number: row.number, candidate: true)
                    }

                    if !candidate.document.coverage.isEmpty {
                        Divider().padding(.vertical, 6)
                        HStack {
                            Text("Source coverage", tableName: "EditorUX")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(candidate.document.coverage.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(candidate.document.coverage, id: \.sourceActionID) { coverage in
                            coverageRow(coverage)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.canCorrectText {
                HStack(spacing: 8) {
                    Image(systemName: "character.cursor.ibeam")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Correct text target", table: "EditorUX"), text: $model.correctedText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button {
                        Task { await model.correctSelectedText() }
                    } label: {
                        Text("Save correction", tableName: "EditorUX")
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .disabled(model.isBusy)
            }

            if model.isSelectedCandidateStale {
                Text("This candidate belongs to an earlier macro version. Export the current version to continue refining.", tableName: "EditorUX")
                    .font(.caption).foregroundStyle(.orange)
            }

            if candidate.document.requiresAttention {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This candidate contains uncertain or unresolved actions. Review its coverage before accepting.", tableName: "EditorUX")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Toggle(isOn: $model.confirmUncertainties) {
                        Text("I reviewed the uncertain actions", tableName: "EditorUX")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.isBusy)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var emptyCandidateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 60, height: 60)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 6) {
                Text("Ready for a better recording", tableName: "EditorUX")
                    .font(.title3.bold())
                Text("Export the recording package for your AI tool, then import its complete candidate. Review and test every version before accepting it.", tableName: "EditorUX")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 8) {
                guideRow(number: "1", title: String(localized: "Export package for AI", table: "EditorUX"))
                guideRow(number: "2", title: String(localized: "Send package to AI (Claude, GPT, etc.)", table: "EditorUX"))
                guideRow(number: "3", title: String(localized: "Import candidate JSON to test and accept", table: "EditorUX"))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Button {
                model.chooseCandidateFile()
            } label: {
                Label(String(localized: "Import candidate…", table: "EditorUX"), systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(model.isBusy)

            Text("Drop candidate .json file here", tableName: "EditorUX")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDraggingOver ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: isDraggingOver ? 2 : 1.5, dash: [6])
                )
        )
        .onDrop(of: [.fileURL, .json], isTargeted: $isDraggingOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await model.importFile(at: url)
                }
            }
            return true
        }
    }

    private func guideRow(number: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption2.bold())
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Rows & Badges

    private func actionRow(_ action: MacroReconstructedAction, number: Int, candidate: Bool) -> some View {
        let isSelected = model.selectedActionID == action.id || (!candidate && model.activeSourceActionID == action.id)
        return Button {
            model.selectAction(action.id, candidate: candidate)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text("\(number)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)

                Image(systemName: actionIconName(action.kind))
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background((isSelected ? Color.accentColor : Color.secondary).opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(humanActionKindName(action.kind))
                            .font(.callout.weight(.medium))

                        if let macro = candidate ? model.selectedCandidate?.macro : model.source,
                           let text = action.sourceEventIndices.compactMap({ macro.events[$0].textAnchor?.text }).first {
                            HStack(spacing: 3) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.caption2)
                                Text(text)
                                    .font(.caption2.bold())
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                            .foregroundStyle(.purple)
                        }
                    }

                    if let macro = candidate ? model.selectedCandidate?.macro : model.source {
                        let typed = action.sourceEventIndices.lazy.map { macro.events[$0] }
                            .filter { $0.kind == .keyDown }.compactMap(\.unicodeString).prefix(80)
                            .reduce(into: "") { result, fragment in
                                if result.count < 160 { result.append(contentsOf: fragment.prefix(160 - result.count)) }
                            }
                        if !typed.isEmpty {
                            Text(typed).font(.caption).lineLimit(2).textSelection(.enabled)
                        }
                    }

                    Text(String(format: "%.2f–%.2f s (%.2f s)", action.startTime, action.endTime, max(0.01, action.endTime - action.startTime)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func actionIconName(_ kind: ActionGroupKind) -> String {
        switch kind {
        case .click: "cursorarrow.click"
        case .doubleClick: "cursorarrow.click.2"
        case .repeatedClick, .multiPointClick: "cursorarrow.click.badge.clock"
        case .longPress: "hand.tap"
        case .drag: "arrow.up.and.down.and.arrow.left.and.right"
        case .scroll: "arrow.up.and.down"
        case .keyPress, .keyHold, .keyRepeat, .shortcut, .modifierHold: "keyboard"
        case .textInput: "character.cursor.ibeam"
        case .waitForText, .waitForTextGone, .verifyText: "text.magnifyingglass"
        case .sequence: "square.stack.3d.up"
        case .wait: "clock"
        case .mouseMove: "cursorarrow.motionlines"
        }
    }

    private func coverageRow(_ coverage: MacroCandidateCoverage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(coverageTitle(coverage))
                    .font(.caption.bold())
                Spacer()
                Text(dispositionTitle(coverage.disposition))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(dispositionColor(coverage.disposition).opacity(0.12), in: Capsule())
                    .foregroundStyle(dispositionColor(coverage.disposition))
            }
            if !coverage.reason.isEmpty {
                Text(coverage.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func dispositionColor(_ disposition: MacroCandidateDisposition) -> Color {
        switch disposition {
        case .preserved: Color.secondary
        case .merged: Color.teal
        case .replacedByLocator: Color.purple
        case .replacedByWait: Color.indigo
        case .removedAsNoise: Color.gray
        case .unresolved: Color.orange
        }
    }

    private func coverageTitle(_ coverage: MacroCandidateCoverage) -> String {
        guard let index = model.sourceActionIndices[coverage.sourceActionID] else {
            return String(localized: "Source action", table: "EditorUX")
        }
        return String(format: String(localized: "Step %d · %@", table: "EditorUX"), index + 1,
                      humanActionKindName(model.sourceActions[index].kind))
    }

    private func dispositionTitle(_ disposition: MacroCandidateDisposition) -> String {
        switch disposition {
        case .preserved: String(localized: "Kept", table: "EditorUX")
        case .merged: String(localized: "Combined", table: "EditorUX")
        case .replacedByLocator: String(localized: "Text target", table: "EditorUX")
        case .replacedByWait: String(localized: "Conditional wait", table: "EditorUX")
        case .removedAsNoise: String(localized: "Noise removed", table: "EditorUX")
        case .unresolved: String(localized: "Needs review", table: "EditorUX")
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            if !model.statusMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(8)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Button {
                    Task { await model.restoreOriginal() }
                } label: {
                    Text("Restore original", tableName: "EditorUX")
                }
                .disabled(model.isBusy || model.candidates.isEmpty)

                Spacer()

                Text("Testing runs this macro once, without chained macros. Accepting keeps your saved repeat settings. Check the result in the target app before accepting.", tableName: "EditorUX")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 420, alignment: .trailing)

                if model.isTesting {
                    Button(role: .destructive) {
                        model.cancelTest()
                    } label: {
                        Label(String(localized: "Stop test", table: "EditorUX"), systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        Task { await model.testSelected() }
                    } label: {
                        Label(String(localized: "Test once", table: "EditorUX"), systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy || model.isSelectedCandidateStale || model.selectedCandidate == nil)
                }

                Button {
                    Task { await model.acceptSelected() }
                } label: {
                    Label(String(localized: "Accept tested version", table: "EditorUX"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAccept)
                .help(!model.canAccept ? String(localized: "You must run 'Test once' before accepting.", table: "EditorUX") : "")
            }
        }
    }
}
