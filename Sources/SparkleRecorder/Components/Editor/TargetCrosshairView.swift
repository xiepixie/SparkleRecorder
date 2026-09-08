import Cocoa
import SwiftUI
import SparkleRecorderCore

private struct ActiveSearchRegionEdit {
    let actionID: UUID
    let handle: PreviewSearchRegionHandle
    let originalRect: CGRect
    var translation: CGSize
}

struct TargetCrosshairView: View {
    @ObservedObject var state: OverlayState

    @State private var pulseScale: CGFloat = 0.8
    @State private var pulseOpacity: Double = 0.8
    @State private var lineDashPhase: CGFloat = 0

    @State private var activeDrag: ActiveDragEdit?
    @State private var confirmFlash: Bool = false
    @State private var flashPoint: CGPoint? = nil
    @State private var hoveredActionID: UUID?
    @State private var activeSearchRegionEdit: ActiveSearchRegionEdit?

    private var actions: [RelativePreviewAction] { state.actions }

    private func isDetailed(_ action: RelativePreviewAction) -> Bool {
        state.detailActionIDs.contains(action.id)
    }

    private func isSelected(_ action: RelativePreviewAction) -> Bool {
        state.selectedActionID == action.id
    }

    private func isFocused(_ action: RelativePreviewAction) -> Bool {
        guard let selectedActionID = state.selectedActionID else { return true }
        return selectedActionID == action.id || hoveredActionID == action.id
    }

    private func previewOpacity(for action: RelativePreviewAction) -> Double {
        isFocused(action) ? 1.0 : 0.28
    }

    private func shouldAnimate(_ action: RelativePreviewAction) -> Bool {
        guard isDetailed(action) else { return false }
        return isSelected(action) || state.detailActionIDs.count == 1
    }

    private func shouldRevealLocatorFallback(_ action: RelativePreviewAction) -> Bool {
        isDetailed(action) && action.usesCoordinateFallback && action.fallbackPoint != nil
    }

    private func canEditGeometry(_ action: RelativePreviewAction) -> Bool {
        action.allowsGeometryEditing && isSelected(action)
    }

    private func displayedSearchRegion(for action: RelativePreviewAction) -> CGRect? {
        guard let region = action.searchRegion else { return nil }
        guard let edit = activeSearchRegionEdit, edit.actionID == action.id else { return region }
        return PreviewSearchRegionProjector.adjusted(
            original: edit.originalRect,
            handle: edit.handle,
            translation: edit.translation,
            bounds: action.targetSurfaceFrame,
            minimumSize: PreviewInteractionMetrics.searchRegionMinimumSize
        )
    }

    private func updateSearchRegionDrag(
        action: RelativePreviewAction,
        handle: PreviewSearchRegionHandle,
        translation: CGSize
    ) {
        guard let region = action.searchRegion else { return }
        if activeSearchRegionEdit?.actionID != action.id || activeSearchRegionEdit?.handle != handle {
            activeSearchRegionEdit = ActiveSearchRegionEdit(
                actionID: action.id,
                handle: handle,
                originalRect: region,
                translation: translation
            )
        } else {
            activeSearchRegionEdit?.translation = translation
        }
    }

    private func finishSearchRegionDrag(action: RelativePreviewAction, handle: PreviewSearchRegionHandle, translation: CGSize) {
        guard let original = action.searchRegion else { return }
        let finalRect = PreviewSearchRegionProjector.adjusted(
            original: original,
            handle: handle,
            translation: translation.clamped(to: 1000),
            bounds: action.targetSurfaceFrame,
            minimumSize: PreviewInteractionMetrics.searchRegionMinimumSize
        )
        activeSearchRegionEdit = nil
        guard let window = state.window else { return }
        let screenRect = swiftuiToScreen(finalRect, window: window, primaryScreenHeight: state.primaryScreenHeight)
        CoordinatePreviewOverlay.shared.onSearchRegionEnded?(action.id, screenRect)
    }

    private func displayedFallbackPoint(for action: RelativePreviewAction) -> CGPoint? {
        guard let fallback = action.fallbackPoint else { return nil }
        guard let drag = activeDrag,
              drag.actionID == action.id,
              drag.handle == .start else {
            return fallback
        }
        return fallback + drag.clampedTranslation
    }

    private func pointMetadata(for action: RelativePreviewAction) -> String? {
        switch action.kind {
        case .doubleClick:
            return "×2"
        case .repeatedClick:
            return "×\(max(action.clickCount, 2))"
        case .longPress:
            return String(format: "%.1fs", max(action.duration, 0))
        default:
            return nil
        }
    }

