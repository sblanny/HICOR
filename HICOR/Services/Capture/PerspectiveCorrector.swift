import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct QuadCorners: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
}

enum PerspectiveCorrector {
    // Corners are in UIKit pixel space (top-left origin). Core Image uses bottom-left origin,
    // so y is flipped internally before passing to CIPerspectiveCorrection.
    static func correct(image: UIImage, corners: QuadCorners) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let flip: (CGPoint) -> CGPoint = { CGPoint(x: $0.x, y: height - $0.y) }
        let tl = flip(corners.topLeft)
        let tr = flip(corners.topRight)
        let bl = flip(corners.bottomLeft)
        let br = flip(corners.bottomRight)

        guard validCorners([tl, tr, bl, br], in: CGSize(width: width, height: height)) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = tl
        filter.topRight = tr
        filter.bottomLeft = bl
        filter.bottomRight = br

        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let rendered = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func validCorners(_ points: [CGPoint], in size: CGSize) -> Bool {
        guard points.count == 4 else { return false }
        let unique = Set(points.map { "\($0.x),\($0.y)" })
        guard unique.count == 4 else { return false }
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1)
        return points.allSatisfy { bounds.contains($0) }
    }
}
