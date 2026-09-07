import AppKit
import AVFoundation
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

enum MacroReconstructionEvidenceMode: Equatable, Sendable {
    case actionsOnly
    case visualEvidenceUnavailable
    case visualEvidenceAvailable
}

enum MacroReconstructionVideoAlignmentState: Equatable, Sendable {
    case unavailable
    case sourceChangedWithoutLineage
    case partial
    case complete
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
    @Published private(set) var videoAlignmentQualityByActionID: [String: MacroReconstructionVideoAlignmentQuality] = [:]
    @Published private(set) var videoAlignmentState: MacroReconstructionVideoAlignmentState = .unavailable
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
    @Published var optimizationObjective: MacroReconstructionObjective = .robust
    @Published var confirmUncertainties = false
    @Published var correctedText = ""
    private let repository: MacroRepository
    private let testMacro: @MainActor (SavedMacro) async throws -> Void
    private let stopTest: @MainActor () -> Void
    private let onRevision: @MainActor (SavedMacro) async -> Void
    private let editCandidate: @MainActor (MacroStoredCandidate, @escaping @MainActor (MacroStoredCandidate) -> Void) -> Void
    private let evidenceLoader: @MainActor (MacroSemanticRecordingReference, String) async throws -> SemanticRecordingReviewState
    private var evidence: SemanticRecordingReviewState?
    private var videoSegmentID: String?
    private var testTask: Task<Void, Error>?
    private var testCancelled = false
    private let canPublish: @MainActor () -> Bool

    init(macroID: UUID, repository: MacroRepository = .shared,
         testMacro: @escaping @MainActor (SavedMacro) async throws -> Void,
         stopTest: @escaping @MainActor () -> Void,
         canPublish: @escaping @MainActor () -> Bool = { true },
         editCandidate: @escaping @MainActor (MacroStoredCandidate, @escaping @MainActor (MacroStoredCandidate) -> Void) -> Void = { _, _ in },
         loadEvidence: @escaping @MainActor (MacroSemanticRecordingReference, String) async throws -> SemanticRecordingReviewState = { reference, sourceName in
             try await SemanticRecordingReviewPresenter.reviewState(from: reference, sourceName: sourceName)
         },
         onRevision: @escaping @MainActor (SavedMacro) async -> Void) {
        self.macroID = macroID; self.repository = repository
        self.testMacro = testMacro; self.stopTest = stopTest; self.onRevision = onRevision
        self.canPublish = canPublish; self.editCandidate = editCandidate; self.evidenceLoader = loadEvidence
    }

