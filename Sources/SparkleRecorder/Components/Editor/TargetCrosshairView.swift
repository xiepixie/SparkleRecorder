import Cocoa
import SwiftUI
import SparkleRecorderCore

struct TargetCrosshairView: View {
    @ObservedObject var state: OverlayState

    @State private var pulseScale: CGFloat = 0.8
    @State private var pulseOpacity: Double = 0.8
    @State private var lineDashPhase: CGFloat = 0

    @State private var activeDrag: ActiveDragEdit?
    @State private var confirmFlashActionID: UUID?
    @State private var confirmFlash: Bool = false
    @State private var flashPoint: CGPoint? = nil
    @State private var hoveredActionID: UUID?
    @State private var hoveredHandle: DragHandle?

    private var actions: [RelativePreviewAction] { state.actions }

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
        case .textClickTarget:
            return NSLocalizedString("Click text", comment: "")
        case .waitTextRegion:
            return NSLocalizedString("Wait text", comment: "")
        case .waitTextGoneRegion:
            return NSLocalizedString("Wait gone", comment: "")
        case .verifyTextRegion:
            return NSLocalizedString("Verify text", comment: "")
        default:
            return nil
        }
    }

    @ViewBuilder
    private func targetBadge(for action: RelativePreviewAction) -> some View {
        if let title = targetBadgeTitle(for: action) {
            HStack(spacing: 4) {
                Text("\(action.order)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(action.themeColor.opacity(action.affordance.showsConditionRegion ? 0.92 : 0.82))
                    .shadow(color: .black.opacity(0.22), radius: 1)
            )
            .fixedSize()
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

        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 1. Connection dashed path in sequential order
                Path { path in
                var lastPt: CGPoint? = nil
                for action in actions {
                    let startPt = actionGeometries[action.id]?.startPoint
                    if let start = startPt {
                        if let last = lastPt {
                            path.move(to: last)
                            path.addLine(to: start)
                        }
                        lastPt = actionGeometries[action.id]?.endPoint
                    }
                }
            }
            .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 4]))

            // 2. Ripple animation overlay
            if let fPt = flashPoint {
                Circle()
                    .stroke(Color.green.opacity(confirmFlash ? 0.8 : 0.0), lineWidth: 2)
                    .frame(width: confirmFlash ? 16 : 48, height: confirmFlash ? 16 : 48)
                    .position(fPt)
            }

            // 3. Render each action's markers
            ForEach(actions) { action in
                if let region = action.searchRegion {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(action.themeColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(action.themeColor.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [7, 5], dashPhase: lineDashPhase))
                        )
                        .overlay(alignment: .topLeading) {
                            if action.affordance.showsTargetRegionLabel {
                                targetBadge(for: action)
                                    .offset(x: 6, y: 6)
                            }
                        }
                        .frame(width: region.width, height: region.height)
                        .position(x: region.midX, y: region.midY)
                        .allowsHitTesting(false)
                }

                if let observed = action.observedFrame {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(action.themeColor.opacity(0.95), lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(action.themeColor.opacity(0.12))
                        )
                        .overlay(alignment: .topLeading) {
                            if action.affordance.showsTargetRegionLabel {
                                targetBadge(for: action)
                                    .offset(x: 6, y: 6)
                            }
                        }
                        .frame(width: observed.width, height: observed.height)
                        .position(x: observed.midX, y: observed.midY)
                        .allowsHitTesting(false)
                }

	                if action.affordance.showsLocatorFallbackPoint, let fallback = action.fallbackPoint {
	                    Image(systemName: "smallcircle.filled.circle")
	                        .font(.system(size: 13, weight: .bold))
	                        .foregroundStyle(action.themeColor)
	                        .shadow(color: .black.opacity(0.3), radius: 2)
	                        .position(fallback)
	                        .allowsHitTesting(false)
		                }

		                // Drag path
		                let displayPath = actionGeometries[action.id]?.path ?? []
	                if action.kind.canPreviewPath, displayPath.count > 1 {
                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(Color.black.opacity(0.3), lineWidth: 3.5)

                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(
                        action.themeColor,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [6, 4], dashPhase: lineDashPhase)
                    )

                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(Color.clear, style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    .contentShape(Path { path in
                        path.addLines(displayPath)
                    })
                    .help(action.kind.previewsPointSequence
                          ? NSLocalizedString("Drag line to move all click points", comment: "")
                          : NSLocalizedString("Drag path to move the whole drag", comment: ""))
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
                                confirmFlashActionID = action.id
                                confirmFlash = true
                                withAnimation(.easeOut(duration: 0.6)) {
                                    confirmFlash = false
                                }
                            }
                    )

                    if action.kind.editsPathTarget {
                        if let startPt = displayPath.first {
                            Circle()
                                .fill(action.themeColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .position(startPt)
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
                                    .overlay(
                                        Group {
                                            if isCurrentDrag, activeDrag != nil {
                                                tooltipView(for: displayEndPt)
                                            }
                                        }
                                    )
                                    .help(NSLocalizedString("Drag to adjust swipe destination (rotate/stretch)", comment: ""))
                                    .frame(width: 100, height: 100) // Large frame to prevent visual clipping of badge/arrow/shadows
                                    .contentShape(Rectangle())
                                    .offset(x: displayEndPt.x - 50, y: displayEndPt.y - 50)
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
                                                confirmFlashActionID = action.id
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
                            }
                            .scaleEffect(isCurrentPointDrag ? 1.18 : 1.0)
                            .help(NSLocalizedString("Drag to adjust this click point", comment: ""))
                            .frame(width: 100, height: 100)
                            .contentShape(Rectangle())
                            .offset(x: point.x - 50, y: point.y - 50)
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
                                        confirmFlashActionID = action.id
                                        confirmFlash = true
                                        withAnimation(.easeOut(duration: 0.6)) {
                                            confirmFlash = false
                                        }
                                    }
                            )
                        }
                    }

                // Targets
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
                            .scaleEffect(isCurrentDrag ? 1.25 : pulseScale)
                            .opacity(isCurrentDrag ? 0.3 : pulseOpacity)

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
                    .scaleEffect(isCurrentDrag ? 1.15 : 1.0)
                    .background(
                        // Sequential Order Badge
                        Text("\(action.order)")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 0.5)
                            .background(
                                Capsule()
                                    .fill(action.themeColor)
                                    .shadow(color: .black.opacity(0.2), radius: 1)
                            )
                            .offset(x: 14, y: -14)
                    )
                    .help(NSLocalizedString("Drag to adjust drag start", comment: ""))
                    .frame(width: 100, height: 100) // Large frame to prevent visual clipping of badge/arrow/shadows
                    .contentShape(Rectangle())
                    .offset(x: displayPt.x - 50, y: displayPt.y - 50)
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
                                confirmFlashActionID = action.id
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
        }
        .onChange(of: actions.map(\.id)) {
            activeDrag = nil
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
