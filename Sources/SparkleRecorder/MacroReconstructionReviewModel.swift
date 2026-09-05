import AppKit
import AVKit
import Combine
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

/// Owns repository/panel/player effects. The sheet renders these projections and sends intents.
@MainActor
final class MacroReconstructionReviewModel: ObservableObject {
    let macroID: UUID
    @Published private(set) var source: SavedMacro?
    @Published private(set) var candidates: [MacroStoredCandidate] = []
    @Published private(set) var selectedCandidateID: UUID?
    @Published private(set) var sourceActions: [MacroReconstructedAction] = []
    @Published private(set) var candidateActions: [MacroReconstructedAction] = []
    @Published private(set) var projectedActions: [MacroReconstructionProjectedAction] = []
    @Published private(set) var selectedActionID: String?
    @Published private(set) var videoPlayer: AVPlayer?
    @Published private(set) var activeSourceActionID: String?
    @Published private(set) var videoTime: Double = 0
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
    var canAccept: Bool {
        !isBusy && canPublish() && selectedCandidateID != nil && testedCandidateID == selectedCandidateID
            && (selectedCandidate?.document.requiresAttention != true || confirmUncertainties)
    }
    var hasAlignedVideo: Bool { projectedActions.contains { $0.videoRange != nil } }
    var canCorrectText: Bool {
        guard let candidate = selectedCandidate,
              let action = candidateActions.first(where: { $0.id == selectedActionID }) else { return false }
        return action.sourceEventIndices.contains { candidate.macro.events[$0].textAnchor != nil }
    }

    func reload(loadEvidence: Bool = true) async {
        do {
            let loaded = try await repository.loadMacro(for: macroID)
            source = loaded
            candidates = try await repository.listCandidates(for: macroID)
            sourceActions = try MacroActionReconstructor.reconstruct(events: loaded.events,
                sourceRevision: MacroCandidateIdentity.revision(of: loaded))
            if loadEvidence, let reference = loaded.semanticRecording {
                do { evidence = try await SemanticRecordingReviewPresenter.reviewState(from: reference, sourceName: loaded.name) }
                catch { evidence = nil; errorMessage = error.localizedDescription }
            }
            try rebuildProjection()
        } catch { errorMessage = error.localizedDescription }
    }

    private func rebuildProjection() throws {
        guard let source else { return }
        let recordedProvenance = evidence?.bundle.reconstructionProvenance
        let provenance = recordedProvenance?.matchesSourceEvents(source.events) == true ? recordedProvenance : nil
        var times: [Int: Double] = [:]
        for item in provenance?.sourceEvents ?? [] {
            guard source.events.indices.contains(item.sourceEventIndex),
                  source.events[item.sourceEventIndex].time == item.sourcePlaybackTime,
                  times[item.sourceEventIndex] == nil else { continue }
            times[item.sourceEventIndex] = item.sessionTime
        }
        projectedActions = try MacroReconstructionProjector.project(events: source.events,
            sourceRevision: MacroCandidateIdentity.revision(of: source), sessionTimesByEventIndex: times,
            videoClock: RecordingVideoClockMapping(segments: provenance?.clockSegments ?? []),
            geometry: RecordingGeometryHistory(snapshots: provenance?.geometrySnapshots ?? []))
        if videoPlayer == nil, let first = evidence?.bundle.videoSegments.first {
            loadVideo(segmentID: first.id.uuidString)
        }
    }

    func selectCandidate(_ id: UUID?) {
        guard !isBusy else { return }
        selectedCandidateID = id; selectedActionID = nil; correctedText = ""
        errorMessage = nil; statusMessage = ""
        testedCandidateID = nil; confirmUncertainties = false
        candidateActions = (try? selectedCandidate.map {
            try MacroActionReconstructor.reconstruct(events: $0.macro.events, sourceRevision: "candidate")
        }) ?? []
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
        guard let row = projectedActions.first(where: { $0.action.id == id }),
              let segment = row.videoSegmentID, let range = row.videoRange else { return }
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
                self.videoTime = time.seconds
                self.activeSourceActionID = self.projectedActions.first {
                    $0.videoSegmentID == self.videoSegmentID && $0.videoRange.map {
                        time.seconds >= $0.startTime && time.seconds <= $0.startTime + max(0.1, $0.duration)
                    } == true
                }?.action.id
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
            candidateActions = try MacroActionReconstructor.reconstruct(events: stored.macro.events, sourceRevision: "candidate")
            statusMessage = String(localized: "Candidate imported. Review its changes, then test it.", table: "EditorUX")
        } catch { errorMessage = error.localizedDescription }
    }

    func importCandidateFile(at url: URL) async {
        guard !isBusy else { return }
        do {
            let data = try Data(contentsOf: url)
            let document = try MacroCandidateValidator.decode(data)
            await importDocument(document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseCandidateFile() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.importCandidateFile(at: url)
            }
        }
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
            if source.semanticRecording != nil && evidence == nil {
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
        guard !isBusy, let id = selectedCandidateID else { return }
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

    /// A measured endpoint appears only at its actual mapped video time; no cursor path is invented.
    var videoMarker: (point: PointValue, size: RecordingImageSize)? {
        guard let row = projectedActions.first(where: { $0.action.id == activeSourceActionID }),
              let range = row.videoRange, let evidence,
              let segment = evidence.bundle.videoSegments.first(where: { $0.id.uuidString == videoSegmentID }),
              let size = segment.frameSize else { return nil }
        if abs(videoTime - range.startTime) <= 0.1, let point = row.startFramePoint { return (point, size) }
        if abs(videoTime - range.startTime - range.duration) <= 0.1, let point = row.endFramePoint { return (point, size) }
        return nil
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
