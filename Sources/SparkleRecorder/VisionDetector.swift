import CoreGraphics
import Foundation
import Vision

public enum VisionDetectorError: Error, Sendable {
    case textNotMatched
}

public struct TextDetection: Equatable, Sendable {
    public var text: String
    public var boundingBox: CGRect // Normalized top-left coordinates [0,1]
    public var confidence: Float
}

public final class VisionDetector: Sendable {
    public init() {}

    /// Detects all text blocks in the given CGImage and returns their strings,
    /// confidences, and top-left normalized bounding boxes.
    public func detectText(
        in image: CGImage,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) async throws -> [TextDetection] {
        let task = Task.detached(priority: .userInitiated) { () -> [TextDetection] in
            try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: [])
                        return
                    }

                    let detections = observations.compactMap { observation -> TextDetection? in
                        guard let topCandidate = observation.topCandidates(1).first else {
                            return nil
                        }

                        // Vision uses normalized bottom-left coordinates. Playback
                        // and editor projections use normalized top-left coordinates.
                        let rect = CGRect(
                            x: observation.boundingBox.minX,
                            y: 1.0 - observation.boundingBox.maxY,
                            width: observation.boundingBox.width,
                            height: observation.boundingBox.height
                        )
                        return TextDetection(
                            text: topCandidate.string,
                            boundingBox: rect,
                            confidence: topCandidate.confidence
                        )
                    }
                    continuation.resume(returning: detections)
                }

                request.recognitionLevel = recognitionLevel
                request.recognitionLanguages = ["ja-JP", "en-US", "zh-Hans", "zh-Hant"]
                request.usesLanguageCorrection = false

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return try await task.value
    }
}
