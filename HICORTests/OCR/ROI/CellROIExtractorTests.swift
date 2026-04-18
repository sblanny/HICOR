import XCTest
import UIKit
@testable import HICOR

final class CellROIExtractorTests: XCTestCase {

    private func solidImage(size: CGSize = CGSize(width: 1000, height: 800)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testCropDimensionsMatchCellRect() {
        let image = solidImage()
        let cell = CellROI(eye: .right, column: .sph, row: .r1,
                           rect: CGRect(x: 100, y: 100, width: 60, height: 40))
        let crops = CellROIExtractor.crop(image: image, cells: [cell], paddingFraction: 0.0)
        XCTAssertEqual(crops.count, 1)
        XCTAssertEqual(crops[0].1.size, CGSize(width: 60, height: 40))
    }

    func testCropAppliesPadding() {
        let image = solidImage()
        let cell = CellROI(eye: .right, column: .sph, row: .r1,
                           rect: CGRect(x: 100, y: 100, width: 60, height: 40))
        let crops = CellROIExtractor.crop(image: image, cells: [cell], paddingFraction: 0.1)
        // 10% padding on each side → 20% wider, 20% taller.
        XCTAssertEqual(crops[0].1.size.width, 60 * 1.2, accuracy: 1.0)
        XCTAssertEqual(crops[0].1.size.height, 40 * 1.2, accuracy: 1.0)
    }

    func testCropClampsToImageBounds() {
        let image = solidImage(size: CGSize(width: 200, height: 200))
        let cell = CellROI(eye: .right, column: .sph, row: .r1,
                           rect: CGRect(x: 180, y: 180, width: 60, height: 40))
        let crops = CellROIExtractor.crop(image: image, cells: [cell], paddingFraction: 0.0)
        // Right/bottom edges clamp: width = 200 - 180 = 20, height = 200 - 180 = 20.
        XCTAssertEqual(crops[0].1.size.width, 20, accuracy: 1.0)
        XCTAssertEqual(crops[0].1.size.height, 20, accuracy: 1.0)
    }

    func testCropPreservesOrder() {
        let image = solidImage()
        let cells = [
            CellROI(eye: .right, column: .sph, row: .r1, rect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            CellROI(eye: .right, column: .cyl, row: .r2, rect: CGRect(x: 50, y: 50, width: 20, height: 20)),
            CellROI(eye: .left,  column: .ax,  row: .avg, rect: CGRect(x: 90, y: 90, width: 20, height: 20))
        ]
        let crops = CellROIExtractor.crop(image: image, cells: cells, paddingFraction: 0.0)
        XCTAssertEqual(crops.map(\.0), cells)
    }
}
