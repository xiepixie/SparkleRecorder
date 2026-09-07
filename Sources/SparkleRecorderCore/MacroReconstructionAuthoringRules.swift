import Foundation

public extension MacroReconstructionAuthoringContract {
    static let authoringRules: [MacroReconstructionAuthoringRule] = [
        .init(id: "schema.knownFieldsOnly", scope: "candidate JSON", requirement: "Use only authoringMacroFields, eventFields, textAnchorFields, and the documented candidate/coverage keys. Unknown playback fields are rejected rather than ignored."),
        .init(id: "schema.supportedMacroVersion", scope: "candidate macro", requirement: "macro.version must be one of capabilities.macroVersions and the event count must not exceed maximumEventCount."),
        .init(id: "timeline.nonDecreasing", scope: "events", requirement: "Event times are finite, nonnegative, nondecreasing, and no later than maximumDuration."),
        .init(id: "coordinates.finiteBounds", scope: "event geometry", requirement: "Absolute/local coordinates are finite and within maximumCoordinateMagnitude; normalized coordinates remain in capabilities.normalizedCoordinateRange."),
        .init(id: "coordinates.completePairs", scope: "event geometry", requirement: "windowLocal, contentLocal, windowNormalized, and contentNormalized coordinates provide both X and Y or neither axis."),
        .init(id: "pointer.fieldBounds", scope: "pointer event", requirement: "mouseButton is between 0 and 31 inclusive and clickCount is between 0 and 100 inclusive."),
        .init(id: "surface.referenceExists", scope: "event", requirement: "Every non-null event.surfaceId references a Playback Surface listed in source-context.json."),
        .init(id: "input.balancedPointer", scope: "events", requirement: "Every enabled mouse-down is released; drag events require the matching button to be held."),
        .init(id: "input.balancedKeyboard", scope: "events", requirement: "Every enabled keyDown is released and transient Command/Option/Shift/Control state is clear at the end."),
        .init(id: "surface.explicitTargetWindow", scope: "event", requirement: "coordinateBinding=targetWindow requires an explicit event.surfaceId that exists in source-context.json."),
        .init(id: "text.explicitSurface", scope: "text operation", requirement: "Text-backed mouse input, waitForText and verifyText require an explicit existing Playback Surface."),
        .init(id: "text.locatorMouseContract", scope: "text-backed mouse input", requirement: "Use coordinateBinding=targetWindow and coordinateStrategy=locatorOnly with a Text Anchor."),
        .init(id: "text.stableGestureIdentity", scope: "locator pointer gesture", requirement: "Mouse-down and mouse-up keep the same surfaceId, Text Anchor, locatorFallbackPolicy and textTimeout; locator-driven gestures cannot drag."),
        .init(id: "text.boundedObservation", scope: "waitForText/verifyText", requirement: "Provide textAnchor and a finite positive textTimeout no greater than maximumTextTimeout."),
        .init(id: "text.anchorBounds", scope: "Text Anchor", requirement: "Anchor text is non-empty and at most 32768 UTF-8 bytes; occurrenceHint is 0...100000; search regions have positive size; normalized regions remain inside [0,1]."),
        .init(id: "text.readableInputBounds", scope: "keyboard/text event", requirement: "unicodeString, when present, is at most 1000000 UTF-8 bytes."),
        .init(id: "text.fallbackRequiresPoint", scope: "Text Anchor", requirement: "locatorFallbackPolicy=allowCoordinateFallback requires coordinateFallback or coordinateFallbackContentNormalized."),
        .init(id: "text.normalizedGeometry", scope: "Text Anchor", requirement: "Normalized rectangles/points remain in [0,1]. If absolute and normalized geometry are both supplied they describe the same recorded content geometry within the validator tolerance."),
        .init(id: "scroll.payloadBounds", scope: "scrollWheel", requirement: "Scroll payload point/fixed deltas are finite and bounded by maximumCoordinateMagnitude; phase and momentumPhase are integer values in 0...255."),
        .init(id: "surface.validDefinition", scope: "Playback Surfaces", requirement: "The Source Revision has at most 1000 surfaces; IDs are non-empty, recorded frames have positive size, and windowTitlePattern is a valid regular expression no larger than 4096 UTF-8 bytes."),
        .init(id: "coverage.complete", scope: "coverage", requirement: "Every source Reconstruction Action, including derived fixed waits, appears exactly once in coverage."),
        .init(id: "coverage.targets", scope: "coverage", requirement: "Preserved/merged/replaced transformations reference real candidate action IDs; removedAsNoise references none; every disposition has a reason."),
        .init(id: "uncertainty.knownActions", scope: "uncertainActionIDs", requirement: "uncertainActionIDs are unique and every ID refers to a known source or candidate Reconstruction Action."),
        .init(id: "surface.sourceOwned", scope: "candidate macro", requirement: "External candidates omit macro.surfaces and select only existing Source Revision Playback Surfaces through event.surfaceId."),
        .init(id: "execution.sourceOwned", scope: "candidate macro", requirement: "loops, speed, followWindowOffset, chainTo, Library metadata, statistics, caches, and evidence links are App-owned and restored from the accepted Source Revision rather than authored in candidate JSON."),
        .init(id: "privacy.noReadableRestoration", scope: "privacy-sanitized source", requirement: "When source playable sanitization withheld readable data, the candidate may reuse readable values already present in the accepted source but may not invent or restore withheld text."),
        .init(id: "disabled.stillValidated", scope: "disabled events", requirement: "Disabled events do not participate in pressed-input balance, but their schema, time, geometry, locator, timeout, surface, and payload fields must still be valid."),
        .init(id: "evidence.noUnalignedInference", scope: "visual evidence", requirement: "When sourceEventsMatchRecording=false, do not infer action-to-video alignment from matching timestamps or indices."),
        .init(id: "evidence.supportedLocatorsOnly", scope: "candidate", requirement: "The current executable locator vocabulary is text only; visible icons/images may inform intent but do not create image/pixel locator event kinds.")
    ]
}
