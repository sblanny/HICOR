import XCTest
import UIKit
@testable import HICOR

final class PerspectiveCorrectorTests: XCTestCase {
    func testSkewedRectangleRectifies() {
        let image = makeCheckerboard(size: CGSize(width: 800, height: 1000))
        let corners = QuadCorners(
            topLeft:     CGPoint(x: 150, y: 100),
            topRight:    CGPoint(x: 650, y: 100),
            bottomRight: CGPoint(x: 750, y: 900),
            bottomLeft:  CGPoint(x: 50,  y: 900)
        )
        let output = PerspectiveCorrector.correct(image: image, corners: corners)
        XCTAssertNotNil(output)
        XCTAssertGreaterThan(output!.size.width, 0)
        XCTAssertGreaterThan(output!.size.height, 0)
    }

    func testReturnsNilForCornersOutsideImage() {
        let image = makeCheckerboard(size: CGSize(width: 800, height: 1000))
        let corners = QuadCorners(
            topLeft:     CGPoint(x: -100, y: 100),
            topRight:    CGPoint(x: 700,  y: 100),
            bottomRight: CGPoint(x: 700,  y: 900),
            bottomLeft:  CGPoint(x: 100,  y: 900)
        )
        XCTAssertNil(PerspectiveCorrector.correct(image: image, corners: corners))
    }

    func testReturnsNilForDegenerateCorners() {
        let image = makeCheckerboard(size: CGSize(width: 800, height: 1000))
        let p = CGPoint(x: 400, y: 500)
        let corners = QuadCorners(topLeft: p, topRight: p, bottomRight: p, bottomLeft: p)
        XCTAssertNil(PerspectiveCorrector.correct(image: image, corners: corners))
    }

    // MARK: - Helpers

    private func makeCheckerboard(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cols = 8, rows = 10
            let cw = size.width / CGFloat(cols), rh = size.height / CGFloat(rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    ((r + c).isMultiple(of: 2) ? UIColor.white : UIColor.black).setFill()
                    ctx.fill(CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * rh, width: cw, height: rh))
                }
            }
        }
    }
}
