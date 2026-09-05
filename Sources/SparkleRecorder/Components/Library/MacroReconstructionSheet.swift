import AVKit
import SparkleRecorderCore
import SwiftUI

struct MacroReconstructionSheet: View {
    @StateObject var model: MacroReconstructionReviewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI-assisted reconstruction", tableName: "EditorUX").font(.title2.bold())
                    Text(model.source?.name ?? "").foregroundStyle(.secondary)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button { model.close(); dismiss() } label: { Text("Close", tableName: "Common") }
                    .disabled(model.isBusy)
            }
            Text("Export the recording package for your AI tool, then import its complete candidate. Review and test every version before accepting it.", tableName: "EditorUX")
                .font(.callout).foregroundStyle(.secondary)
            workflowProgress
            HStack {
                Button { model.chooseExportDirectory() } label: {
                    Label(String(localized: "Export AI package…", table: "EditorUX"), systemImage: "square.and.arrow.up")
                }
                Toggle(isOn: $model.includeVisualEvidence) {
                    Text("Include permitted video and frames", tableName: "EditorUX")
                }.toggleStyle(.checkbox)
                Spacer()
                Button { model.chooseCandidateFile() } label: {
                    Label(String(localized: "Import candidate…", table: "EditorUX"), systemImage: "square.and.arrow.down")
                }
            }.disabled(model.isBusy)
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    if let player = model.videoPlayer {
                        VideoPlayer(player: player).frame(minHeight: 190, maxHeight: 280)
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
                    } else {
                        ContentUnavailableView {
                            Label(String(localized: "Video unavailable", table: "EditorUX"), systemImage: "video.slash")
                        } description: {
                            Text("Enable visual evidence before your next recording to review it alongside video.", tableName: "EditorUX")
                        }.frame(height: 130)
                    }
                    if !model.hasAlignedVideo {
                        Text("Precise video alignment is unavailable. Action times below belong to the macro; they are not video seek times.", tableName: "EditorUX")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Current macro", tableName: "EditorUX").font(.headline)
                        Spacer()
                        Text(String(format: String(localized: "Actions: %d", table: "EditorUX"), model.sourceActions.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.sourceRows) { row in
                                actionRow(row.action, number: row.number, candidate: false)
                            }
                        }
                    }
                }.padding(.trailing, 12).frame(minWidth: 330)
                VStack(alignment: .leading, spacing: 8) {
                    Picker(selection: Binding(get: { model.selectedCandidateID }, set: { id in Task { await model.selectCandidate(id) } })) {
                        Text("Select a candidate", tableName: "EditorUX").tag(Optional<UUID>.none)
                        ForEach(model.candidates) { candidate in
                            Text(candidate.createdAt.formatted(date: .abbreviated, time: .standard))
                                .tag(Optional(candidate.id))
                        }
                    } label: { Text("Candidate", tableName: "EditorUX") }.disabled(model.isBusy)
                    if let candidate = model.selectedCandidate {
                        if model.isSelectedCandidateStale {
                            Label(String(localized: "This candidate belongs to an earlier macro version. Export the current version to continue refining.", table: "EditorUX"), systemImage: "clock.arrow.circlepath")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Text(String(format: String(localized: "Actions · %d → %d", table: "EditorUX"), model.sourceActions.count, model.candidateActions.count))
                                .font(.headline).monospacedDigit()
                            Spacer()
                            if model.testedCandidateID == candidate.id {
                                Label(String(localized: "Test completed", table: "EditorUX"), systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        Text(candidate.document.summary).font(.callout).lineLimit(4).textSelection(.enabled)
                        Text(candidate.document.model).font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(model.candidateRows) { row in
                                    actionRow(row.action, number: row.number, candidate: true)
                                }
                                Divider().padding(.vertical, 6)
                                Text("Source coverage", tableName: "EditorUX").font(.headline)
                                ForEach(candidate.document.coverage, id: \.sourceActionID) { coverage in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(coverageTitle(coverage)).font(.caption.bold())
                                            Spacer()
                                            Text(dispositionTitle(coverage.disposition)).font(.caption)
                                                .foregroundStyle(coverage.disposition == .unresolved ? Color.orange : Color.secondary)
                                        }
                                        Text(coverage.reason).font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                        if model.canCorrectText {
                            HStack {
                                TextField(String(localized: "Correct text target", table: "EditorUX"), text: $model.correctedText)
                                Button { Task { await model.correctSelectedText() } } label: {
                                    Text("Save correction", tableName: "EditorUX")
                                }
                            }.disabled(model.isBusy)
                        }
                        if candidate.document.requiresAttention {
                            Text("This candidate contains uncertain or unresolved actions. Review its coverage before accepting.", tableName: "EditorUX")
                                .font(.caption).foregroundStyle(.orange)
                            Toggle(isOn: $model.confirmUncertainties) {
                                Text("I reviewed the uncertain actions", tableName: "EditorUX")
                            }.toggleStyle(.checkbox).disabled(model.isBusy)
                        }
                    } else {
                        ContentUnavailableView {
                            Label(String(localized: "Ready for a better recording", table: "EditorUX"), systemImage: "wand.and.stars")
                        } description: {
                            Text("Export a package, ask your AI tool to follow its instructions, then import the resulting candidate here. Your current macro stays available throughout.", tableName: "EditorUX")
                        }
                    }
                }.padding(.leading, 12).frame(minWidth: 340)
            }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Divider()
            Text("Testing runs this macro once, without chained macros. Accepting keeps your saved repeat settings. Check the result in the target app before accepting.", tableName: "EditorUX")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { Task { await model.restoreOriginal() } } label: { Text("Restore original", tableName: "EditorUX") }
                    .disabled(model.isBusy || model.candidates.isEmpty)
                Spacer()
                if model.isTesting {
                    Button(role: .destructive) { model.cancelTest() } label: { Text("Stop test", tableName: "EditorUX") }
                } else {
                    Button { Task { await model.testSelected() } } label: { Text("Test once", tableName: "EditorUX") }
                        .disabled(model.isBusy || model.selectedCandidate == nil || model.isSelectedCandidateStale)
                }
                Button { Task { await model.acceptSelected() } } label: { Text("Accept tested version", tableName: "EditorUX") }
                    .buttonStyle(.borderedProminent).disabled(!model.canAccept)
            }
        }
        .padding(20).frame(minWidth: 850, idealWidth: 980, minHeight: 720, idealHeight: 820)
        .interactiveDismissDisabled(model.isBusy)
        .task { await model.reload() }
        .onDisappear { model.close() }
    }

    private var workflowProgress: some View {
        HStack(spacing: 8) {
            phase(String(localized: "Prepare package", table: "EditorUX"), number: 1, active: model.selectedCandidate == nil)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            phase(String(localized: "Compare & refine", table: "EditorUX"), number: 2, active: model.selectedCandidate != nil && model.testedCandidateID == nil)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            phase(String(localized: "Test & accept", table: "EditorUX"), number: 3, active: model.isTesting || model.testedCandidateID != nil)
            Spacer()
        }
    }

    private func phase(_ title: String, number: Int, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(number)").font(.caption.bold()).frame(width: 19, height: 19)
                .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Circle())
            Text(title).font(.caption.weight(active ? .semibold : .regular))
        }.foregroundStyle(active ? Color.accentColor : Color.secondary)
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

    private func actionRow(_ action: MacroReconstructedAction, number: Int, candidate: Bool) -> some View {
        Button { model.selectAction(action.id, candidate: candidate) } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number)").monospacedDigit().foregroundStyle(.secondary).frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(humanActionKindName(action.kind)).font(.callout.bold())
                    Text(String(format: "%.2f–%.2f s", action.startTime, action.endTime))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let macro = candidate ? model.selectedCandidate?.macro : model.source {
                        if let text = action.sourceEventIndices.compactMap({ macro.events[$0].textAnchor?.text }).first {
                            Text(text).font(.caption).lineLimit(2).textSelection(.enabled)
                        } else {
                            let typed = action.sourceEventIndices.lazy.map { macro.events[$0] }
                                .filter { $0.kind == .keyDown }.compactMap(\.unicodeString).prefix(80)
                                .reduce(into: "") { result, fragment in
                                    if result.count < 160 { result.append(contentsOf: fragment.prefix(160 - result.count)) }
                                }
                            if !typed.isEmpty { Text(String(typed.prefix(160))).font(.caption).lineLimit(2).textSelection(.enabled) }
                        }
                    }
                }
                Spacer()
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background((model.selectedActionID == action.id || (!candidate && model.activeSourceActionID == action.id)) ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}
