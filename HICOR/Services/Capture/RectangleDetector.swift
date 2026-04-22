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
    static let minimumAspectRatio: Float = 0.2
    static let maximumAspectRatio: Float = 1.0
    static let minimumConfidence: VNConfidence = 0.6
    // 0.35 excludes interior printout sections (header/R-block/AVG-bounded boxes) whose
    // normalized area lands in the 0.15–0.30 range when the full printout fills the frame.
    // The outer paper itself typically clears 0.35 with room to spare.
    static let minimumSize: Float = 0.35
    static let quadratureToleranceDegrees: Float = 30
    // Similar areas (within 2%) fall back to confidence as the tiebreaker.
    static let similarAreaTolerance: Float = 0.02

    private let sequenceHandler = VNSequenceRequestHandler()

    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [DetectedRectangle] {
        let request = makeRequest()
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)
        } catch {
            return []
        }
        return mapResults(request.results)
    }

    func detectSync(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) -> [DetectedRectangle] {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return mapResults(request.results)
    }

    private func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = Self.minimumAspectRatio
        request.maximumAspectRatio = Self.maximumAspectRatio
        request.minimumConfidence = Self.minimumConfidence
        request.minimumSize = Self.minimumSize
        request.quadratureTolerance = Self.quadratureToleranceDegrees
        request.maximumObservations = 8
        return request
    }

    private func mapResults(_ results: [VNObservation]?) -> [DetectedRectangle] {
        let observations = (results as? [VNRectangleObservation]) ?? []
        let rectangles = observations.map { obs in
            // Vision returns corners in bottom-left normalized space; flip y to match
            // UIKit top-left normalized space so callers can denormalize against view/image size.
            DetectedRectangle(
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

    // Area-first, confidence-as-tiebreaker. Interior printout sections (R-block,
    // AVG-bounded boxes) can score higher confidence than the outer paper because
    // their edges are crisp white-on-white while the paper edge against a surface
    // is softer. Sorting by area first ensures the outer paper wins.
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
