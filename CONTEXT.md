# SparkleRecorder

SparkleRecorder records, refines, and replays desktop automation while preserving enough target context to survive ordinary UI movement and change.

## Language

**Macro**:
A reusable automation made of an ordered playable timeline and its target context.
_Avoid_: Script, recording file

**Recorded Event**:
The smallest persisted timeline item representing playable input or a semantic text observation.
_Avoid_: Action

**Playback Surface**:
The persisted identity and geometry of a target application window used by a Macro.
_Avoid_: Window binding, target window record

**Text Anchor**:
Persisted evidence describing which text should match and where it was observed relative to a Playback Surface.
_Avoid_: OCR box, text locator config

**Text Target**:
The live text match selected from the current Playback Surface for a Text Anchor.
_Avoid_: OCR result, anchor

**Reconstruction Action**:
A deterministic, evidence-facing grouping of Source Revision Recorded Events with explicit Playback Surface and geometry context for AI/review understanding. It is not itself executable.
_Avoid_: AI action, playback event

**Candidate**:
An immutable proposed Macro reconstruction that remains separate from the accepted Macro until review and acceptance.
_Avoid_: Replacement macro, draft macro

**Candidate Draft**:
An editable working copy of one Candidate that becomes a new immutable Candidate when saved.
_Avoid_: Candidate mutation, replacement macro

**Source Revision**:
The executable identity of the accepted Macro from which a Candidate was authored.
_Avoid_: File version, candidate version

## Relationships

- A **Macro** contains many **Recorded Events** and may reference one or more **Playback Surfaces**.
- A **Recorded Event** may carry a **Text Anchor** and reference exactly one **Playback Surface** when its geometry is content-relative.
- A **Text Anchor** may resolve to one **Text Target** during a playback observation.
- A **Reconstruction Action** groups Source Revision **Recorded Events** and carries their known **Playback Surface** context without replacing executable events.
- A **Candidate** is authored against exactly one **Source Revision**.
- A **Candidate Draft** is derived from exactly one **Candidate** and never changes the accepted **Macro** directly.
- Saving a changed **Candidate Draft** creates a new **Candidate** that requires its own playback test.
- Accepting a **Candidate** updates the executable content of its **Macro** while app-owned Library state remains separate.

## Example dialogue

> **Dev:** "The **Text Anchor** uses content-relative geometry. Can playback fall back to another window if its surface is missing?"
> **Domain expert:** "No. Content-relative geometry belongs to one **Playback Surface**; guessing another surface would produce the wrong **Text Target**."

## Flagged ambiguities

- "window" previously referred both to persisted targeting data and the live OS window. Use **Playback Surface** for persisted target identity and "current window" only for the live window resolved during playback.
- "OCR result" and **Text Target** were sometimes used interchangeably. OCR may produce many candidates; the selected live match is the **Text Target**.
