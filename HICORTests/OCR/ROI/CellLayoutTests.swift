import XCTest
import UIKit
@testable import HICOR

final class CellLayoutTests: XCTestCase {

    /// Build a synthetic Anchors set mimicking a GRK-6000 layout on a
    /// 1500×1100 rectified image. Right section in top half, left in bottom.
    private func syntheticAnchors() -> Anchors {
        let right = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y:  60, width: 60, height: 60),  // <R>
            sph:       CGRect(x:  120, y: 100, width: 80, height: 60),
            cyl:       CGRect(x:  120, y: 240, width: 80, height: 60),
            ax:        CGRect(x:  120, y: 380, width: 80, height: 60),
            avg:       CGRect(x:  120, y: 520, width: 80, height: 60)
        )
        let left = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y: 640, width: 60, height: 60),  // <L>
            sph:       CGRect(x:  120, y: 680, width: 80, height: 60),
            cyl:       CGRect(x:  120, y: 800, width: 80, height: 60),
            ax:        CGRect(x:  120, y: 920, width: 80, height: 60),
            avg:       CGRect(x:  120, y:1040, width: 80, height: 60)
        )
        return Anchors(right: right, left: left)
    }

    func testLayoutProduces24Cells() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        XCTAssertEqual(cells.count, 24)
    }

    func testEachEyeHas12Cells() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        XCTAssertEqual(cells.filter { $0.eye == .right }.count, 12)
        XCTAssertEqual(cells.filter { $0.eye == .left }.count, 12)
    }

    func testEachColumnHasEightCells() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        XCTAssertEqual(cells.filter { $0.column == .sph }.count, 8)
        XCTAssertEqual(cells.filter { $0.column == .cyl }.count, 8)
        XCTAssertEqual(cells.filter { $0.column == .ax  }.count, 8)
    }

    func testRowKindsPerEye() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        for eye in [CellROI.Eye.right, .left] {
            for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                let count = cells.filter { $0.eye == eye && $0.row == row }.count
                XCTAssertEqual(count, 3, "eye=\(eye) row=\(row) should have 3 cells (one per column)")
            }
        }
    }

    func testSPHCellsAlignHorizontallyWithSPHHeader() {
        let anchors = syntheticAnchors()
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        for cell in cells where cell.eye == .right && cell.column == .sph {
            let sphHeaderMidX = anchors.right.sph.midX
            XCTAssertEqual(cell.rect.midX, sphHeaderMidX, accuracy: 1.0,
                           "SPH cells should share X with SPH header")
        }
    }

    func testRightEyeRowsAreOrderedTopToBottom() {
        let anchors = syntheticAnchors()
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        let rightSPH = cells
            .filter { $0.eye == .right && $0.column == .sph }
            .sorted { rowOrder($0.row) < rowOrder($1.row) }
        // r1 above r2 above r3 above avg → minY ascending
        let minYs = rightSPH.map(\.rect.minY)
        XCTAssertEqual(minYs, minYs.sorted(), "right-eye SPH rows should ascend in Y")
    }

    private func rowOrder(_ row: CellROI.Row) -> Int {
        switch row {
        case .r1:  return 0
        case .r2:  return 1
        case .r3:  return 2
        case .avg: return 3
        }
    }
}
