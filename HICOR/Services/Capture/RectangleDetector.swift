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
    static let minimumSize: Float = 0.2
    static let quadratureToleranceDegrees: Float = 30

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
        request.maximumObservations = 3
        return request
    }

    private func mapResults(_ results: [VNObservation]?) -> [DetectedRectangle] {
        let observations = (results as? [VNRectangleObservation]) ?? []
        return observations
            .sorted { $0.confidence > $1.confidence }
            .map { obs in
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
    }
}
