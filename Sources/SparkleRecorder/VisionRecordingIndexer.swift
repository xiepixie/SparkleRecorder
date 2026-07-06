import Foundation
import ImageIO
import SparkleRecorderCore

struct VisionRecordingIndexer: Sendable {
    private let bundleDirectory: URL
    private let detector: VisionDetector
    private let idProvider: SemanticRecordingCaptureIDProvider

    init(
        bundleDirectory: URL,
        detector: VisionDetector = VisionDetector(),
        idProvider: SemanticRecordingCaptureIDProvider = SemanticRecordingCaptureIDProvider()
    ) {
        self.bundleDirectory = bundleDirectory
        self.detector = detector
        self.idProvider = idProvider
    }

    func indexFrame(_ request: SemanticRecordingFrameIndexRequest) async throws -> [RecordingVisualObservation] {
        let imageURL = bundleDirectory.appendingRecordingArtifactRef(request.frame.imageRef)
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return []
        }

        let detections = try await detector.detectText(in: image)
        return detections.map { detection in
            RecordingVisualObservation(
                id: idProvider.next(.visualObservation),
                kind: .ocrText,
                recordingTime: request.frame.recordingTime,
                frameID: request.frame.id,
                bounds: RecordingBounds(
                    rect: RecordingRect(
                        x: detection.boundingBox.origin.x,
                        y: detection.boundingBox.origin.y,
                        width: detection.boundingBox.width,
                        height: detection.boundingBox.height
                    ),
                    coordinateSpace: .normalizedFrame
                ),
                text: detection.text,
                confidence: Double(detection.confidence),
                provider: "Vision.VNRecognizeTextRequest",
                providerVersion: "0.1",
                labels: ["ocr"],
                createdAt: request.createdAt
            )
        }
    }
}
