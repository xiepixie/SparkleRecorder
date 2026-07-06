---
Evidence type: fixture screenshot
Generated: 2026-07-07
Scenario command: swift run SparkleRecorder workflow product-evidence snapshot editor-preview-affordances --output docs/workflow-page-productization/product-evidence/editor-preview-affordances.png
Screenshot file: editor-preview-affordances.png
Source: deterministic fixture overlay actions rendered through TargetCrosshairView
---

# Editor Preview Affordances

This fixture screenshot proves the Macro Editor preview overlay renders action intent from `ActionPreviewAffordance`:

- wait text renders as a labeled condition region with no click pulse
- verify text renders as a labeled condition region with no click pulse
- text click renders a text target region plus click pulse because it sends input
- ordinary coordinate click renders a click pulse target

Boundary: this is fixture product evidence for the overlay component and projection mapping. It does not claim live installed-app editor recording, semantic recording capture, OCR region picker capture, or frame-to-condition Review completion.
