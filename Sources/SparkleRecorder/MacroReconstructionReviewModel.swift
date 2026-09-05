import AppKit
import AVKit
import Combine
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

struct MacroReconstructionReviewRow: Identifiable, Sendable {
    let number: Int
    let action: MacroReconstructedAction
    var id: String { action.id }
}

struct MacroReconstructionVideoMarker: Equatable {
    var point: PointValue
    var size: RecordingImageSize
}

/// Owns repository/panel/player effects. The sheet renders these projections and sends intents.
@MainActor
final class MacroReconstructionReviewModel: ObservableObject {
    let macroID: UUID
    @Published private(set) var source: SavedMacro?
    @Published private(set) var candidates: [MacroStoredCandidate] = []
    @Published private(set) var selectedCandidateID: UUID?
    @Published private(set) var sourceActions: [MacroReconstructedAction] = []
    @Published private(set) var sourceRows: [MacroReconstructionReviewRow] = []
    @Published private(set) var candidateRows: [MacroReconstructionReviewRow] = []
    @Published private(set) var candidateActions: [MacroReconstructedAction] = []
    @Published private(set) var projectedActions: [MacroReconstructionProjectedAction] = []
    @Published private(set) var selectedActionID: String?
    @Published private(set) var videoPlayer: AVPlayer?
    @Published private(set) var activeSourceActionID: String?
    @Published private(set) var videoMarker: MacroReconstructionVideoMarker?
    private var videoIndex = MacroReconstructionVideoIndex(rows: [])
    private var frameSizes: [String: RecordingImageSize] = [:]
    private(set) var sourceActionIndices: [String: Int] = [:]
    private var currentSourceRevision: String?
    private var videoObserver: Any?
    @Published private(set) var isBusy = false
    @Published private(set) var isTesting = false
    @Published private(set) var testedCandidateID: UUID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage = ""
    @Published var includeVisualEvidence = false
    @Published var confirmUncertainties = false
    @Published var correctedText = ""
    private let repository: MacroRepository
    private let testMacro: @MainActor (SavedMacro) async throws -> Void
    private let stopTest: @MainActor () -> Void
    private let onRevision: @MainActor (SavedMacro) async -> Void
    private var evidence: SemanticRecordingReviewState?
    private var videoSegmentID: String?
    private var testTask: Task<Void, Error>?
    private var testCancelled = false
    private let canPublish: @MainActor () -> Bool

    init(macroID: UUID, repository: MacroRepository = .shared,
         testMacro: @escaping @MainActor (SavedMacro) async throws -> Void,
         stopTest: @escaping @MainActor () -> Void,
         canPublish: @escaping @MainActor () -> Bool = { true },
         onRevision: @escaping @MainActor (SavedMacro) async -> Void) {
        self.macroID = macroID; self.repository = repository
        self.testMacro = testMacro; self.stopTest = stopTest; self.onRevision = onRevision
        self.canPublish = canPublish
    }

    var selectedCandidate: MacroStoredCandidate? { candidates.first { $0.id == selectedCandidateID } }
    var isSelectedCandidateStale: Bool {
        guard let candidate = selectedCandidate, let currentSourceRevision else { return false }
        return candidate.document.sourceRevision != currentSourceRevision
    }
    var canAccept: Bool {
        !isBusy && !isSelectedCandidateStale && canPublish() && selectedCandidateID != nil && testedCandidateID == selectedCandidateID
            && (selectedCandidate?.document.requiresAttention != true || confirmUncertainties)
    }
    var hasAlignedVideo: Bool { !videoIndex.isEmpty }
    var canCorrectText: Bool {
        guard let candidate = selectedCandidate,
              let action = candidateActions.first(where: { $0.id == selectedActionID }) else { return false }
        return action.sourceEventIndices.contains { candidate.macro.events[$0].textAnchor != nil }
    }

