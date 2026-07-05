import Foundation
import CoreGraphics
import SparkleRecorderCore
import OSLog

public enum LocatorStrategy: @unchecked Sendable {
    case coordinates
    case ocr(TextAnchor)
    case template(CGImage)
}

@available(macOS 14.0, *)
public final class LocatorEngine: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.sparklerecorder.mac", category: "LocatorEngine")
    private let pointResolver = PointResolver()
    private let visionDetector = VisionDetector()
    
    public init() {}
    
    private struct ResolvedTextDetection {
        let detection: TextDetection
        let screenRect: CGRect
        let score: Double
    }
    
    /// Tries to resolve a point using the specified strategies in fallback order
    public func locate(event: RecordedEvent, context: PlaybackContext, strategies: [LocatorStrategy]) async throws -> CGPoint {
        var lastError: Error = PointResolveError.missingWindowLocalPoint
        
        for strategy in strategies {
            switch strategy {
            case .coordinates:
                let result = pointResolver.resolve(event, context: context)
                switch result {
                case .success(let point):
                    return point
                case .failure(let error):
                    lastError = error
                }
                
            case .ocr(let anchor):
                let surfaceId: String
                if let sId = event.surfaceId, context.surfaces[sId] != nil {
                    surfaceId = sId
                } else if let firstKey = context.surfaces.keys.first {
                    surfaceId = firstKey
                } else {
                    surfaceId = event.surfaceId ?? "surface-1"
                }
                
                guard let surface = context.surfaces[surfaceId],
                      let currentFrame = context.currentSurfaceFrames[surfaceId] else {
                    lastError = PointResolveError.missingSurface(event.surfaceId ?? "nil")
                    continue
                }
                let contentFrame = context.currentContentFrames[surfaceId] ?? currentFrame
                
                do {
                    let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: surface.bundleIdentifier, title: surface.windowTitle)
                    let prepared = prepareImage(image, for: anchor, windowFrame: currentFrame, contentFrame: contentFrame)
                    let detections = try await visionDetector.detectText(in: prepared.image)
                    
                    if let bestDetection = resolve(anchor: anchor, detections: detections, detectionFrame: prepared.detectionFrame, contentFrame: contentFrame) {
                        let screenX = bestDetection.screenRect.midX
                        let screenY = bestDetection.screenRect.midY
                        logger.info("OCR successfully found text '\(anchor.text)' at (\(screenX), \(screenY))")
                        return CGPoint(x: screenX, y: screenY)
                    } else {
                        throw VisionDetectorError.textNotMatched
                    }
                } catch {
                    lastError = error
                }
                
            case .template(let templateImage):
                let surfaceId: String
                if let sId = event.surfaceId, context.surfaces[sId] != nil {
                    surfaceId = sId
                } else if let firstKey = context.surfaces.keys.first {
                    surfaceId = firstKey
                } else {
                    surfaceId = event.surfaceId ?? "surface-1"
                }
                
                guard let surface = context.surfaces[surfaceId],
                      let currentFrame = context.currentSurfaceFrames[surfaceId] else {
                    lastError = PointResolveError.missingSurface(event.surfaceId ?? "nil")
                    continue
                }
                
                do {
                    let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: surface.bundleIdentifier, title: surface.windowTitle)
                    let normalizedRect = try await visionDetector.locateTemplate(templateImage, in: image)
                    
                    let screenX = currentFrame.x + (normalizedRect.midX * currentFrame.width)
                    let screenY = currentFrame.y + (normalizedRect.midY * currentFrame.height)
                    
                    logger.info("Template successfully matched at (\(screenX), \(screenY))")
                    return CGPoint(x: screenX, y: screenY)
                } catch {
                    lastError = error
                }
            }
        }
        
        throw lastError
    }
    
    private func prepareImage(_ image: CGImage, for anchor: TextAnchor, windowFrame: RectValue, contentFrame: RectValue) -> (image: CGImage, detectionFrame: RectValue) {
        let resolvedSearch = currentSearchRegion(for: anchor, contentFrame: contentFrame)
        guard let search = resolvedSearch, search.width > 0, search.height > 0 else {
            return (image, windowFrame)
        }
        
        let windowRect = CGRect(x: windowFrame.x, y: windowFrame.y, width: windowFrame.width, height: windowFrame.height)
        let clampedSearch = CGRect(x: search.x, y: search.y, width: search.width, height: search.height).intersection(windowRect)
        guard !clampedSearch.isNull, clampedSearch.width > 1, clampedSearch.height > 1 else {
            return (image, windowFrame)
        }
        
        let nx = (clampedSearch.minX - windowRect.minX) / max(1, windowRect.width)
        let ny = (clampedSearch.minY - windowRect.minY) / max(1, windowRect.height)
        let nw = clampedSearch.width / max(1, windowRect.width)
        let nh = clampedSearch.height / max(1, windowRect.height)
        let pixelRect = CGRect(
            x: nx * CGFloat(image.width),
            y: ny * CGFloat(image.height),
            width: nw * CGFloat(image.width),
            height: nh * CGFloat(image.height)
        ).integral
        
        let fullPixelRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = pixelRect.intersection(fullPixelRect)
        guard !cropRect.isNull, let cropped = image.cropping(to: cropRect) else {
            return (image, windowFrame)
        }
        
        return (
            cropped,
            RectValue(x: clampedSearch.minX, y: clampedSearch.minY, width: clampedSearch.width, height: clampedSearch.height)
        )
    }
    
    private func resolve(anchor: TextAnchor, detections: [TextDetection], detectionFrame: RectValue, contentFrame: RectValue) -> ResolvedTextDetection? {
        var candidates: [ResolvedTextDetection] = []
        
        let targetText = anchor.text.lowercased()
        
        for det in detections {
            let detText = det.text.lowercased()
            
            let similarity = textSimilarity(candidate: detText, target: targetText, mode: anchor.matchMode)
            guard similarity > 0 else { continue }
            
            let screenRect = CGRect(
                x: detectionFrame.x + det.boundingBox.minX * detectionFrame.width,
                y: detectionFrame.y + det.boundingBox.minY * detectionFrame.height,
                width: det.boundingBox.width * detectionFrame.width,
                height: det.boundingBox.height * detectionFrame.height
            )
            
            var distanceScore = 0.5
            
            if let observed = currentObservedFrame(for: anchor, contentFrame: contentFrame),
               observed.width > 0 && observed.height > 0 {
                let dx = screenRect.midX - observed.midX
                let dy = screenRect.midY - observed.midY
                let dist = sqrt(dx*dx + dy*dy)
                let diag = max(1, sqrt(detectionFrame.width * detectionFrame.width + detectionFrame.height * detectionFrame.height))
                distanceScore = max(0, 1 - Double(dist / diag))
            }
            
            let score = similarity * 0.6 + distanceScore * 0.3 + Double(det.confidence) * 0.1
            candidates.append(ResolvedTextDetection(detection: det, screenRect: screenRect, score: score))
        }
        
        guard !candidates.isEmpty else { return nil }
        
        if let hint = anchor.occurrenceHint {
            let sortedByPosition = candidates.sorted {
                if abs($0.screenRect.minY - $1.screenRect.minY) > 4 {
                    return $0.screenRect.minY < $1.screenRect.minY
                }
                return $0.screenRect.minX < $1.screenRect.minX
            }
            let zeroBased = hint > 0 ? hint - 1 : hint
            if sortedByPosition.indices.contains(zeroBased) {
                return sortedByPosition[zeroBased]
            }
        }
        
        return candidates.max { $0.score < $1.score }
    }
    
    private func currentObservedFrame(for anchor: TextAnchor, contentFrame: RectValue) -> CGRect? {
        if let normalized = anchor.observedContentNormalizedFrame {
            return denormalized(normalized, in: contentFrame)
        }
        guard anchor.observedFrame.width > 0, anchor.observedFrame.height > 0 else { return nil }
        return CGRect(x: anchor.observedFrame.x, y: anchor.observedFrame.y, width: anchor.observedFrame.width, height: anchor.observedFrame.height)
    }
    
    private func currentSearchRegion(for anchor: TextAnchor, contentFrame: RectValue) -> RectValue? {
        if let normalized = anchor.searchContentNormalizedRegion {
            let rect = denormalized(normalized, in: contentFrame)
            return RectValue(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        }
        return anchor.searchRegion
    }
    
    private func denormalized(_ rect: RectValue, in bounds: RectValue) -> CGRect {
        CGRect(
            x: bounds.x + rect.x * bounds.width,
            y: bounds.y + rect.y * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
    }
    
    private func textSimilarity(candidate: String, target: String, mode: TextMatchMode) -> Double {
        guard !target.isEmpty else { return 0 }
        switch mode {
        case .exact:
            return candidate == target ? 1.0 : 0.0
        case .contains:
            if candidate.contains(target) {
                return min(1.0, Double(target.count) / Double(max(target.count, candidate.count)) + 0.4)
            }
            let distance = levenshtein(candidate, target)
            let maxLen = max(candidate.count, target.count, 1)
            let score = 1.0 - Double(distance) / Double(maxLen)
            return score >= 0.65 ? score : 0
        }
    }
    
    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