    var selectedCandidate: MacroStoredCandidate? { candidates.first { $0.id == selectedCandidateID } }
    var isSelectedCandidateStale: Bool {
        guard let candidate = selectedCandidate, let currentSourceRevision else { return false }
        return candidate.document.sourceRevision != currentSourceRevision
    }
    var hasSuccessfulTestForSelectedCandidate: Bool {
        selectedCandidateID != nil && testedCandidateID == selectedCandidateID
    }
    var canAccept: Bool {
        !isBusy && !isSelectedCandidateStale && canPublish() && selectedCandidateID != nil && hasSuccessfulTestForSelectedCandidate
            && (selectedCandidate?.document.requiresAttention != true || confirmUncertainties)
    }
    var canEditSelectedCandidate: Bool {
        !isBusy && !isTesting && !isSelectedCandidateStale && selectedCandidate != nil
    }
    var acceptanceBlockedReason: String {
        guard selectedCandidate != nil else {
            return String(localized: "Select a candidate before accepting it.", table: "EditorUX")
        }
        if isSelectedCandidateStale {
            return String(localized: "This candidate belongs to an earlier macro version. Export the current version to continue refining.", table: "EditorUX")
        }
        if !hasSuccessfulTestForSelectedCandidate {
            return String(localized: "You must run 'Test once' before accepting.", table: "EditorUX")
        }
        if selectedCandidate?.document.requiresAttention == true && !confirmUncertainties {
            return String(localized: "Review and acknowledge the candidate's unresolved actions before accepting it.", table: "EditorUX")
        }
        if !canPublish() {
            return String(localized: "Stop recording or playback before changing the accepted version.", table: "EditorUX")
        }
        return ""
    }
    var hasAlignedVideo: Bool { videoAlignmentState == .complete || videoAlignmentState == .partial }
    var hasPartialVideoAlignment: Bool { videoAlignmentState == .partial }
    var evidenceMode: MacroReconstructionEvidenceMode {
        guard source?.semanticRecording != nil else { return .actionsOnly }
        guard let evidence,
              !evidence.bundle.frames.isEmpty || !evidence.bundle.videoSegments.isEmpty else {
            return .visualEvidenceUnavailable
        }
        return .visualEvidenceAvailable
    }
    var canIncludeVisualEvidence: Bool { evidenceMode == .visualEvidenceAvailable }
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
            if loadEvidence {
                evidence = nil
                if let reference = loaded.semanticRecording {
                    do { evidence = try await evidenceLoader(reference, loaded.name) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            try await rebuildProjection(for: loaded)
        } catch { errorMessage = error.localizedDescription }
    }

    private func rebuildProjection(for source: SavedMacro) async throws {
        let recordedProvenance = evidence?.bundle.reconstructionProvenance
        var retainedSources: [String: SavedMacro] = [:]
        for revision in Set(candidates.map { $0.document.sourceRevision }) {
            if let retained = try await repository.loadRetainedSource(revision: revision, for: macroID) {
                retainedSources[revision] = retained
            }
        }
        let lineage = candidates.compactMap { candidate -> MacroReconstructionCandidateLineageStep? in
            guard let retained = retainedSources[candidate.document.sourceRevision] else { return nil }
            return MacroReconstructionCandidateLineageStep(
                sourceRevision: candidate.document.sourceRevision,
                sourceEvents: retained.events,
                targetRevision: candidate.normalizedDigest,
                targetEvents: candidate.macro.events,
                coverage: candidate.document.coverage
            )
        }
        let retainedSourceValues = Array(retainedSources.values)
        let (rows, alignments, alignmentState, revision, index, reviewRows, sourceIndices) = try await Task.detached(priority: .userInitiated) {
            let revision = try MacroCandidateIdentity.revision(of: source)
            let currentActions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
            let unavailable = currentActions.map {
                MacroReconstructionAlignedAction(action: $0, quality: .unavailable, issues: [.videoUnavailable])
            }
            guard let recordedProvenance else {
                let rows = unavailable.map(\.projectedAction)
                let reviewRows = rows.enumerated().map { MacroReconstructionReviewRow(number: $0.offset + 1, action: $0.element.action) }
                let sourceIndices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.action.id, $0.offset) })
                return (rows, unavailable, MacroReconstructionVideoAlignmentState.unavailable, revision, MacroReconstructionVideoIndex(rows: rows), reviewRows, sourceIndices)
            }

            var evidenceSources: [SavedMacro] = []
            if recordedProvenance.matchesSourceEvents(source.events) {
                evidenceSources.append(source)
            }
            for retained in retainedSourceValues where recordedProvenance.matchesSourceEvents(retained.events) {
                let retainedRevision = try MacroCandidateIdentity.revision(of: retained)
                if !evidenceSources.contains(where: { (try? MacroCandidateIdentity.revision(of: $0)) == retainedRevision }) {
                    evidenceSources.append(retained)
                }
            }

