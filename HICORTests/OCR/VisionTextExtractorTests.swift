import XCTest
@testable import HICOR

final class VisionTextExtractorTests: XCTestCase {

    func testColumnReconstructionHandheld() {
        // Vision returned observations in column-first order (the actual failure mode).
        // 4 columns: SPH, CYL, AX, Quality. 3 rows of readings.
        let boxes: [TextBox] = [
            // Column 1 (SPH) — top to bottom
            TextBox(midX: 0.20, midY: 0.80, minX: 0.18, text: "- 2.25"),
            TextBox(midX: 0.20, midY: 0.70, minX: 0.18, text: "- 2.25"),
            TextBox(midX: 0.20, midY: 0.60, minX: 0.18, text: "- 2.50"),
            // Column 2 (CYL)
            TextBox(midX: 0.40, midY: 0.80, minX: 0.38, text: "- 0.50"),
            TextBox(midX: 0.40, midY: 0.70, minX: 0.38, text: "- 0.50"),
            TextBox(midX: 0.40, midY: 0.60, minX: 0.38, text: "- 0.50"),
            // Column 3 (AX)
            TextBox(midX: 0.60, midY: 0.80, minX: 0.58, text: "54"),
            TextBox(midX: 0.60, midY: 0.70, minX: 0.58, text: "55"),
            TextBox(midX: 0.60, midY: 0.60, minX: 0.58, text: "56"),
            // Column 4 (Quality)
            TextBox(midX: 0.80, midY: 0.80, minX: 0.78, text: "AQ"),
            TextBox(midX: 0.80, midY: 0.70, minX: 0.78, text: "AQ"),
            TextBox(midX: 0.80, midY: 0.60, minX: 0.78, text: "E"),
        ]

        let rows = VisionTextExtractor.reconstructColumnarLines(from: boxes)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], "- 2.25  - 0.50  54  AQ")
        XCTAssertEqual(rows[1], "- 2.25  - 0.50  55  AQ")
        XCTAssertEqual(rows[2], "- 2.50  - 0.50  56  E")
    }

    func testRowReconstructionDesktop() {
        // Desktop format: each printed row arrives as a single observation.
        let boxes: [TextBox] = [
            TextBox(midX: 0.5, midY: 0.95, minX: 0.1, text: "Highlands Optical"),
            TextBox(midX: 0.4, midY: 0.85, minX: 0.1, text: "[R]"),
            TextBox(midX: 0.5, midY: 0.80, minX: 0.1, text: "+ 1.50  - 0.25  108"),
            TextBox(midX: 0.5, midY: 0.75, minX: 0.1, text: "+ 1.25  - 0.25  110"),
            TextBox(midX: 0.5, midY: 0.70, minX: 0.1, text: "AVG + 1.50  - 0.50  108"),
        ]

        let rows = VisionTextExtractor.reconstructRows(from: boxes)

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0], "Highlands Optical")
        XCTAssertEqual(rows[1], "[R]")
        XCTAssertEqual(rows[2], "+ 1.50  - 0.25  108")
        XCTAssertEqual(rows[3], "+ 1.25  - 0.25  110")
        XCTAssertEqual(rows[4], "AVG + 1.50  - 0.50  108")
    }

    func testColumnReconstructionWithUnevenColumnHeights() {
        // Quality column shorter than data columns (common: header line on AX only)
        let boxes: [TextBox] = [
            TextBox(midX: 0.20, midY: 0.80, minX: 0.18, text: "- 1.00"),
            TextBox(midX: 0.20, midY: 0.70, minX: 0.18, text: "- 1.25"),
            TextBox(midX: 0.40, midY: 0.80, minX: 0.38, text: "- 0.25"),
            TextBox(midX: 0.40, midY: 0.70, minX: 0.38, text: "- 0.25"),
            TextBox(midX: 0.60, midY: 0.80, minX: 0.58, text: "90"),
            TextBox(midX: 0.60, midY: 0.70, minX: 0.58, text: "92"),
            TextBox(midX: 0.80, midY: 0.80, minX: 0.78, text: "AQ"),
        ]

        let rows = VisionTextExtractor.reconstructColumnarLines(from: boxes)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], "- 1.00  - 0.25  90  AQ")
        XCTAssertEqual(rows[1], "- 1.25  - 0.25  92")
    }
}