    func reload(loadEvidence: Bool = true) async {
        let wasBusy = isBusy
        isBusy = true
        defer { isBusy = wasBusy }
        do {
            let loaded = try await repository.loadMacro(for: macroID)
            candidates = try await repository.listCandidates(for: macroID)
            if loadEvidence, let reference = loaded.semanticRecording {
                do { evidence = try await SemanticRecordingReviewPresenter.reviewState(from: reference, sourceName: loaded.name) }
                catch { evidence = nil; errorMessage = error.localizedDescription }
            }
            try await rebuildProjection(for: loaded)
        } catch { errorMessage = error.localizedDescription }
    }

    private func rebuildProjection(for source: SavedMacro) async throws {
        let recordedProvenance = evidence?.bundle.reconstructionProvenance
        let (rows, revision, index, reviewRows, sourceIndices) = try await Task.detached(priority: .userInitiated) {
            let provenance = recordedProvenance?.matchesSourceEvents(source.events) == true ? recordedProvenance : nil
            var times: [Int: Double] = [:]
            for item in provenance?.sourceEvents ?? [] {
                guard source.events.indices.contains(item.sourceEventIndex),
                      source.events[item.sourceEventIndex].time == item.sourcePlaybackTime,
                      times[item.sourceEventIndex] == nil else { continue }
                times[item.sourceEventIndex] = item.sessionTime
            }
            let revision = try MacroCandidateIdentity.revision(of: source)
            let rows = try MacroReconstructionProjector.project(events: source.events,
                sourceRevision: revision, sessionTimesByEventIndex: times,
                videoClock: RecordingVideoClockMapping(segments: provenance?.clockSegments ?? []),
                geometry: RecordingGeometryHistory(snapshots: provenance?.geometrySnapshots ?? []))
            let reviewRows = rows.enumerated().map { MacroReconstructionReviewRow(number: $0.offset + 1, action: $0.element.action) }
            let sourceIndices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.action.id, $0.offset) })
            return (rows, revision, MacroReconstructionVideoIndex(rows: rows), reviewRows, sourceIndices)
        }.value
        self.source = source
        currentSourceRevision = revision
        projectedActions = rows
        sourceActions = rows.map(\.action)
        sourceActionIndices = sourceIndices
        sourceRows = reviewRows
        videoIndex = index
        frameSizes = Dictionary((evidence?.bundle.videoSegments ?? []).compactMap { segment in
            segment.frameSize.map { (segment.id.uuidString, $0) }
        }, uniquingKeysWith: { first, _ in first })
        if activeSourceActionID != nil { activeSourceActionID = nil }
        if videoMarker != nil { videoMarker = nil }
        if videoPlayer == nil, let first = evidence?.bundle.videoSegments.first { loadVideo(segmentID: first.id.uuidString) }
    }

    func selectCandidate(_ id: UUID?) async {
        guard !isBusy else { return }
        selectedCandidateID = id; selectedActionID = nil; correctedText = ""
        errorMessage = nil; statusMessage = ""
        testedCandidateID = nil; confirmUncertainties = false
        isBusy = true
        defer { isBusy = false }
        do { try await updateCandidateRows() }
        catch { candidateActions = []; candidateRows = []; errorMessage = error.localizedDescription }
    }

    private func updateCandidateRows() async throws {
        guard let candidate = selectedCandidate else { candidateActions = []; candidateRows = []; return }
        let (actions, rows) = try await Task.detached(priority: .userInitiated) {
            let actions = try MacroActionReconstructor.reconstruct(events: candidate.macro.events, sourceRevision: "candidate")
            return (actions, actions.enumerated().map { MacroReconstructionReviewRow(number: $0.offset + 1, action: $0.element) })
        }.value
        candidateActions = actions
        candidateRows = rows
    }

    func selectAction(_ id: String, candidate: Bool) {
        selectedActionID = id
        if candidate, let selectedCandidate,
           let action = candidateActions.first(where: { $0.id == id }) {
            correctedText = action.sourceEventIndices.compactMap { selectedCandidate.macro.events[$0].textAnchor?.text }.first ?? ""
            if let coverage = selectedCandidate.document.coverage.first(where: { $0.candidateActionIDs.contains(id) }) {
                seekSourceAction(coverage.sourceActionID)
            }
        } else { seekSourceAction(id) }
    }

    private func seekSourceAction(_ id: String) {
        guard let row = videoIndex.row(actionID: id),
              let segment = row.videoSegmentID, let range = row.videoRange else {
            videoPlayer?.pause()
            if activeSourceActionID != nil { activeSourceActionID = nil }
            if videoMarker != nil { videoMarker = nil }
            statusMessage = String(localized: "This step has no verified video time. Review the macro step directly or inspect the video manually.", table: "EditorUX")
            return
        }
        statusMessage = ""
        loadVideo(segmentID: segment)
        videoPlayer?.pause()
        videoPlayer?.seek(to: CMTime(seconds: range.startTime, preferredTimescale: 600),
                          toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loadVideo(segmentID: String) {
        guard videoSegmentID != segmentID, let evidence, let root = evidence.bundleDirectory,
              let segment = evidence.bundle.videoSegments.first(where: { $0.id.uuidString == segmentID }) else { return }
        // Local review is explicit. Never resolve a bundle path outside its own directory.
        let directory = root.resolvingSymlinksInPath().standardizedFileURL
        let url = directory.appendingRecordingArtifactRef(segment.artifactRef).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(directory.path + "/"), FileManager.default.fileExists(atPath: url.path) else { return }
        videoPlayer?.pause()
        if let videoObserver { videoPlayer?.removeTimeObserver(videoObserver) }
        videoPlayer = AVPlayer(url: url); videoSegmentID = segmentID
        videoObserver = videoPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.videoSegmentID == segmentID else { return }
                self.updateVideoPosition(time.seconds, segmentID: segmentID)
            }
        }
    }

    func importDocument(_ document: MacroCandidateDocument) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; statusMessage = ""
        defer { isBusy = false }
        do {
            let stored = try await repository.importCandidate(document, for: macroID)
            candidates = try await repository.listCandidates(for: macroID)
            selectedCandidateID = stored.id; testedCandidateID = nil; confirmUncertainties = false
            selectedActionID = nil; correctedText = ""
            try await updateCandidateRows()
            statusMessage = String(localized: "Candidate imported. Review its changes, then test it.", table: "EditorUX")
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseCandidateFile() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.importFile(at: url)
            }
        }
    }

    func importFile(at url: URL) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; statusMessage = ""
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try MacroCandidateValidator.decode(Data(contentsOf: url, options: .mappedIfSafe))
            }.value
            isBusy = false
            await importDocument(document)
        } catch { isBusy = false; errorMessage = error.localizedDescription }
    }

    func correctSelectedText() async {
        guard canCorrectText, !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var document = selectedCandidate?.document,
              let action = candidateActions.first(where: { $0.id == selectedActionID }) else { return }
        for index in action.sourceEventIndices where document.macro.events[index].textAnchor != nil {
            document.macro.events[index].textAnchor?.text = correctedText
        }
        // Local corrections create a fresh immutable candidate and require a new test.
        await importDocument(document)
    }

    func chooseExportDirectory() {
        guard !isBusy, source != nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macro-reconstruction-\(macroID.uuidString.prefix(8))"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in await self?.exportPackage(to: url) }
        }
    }

    func exportPackage(to url: URL) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; statusMessage = ""
        defer { isBusy = false }
        do {
            let source = try await repository.loadMacro(for: macroID)
            if let reference = source.semanticRecording, evidence?.bundle.id != reference.recordingID {
                throw MacroReconstructionReviewError.recordingUnavailable
            }
            let bundle = evidence?.bundle
            let directory = evidence?.bundleDirectory
            let includeVisual = includeVisualEvidence
            let report = try await Task.detached(priority: .userInitiated) {
                try MacroReconstructionPackage.export(source: source, bundle: bundle,
                    bundleDirectory: directory, includeVisualEvidence: includeVisual, to: url)
            }.value
            statusMessage = ([String(localized: "AI package exported. Follow instructions.md and import the completed candidate.", table: "EditorUX")] + report.warnings).joined(separator: "\n")
        } catch { errorMessage = error.localizedDescription }
    }

    func testSelected() async {
        guard !isBusy, !isSelectedCandidateStale, let id = selectedCandidateID else { return }
        isBusy = true; isTesting = true; testedCandidateID = nil; errorMessage = nil; testCancelled = false
        statusMessage = String(localized: "Testing one iteration. Use Stop test or your stop hotkey to cancel.", table: "EditorUX")
        videoPlayer?.pause()
        defer { isBusy = false; isTesting = false; testTask = nil }
        do {
            let run = try await repository.prepareCandidateTest(candidateID: id, for: macroID)
            do {
                guard !testCancelled else { throw CancellationError() }
                let task = Task { try await self.testMacro(run.macro) }
                testTask = task
                try await task.value
                guard !testCancelled else { throw CancellationError() }
                try await repository.recordCandidateTest(run, succeeded: true)
                testedCandidateID = id
                statusMessage = String(localized: "Playback completed. Check the result before accepting this version.", table: "EditorUX")
            } catch {
                try? await repository.recordCandidateTest(run, succeeded: false)
                throw error
            }
        } catch {
            statusMessage = ""
            errorMessage = testCancelled || error is CancellationError
                ? String(localized: "Test stopped. Nothing was accepted. You can edit the candidate or test again.", table: "EditorUX")
                : error.localizedDescription
        }
    }

    func cancelTest() {
        if isTesting { testCancelled = true; testTask?.cancel(); stopTest() }
    }

    func acceptSelected() async {
        guard canPublish() else {
            errorMessage = String(localized: "Stop recording or playback before changing the accepted version.", table: "EditorUX")
            return
        }
        guard canAccept, let id = selectedCandidateID else { return }
        isBusy = true; errorMessage = nil; statusMessage = ""
        defer { isBusy = false }
        do {
            let macro = try await repository.acceptCandidate(candidateID: id, for: macroID,
                confirmUncertainties: confirmUncertainties)
            testedCandidateID = nil
            await onRevision(macro)
            await reload(loadEvidence: false)
            selectedCandidateID = nil; candidateActions = []; candidateRows = []; selectedActionID = nil; correctedText = ""
            statusMessage = String(localized: "Tested version accepted. The original remains available to restore.", table: "EditorUX")
        } catch {
            // Atomic publication may have succeeded before an IO error. Refresh the complete snapshot.
            testedCandidateID = nil
            if let current = try? await repository.loadMacro(for: macroID) { await onRevision(current) }
            await reload(loadEvidence: false)
            errorMessage = error.localizedDescription
        }
    }

    func restoreOriginal() async {
        guard !isBusy else { return }
        guard canPublish() else {
            errorMessage = String(localized: "Stop recording or playback before changing the accepted version.", table: "EditorUX")
            return
        }
        isBusy = true; errorMessage = nil; statusMessage = ""
        defer { isBusy = false }
        do {
            let restored = try await repository.restoreOriginal(for: macroID)
            testedCandidateID = nil; await onRevision(restored); await reload(loadEvidence: false)
            statusMessage = String(localized: "Original version restored.", table: "EditorUX")
        } catch { errorMessage = error.localizedDescription }
    }

    /// Periodic ticks only invalidate SwiftUI when visible state actually changes.
    func updateVideoPosition(_ time: Double, segmentID: String) {
        let row = videoIndex.activeRow(at: time, segmentID: segmentID)
        if activeSourceActionID != row?.action.id { activeSourceActionID = row?.action.id }
        var marker: MacroReconstructionVideoMarker?
        if let row, let range = row.videoRange, let size = frameSizes[segmentID] {
            if abs(time - range.startTime) <= 0.1, let point = row.startFramePoint { marker = .init(point: point, size: size) }
            else if abs(time - range.startTime - range.duration) <= 0.1, let point = row.endFramePoint { marker = .init(point: point, size: size) }
        }
        if videoMarker != marker { videoMarker = marker }
    }

    func close() {
        videoPlayer?.pause()
        if let videoObserver { videoPlayer?.removeTimeObserver(videoObserver); self.videoObserver = nil }
        cancelTest()
    }
}

private enum MacroReconstructionReviewError: LocalizedError {
    case recordingUnavailable
    var errorDescription: String? {
        String(localized: "The linked recording could not be loaded. Reload it before exporting evidence.", table: "EditorUX")
    }
}
