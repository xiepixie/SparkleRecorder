import Foundation
import CoreGraphics
import Vision
import CoreImage
import AppKit

public enum VisionDetectorError: Error {
    case noTextFound
    case textNotMatched
    case imageProcessingFailed
    case templateMatchingUnavailable
    case templateMatchingFailed
}

public struct TextDetection: Equatable {
    public var text: String
    public var boundingBox: CGRect // Normalized top-left coordinates [0,1]
    public var confidence: Float
}

public class VisionDetector {
    
    public init() {}
    
    /// Uses VNRecognizeTextRequest to find the bounding box of a target text in a CGImage
    @available(*, deprecated, message: "Use detectText and resolve using TextAnchor scoring instead")
    public func locateText(_ text: String, in image: CGImage) async throws -> CGRect {
        let detections = try await detectText(in: image)
        if let first = detections.first(where: { $0.text.localizedCaseInsensitiveContains(text) }) {
            return first.boundingBox
        }
        throw VisionDetectorError.textNotMatched
    }
    
    /// Detects all text blocks in the given CGImage and returns their strings, confidences, and top-left normalized bounding boxes.
    public func detectText(in image: CGImage, recognitionLevel: VNRequestTextRecognitionLevel = .accurate) async throws -> [TextDetection] {
        let task = Task.detached(priority: .userInitiated) { () -> [TextDetection] in
            return try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var detections: [TextDetection] = []
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    
                    // Vision returns coordinates with origin at bottom-left, normalized [0,1]
                    // We convert it to top-left normalized
                    let y = 1.0 - observation.boundingBox.maxY
                    let rect = CGRect(
                        x: observation.boundingBox.minX,
                        y: y,
                        width: observation.boundingBox.width,
                        height: observation.boundingBox.height
                    )
                    
                    detections.append(TextDetection(
                        text: topCandidate.string,
                        boundingBox: rect,
                        confidence: topCandidate.confidence
                    ))
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
    
    /// Template matching is reserved for a future visual locator backend.
    public func locateTemplate(_ template: CGImage, in image: CGImage) async throws -> CGRect {
        throw VisionDetectorError.templateMatchingUnavailable
    }
}
