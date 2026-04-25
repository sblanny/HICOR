import CoreGraphics
import CoreImage
import UIKit
import Vision

struct DetectedRectangle: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    let confidence: Float
    let boundingBox: CGRect
}

final class RectangleDetector {
    // VNDetectDocumentSegmentationRequest doesn't expose aspect/size/quadrature knobs —
    // it uses a neural-net document segmenter. We keep a confidence floor so transient
    // low-probability segmentations don't drive auto-capture.
    static let minimumConfidence: VNConfidence = 0.6
    // Similar areas (within 2%) fall back to confidence as the tiebreaker.
    static let similarAreaTolerance: Float = 0.02

    private let sequenceHandler = VNSequenceRequestHandler()

    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [DetectedRectangle] {
        let request = VNDetectDocumentSegmentationRequest()
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)
        } catch {
            return []
        }
        return mapResults(request.results)
    }

    func detectSync(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) -> [DetectedRectangle] {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return mapResults(request.results)
    }

    private func mapResults(_ results: [VNObservation]?) -> [DetectedRectangle] {
        let observations = (results as? [VNRectangleObservation]) ?? []
        // Vision returns corners in bottom-left normalized space; flip y to match
        // UIKit top-left normalized space so callers can denormalize against view/image size.
        let rectangles = observations.compactMap { obs -> DetectedRectangle? in
            guard obs.confidence >= Self.minimumConfidence else { return nil }
            return DetectedRectangle(
                topLeft:     CGPoint(x: obs.topLeft.x,     y: 1 - obs.topLeft.y),
                topRight:    CGPoint(x: obs.topRight.x,    y: 1 - obs.topRight.y),
                bottomRight: CGPoint(x: obs.bottomRight.x, y: 1 - obs.bottomRight.y),
                bottomLeft:  CGPoint(x: obs.bottomLeft.x,  y: 1 - obs.bottomLeft.y),
                confidence: obs.confidence,
                boundingBox: obs.boundingBox
            )
        }
        return Self.sortedByPreference(rectangles)
    }

    // Area-first, confidence-as-tiebreaker. Document segmentation usually returns one
    // observation, but we keep the sort so multi-candidate results stay deterministic.
    static func sortedByPreference(_ rectangles: [DetectedRectangle]) -> [DetectedRectangle] {
        rectangles.sorted { a, b in
            let areaA = a.boundingBox.width * a.boundingBox.height
            let areaB = b.boundingBox.width * b.boundingBox.height
            if abs(areaA - areaB) < CGFloat(Self.similarAreaTolerance) {
                return a.confidence > b.confidence
            }
            return areaA > areaB
        }
    }
}
