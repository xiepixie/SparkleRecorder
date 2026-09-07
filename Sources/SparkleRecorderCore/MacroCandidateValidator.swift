import Foundation

public enum MacroCandidateValidationError: Error, Equatable, Sendable, LocalizedError {
    case malformedDocument(String)
    case unknownField(String)
    case invalidExecutableIdentity(String)
    case staleSource(expected: String, actual: String)
    case unsupportedVersion(Int)
    case invalidConfiguration(String)
    case invalidEvent(index: Int, reason: String)
    case invalidSurface(id: String, reason: String)
    case invalidCoverage(String)
    case suppressedReadableData

    public var errorDescription: String? {
        switch self {
        case .malformedDocument(let reason): "Candidate document cannot be decoded: \(reason)"
        case .unknownField(let path): "Unsupported candidate field: \(path)"
        case .invalidExecutableIdentity(let reason): "Executable identity cannot be computed: \(reason)"
        case .staleSource(let expected, let actual): "Candidate source revision \(actual) does not match \(expected)."
        case .unsupportedVersion(let version): "Unsupported candidate macro version \(version)."
        case .invalidConfiguration(let reason): "Invalid candidate configuration: \(reason)"
        case .invalidEvent(let index, let reason): "Candidate event \(index): \(reason)"
        case .invalidSurface(let id, let reason): "Candidate surface \(id): \(reason)"
        case .invalidCoverage(let reason): "Candidate coverage: \(reason)"
        case .suppressedReadableData: "Candidate introduces readable fields withheld by source privacy sanitization."
        }
    }
}

public enum MacroCandidateValidator {
    /// Untrusted authoring input must enter here. Nested playback fields are
    /// checked before Codable can discard an unsupported execution instruction.
    public static func decode(_ data: Data) throws -> MacroCandidateDocument {
        guard data.count <= 100_000_000 else {
            throw MacroCandidateValidationError.malformedDocument("Document exceeds 100 MB.")
        }
        do {
            let root = try object(JSONSerialization.jsonObject(with: data), at: "candidate")
            try keys(root, allowed: ["macro", "sourceRevision", "summary", "coverage", "uncertainActionIDs", "model"], at: "candidate")
            let macro = try object(root["macro"], at: "macro")
            try auditMacro(macro)
            if let coverage = root["coverage"] as? [[String: Any]] {
                for (index, entry) in coverage.enumerated() {
                    try keys(entry, allowed: ["sourceActionID", "disposition", "candidateActionIDs", "reason"], at: "coverage[\(index)]")
                }
            }
            return try JSONDecoder().decode(MacroCandidateDocument.self, from: data)
        } catch let error as MacroCandidateValidationError {
            throw error
        } catch {
            throw MacroCandidateValidationError.malformedDocument(String(describing: error))
        }
    }

    public static func normalize(
        _ document: MacroCandidateDocument,
        source: SavedMacro,
        surfaceAuthority: MacroCandidatePlaybackSurfaceAuthority = .sourceRevision
    ) throws -> SavedMacro {
        let revision = try MacroCandidateIdentity.revision(of: source)
        guard document.sourceRevision == revision else {
            throw MacroCandidateValidationError.staleSource(expected: revision, actual: document.sourceRevision)
        }
        let candidate = document.macro
        guard MacroCandidateCapabilities.current.macroVersions.contains(candidate.version) else {
            throw MacroCandidateValidationError.unsupportedVersion(candidate.version)
        }
        guard candidate.events.count <= MacroCandidateCapabilities.current.maximumEventCount else {
            throw MacroCandidateValidationError.invalidConfiguration("Too many events.")
        }
        // Playback configuration belongs to the source; model changes to it do
        // not silently modify the user's loops, speed, chaining or window policy.
        guard source.speed.isFinite, source.speed > 0, source.speed <= 100,
              source.loops >= 0, source.loops <= 1_000_000 else {
            throw MacroCandidateValidationError.invalidConfiguration("Source speed or loop count is out of bounds.")
        }
        let executionSurfaces = surfaceAuthority == .sourceRevision ? source.surfaces : candidate.surfaces
        try validateSurfaces(executionSurfaces)
        if let violation = MacroCandidatePlaybackSurfaceContract.violation(
            candidate: candidate.surfaces,
            source: source.surfaces,
            authority: surfaceAuthority
        ) {
            switch violation {
            case .surfaceSetChanged:
                throw MacroCandidateValidationError.invalidConfiguration(
                    "External candidates must preserve the Source Revision Playback Surface set. Change event.surfaceId to choose a target; live window rebinding is app-owned."
                )
            case .surfaceChanged(let id):
                throw MacroCandidateValidationError.invalidSurface(
                    id: id,
                    reason: "External candidates must preserve Source Revision Playback Surface identity and geometry. Live window rebinding is app-owned."
                )
            }
        }
        try validateEvents(candidate.events, surfaces: executionSurfaces)
        try validateCoverage(document, source: source)
        try validateSuppression(candidate, source: source)
        var normalized = source
        normalized.version = candidate.version
        normalized.events = candidate.events
        normalized.surfaces = surfaceAuthority == .sourceRevision ? source.surfaces : candidate.surfaces
        normalized.refreshCachesFromEvents()
        return normalized
    }