            if evidenceSources.isEmpty {
                let rows = unavailable.map(\.projectedAction)
                let reviewRows = rows.enumerated().map { MacroReconstructionReviewRow(number: $0.offset + 1, action: $0.element.action) }
                let sourceIndices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.action.id, $0.offset) })
                let state: MacroReconstructionVideoAlignmentState = recordedProvenance.sourceEventDigest == nil
                    ? .unavailable
                    : .sourceChangedWithoutLineage
                return (rows, unavailable, state, revision, MacroReconstructionVideoIndex(rows: rows), reviewRows, sourceIndices)
            }

            var bestAlignment: [MacroReconstructionAlignedAction]?
            var bestAlignedCount = -1
            for evidenceSource in evidenceSources {
                let evidenceRevision = try MacroCandidateIdentity.revision(of: evidenceSource)
                var times: [Int: Double] = [:]
                for item in recordedProvenance.sourceEvents {
                    guard evidenceSource.events.indices.contains(item.sourceEventIndex),
                          evidenceSource.events[item.sourceEventIndex].time == item.sourcePlaybackTime,
                          times[item.sourceEventIndex] == nil else { continue }
                    times[item.sourceEventIndex] = item.sessionTime
                }
                let evidenceRows = try MacroReconstructionProjector.project(
                    events: evidenceSource.events,
                    sourceRevision: evidenceRevision,
                    sessionTimesByEventIndex: times,
                    videoClock: RecordingVideoClockMapping(segments: recordedProvenance.clockSegments),
                    geometry: RecordingGeometryHistory(snapshots: recordedProvenance.geometrySnapshots)
                )
                guard let aligned = try? MacroReconstructionPartialAlignmentProjector.project(
                    evidenceRows: evidenceRows,
                    evidenceSourceEvents: evidenceSource.events,
                    evidenceSourceRevision: evidenceRevision,
                    targetEvents: source.events,
                    targetRevision: revision,
                    lineage: lineage
                ) else { continue }
                let alignedCount = aligned.reduce(into: 0) { count, row in
                    if row.videoRange != nil { count += 1 }
                }
                if alignedCount > bestAlignedCount {
                    bestAlignment = aligned
                    bestAlignedCount = alignedCount
                }
            }

            let resolved = bestAlignment ?? unavailable
            let alignedCount = resolved.reduce(into: 0) { count, row in
                if row.videoRange != nil { count += 1 }
            }
            let alignmentState: MacroReconstructionVideoAlignmentState
            if alignedCount == resolved.count, !resolved.isEmpty {
                alignmentState = .complete
            } else if alignedCount > 0 {
                alignmentState = .partial
            } else {
                alignmentState = .unavailable
            }
            let rows = resolved.map(\.projectedAction)
            let reviewRows = rows.enumerated().map { MacroReconstructionReviewRow(number: $0.offset + 1, action: $0.element.action) }
            let sourceIndices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.action.id, $0.offset) })
            return (rows, resolved, alignmentState, revision, MacroReconstructionVideoIndex(rows: rows), reviewRows, sourceIndices)
        }.value
        self.source = source
        if !canIncludeVisualEvidence {
            includeVisualEvidence = false
        }
        currentSourceRevision = revision
        projectedActions = rows
        sourceActions = rows.map(\.action)
        sourceActionIndices = sourceIndices
        sourceRows = reviewRows
        videoAlignmentQualityByActionID = Dictionary(uniqueKeysWithValues: alignments.map { ($0.action.id, $0.quality) })
        videoAlignmentState = alignmentState
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

    func importDocument(
        _ document: MacroCandidateDocument,
        importProvenance: MacroCandidateImportProvenance? = .standalone
    ) async {
        await storeCandidateDocument(
            document,
            importProvenance: importProvenance,
            localDraft: false,
            successMessage: String(localized: "Candidate imported. Review its changes, then test it.", table: "EditorUX")
        )
    }

    private func storeCandidateDocument(
        _ document: MacroCandidateDocument,
        importProvenance: MacroCandidateImportProvenance?,
        localDraft: Bool,
        successMessage: String
    ) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; statusMessage = ""
        defer { isBusy = false }
        do {
            let stored: MacroStoredCandidate
            if localDraft {
                stored = try await repository.importCandidateDraft(
                    document,
                    for: macroID,
                    importProvenance: importProvenance
                )
            } else {
                stored = try await repository.importCandidate(
                    document,
                    for: macroID,
                    importProvenance: importProvenance
                )
            }
            candidates = try await repository.listCandidates(for: macroID)
            selectedCandidateID = stored.id; testedCandidateID = nil; confirmUncertainties = false
            selectedActionID = nil; correctedText = ""
            try await updateCandidateRows()
            statusMessage = successMessage
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseCandidateFile() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = true
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
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
            let currentSource = try await repository.loadMacro(for: macroID)
            let input = try await Task.detached(priority: .userInitiated) {
                try MacroReconstructionCandidateInputResolver.decodeInput(
                    at: url,
                    source: currentSource
                )
            }.value
            isBusy = false
            await importDocument(input.document, importProvenance: input.importProvenance)
        } catch { isBusy = false; errorMessage = error.localizedDescription }
    }

    func editSelectedCandidate() {
        guard canEditSelectedCandidate, let candidate = selectedCandidate else { return }
        editCandidate(candidate) { [weak self] saved in
            Task { @MainActor [weak self] in
                await self?.candidateSavedFromEditor(saved)
            }
        }
    }

    private func candidateSavedFromEditor(_ saved: MacroStoredCandidate) async {
        let previousSelection = selectedCandidateID
        do {
            candidates = try await repository.listCandidates(for: macroID)
            selectedCandidateID = saved.id
            selectedActionID = nil
            correctedText = ""
            confirmUncertainties = false
            if saved.id != previousSelection {
                testedCandidateID = nil
                statusMessage = String(localized: "Edited candidate saved. Test this new version before accepting it.", table: "EditorUX")
            }
            try await updateCandidateRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func correctSelectedText() async {
        guard canCorrectText, !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var document = selectedCandidate?.document,
              let action = candidateActions.first(where: { $0.id == selectedActionID }) else { return }
        for index in action.sourceEventIndices where document.macro.events[index].textAnchor != nil {
            document.macro.events[index].textAnchor?.text = correctedText
        }
        // Local corrections create a fresh immutable candidate, preserve package
        // provenance, and require a new test without masquerading as external AI authoring.
        await storeCandidateDocument(
            document,
            importProvenance: selectedCandidate?.importProvenance,
            localDraft: true,
            successMessage: String(localized: "Edited candidate saved. Test this new version before accepting it.", table: "EditorUX")
        )
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
            let objective = optimizationObjective
            let report = try await Task.detached(priority: .userInitiated) {
                try MacroReconstructionPackage.export(source: source, bundle: bundle,
                    bundleDirectory: directory, includeVisualEvidence: includeVisual,
                    objective: objective, to: url)
            }.value
            let localizedWarnings = report.warnings.map(Self.localizedPackageWarning)
            statusMessage = ([String(localized: "AI package exported. Start with harness.json, follow its staged reading plan, generate candidate.json, then import the package or candidate.json.", table: "EditorUX")] + localizedWarnings).joined(separator: "\n")
        } catch { errorMessage = error.localizedDescription }
    }

    static func localizedPackageWarning(_ warning: String) -> String {
        if warning.contains("Video clock alignment is unavailable") {
            return String(localized: "Video clock alignment is unavailable; do not assume video time equals event time.", table: "EditorUX")
        }
        if warning.contains("Recording source event content is unverified") {
            return String(localized: "Recording source event content is unverified or differs from this macro. Alignment is withheld.", table: "EditorUX")
        }
        if warning.hasPrefix("Missing evidence: ") {
            let path = String(warning.dropFirst("Missing evidence: ".count))
            return String(format: String(localized: "Missing evidence: %@", table: "EditorUX"), path)
        }
        if warning.contains("verified redaction clock alignment unavailable") {
            return String(localized: "Video withheld: verified redaction clock alignment unavailable.", table: "EditorUX")
        }
        if warning.contains("Video withheld: complete redaction evidence unavailable") {
            return String(localized: "Video withheld: complete redaction evidence unavailable.", table: "EditorUX")
        }
        if warning.contains("Frame withheld: complete redaction evidence unavailable") {
            return String(localized: "Frame withheld: complete redaction evidence unavailable.", table: "EditorUX")
        }
        if warning.contains("No visual bytes included") {
            return String(localized: "No visual bytes included. Export with explicit visual inclusion to provide permitted video/frames.", table: "EditorUX")
        }
        return warning
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
