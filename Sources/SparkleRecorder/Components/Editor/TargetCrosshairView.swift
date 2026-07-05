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
    
    func getDisplayStartPoint(for action: RelativePreviewAction) -> CGPoint? {
        if action.kind.previewsPointSequence {
            return getDisplayPath(for: action).first
        }
        guard let pt = action.selectedPoint else { return nil }
        if let drag = activeDrag, drag.actionID == action.id {
            switch drag.handle {
            case .start, .body:
                return pt + drag.clampedTranslation
            case .end, .point(_):
                return pt
            }
        }
        return pt
    }
    
    func getDisplayEndPoint(for action: RelativePreviewAction) -> CGPoint? {
        if action.kind.previewsPointSequence {
            return getDisplayPath(for: action).last
        }
        guard let endPt = action.dragPath.last else { return action.selectedPoint }
        if let drag = activeDrag, drag.actionID == action.id {
            switch drag.handle {
            case .end, .body:
                return endPt + drag.clampedTranslation
            case .start, .point(_):
                return endPt
            }
        }
        return endPt
    }
    
    func getDisplayPath(for action: RelativePreviewAction) -> [CGPoint] {
        guard action.dragPath.count > 1 else { return [] }
        if let drag = activeDrag, drag.actionID == action.id {
            switch drag.handle {
            case .start:
                if action.kind.previewsPointSequence {
                    return action.dragPath
                }
                if let start = action.selectedPoint ?? action.dragPath.first, let end = action.dragPath.last {
                    let newStart = start + drag.clampedTranslation
                    return action.dragPath.map {
                        conformPathPoint(pt: $0, oldStart: start, oldEnd: end, newStart: newStart, newEnd: end)
                    }
                }
            case .end:
                if action.kind.previewsPointSequence {
                    return action.dragPath
                }
                if let start = action.selectedPoint ?? action.dragPath.first, let end = action.dragPath.last {
                    let newEnd = end + drag.clampedTranslation
                    return action.dragPath.map {
                        conformPathPoint(pt: $0, oldStart: start, oldEnd: end, newStart: start, newEnd: newEnd)
                    }
                }
            case .body:
                return action.dragPath.map { $0 + drag.clampedTranslation }
            case .point(let pointIndex):
                guard action.dragPath.indices.contains(pointIndex) else { return action.dragPath }
                return action.dragPath.enumerated().map { index, point in
                    index == pointIndex ? point + drag.clampedTranslation : point
                }
            }
        }
        return action.dragPath
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
    
    func conformPathPoint(pt: CGPoint, oldStart: CGPoint, oldEnd: CGPoint, newStart: CGPoint, newEnd: CGPoint) -> CGPoint {
        let mainVector = CGPoint(x: oldEnd.x - oldStart.x, y: oldEnd.y - oldStart.y)
        let newVector = CGPoint(x: newEnd.x - newStart.x, y: newEnd.y - newStart.y)
        
        let oldLen2 = mainVector.x * mainVector.x + mainVector.y * mainVector.y
        guard oldLen2 > 0.001 else {
            let dx = newStart.x - oldStart.x
            let dy = newStart.y - oldStart.y
            return CGPoint(x: pt.x + dx, y: pt.y + dy)
        }
        
        let mainVectorPerp = CGPoint(x: -mainVector.y, y: mainVector.x)
        let newVectorPerp = CGPoint(x: -newVector.y, y: newVector.x)
        
        let dx = pt.x - oldStart.x
        let dy = pt.y - oldStart.y
        
        let u = (dx * mainVector.x + dy * mainVector.y) / oldLen2
        let v = (dx * mainVectorPerp.x + dy * mainVectorPerp.y) / oldLen2
        
        return CGPoint(
            x: newStart.x + u * newVector.x + v * newVectorPerp.x,
            y: newStart.y + u * newVector.y + v * newVectorPerp.y
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 1. Connection dashed path in sequential order
                Path { path in
                var lastPt: CGPoint? = nil
                for action in actions {
                    let startPt = getDisplayStartPoint(for: action)
                    if let start = startPt {
                        if let last = lastPt {
                            path.move(to: last)
                            path.addLine(to: start)
                        }
                        lastPt = getDisplayEndPoint(for: action)
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
	                        .frame(width: observed.width, height: observed.height)
	                        .position(x: observed.midX, y: observed.midY)
	                        .allowsHitTesting(false)
	                }
	                
	                if let fallback = action.fallbackPoint {
	                    Image(systemName: "smallcircle.filled.circle")
	                        .font(.system(size: 13, weight: .bold))
	                        .foregroundStyle(action.themeColor)
	                        .shadow(color: .black.opacity(0.3), radius: 2)
	                        .position(fallback)
	                        .allowsHitTesting(false)
	                }
	                
	                // Drag path
	                let displayPath = getDisplayPath(for: action)
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
                                if activeDrag == nil {
                                    activeDrag = ActiveDragEdit(actionID: action.id, handle: .body, translation: value.translation)
                                    CoordinatePreviewOverlay.shared.onDragStarted?(action.id)
                                } else {
                                    activeDrag?.translation = value.translation
                                }
                            }
                            .onEnded { value in
                                let finalTranslation = value.translation.clamped(to: 800)
                                activeDrag = nil
                                
                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                guard distance >= 0.5 else { return }
                                
                                CoordinatePreviewOverlay.shared.onDragPathEnded?(action.id, finalTranslation.width, finalTranslation.height)
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
                        
                        if let endPt = displayPath.last {
                            let showArrow: Bool = {
                                if let startPt = getDisplayStartPoint(for: action) {
                                    let dx = endPt.x - startPt.x
                                    let dy = endPt.y - startPt.y
                                    return (dx * dx + dy * dy) > 225
                                }
                                return true
                            }()
                            
                            if showArrow, let displayEndPt = getDisplayEndPoint(for: action) {
                                let isCurrentDrag = (activeDrag?.actionID == action.id && activeDrag?.handle == .end)
                                
                                Image(systemName: "arrowtriangle.down.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(action.themeColor)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                                    .rotationEffect(arrowRotation(for: displayPath))
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
                                                if activeDrag == nil {
                                                    activeDrag = ActiveDragEdit(actionID: action.id, handle: .end, translation: value.translation)
                                                    CoordinatePreviewOverlay.shared.onDragStarted?(action.id)
                                                } else {
                                                    activeDrag?.translation = value.translation
                                                }
                                            }
                                            .onEnded { value in
                                                let finalTranslation = value.translation.clamped(to: 800)
                                                activeDrag = nil
                                                
                                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                                guard distance >= 0.5 else { return }
                                                
                                                CoordinatePreviewOverlay.shared.onDragEndPointEnded?(action.id, finalTranslation.width, finalTranslation.height)
                                                
                                                // Trigger ripple
                                                flashPoint = endPt + finalTranslation
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
                                        if activeDrag == nil {
                                            activeDrag = ActiveDragEdit(actionID: action.id, handle: .point(pointIndex), translation: value.translation)
                                            CoordinatePreviewOverlay.shared.onDragStarted?(action.id)
                                        } else {
                                            activeDrag?.translation = value.translation
                                        }
                                    }
                                    .onEnded { value in
                                        let finalTranslation = value.translation.clamped(to: 800)
                                        activeDrag = nil

                                        let distance = hypot(finalTranslation.width, finalTranslation.height)
                                        guard distance >= 0.5 else { return }

                                        CoordinatePreviewOverlay.shared.onDragPathPointEnded?(action.id, pointIndex, finalTranslation.width, finalTranslation.height)

                                        flashPoint = point + finalTranslation
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
                
                // Targets
                if !action.kind.previewsPointSequence, let pt = action.selectedPoint, let displayPt = getDisplayStartPoint(for: action) {
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
                                if activeDrag == nil {
                                    activeDrag = ActiveDragEdit(actionID: action.id, handle: .start, translation: value.translation)
                                    CoordinatePreviewOverlay.shared.onDragStarted?(action.id)
                                } else {
                                    activeDrag?.translation = value.translation
                                }
                             }
                            .onEnded { value in
                                let finalTranslation = value.translation.clamped(to: 800)
                                activeDrag = nil
                                
                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                guard distance >= 0.5 else { return }
                                
                                CoordinatePreviewOverlay.shared.onDragStartPointEnded?(action.id, finalTranslation.width, finalTranslation.height)
                                
                                // Trigger ripple
                                flashPoint = pt + finalTranslation
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
    
    func arrowRotation(for path: [CGPoint]) -> Angle {
        guard path.count >= 2 else { return .zero }
        let p1 = path[path.count - 2]
        let p2 = path[path.count - 1]
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let angle = atan2(dy, dx)
        return Angle(radians: Double(angle) - .pi / 2)
    }
}
