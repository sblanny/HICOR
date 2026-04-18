import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum DocumentRectifier {

    /// Detects the printout rectangle in `image` and returns a perspective-
    /// corrected UIImage normalized to long-side-horizontal orientation.
    /// Returns nil when no suitable rectangle is found.
    static func rectify(_ image: UIImage) async -> UIImage? {
        guard let cg = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.7
        // Vision's aspect ratio is width/height. Accept both portrait
        // (tall printout photographed upright) and landscape; we normalize
        // orientation after perspective correction.
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 3.0
        request.maximumObservations = 8

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        // Select: biggest rectangle whose center is in the inner 70% of the
        // frame. Biases toward the framing guide, against background clutter.
        let innerRect = CGRect(x: 0.15, y: 0.15, width: 0.70, height: 0.70)
        let eligible = observations.filter { obs in
            innerRect.contains(CGPoint(
                x: (obs.topLeft.x + obs.topRight.x + obs.bottomLeft.x + obs.bottomRight.x) / 4.0,
                y: (obs.topLeft.y + obs.topRight.y + obs.bottomLeft.y + obs.bottomRight.y) / 4.0
            ))
        }
        let pool = eligible.isEmpty ? observations : eligible
        let chosen = pool.max { area($0) < area($1) }!

        let ciInput = CIImage(cgImage: cg)
        let imageSize = ciInput.extent.size

        // Vision returns normalized coords, origin bottom-left.
        // CIPerspectiveCorrection expects pixel coords, origin bottom-left.
        let tl = CGPoint(x: chosen.topLeft.x * imageSize.width,
                         y: chosen.topLeft.y * imageSize.height)
        let tr = CGPoint(x: chosen.topRight.x * imageSize.width,
                         y: chosen.topRight.y * imageSize.height)
        let bl = CGPoint(x: chosen.bottomLeft.x * imageSize.width,
                         y: chosen.bottomLeft.y * imageSize.height)
        let br = CGPoint(x: chosen.bottomRight.x * imageSize.width,
                         y: chosen.bottomRight.y * imageSize.height)

        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = ciInput
        correction.topLeft = tl
        correction.topRight = tr
        correction.bottomLeft = bl
        correction.bottomRight = br

        guard let corrected = correction.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgOut = context.createCGImage(corrected, from: corrected.extent) else { return nil }

        let rectified = UIImage(cgImage: cgOut)

        // Normalize to long-side-horizontal.
        if rectified.size.height > rectified.size.width {
            return rotate90CW(rectified)
        }
        return rectified
    }

    private static func area(_ obs: VNRectangleObservation) -> CGFloat {
        let w = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
        let h = hypot(obs.topLeft.x - obs.bottomLeft.x, obs.topLeft.y - obs.bottomLeft.y)
        return w * h
    }

    private static func rotate90CW(_ image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        return UIGraphicsImageRenderer(size: newSize).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width, y: 0)
            cg.rotate(by: .pi / 2)
            image.draw(at: .zero)
        }
    }
}
