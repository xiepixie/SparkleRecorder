import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphLinkPreviewState: Equatable {
    let sourceTaskID: UUID
    let end: AutomationGraphPoint
}

struct AutomationFlowGraphLinkPreview: View {
    let start: AutomationGraphPoint
    let end: AutomationGraphPoint

    var body: some View {
        Canvas { context, _ in
            let startPoint = CGPoint(x: CGFloat(start.x), y: CGFloat(start.y))
            let endPoint = CGPoint(x: CGFloat(end.x), y: CGFloat(end.y))
            let controlDistance = max(42, abs(endPoint.x - startPoint.x) * 0.45)
            let firstControl = CGPoint(x: startPoint.x + controlDistance, y: startPoint.y)
            let secondControl = CGPoint(x: endPoint.x - controlDistance, y: endPoint.y)

            var path = Path()
            path.move(to: startPoint)
            path.addCurve(to: endPoint, control1: firstControl, control2: secondControl)

            context.stroke(
                path,
                with: .color(Brand.sigAmber.opacity(0.82)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [7, 5])
            )
            context.fill(endpointCircle(at: startPoint), with: .color(Brand.sigAmber.opacity(0.72)))
            context.fill(endpointCircle(at: endPoint), with: .color(Brand.sigAmber.opacity(0.72)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func endpointCircle(at point: CGPoint) -> Path {
        Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
    }
}
