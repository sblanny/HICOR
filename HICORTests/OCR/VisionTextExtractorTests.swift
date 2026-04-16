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

    func testSectionAwareUnevenRowsPerEye() {
        // 8 right-eye rows, 3 left-eye rows. Markers + * lines included.
        var boxes: [TextBox] = [
            TextBox(midX: 0.5, midY: 0.97, minX: 0.4, text: "-REF-"),
            TextBox(midX: 0.3, midY: 0.92, minX: 0.28, text: "[R]"),
        ]
        // 8 right rows from Y=0.88 down to 0.53, 0.05 spacing
        let rightYs: [CGFloat] = [0.88, 0.83, 0.78, 0.73, 0.68, 0.63, 0.58, 0.53]
        for y in rightYs {
            boxes.append(TextBox(midX: 0.20, midY: y, minX: 0.18, text: "- 3.25"))
            boxes.append(TextBox(midX: 0.40, midY: y, minX: 0.38, text: "- 1.00"))
            boxes.append(TextBox(midX: 0.60, midY: y, minX: 0.58, text: "81"))
            boxes.append(TextBox(midX: 0.80, midY: y, minX: 0.78, text: "AQ"))
        }
        // Right * line at Y=0.48
        boxes.append(TextBox(midX: 0.10, midY: 0.48, minX: 0.08, text: "*"))
        boxes.append(TextBox(midX: 0.20, midY: 0.48, minX: 0.18, text: "- 3.25"))
        boxes.append(TextBox(midX: 0.40, midY: 0.48, minX: 0.38, text: "- 1.00"))
        boxes.append(TextBox(midX: 0.60, midY: 0.48, minX: 0.58, text: "83"))
        boxes.append(TextBox(midX: 0.80, midY: 0.48, minX: 0.78, text: "5"))
        // [L] at Y=0.43
        boxes.append(TextBox(midX: 0.30, midY: 0.43, minX: 0.28, text: "[L]"))
        // 3 left rows
        let leftYs: [CGFloat] = [0.38, 0.33, 0.28]
        for y in leftYs {
            boxes.append(TextBox(midX: 0.20, midY: y, minX: 0.18, text: "- 3.50"))
            boxes.append(TextBox(midX: 0.40, midY: y, minX: 0.38, text: "- 1.25"))
            boxes.append(TextBox(midX: 0.60, midY: y, minX: 0.58, text: "85"))
            boxes.append(TextBox(midX: 0.80, midY: y, minX: 0.78, text: "AQ"))
        }
        // Left * line at Y=0.20
        boxes.append(TextBox(midX: 0.10, midY: 0.20, minX: 0.08, text: "*"))
        boxes.append(TextBox(midX: 0.20, midY: 0.20, minX: 0.18, text: "- 3.50"))
        boxes.append(TextBox(midX: 0.40, midY: 0.20, minX: 0.38, text: "- 1.25"))
        boxes.append(TextBox(midX: 0.60, midY: 0.20, minX: 0.58, text: "85"))
        boxes.append(TextBox(midX: 0.80, midY: 0.20, minX: 0.78, text: "5"))

        let lines = VisionTextExtractor.reconstructColumnarLines(from: boxes)

        XCTAssertTrue(lines.contains("-REF-"), "Header preserved")
        XCTAssertTrue(lines.contains("[R]"))
        XCTAssertTrue(lines.contains("[L]"))
        let rIndex = lines.firstIndex(of: "[R]")!
        let lIndex = lines.firstIndex(of: "[L]")!
        let rightRows = lines[(rIndex + 1)..<lIndex].filter { !$0.hasPrefix("*") }
        let leftRows = lines[(lIndex + 1)...].filter { !$0.hasPrefix("*") && !$0.isEmpty }
        XCTAssertEqual(rightRows.count, 8, "Right eye should yield 8 data rows")
        XCTAssertEqual(leftRows.count, 3, "Left eye should yield 3 data rows")
        XCTAssertEqual(rightRows.first, "- 3.25  - 1.00  81  AQ")
        XCTAssertEqual(leftRows.first, "- 3.50  - 1.25  85  AQ")
        // Star rows present in both sections
        XCTAssertTrue(lines.contains { $0.hasPrefix("*") && $0.contains("3.25") }, "Right * line present")
        XCTAssertTrue(lines.contains { $0.hasPrefix("*") && $0.contains("3.50") }, "Left * line present")
    }

    func testSectionAwareBlindRightEye() {
        // [R] section empty, [L] section has 4 rows + *
        var boxes: [TextBox] = [
            TextBox(midX: 0.5, midY: 0.97, minX: 0.4, text: "-REF-"),
            TextBox(midX: 0.3, midY: 0.92, minX: 0.28, text: "[R]"),
            TextBox(midX: 0.3, midY: 0.50, minX: 0.28, text: "[L]"),
        ]
        let leftYs: [CGFloat] = [0.45, 0.40, 0.35, 0.30]
        for y in leftYs {
            boxes.append(TextBox(midX: 0.20, midY: y, minX: 0.18, text: "- 1.50"))
            boxes.append(TextBox(midX: 0.40, midY: y, minX: 0.38, text: "- 0.25"))
            boxes.append(TextBox(midX: 0.60, midY: y, minX: 0.58, text: "85"))
            boxes.append(TextBox(midX: 0.80, midY: y, minX: 0.78, text: "AQ"))
        }
        boxes.append(TextBox(midX: 0.10, midY: 0.20, minX: 0.08, text: "*"))
        boxes.append(TextBox(midX: 0.20, midY: 0.20, minX: 0.18, text: "- 1.50"))
        boxes.append(TextBox(midX: 0.40, midY: 0.20, minX: 0.38, text: "- 0.25"))
        boxes.append(TextBox(midX: 0.60, midY: 0.20, minX: 0.58, text: "85"))
        boxes.append(TextBox(midX: 0.80, midY: 0.20, minX: 0.78, text: "5"))

        let lines = VisionTextExtractor.reconstructColumnarLines(from: boxes)

        let rIndex = lines.firstIndex(of: "[R]")!
        let lIndex = lines.firstIndex(of: "[L]")!
        // Between [R] and [L]: nothing
        let between = lines[(rIndex + 1)..<lIndex]
        XCTAssertTrue(between.isEmpty, "Right section should be empty between [R] and [L]")
        // After [L]: 4 data rows + 1 star row
        let afterL = lines[(lIndex + 1)...]
        let dataRows = afterL.filter { !$0.hasPrefix("*") && !$0.isEmpty }
        XCTAssertEqual(dataRows.count, 4)
        XCTAssertTrue(afterL.contains { $0.hasPrefix("*") })
    }

    func testSectionAwareBlindLeftEye() {
        // [R] section has 6 rows + *, [L] section empty
        var boxes: [TextBox] = [
            TextBox(midX: 0.5, midY: 0.97, minX: 0.4, text: "-REF-"),
            TextBox(midX: 0.3, midY: 0.92, minX: 0.28, text: "[R]"),
        ]
        let rightYs: [CGFloat] = [0.88, 0.83, 0.78, 0.73, 0.68, 0.63]
        for y in rightYs {
            boxes.append(TextBox(midX: 0.20, midY: y, minX: 0.18, text: "- 2.00"))
            boxes.append(TextBox(midX: 0.40, midY: y, minX: 0.38, text: "- 0.50"))
            boxes.append(TextBox(midX: 0.60, midY: y, minX: 0.58, text: "90"))
            boxes.append(TextBox(midX: 0.80, midY: y, minX: 0.78, text: "AQ"))
        }
        boxes.append(TextBox(midX: 0.10, midY: 0.55, minX: 0.08, text: "*"))
        boxes.append(TextBox(midX: 0.20, midY: 0.55, minX: 0.18, text: "- 2.00"))
        boxes.append(TextBox(midX: 0.40, midY: 0.55, minX: 0.38, text: "- 0.50"))
        boxes.append(TextBox(midX: 0.60, midY: 0.55, minX: 0.58, text: "90"))
        boxes.append(TextBox(midX: 0.80, midY: 0.55, minX: 0.78, text: "5"))
        boxes.append(TextBox(midX: 0.30, midY: 0.50, minX: 0.28, text: "[L]"))

        let lines = VisionTextExtractor.reconstructColumnarLines(from: boxes)

        let rIndex = lines.firstIndex(of: "[R]")!
        let lIndex = lines.firstIndex(of: "[L]")!
        // Between [R] and [L]: 6 data rows + 1 star
        let between = lines[(rIndex + 1)..<lIndex]
        let dataRows = between.filter { !$0.hasPrefix("*") && !$0.isEmpty }
        XCTAssertEqual(dataRows.count, 6)
        XCTAssertTrue(between.contains { $0.hasPrefix("*") })
        // After [L]: nothing
        let afterL = lines[(lIndex + 1)...].filter { !$0.isEmpty }
        XCTAssertTrue(afterL.isEmpty, "Left section should be empty")
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
