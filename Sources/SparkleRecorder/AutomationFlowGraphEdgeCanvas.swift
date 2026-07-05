import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphEdgeCanvas: View {
    let edges: [AutomationDependencyEdgeProjection]

    var body: some View {
        Canvas { context, _ in
            for edge in edges {
                let start = CGPoint(x: CGFloat(edge.start.x), y: CGFloat(edge.start.y))
                let end = CGPoint(x: CGFloat(edge.end.x), y: CGFloat(edge.end.y))
                let controlDistance = max(42, abs(end.x - start.x) * 0.45)
                let firstControl = CGPoint(x: start.x + controlDistance, y: start.y)
                let secondControl = CGPoint(x: end.x - controlDistance, y: end.y)

                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: firstControl, control2: secondControl)

                let color = edge.status.tint
                let style = StrokeStyle(
                    lineWidth: edge.status == .satisfied ? 2.2 : 1.4,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: edge.status.dashPattern
                )
                context.stroke(path, with: .color(color.opacity(0.78)), style: style)
                context.fill(arrowHead(start: start, end: end), with: .color(color.opacity(0.82)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func arrowHead(start: CGPoint, end: CGPoint) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = CGFloat(7)
        let spread = CGFloat.pi / 7
        let left = CGPoint(
            x: end.x - cos(angle - spread) * length,
            y: end.y - sin(angle - spread) * length
        )
        let right = CGPoint(
            x: end.x - cos(angle + spread) * length,
            y: end.y - sin(angle + spread) * length
        )

        var path = Path()
        path.move(to: end)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}