    private static func validateEvents(_ events: [RecordedEvent], surfaces: [String: PlaybackSurface]) throws {
        if let violation = MacroCandidateTextOperationContract.violation(events: events, surfaces: surfaces) {
            switch violation {
            case .missingTextAnchor(let index):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text operation requires a text anchor.")
            case .missingSurface(let index):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text operation requires an explicit Playback Surface.")
            case .unknownSurface(let index, let id):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text operation references missing Playback Surface \(id).")
            case .locatorRequiresMouseEvent(let index):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text locator input is only supported for mouse events.")
            case .locatorRequiresTargetWindowBinding(let index):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text locator mouse input must use target-window binding.")
            case .locatorRequiresLocatorOnlyStrategy(let index):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text locator mouse input must use locator-only coordinate strategy.")
            case .pointerGestureLocatorMismatch(let index, let downIndex):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text locator pointer gesture must keep the same Playback Surface, Text Anchor, fallback policy, and timeout as mouse-down event \(downIndex).")
            case .locatorDrivenPointerGestureCannotDrag(let index, let downIndex):
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: "Text locator pointer gesture from mouse-down event \(downIndex) cannot contain drag movement.")
            }
        }

        var buttons = Set<Int64>()
        var keysDown = Set<UInt16>()
        var modifierFlags: UInt64 = 0
        for (index, event) in events.enumerated() {
            func fail(_ reason: String) throws -> Never {
                throw MacroCandidateValidationError.invalidEvent(index: index, reason: reason)
            }
            guard event.time.isFinite, event.time >= 0,
                  event.time <= MacroCandidateCapabilities.current.maximumDuration,
                  index == 0 || event.time >= events[index - 1].time else {
                try fail("Time must be finite, nonnegative, nondecreasing and at most 24 hours.")
            }
            let coordinates: [CGFloat?] = [event.x, event.y, event.windowLocalX, event.windowLocalY,
                                           event.contentLocalX, event.contentLocalY]
            guard coordinates.compactMap({ $0 }).allSatisfy(validCoordinate) else { try fail("Invalid coordinate.") }
            let normalized = [event.windowNormalizedX, event.windowNormalizedY,
                              event.contentNormalizedX, event.contentNormalizedY].compactMap { $0 }
            guard normalized.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { try fail("Invalid normalized coordinate.") }
            for pair in [(event.windowLocalX, event.windowLocalY), (event.contentLocalX, event.contentLocalY),
                         (event.windowNormalizedX, event.windowNormalizedY), (event.contentNormalizedX, event.contentNormalizedY)] {
                guard (pair.0 == nil) == (pair.1 == nil) else { try fail("Coordinate pairs must supply both axes.") }
            }
            guard event.mouseButton >= 0, event.mouseButton <= 31, event.clickCount >= 0, event.clickCount <= 100 else {
                try fail("Mouse button or click count is out of bounds.")
            }
            if let id = event.surfaceId, surfaces[id] == nil { try fail("Referenced surface \(id) does not exist.") }
            if event.coordinateBinding == .targetWindow, event.surfaceId == nil { try fail("Target-window binding needs an explicit surface.") }
            if let timeout = event.textTimeout, !timeout.isFinite || timeout <= 0 || timeout > MacroCandidateCapabilities.current.maximumTextTimeout {
                try fail("Text timeout must be positive, finite and at most 3600 seconds.")
            }
            if event.kind == .waitForText || event.kind == .verifyText {
                guard event.textAnchor != nil, event.textTimeout != nil else { try fail("Text observation requires an anchor and explicit bounded timeout.") }
            }
            if event.coordinateStrategy == .locatorOnly, event.textAnchor == nil { try fail("Locator-only strategy requires a text anchor.") }
            if let anchor = event.textAnchor {
                guard !anchor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      anchor.text.utf8.count <= 32_768, validRect(anchor.observedFrame) else { try fail("Invalid text or observed anchor frame.") }
                if let hint = anchor.occurrenceHint, hint < 0 || hint > 100_000 { try fail("Invalid locator occurrence hint.") }
                if let rect = anchor.searchRegion, !validRect(rect, positive: true) { try fail("Invalid locator search region.") }
                for rect in [anchor.observedContentNormalizedFrame, anchor.searchContentNormalizedRegion].compactMap({ $0 }) {
                    guard validNormalizedRect(rect) else { try fail("Invalid normalized locator region.") }
                }
                if let point = anchor.coordinateFallback, !validCoordinate(point.x) || !validCoordinate(point.y) { try fail("Invalid locator fallback coordinate.") }
                if let point = anchor.coordinateFallbackContentNormalized,
                   !point.x.isFinite || !point.y.isFinite || !(0...1).contains(point.x) || !(0...1).contains(point.y) {
                    try fail("Invalid normalized locator fallback.")
                }
                if event.surfaceId == nil {
                    try fail("Text operation requires an explicit Playback Surface.")
                }
                if let surfaceId = event.surfaceId,
                   let contentFrame = surfaces[surfaceId]?.recordedContentFrame,
                   !textAnchorGeometryIsConsistent(anchor, in: contentFrame) {
                    try fail("Absolute and content-normalized text geometry disagree.")
                }
                if event.locatorFallbackPolicy == .allowCoordinateFallback,
                   anchor.coordinateFallback == nil && anchor.coordinateFallbackContentNormalized == nil {
                    try fail("Coordinate fallback policy requires an explicit fallback point.")
                }
            }
            if let text = event.unicodeString, text.utf8.count > 1_000_000 { try fail("Readable input exceeds size limit.") }
            if let payload = event.scrollPayload {
                guard validCoordinate(payload.deltaX), validCoordinate(payload.deltaY),
                      [payload.fixedDeltaX, payload.fixedDeltaY].compactMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                      payload.phase >= 0, payload.phase <= 255,
                      payload.momentumPhase == nil || (0...255).contains(payload.momentumPhase!) else { try fail("Invalid scroll payload.") }
            }
            guard event.isDisabled != true else { continue }
            switch event.kind {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                let button = buttonNumber(event)
                guard buttons.insert(button).inserted else { try fail("Mouse button is already down.") }
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                guard buttons.remove(buttonNumber(event)) != nil else { try fail("Mouse release has no matching press.") }
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                guard buttons.contains(buttonNumber(event)) else { try fail("Drag has no matching mouse press.") }
            case .keyDown: keysDown.insert(event.keyCode) // Repeated key downs are valid key repeat.
            case .keyUp:
                guard keysDown.remove(event.keyCode) != nil else { try fail("Key release has no matching press.") }
            case .flagsChanged:
                // Ignore Caps Lock and device-specific flags; these four are
                // transient modifiers whose final pressed state must be released.
                modifierFlags = event.flags & 0x1e0000
            default: break
            }
        }
        guard buttons.isEmpty, keysDown.isEmpty, modifierFlags == 0 else {
            throw MacroCandidateValidationError.invalidEvent(index: max(0, events.count - 1), reason: "Input ends with a held mouse button, key or modifier.")
        }
    }

    private static func textAnchorGeometryIsConsistent(
        _ anchor: TextAnchor,
        in contentFrame: RectValue,
        tolerance: CGFloat = 3
    ) -> Bool {
        func projected(_ normalized: RectValue) -> RectValue {
            RectValue(
                x: contentFrame.x + normalized.x * contentFrame.width,
                y: contentFrame.y + normalized.y * contentFrame.height,
                width: normalized.width * contentFrame.width,
                height: normalized.height * contentFrame.height
            )
        }
        func projected(_ normalized: PointValue) -> PointValue {
            PointValue(
                x: contentFrame.x + normalized.x * contentFrame.width,
                y: contentFrame.y + normalized.y * contentFrame.height
            )
        }
        func agrees(_ lhs: RectValue, _ rhs: RectValue) -> Bool {
            abs(lhs.x - rhs.x) <= tolerance
                && abs(lhs.y - rhs.y) <= tolerance
                && abs(lhs.width - rhs.width) <= tolerance
                && abs(lhs.height - rhs.height) <= tolerance
        }
        func agrees(_ lhs: PointValue, _ rhs: PointValue) -> Bool {
            abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
        }

        if let normalized = anchor.observedContentNormalizedFrame,
           anchor.observedFrame.width > 0,
           anchor.observedFrame.height > 0,
           !agrees(projected(normalized), anchor.observedFrame) {
            return false
        }
        if let normalized = anchor.searchContentNormalizedRegion,
           let absolute = anchor.searchRegion,
           !agrees(projected(normalized), absolute) {
            return false
        }
        if let normalized = anchor.coordinateFallbackContentNormalized,
           let absolute = anchor.coordinateFallback,
           !agrees(projected(normalized), absolute) {
            return false
        }
        return true
    }

    private static func buttonNumber(_ event: RecordedEvent) -> Int64 {
        switch event.kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: 0
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: 1
        default: event.mouseButton
        }
    }

    private static func validCoordinate(_ value: CGFloat) -> Bool {
        value.isFinite && abs(value) <= MacroCandidateCapabilities.current.maximumCoordinateMagnitude
    }
    private static func validRect(_ rect: RectValue, positive: Bool = false) -> Bool {
        [rect.x, rect.y, rect.width, rect.height].allSatisfy(validCoordinate)
            && (positive ? rect.width > 0 && rect.height > 0 : rect.width >= 0 && rect.height >= 0)
    }
    private static func validNormalizedRect(_ rect: RectValue) -> Bool {
        validRect(rect, positive: true) && rect.x >= 0 && rect.y >= 0
            && rect.x + rect.width <= 1 && rect.y + rect.height <= 1
    }
    private static func validateSurfaces(_ surfaces: [String: PlaybackSurface]) throws {
        guard surfaces.count <= 1000 else { throw MacroCandidateValidationError.invalidConfiguration("Too many surfaces.") }
        for (id, surface) in surfaces {
            guard !id.isEmpty, validRect(surface.recordedFrame, positive: true),
                  surface.recordedContentFrame.map({ validRect($0, positive: true) }) ?? true else {
                throw MacroCandidateValidationError.invalidSurface(id: id, reason: "Invalid identifier or geometry.")
            }
            if let pattern = surface.windowTitlePattern {
                guard pattern.utf8.count <= 4096, (try? NSRegularExpression(pattern: pattern)) != nil else {
                    throw MacroCandidateValidationError.invalidSurface(id: id, reason: "Invalid window title pattern.")
                }
            }
        }
    }

    private static func validateCoverage(_ document: MacroCandidateDocument, source: SavedMacro) throws {
        do {
            let sourceIDs = Set(try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: document.sourceRevision).map(\.id))
            let candidateIDs = Set(try MacroActionReconstructor.reconstruct(events: document.macro.events, sourceRevision: "candidate").map(\.id))
            var seen = Set<String>()
            for item in document.coverage {
                guard sourceIDs.contains(item.sourceActionID), seen.insert(item.sourceActionID).inserted else {
                    throw MacroCandidateValidationError.invalidCoverage("Unknown or duplicate source action \(item.sourceActionID).")
                }
                guard !item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MacroCandidateValidationError.invalidCoverage("Every disposition requires an explanation.")
                }
                guard Set(item.candidateActionIDs).count == item.candidateActionIDs.count,
                      item.candidateActionIDs.allSatisfy(candidateIDs.contains) else {
                    throw MacroCandidateValidationError.invalidCoverage("Unknown or duplicate candidate action target.")
                }
                switch item.disposition {
                case .removedAsNoise:
                    guard item.candidateActionIDs.isEmpty else { throw MacroCandidateValidationError.invalidCoverage("Noise removal cannot reference replacement actions.") }
                case .unresolved: break
                default:
                    guard !item.candidateActionIDs.isEmpty else { throw MacroCandidateValidationError.invalidCoverage("Transformation needs a real candidate action target.") }
                }
            }
            guard seen == sourceIDs else { throw MacroCandidateValidationError.invalidCoverage("Every source action, including fixed waits, must have a disposition.") }
            let knownIDs = sourceIDs.union(candidateIDs)
            guard Set(document.uncertainActionIDs).count == document.uncertainActionIDs.count,
                  document.uncertainActionIDs.allSatisfy(knownIDs.contains) else {
                throw MacroCandidateValidationError.invalidCoverage("Uncertain action IDs must identify source or candidate actions.")
            }
        } catch let error as MacroCandidateValidationError {
            throw error
        } catch {
            throw MacroCandidateValidationError.invalidCoverage(String(describing: error))
        }
    }

    private static func validateSuppression(_ candidate: SavedMacro, source: SavedMacro) throws {
        guard let sanitization = source.playableSanitization,
              sanitization.withheldReadableFieldCount > 0 || sanitization.reviewRequiredFieldCount > 0 else { return }
        let readable = Set(source.events.flatMap { [$0.unicodeString, $0.textAnchor?.text, $0.behaviorGroupName].compactMap { $0 }.filter { !$0.isEmpty } })
        let proposed = candidate.events.flatMap { [$0.unicodeString, $0.textAnchor?.text, $0.behaviorGroupName].compactMap { $0 }.filter { !$0.isEmpty } }
        guard proposed.allSatisfy(readable.contains) else { throw MacroCandidateValidationError.suppressedReadableData }
    }

    private static func object(_ value: Any?, at path: String) throws -> [String: Any] {
        guard let result = value as? [String: Any] else { throw MacroCandidateValidationError.malformedDocument("Expected object at \(path).") }
        return result
    }
    private static func keys(_ object: [String: Any], allowed: Set<String>, at path: String) throws {
        if let unknown = Set(object.keys).subtracting(allowed).sorted().first { throw MacroCandidateValidationError.unknownField("\(path).\(unknown)") }
    }
    private static func nested(_ object: [String: Any], field: String, allowed: Set<String>, at path: String) throws {
        guard let value = object[field], !(value is NSNull) else { return }
        try keys(try self.object(value, at: "\(path).\(field)"), allowed: allowed, at: "\(path).\(field)")
    }
    private static func auditMacro(_ macro: [String: Any]) throws {
        try keys(macro, allowed: MacroCandidateSchema.acceptedMacroFields, at: "macro")
        let rect: Set<String> = ["x", "y", "width", "height"]
        let point: Set<String> = ["x", "y"]
        func surface(_ value: Any, path: String) throws {
            let value = try object(value, at: path)
            try keys(value, allowed: MacroCandidateSchema.surfaceFields, at: path)
            for field in ["recordedFrame", "recordedContentFrame"] { try nested(value, field: field, allowed: rect, at: path) }
        }
        if let value = macro["surface"], !(value is NSNull) { try surface(value, path: "macro.surface") }
        if let values = macro["surfaces"] as? [String: Any] {
            for (id, value) in values { try surface(value, path: "macro.surfaces.\(id)") }
        }
        guard let events = macro["events"] as? [[String: Any]] else { throw MacroCandidateValidationError.malformedDocument("Expected macro.events array.") }
        for (index, event) in events.enumerated() {
            let path = "macro.events[\(index)]"
            try keys(event, allowed: MacroCandidateSchema.eventFields, at: path)
            try nested(event, field: "scrollPayload", allowed: ["deltaX", "deltaY", "lineDeltaX", "lineDeltaY", "phase", "momentumPhase", "fixedDeltaX", "fixedDeltaY", "isContinuous"], at: path)
            try nested(event, field: "behaviorGroupID", allowed: ["rawValue"], at: path)
            if let anchor = event["textAnchor"], !(anchor is NSNull) {
                let anchor = try object(anchor, at: "\(path).textAnchor")
                try keys(anchor, allowed: MacroCandidateSchema.anchorFields, at: "\(path).textAnchor")
                for field in ["observedFrame", "searchRegion", "observedContentNormalizedFrame", "searchContentNormalizedRegion"] {
                    try nested(anchor, field: field, allowed: rect, at: "\(path).textAnchor")
                }
                for field in ["coordinateFallback", "coordinateFallbackContentNormalized"] {
                    try nested(anchor, field: field, allowed: point, at: "\(path).textAnchor")
                }
            }
        }
    }
}
