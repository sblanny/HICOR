import UIKit
import CoreGraphics

enum CellROIExtractor {

    /// Crops each cell rectangle from `image` with `paddingFraction` expansion
    /// on every side. Rectangles are clamped to the image bounds so crops
    /// near the edge return smaller images rather than empty ones.
    static func crop(
        image: UIImage,
        cells: [CellROI],
        paddingFraction: CGFloat = 0.1
    ) -> [(CellROI, UIImage)] {
        guard let cg = image.cgImage else { return [] }
        let scale = image.scale
        // cell.rect and image bounds are expressed in point coordinates
        // (match image.size). Clamp in point space, then convert to pixel
        // coordinates for cgImage.cropping(to:) which operates on pixels.
        let pointBounds = CGRect(x: 0, y: 0,
                                 width: CGFloat(cg.width) / scale,
                                 height: CGFloat(cg.height) / scale)
        var out: [(CellROI, UIImage)] = []
        for cell in cells {
            let padded = cell.rect.insetBy(
                dx: -cell.rect.width * paddingFraction,
                dy: -cell.rect.height * paddingFraction
            )
            let clampedPoints = padded.intersection(pointBounds)
            if clampedPoints.isEmpty { continue }
            let clampedPixels = CGRect(
                x: clampedPoints.minX * scale,
                y: clampedPoints.minY * scale,
                width: clampedPoints.width * scale,
                height: clampedPoints.height * scale
            ).integral
            if clampedPixels.isEmpty { continue }
            guard let cropped = cg.cropping(to: clampedPixels) else { continue }
            out.append((cell, UIImage(cgImage: cropped,
                                       scale: scale,
                                       orientation: image.imageOrientation)))
        }
        return out
    }
}
