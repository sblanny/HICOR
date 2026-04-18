import XCTest
import UIKit
@testable import HICOR

final class DocumentRectifierTests: XCTestCase {

    /// Draw a dark rectangle on a light background at the given normalized
    /// coordinates (Vision-style, origin bottom-left, 0..1). Vision has no
    /// trouble detecting this kind of high-contrast quad.
    private func imageWithRect(
        rectNormalized: CGRect,
        imageSize: CGSize = CGSize(width: 600, height: 800)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: imageSize).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: imageSize))
            UIColor.black.setFill()
            let pixelRect = CGRect(
                x: rectNormalized.minX * imageSize.width,
                // Flip Y: we pass normalized bottom-left, draw top-left.
                y: (1.0 - rectNormalized.maxY) * imageSize.height,
                width: rectNormalized.width * imageSize.width,
                height: rectNormalized.height * imageSize.height
            )
            ctx.fill(pixelRect)
        }
    }

    func testRectifyReturnsImageWhenPrintoutFillsFrame() async {
        let image = imageWithRect(rectNormalized: CGRect(x: 0.1, y: 0.15, width: 0.8, height: 0.7))
        let out = await DocumentRectifier.rectify(image)
        XCTAssertNotNil(out)
    }

    func testRectifyReturnsNilWhenNoRectanglePresent() async {
        // A flat gray image has no detectable rectangle.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        let out = await DocumentRectifier.rectify(image)
        XCTAssertNil(out)
    }

    func testRectifyOutputIsLongSideHorizontal() async {
        // Tall rectangle in a tall source image. Expect output to be
        // wider-than-tall (normalized to long-side-horizontal).
        let image = imageWithRect(
            rectNormalized: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8),
            imageSize: CGSize(width: 600, height: 1000)
        )
        guard let out = await DocumentRectifier.rectify(image) else {
            return XCTFail("expected rectification to succeed")
        }
        XCTAssertGreaterThanOrEqual(out.size.width, out.size.height,
                                    "rectified image should be normalized to landscape")
    }
}