    private func mouseButtonMetadata(for action: RelativePreviewAction) -> String? {
        guard action.kind.isClickFamily, let mouseButton = action.mouseButton else { return nil }
        switch mouseButton {
        case 0:
            return nil
        case 1:
            return String(localized: "Right", table: "Common")
        case 2:
            return String(localized: "Middle", table: "Common")
        default:
            return "#\(mouseButton + 1)"
        }
    }

    private func scrollSymbol(for action: RelativePreviewAction) -> String {
        let dx = Int64(action.scrollDeltaX ?? 0)
        let dy = Int64(action.scrollDeltaY ?? 0)
        if abs(dy) >= abs(dx), dy != 0 {
            return dy > 0 ? "arrow.up" : "arrow.down"
        }
        if dx != 0 {
            return dx > 0 ? "arrow.right" : "arrow.left"
        }
        return "arrow.up.and.down"
    }

    private func scrollAmount(for action: RelativePreviewAction) -> String? {
        let dx = Int64(action.scrollDeltaX ?? 0)
        let dy = Int64(action.scrollDeltaY ?? 0)
        let amount = max(abs(dx), abs(dy))
        return amount > 0 ? "\(amount)" : nil
    }

    @ViewBuilder
    private func orderBadge(for action: RelativePreviewAction) -> some View {
        Text("\(action.order)")
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 0.5)
            .background(
                Capsule()
                    .fill(action.themeColor)
                    .shadow(color: .black.opacity(0.2), radius: 1)
            )
    }

    @ViewBuilder
    private func semanticBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.94)))
            .shadow(color: .black.opacity(0.18), radius: 1)
    }

    private func pathStrokeStyle(for action: RelativePreviewAction) -> StrokeStyle {
        if action.affordance == .pointSequence {
            return StrokeStyle(
                lineWidth: 1.8,
                lineCap: .round,
                lineJoin: .round,
                dash: [3, 5],
                dashPhase: shouldAnimate(action) ? lineDashPhase : 0
            )
        }
        return StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
    }

    private func previewEdit(for action: RelativePreviewAction) -> PreviewPathEdit? {
        guard let drag = activeDrag, drag.actionID == action.id else { return nil }
        switch drag.handle {
        case .start:
            return .start(drag.clampedTranslation)
        case .end:
            return .end(drag.clampedTranslation)
        case .body:
            return .body(drag.clampedTranslation)
        case .point(let pointIndex):
            return .point(index: pointIndex, translation: drag.clampedTranslation)
        }
    }

    private func displayGeometry(for action: RelativePreviewAction) -> PreviewPathGeometry {
        let edit = previewEdit(for: action)
        return PreviewPathProjector.geometry(
            dragPath: action.dragPath,
            selectedPoint: action.selectedPoint,
            previewsPointSequence: action.kind.previewsPointSequence,
            edit: edit
        )
    }

    private func beginOrUpdateDrag(actionID: UUID, handle: DragHandle, translation: CGSize) {
        let shouldStartSession = activeDrag == nil || activeDrag?.actionID != actionID || activeDrag?.handle != handle
        activeDrag = ActiveDragEdit(actionID: actionID, handle: handle, translation: translation)
        if shouldStartSession {
            CoordinatePreviewOverlay.shared.onDragStarted?(actionID)
        }
    }

    private func confirmationPoint(for action: RelativePreviewAction, handle: DragHandle, translation: CGSize) -> CGPoint? {
        let edit: PreviewPathEdit
        switch handle {
        case .start:
            edit = .start(translation)
        case .end:
            edit = .end(translation)
        case .body:
            edit = .body(translation)
        case .point(let pointIndex):
            edit = .point(index: pointIndex, translation: translation)
        }

        let geometry = PreviewPathProjector.geometry(
            dragPath: action.dragPath,
            selectedPoint: action.selectedPoint,
            previewsPointSequence: action.kind.previewsPointSequence,
            edit: edit
        )

        switch handle {
        case .start:
            return geometry.startPoint
        case .end:
            return geometry.endPoint
        case .body:
            return geometry.endPoint ?? geometry.startPoint ?? geometry.path.last
        case .point(let pointIndex):
            guard geometry.path.indices.contains(pointIndex) else { return nil }
            return geometry.path[pointIndex]
        }
    }

    private func targetBadgeTitle(for action: RelativePreviewAction) -> String? {
        switch action.affordance {
        case .locatorInputTarget:
            return humanActionKindName(action.kind)
        case .waitTextRegion:
            return String(localized: "Wait text", table: "EditorUX")
        case .waitTextGoneRegion:
            return String(localized: "Wait gone", table: "EditorUX")
        case .verifyTextRegion:
            return String(localized: "Verify text", table: "EditorUX")
        default:
            return nil
        }
    }

    @ViewBuilder
    private func targetBadge(for action: RelativePreviewAction) -> some View {
        if let title = targetBadgeTitle(for: action) {
            let targetText = action.targetText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTargetText = !(targetText?.isEmpty ?? true)

            VStack(alignment: .leading, spacing: hasTargetText ? 5 : 0) {
                HStack(spacing: 5) {
                    Text("\(action.order)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(Capsule().fill(Color.white.opacity(0.18)))

                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if let metadata = pointMetadata(for: action) {
                        Text(metadata)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    }

                    if let button = mouseButtonMetadata(for: action) {
                        Text(button)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    }
                }

                if let targetText, !targetText.isEmpty {
                    Text("“\(targetText)”")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if action.usesCoordinateFallback && action.fallbackPoint == nil {
                    Label(
                        String(localized: "Fallback not set", table: "EditorUX"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(width: hasTargetText ? 300 : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(action.themeColor.opacity(action.affordance.showsConditionRegion ? 0.94 : 0.88))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            )
            .fixedSize(horizontal: !hasTargetText, vertical: true)
            .allowsHitTesting(false)
        }
    }

    private func backdropTitle(for mode: PreviewSurfaceBackdropMode) -> String {
        switch mode {
        case .recordedLayout:
            return String(localized: "Target window unavailable", table: "EditorUX")
        case .unboundLastPosition, .unboundCentered:
            return String(localized: "No target window", table: "EditorUX")
        }
    }

    private func backdropSubtitle(for mode: PreviewSurfaceBackdropMode) -> String {
        switch mode {
        case .recordedLayout:
            return String(localized: "Showing the recorded window layout", table: "EditorUX")
        case .unboundLastPosition:
            return String(localized: "Using the last recorded position", table: "EditorUX")
        case .unboundCentered:
            return String(localized: "The recorded position is off-screen; showing it in the center", table: "EditorUX")
        }
    }

    private func targetBadgeOrigin(
        for action: RelativePreviewAction,
        anchorFrame: CGRect,
        canvasSize: CGSize
    ) -> CGPoint {
        let cardWidth: CGFloat = 316
        let margin: CGFloat = 12
        let x = min(max(anchorFrame.minX, margin), max(margin, canvasSize.width - cardWidth - margin))

        if !action.searchRegionIsExplicit,
           action.affordance.showsConditionRegion {
            return CGPoint(x: x, y: min(anchorFrame.minY + 42, max(margin, canvasSize.height - 120)))
        }

        let below = anchorFrame.maxY + 8
        if below < canvasSize.height - 120 {
            return CGPoint(x: x, y: below)
        }
        return CGPoint(x: x, y: max(margin, anchorFrame.minY - 96))
    }

    @ViewBuilder
    private func searchRegionCornerHandle(
        action: RelativePreviewAction,
        region: CGRect,
        handle: PreviewSearchRegionHandle,
        point: CGPoint
    ) -> some View {
        Circle()
            .fill(Color.black.opacity(0.82))
            .overlay(Circle().stroke(action.themeColor, lineWidth: 2))
            .frame(
                width: PreviewInteractionMetrics.searchCornerVisualDiameter,
                height: PreviewInteractionMetrics.searchCornerVisualDiameter
            )
            .shadow(color: .black.opacity(0.24), radius: 2)
            .frame(
                width: PreviewInteractionMetrics.searchCornerHitDiameter,
                height: PreviewInteractionMetrics.searchCornerHitDiameter
            )
            .contentShape(Circle())
            .position(point)
            .help(String(localized: "Resize search area", table: "EditorUX"))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSearchRegionDrag(action: action, handle: handle, translation: value.translation)
                    }
                    .onEnded { value in
                        finishSearchRegionDrag(action: action, handle: handle, translation: value.translation)
                    }
            )
    }

    @ViewBuilder
    private func searchRegionEditorHandles(for action: RelativePreviewAction, region: CGRect) -> some View {
        if action.searchRegionIsExplicit && canEditGeometry(action) {
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.84))
                    .overlay(Capsule().stroke(action.themeColor.opacity(0.95), lineWidth: 1.5))
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(action.themeColor)
            }
            .frame(
                width: PreviewInteractionMetrics.searchMoveVisualSize.width,
                height: PreviewInteractionMetrics.searchMoveVisualSize.height
            )
            .frame(
                width: PreviewInteractionMetrics.searchMoveHitSize.width,
                height: PreviewInteractionMetrics.searchMoveHitSize.height
            )
            .contentShape(Rectangle())
            .position(x: region.midX, y: region.minY)
            .help(String(localized: "Move search area", table: "EditorUX"))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSearchRegionDrag(action: action, handle: .move, translation: value.translation)
                    }
                    .onEnded { value in
                        finishSearchRegionDrag(action: action, handle: .move, translation: value.translation)
                    }
            )

            searchRegionCornerHandle(
                action: action,
                region: region,
                handle: .topLeft,
                point: CGPoint(x: region.minX, y: region.minY)
            )
            searchRegionCornerHandle(
                action: action,
                region: region,
                handle: .topRight,
                point: CGPoint(x: region.maxX, y: region.minY)
            )
            searchRegionCornerHandle(
                action: action,
                region: region,
                handle: .bottomLeft,
                point: CGPoint(x: region.minX, y: region.maxY)
            )
            searchRegionCornerHandle(
                action: action,
                region: region,
                handle: .bottomRight,
                point: CGPoint(x: region.maxX, y: region.maxY)
            )
        }
    }

    private func coordinateString(_ pt: CGPoint) -> String {
        return "(\(Int(pt.x.rounded())), \(Int(pt.y.rounded())))"
    }

    @ViewBuilder
    private func tooltipView(for displayPt: CGPoint) -> some View {
        let screenPt = {
            if let win = state.window {
                return swiftuiToScreen(displayPt, window: win, primaryScreenHeight: state.primaryScreenHeight)
            }
            return displayPt
        }()

        Text(coordinateString(screenPt))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.8))
            .clipShape(.rect(cornerRadius: 5))
            .offset(y: -36)
            .fixedSize()
    }

    var body: some View {
        let actionGeometries = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, displayGeometry(for: $0)) })
        let surfaceBackdrops = Dictionary(
            actions.compactMap(\.surfaceBackdrop).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted { $0.id < $1.id }

        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
            ForEach(surfaceBackdrops) { backdrop in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    Color.secondary.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 1.25, dash: [7, 6])
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 7, height: 7)
                            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                            Circle().fill(Color.secondary.opacity(0.28)).frame(width: 7, height: 7)
                            if let title = backdrop.title, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.bottom, 5)

                        Text(backdropTitle(for: backdrop.mode))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.78))
                        Text(backdropSubtitle(for: backdrop.mode))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: min(backdrop.frame.width - 24, 360), alignment: .leading)
                }
                .frame(width: backdrop.frame.width, height: backdrop.frame.height)
                .offset(x: backdrop.frame.minX, y: backdrop.frame.minY)
                .allowsHitTesting(false)
            }

            // 1. Confirmation ripple. We intentionally do not connect unrelated actions:
            // a sequence line would imply pointer travel that playback does not perform.
            if let fPt = flashPoint {
                Circle()
                    .stroke(Color.green.opacity(confirmFlash ? 0.8 : 0.0), lineWidth: 2)
                    .frame(width: confirmFlash ? 16 : 48, height: confirmFlash ? 16 : 48)
                    .position(fPt)
            }

            // 3. Render each action's markers
            ForEach(actions) { action in
                if let region = displayedSearchRegion(for: action) {
                    let isSecondaryLocatorRegion = action.affordance == .locatorInputTarget && action.observedFrame != nil
                    let isImplicitWholeSurface = !action.searchRegionIsExplicit
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            action.themeColor.opacity(
                                isImplicitWholeSurface ? 0.018 : (isSecondaryLocatorRegion ? 0.035 : 0.08)
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    action.themeColor.opacity(
                                        isImplicitWholeSurface ? 0.34 : (isSecondaryLocatorRegion ? 0.42 : 0.9)
                                    ),
                                    style: StrokeStyle(
                                        lineWidth: isImplicitWholeSurface ? 1 : (isSecondaryLocatorRegion ? 1 : (isSelected(action) ? 2 : 1.5)),
                                        dash: isImplicitWholeSurface ? [4, 7] : [7, 5],
                                        dashPhase: shouldAnimate(action) && !isImplicitWholeSurface ? lineDashPhase : 0
                                    )
                                )
                        )
                        .frame(width: region.width, height: region.height)
                        .position(x: region.midX, y: region.midY)
                        .opacity(previewOpacity(for: action))
                        .allowsHitTesting(false)

                    searchRegionEditorHandles(for: action, region: region)
                        .opacity(previewOpacity(for: action))
                }

                if let observed = action.observedFrame {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(action.themeColor.opacity(0.95), lineWidth: isSelected(action) ? 2 : 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(action.themeColor.opacity(0.12))
                        )
                        .frame(width: observed.width, height: observed.height)
                        .position(x: observed.midX, y: observed.midY)
                        .opacity(previewOpacity(for: action))
                        .allowsHitTesting(false)
                }

                if isDetailed(action),
                   action.affordance.showsTargetRegionLabel,
                   let anchorFrame = action.observedFrame ?? displayedSearchRegion(for: action) {
                    let origin = targetBadgeOrigin(for: action, anchorFrame: anchorFrame, canvasSize: geometry.size)
                    targetBadge(for: action)
                        .offset(x: origin.x, y: origin.y)
                        .opacity(previewOpacity(for: action))
                }

	                if action.affordance.showsLocatorFallbackPoint,
                       shouldRevealLocatorFallback(action),
                       let fallback = displayedFallbackPoint(for: action) {
                        let isCurrentFallbackDrag = activeDrag?.actionID == action.id && activeDrag?.handle == .start
                        ZStack {
                            if isCurrentFallbackDrag {
                                tooltipView(for: fallback)
                            }

                            Circle()
                                .stroke(action.themeColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
                                .frame(width: 18, height: 18)
                            Circle()
                                .fill(action.themeColor)
                                .frame(width: 4, height: 4)

                            if isSelected(action) || actions.count == 1 {
                                semanticBadge(String(localized: "Fallback", table: "Common"), color: action.themeColor)
                                    .offset(x: 28, y: 17)
                            }
                        }
                        .frame(
                            width: PreviewInteractionMetrics.fallbackHitRadius * 2,
                            height: PreviewInteractionMetrics.fallbackHitRadius * 2
                        )
                        .contentShape(Circle())
                        .offset(
                            x: fallback.x - PreviewInteractionMetrics.fallbackHitRadius,
                            y: fallback.y - PreviewInteractionMetrics.fallbackHitRadius
                        )
                        .opacity(isCurrentFallbackDrag ? 1 : max(0.42, previewOpacity(for: action) * 0.72))
                        .help(String(localized: "Fallback", table: "Common"))
                        .allowsHitTesting(canEditGeometry(action))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    activeDrag = ActiveDragEdit(
                                        actionID: action.id,
                                        handle: .start,
                                        translation: value.translation
                                    )
                                }
                                .onEnded { value in
                                    let finalTranslation = value.translation.clamped(to: 800)
                                    activeDrag = nil
                                    let distance = hypot(finalTranslation.width, finalTranslation.height)
                                    guard distance >= 0.5,
                                          let originalFallback = action.fallbackPoint,
                                          let window = state.window else { return }

                                    let finalPoint = originalFallback + finalTranslation
                                    let screenPoint = swiftuiToScreen(
                                        finalPoint,
                                        window: window,
                                        primaryScreenHeight: state.primaryScreenHeight
                                    )
                                    CoordinatePreviewOverlay.shared.onLocatorFallbackEnded?(action.id, screenPoint)
                                    flashPoint = finalPoint
                                    confirmFlash = true
                                    withAnimation(.easeOut(duration: 0.6)) {
                                        confirmFlash = false
                                    }
                                }
                        )
		                }

		                // Drag path
		                let displayPath = actionGeometries[action.id]?.path ?? []
	                if action.affordance.showsPath, displayPath.count > 1 {
                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(Color.black.opacity(0.22 * previewOpacity(for: action)), lineWidth: 3.8)

                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(
                        action.themeColor.opacity(previewOpacity(for: action)),
                        style: pathStrokeStyle(for: action)
                    )

                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(
                        Color.clear,
                        style: StrokeStyle(
                            lineWidth: PreviewInteractionMetrics.pathHitTolerance * 2,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .contentShape(Path { path in
                        path.addLines(displayPath)
                    })
                    .allowsHitTesting(isDetailed(action))
                    .help(action.kind.previewsPointSequence
                          ? String(localized: "Drag line to move all click points", table: "EditorUX")
                          : String(localized: "Drag path to move the whole drag", table: "EditorUX"))
                    .onHover { hovering in
                        hoveredActionID = hovering ? action.id : (hoveredActionID == action.id ? nil : hoveredActionID)
                    }
	                    .gesture(
	                        DragGesture(minimumDistance: 0)
	                            .onChanged { value in
	                                beginOrUpdateDrag(actionID: action.id, handle: .body, translation: value.translation)
	                            }
                            .onEnded { value in
                                let finalTranslation = value.translation.clamped(to: 800)
                                activeDrag = nil

                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                guard distance >= 0.5 else { return }

                                CoordinatePreviewOverlay.shared.onDragPathEnded?(action.id, finalTranslation.width, finalTranslation.height)
                                flashPoint = confirmationPoint(for: action, handle: .body, translation: finalTranslation)
                                confirmFlash = true
                                withAnimation(.easeOut(duration: 0.6)) {
                                    confirmFlash = false
                                }
                            }
                    )

                    if action.kind.editsPathTarget {
                        if let startPt = displayPath.first {
                            let isCurrentStartDrag = activeDrag?.actionID == action.id && activeDrag?.handle == .start
                            ZStack {
                                if isCurrentStartDrag {
                                    tooltipView(for: startPt)
                                }
                                Circle()
                                    .fill(action.themeColor)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                                Circle()
                                    .stroke(action.themeColor.opacity(0.5), lineWidth: 1)
                                    .frame(width: 20, height: 20)
                                orderBadge(for: action)
                                    .offset(x: 17, y: -17)
                            }
                            .frame(width: 72, height: 72)
                            .contentShape(Circle())
                            .allowsHitTesting(isDetailed(action))
                            .offset(x: startPt.x - 36, y: startPt.y - 36)
                            .opacity(isCurrentStartDrag ? 1 : previewOpacity(for: action))
                            .help(String(localized: "Drag to adjust drag start", table: "EditorUX"))
                            .onHover { hovering in
                                hoveredActionID = hovering ? action.id : (hoveredActionID == action.id ? nil : hoveredActionID)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        beginOrUpdateDrag(actionID: action.id, handle: .start, translation: value.translation)
                                    }
                                    .onEnded { value in
                                        let finalTranslation = value.translation.clamped(to: 800)
                                        activeDrag = nil
                                        let distance = hypot(finalTranslation.width, finalTranslation.height)
                                        guard distance >= 0.5 else { return }

                                        CoordinatePreviewOverlay.shared.onDragStartPointEnded?(
                                            action.id,
                                            finalTranslation.width,
                                            finalTranslation.height
                                        )
                                        flashPoint = confirmationPoint(
                                            for: action,
                                            handle: .start,
                                            translation: finalTranslation
                                        )
                                        confirmFlash = true
                                        withAnimation(.easeOut(duration: 0.6)) {
                                            confirmFlash = false
                                        }
                                    }
                            )
                        }

	                        if let actionGeometry = actionGeometries[action.id],
	                           let displayEndPt = actionGeometry.endPoint {
	                            let showArrow: Bool = {
	                                if let startPt = actionGeometry.startPoint {
	                                    let dx = displayEndPt.x - startPt.x
	                                    let dy = displayEndPt.y - startPt.y
	                                    return (dx * dx + dy * dy) > 225
                                }
                                return true
	                            }()

	                            if showArrow {
	                                let isCurrentDrag = (activeDrag?.actionID == action.id && activeDrag?.handle == .end)

                                Image(systemName: "arrowtriangle.down.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
	                                    .frame(width: 14, height: 14)
	                                    .foregroundStyle(action.themeColor)
	                                    .shadow(color: .black.opacity(0.3), radius: 2)
	                                    .rotationEffect(arrowRotation(for: actionGeometry))
                                    .scaleEffect(isCurrentDrag ? 1.25 : 1.0)
                                    .opacity(isCurrentDrag ? 1 : previewOpacity(for: action))
                                    .overlay(
                                        Group {
                                            if isCurrentDrag, activeDrag != nil {
                                                tooltipView(for: displayEndPt)
                                            }
                                        }
                                    )
                                    .help(String(localized: "Drag to adjust swipe destination (rotate/stretch)", table: "EditorUX"))
                                    .frame(width: 100, height: 100) // Large frame to prevent visual clipping of badge/arrow/shadows
                                    .contentShape(Rectangle())
                                    .allowsHitTesting(isDetailed(action))
                                    .offset(x: displayEndPt.x - 50, y: displayEndPt.y - 50)
                                    .onHover { hovering in
                                        hoveredActionID = hovering ? action.id : (hoveredActionID == action.id ? nil : hoveredActionID)
                                    }
	                                    .gesture(
	                                        DragGesture(minimumDistance: 0)
	                                            .onChanged { value in
	                                                beginOrUpdateDrag(actionID: action.id, handle: .end, translation: value.translation)
	                                            }
                                            .onEnded { value in
                                                let finalTranslation = value.translation.clamped(to: 800)
                                                activeDrag = nil

                                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                                guard distance >= 0.5 else { return }

                                                CoordinatePreviewOverlay.shared.onDragEndPointEnded?(action.id, finalTranslation.width, finalTranslation.height)

                                                // Trigger ripple
	                                                flashPoint = confirmationPoint(for: action, handle: .end, translation: finalTranslation)
                                                confirmFlash = true
                                                withAnimation(.easeOut(duration: 0.6)) {
                                                    confirmFlash = false
                                                }
                                            }
                                    )
                            }
                        }
                    }

	                }

                    if action.kind.previewsPointSequence {
                        ForEach(Array(displayPath.enumerated()), id: \.offset) { pointIndex, point in
                            let isCurrentPointDrag: Bool = {
                                guard activeDrag?.actionID == action.id,
                                      case .point(let activePointIndex)? = activeDrag?.handle else { return false }
                                return activePointIndex == pointIndex
                            }()

                            ZStack {
                                if isCurrentPointDrag, activeDrag != nil {
                                    tooltipView(for: point)
                                }

                                Circle()
                                    .fill(action.themeColor)
                                    .frame(width: 21, height: 21)
                                    .shadow(color: .black.opacity(0.28), radius: 2)

                                Text("\(pointIndex + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                if pointIndex == 0 {
                                    orderBadge(for: action)
                                        .offset(x: -18, y: -18)
                                }
                            }
                            .scaleEffect(isCurrentPointDrag ? 1.18 : 1.0)
                            .opacity(isCurrentPointDrag ? 1 : previewOpacity(for: action))
                            .help(String(localized: "Drag to adjust this click point", table: "EditorUX"))
                            .frame(width: 100, height: 100)
                            .contentShape(Rectangle())
                            .allowsHitTesting(isDetailed(action))
                            .offset(x: point.x - 50, y: point.y - 50)
                            .onHover { hovering in
                                hoveredActionID = hovering ? action.id : (hoveredActionID == action.id ? nil : hoveredActionID)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        beginOrUpdateDrag(actionID: action.id, handle: .point(pointIndex), translation: value.translation)
                                    }
                                    .onEnded { value in
                                        let finalTranslation = value.translation.clamped(to: 800)
                                        activeDrag = nil

                                        let distance = hypot(finalTranslation.width, finalTranslation.height)
                                        guard distance >= 0.5 else { return }

                                        CoordinatePreviewOverlay.shared.onDragPathPointEnded?(action.id, pointIndex, finalTranslation.width, finalTranslation.height)

                                        flashPoint = confirmationPoint(for: action, handle: .point(pointIndex), translation: finalTranslation)
                                        confirmFlash = true
                                        withAnimation(.easeOut(duration: 0.6)) {
                                            confirmFlash = false
                                        }
                                    }
                            )
                        }
                    }

                // Scroll is an anchored gesture, not a click and not pointer travel. Show the
                // dominant wheel direction and magnitude while keeping the exact anchor visible.
                if action.kind == .scroll,
                   let displayPt = actionGeometries[action.id]?.startPoint {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.74))
                            .frame(width: 34, height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(action.themeColor.opacity(0.9), lineWidth: isSelected(action) ? 2 : 1.25)
                            )

                        Image(systemName: scrollSymbol(for: action))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(action.themeColor)

                        Circle()
                            .fill(action.themeColor)
                            .frame(width: 4, height: 4)
                            .offset(y: 14)

                        orderBadge(for: action)
                            .offset(x: 20, y: -22)

                        if let amount = scrollAmount(for: action) {
                            semanticBadge(amount, color: action.themeColor)
                                .offset(x: 21, y: 21)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .position(displayPt)
                    .opacity(previewOpacity(for: action))
                    .allowsHitTesting(false)
                }

                // Mouse move only identifies a cursor destination. A cursor glyph avoids the
                // false implication that playback clicks at this coordinate.
                if action.affordance == .pointerMove,
                   let displayPt = actionGeometries[action.id]?.startPoint {
                    ZStack {
                        Circle()
                            .stroke(action.themeColor.opacity(0.75), style: StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(action.themeColor)
                            .frame(width: 3.5, height: 3.5)
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(action.themeColor)
                            .offset(x: 8, y: 8)
                        orderBadge(for: action)
                            .offset(x: 17, y: -17)
                    }
                    .frame(width: 54, height: 54)
                    .position(displayPt)
                    .opacity(previewOpacity(for: action) * 0.72)
                    .allowsHitTesting(false)
                }

                // Discrete pointer targets.
                if !action.kind.previewsPointSequence,
                   action.affordance.showsClickPulse,
                   action.selectedPoint != nil,
                   let displayPt = actionGeometries[action.id]?.startPoint {
                    let isCurrentDrag = (activeDrag?.actionID == action.id && activeDrag?.handle == .start)

                    ZStack {
                        // Current Drag Tooltip
                        if isCurrentDrag, activeDrag != nil {
                            tooltipView(for: displayPt)
                        }

                        Circle()
                            .stroke(action.themeColor.opacity(0.8), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                            .scaleEffect(isCurrentDrag ? 1.25 : (shouldAnimate(action) ? pulseScale : 1.0))
                            .opacity(isCurrentDrag ? 0.3 : (shouldAnimate(action) ? pulseOpacity : 0.34))

                        Circle()
                            .stroke(action.themeColor, lineWidth: 1.5)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(action.themeColor)
                            .frame(width: 3.5, height: 3.5)

                        Rectangle()
                            .fill(action.themeColor.opacity(0.6))
                            .frame(width: 16, height: 1)
                        Rectangle()
                            .fill(action.themeColor.opacity(0.6))
                            .frame(width: 1, height: 16)
                    }
                    .overlay {
                        orderBadge(for: action)
                            .offset(x: 16, y: -16)
                        if let metadata = pointMetadata(for: action) {
                            semanticBadge(metadata, color: action.themeColor)
                                .offset(x: 18, y: 17)
                        }
                        if let button = mouseButtonMetadata(for: action) {
                            semanticBadge(button, color: action.themeColor)
                                .offset(x: -21, y: 17)
                        }
                    }
                    .scaleEffect(isCurrentDrag ? 1.15 : 1.0)
                    .opacity(previewOpacity(for: action))
                    .help(humanActionKindName(action.kind))
                    .frame(width: 100, height: 100) // Large frame to prevent visual clipping of badge/arrow/shadows
                    .contentShape(Rectangle())
                    .allowsHitTesting(isDetailed(action))
                    .offset(x: displayPt.x - 50, y: displayPt.y - 50)
                    .onHover { hovering in
                        hoveredActionID = hovering ? action.id : (hoveredActionID == action.id ? nil : hoveredActionID)
                    }
	                    .gesture(
	                        DragGesture(minimumDistance: 0)
	                            .onChanged { value in
	                                beginOrUpdateDrag(actionID: action.id, handle: .start, translation: value.translation)
	                             }
                            .onEnded { value in
                                let finalTranslation = value.translation.clamped(to: 800)
                                activeDrag = nil

                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                guard distance >= 0.5 else { return }

                                CoordinatePreviewOverlay.shared.onDragStartPointEnded?(action.id, finalTranslation.width, finalTranslation.height)

                                // Trigger ripple
                                flashPoint = confirmationPoint(for: action, handle: .start, translation: finalTranslation)
                                confirmFlash = true
                                withAnimation(.easeOut(duration: 0.6)) {
                                    confirmFlash = false
                                }
                            }
                    )
                }
            }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
                pulseOpacity = 0.2
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                lineDashPhase = -10
            }
        }
        .onDisappear {
            activeDrag = nil
            activeSearchRegionEdit = nil
        }
        .onChange(of: actions.map(\.id)) {
            activeDrag = nil
            activeSearchRegionEdit = nil
        }
        .transaction { transaction in
            if activeDrag != nil {
                transaction.animation = nil
            }
        }
    }

    func arrowRotation(for geometry: PreviewPathGeometry) -> Angle {
        if let start = geometry.startPoint,
           let end = geometry.endPoint,
           hypot(end.x - start.x, end.y - start.y) > 0.001 {
            return arrowRotation(from: start, to: end)
        }

        let path = geometry.path
        guard path.count >= 2 else { return .zero }
        return arrowRotation(from: path[path.count - 2], to: path[path.count - 1])
    }

    func arrowRotation(from start: CGPoint, to end: CGPoint) -> Angle {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        return Angle(radians: Double(angle) - .pi / 2)
    }
}
