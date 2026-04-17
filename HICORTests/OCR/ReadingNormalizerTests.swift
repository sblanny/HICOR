import XCTest
@testable import HICOR

final class ReadingNormalizerTests: XCTestCase {

    func testSPHRoundsToNearestQuarterDiopter() {
        XCTAssertEqual(ReadingNormalizer.normalize(sph: 1.40), 1.50)
        XCTAssertEqual(ReadingNormalizer.normalize(sph: 1.10), 1.00)
        XCTAssertEqual(ReadingNormalizer.normalize(sph: -2.13), -2.25)
    }

    func testSPHHandlesZeroExactly() {
        XCTAssertEqual(ReadingNormalizer.normalize(sph: 0.0), 0.0)
        XCTAssertEqual(ReadingNormalizer.normalize(sph: 0.10), 0.0)
        XCTAssertEqual(ReadingNormalizer.normalize(sph: 0.13), 0.25)
    }

    func testCYLRoundsToNearestQuarterDiopter() {
        XCTAssertEqual(ReadingNormalizer.normalize(cyl: -0.55), -0.50)
        XCTAssertEqual(ReadingNormalizer.normalize(cyl: -1.13), -1.25)
        XCTAssertEqual(ReadingNormalizer.normalize(cyl: -2.10), -2.00)
    }

    func testCYLInsideInventoryRangeIsDetected() {
        XCTAssertTrue(ReadingNormalizer.isCylInsideInventoryRange(0.0))
        XCTAssertTrue(ReadingNormalizer.isCylInsideInventoryRange(-0.50))
        XCTAssertTrue(ReadingNormalizer.isCylInsideInventoryRange(-2.00))
    }

    func testCYLOutsideInventoryRangeIsRejected() {
        XCTAssertFalse(ReadingNormalizer.isCylInsideInventoryRange(-0.25))
        XCTAssertFalse(ReadingNormalizer.isCylInsideInventoryRange(-0.75))
        XCTAssertFalse(ReadingNormalizer.isCylInsideInventoryRange(-2.25))
    }

    func testAXClampsToOneEighty() {
        XCTAssertEqual(ReadingNormalizer.normalize(ax: 0), 1)
        XCTAssertEqual(ReadingNormalizer.normalize(ax: 200), 180)
        XCTAssertEqual(ReadingNormalizer.normalize(ax: 90), 90)
        XCTAssertEqual(ReadingNormalizer.normalize(ax: -5), 1)
    }

    func testNormalizeOCRStringFixesCommonMisreads() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("1O8"), "108")
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("l.50"), "1.50")
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("S.25"), "5.25")
    }

    func testNormalizeOCRStringCollapsesWhitespace() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("  +  1.50    -0.25  "), "+ 1.50 -0.25")
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("AVG    +1.50"), "AVG +1.50")
    }

    func testNormalizePreservesSPHHeader() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("SPH"), "SPH")
    }

    func testNormalizePreservesAQMarker() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("- 2.00  - 0.50  85 AQ"), "- 2.00 - 0.50 85 AQ")
    }

    func testNormalizeFixesNumericTokenWithLetterO() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("- 2.O0"), "- 2.00")
    }

    func testNormalizeLeavesLetterBUnchanged() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("B"), "B")
    }

    func testNormalizePreservesREFMarker() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("-REF-"), "-REF-")
    }

    func testNormalizePreservesAVGLabel() {
        XCTAssertEqual(ReadingNormalizer.normalizeOCRString("AVG + 1.50"), "AVG + 1.50")
    }
}
