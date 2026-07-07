import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Visual Condition Evaluator Client Tests")
struct AutomationVisualConditionEvaluatorClientTests {
    @Test("Live visual image condition reports locator evidence")
    func liveVisualImageConditionReportsLocatorEvidence() async throws {
        let displayImage = try makeImage(
            width: 80,
            height: 60,
            fill: .black,
            highlight: CGRect(x: 22, y: 14, width: 6, height: 6),
            highlightColor: .green
        )
        let templateImage = try makeImage(width: 6, height: 6, fill: .green)
        let visual = AutomationVisualCondition(
            type: .imageAppeared,
            searchRegion: RectValue(x: 10, y: 10, width: 30, height: 20),
            searchRegionSpace: .displayAbsolute,
            imageRef: "ready_template",
            threshold: 0.99
        )
        let condition = AutomationConditionSpec(
            name: "Wait for ready icon",
            kind: .visual(visual)
        )
        let request = request(condition: condition)
        let evaluator = AutomationVisualConditionEvaluatorClient.live(
            captureDisplay: { displayImage },
            imageProvider: { _, reference in
                #expect(reference == "ready_template")
                return templateImage
            },
            artifactWriter: .inactive,
            now: { Date(timeIntervalSince1970: 10) },
            sleep: { _ in }
        )

        let result = await evaluator.evaluate(request, visual)

        #expect(result.outcome == .conditionMatched)
        let evidence = try #require(result.evidence)
        #expect(evidence.kind == .imageAppeared)
        #expect(evidence.observedSummary == "Template similarity 1.00")
        #expect(evidence.score == 1)
        #expect(evidence.threshold == 0.99)
        #expect(evidence.resolvedSearchRegion == RectValue(x: 10, y: 10, width: 30, height: 20))
        #expect(field("locatorSimilarity", in: evidence.fields) == "1.00")
        #expect(field("locatorThreshold", in: evidence.fields) == "0.99")
        #expect(field("locatorX", in: evidence.fields) == "12.00")
        #expect(field("locatorY", in: evidence.fields) == "4.00")
        #expect(field("locatorWidth", in: evidence.fields) == "6.00")
        #expect(field("locatorHeight", in: evidence.fields) == "6.00")
    }

    @Test("Live visual disappeared condition reports absent locator evidence")
    func liveVisualDisappearedConditionReportsAbsentLocatorEvidence() async throws {
        let displayImage = try makeImage(width: 80, height: 60, fill: .black)
        let templateImage = try makeImage(width: 6, height: 6, fill: .green)
        let visual = AutomationVisualCondition(
            type: .imageDisappeared,
            searchRegion: RectValue(x: 10, y: 10, width: 30, height: 20),
            searchRegionSpace: .displayAbsolute,
            imageRef: "spinner_template",
            threshold: 0.99
        )
        let condition = AutomationConditionSpec(
            name: "Wait for spinner gone",
            kind: .visual(visual)
        )
        let request = request(condition: condition)
        let evaluator = AutomationVisualConditionEvaluatorClient.live(
            captureDisplay: { displayImage },
            imageProvider: { _, reference in
                #expect(reference == "spinner_template")
                return templateImage
            },
            artifactWriter: .inactive,
            now: { Date(timeIntervalSince1970: 12) },
            sleep: { _ in }
        )

        let result = await evaluator.evaluate(request, visual)

        #expect(result.outcome == .conditionMatched)
        let evidence = try #require(result.evidence)
        #expect(evidence.kind == .imageDisappeared)
        #expect(evidence.observedSummary == "Template absent 0.42")
        let score = try #require(evidence.score)
        #expect(score > 0.42)
        #expect(score < 0.43)
        #expect(evidence.threshold == 0.99)
        #expect(field("locatorSimilarity", in: evidence.fields) == "0.42")
        #expect(field("locatorThreshold", in: evidence.fields) == "0.99")
        #expect(field("locatorX", in: evidence.fields) == nil)
    }

    private func request(condition: AutomationConditionSpec) -> AutomationConditionEvaluationRequest {
        AutomationConditionEvaluationRequest(
            runID: UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!,
            workflowID: UUID(uuidString: "F0000000-0000-0000-0000-000000000002")!,
            taskID: UUID(uuidString: "F0000000-0000-0000-0000-000000000003")!,
            condition: condition
        )
    }

    private func field(
        _ id: String,
        in fields: [AutomationConditionDiagnosticField]
    ) -> String? {
        fields.first { $0.id == id }?.value
    }

    private func makeImage(
        width: Int,
        height: Int,
        fill: TestRGBA,
        highlight: CGRect? = nil,
        highlightColor: TestRGBA? = nil
    ) throws -> CGImage {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let color = highlight?.contains(point) == true ? (highlightColor ?? fill) : fill
                let offset = (y * width + x) * 4
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                bytes[offset + 3] = color.alpha
            }
        }
        var image: CGImage?

        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return
            }
            image = context.makeImage()
        }

        return try #require(image)
    }
}

private struct TestRGBA: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8 = 255

    static let black = TestRGBA(red: 0, green: 0, blue: 0)
    static let green = TestRGBA(red: 0, green: 255, blue: 0)
}
