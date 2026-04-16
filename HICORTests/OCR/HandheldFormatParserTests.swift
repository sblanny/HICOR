import XCTest
@testable import HICOR

final class HandheldFormatParserTests: XCTestCase {

    func testStandardFixtureParsesEightReadingsPerEye() {
        let lines = OCRFixture.load("handheld_standard")
        let result = HandheldFormatParser.parse(lines: lines, photoIndex: 0)

        XCTAssertEqual(result.machineType, .handheld)
        XCTAssertEqual(result.rightEye?.readings.count, 8)
        XCTAssertEqual(result.leftEye?.readings.count, 8)
        XCTAssertNil(result.pd)
    }

    func testEQualityReadingsAreFlaggedAsLowConfidence() {
        let lines = OCRFixture.load("handheld_standard")
        let result = HandheldFormatParser.parse(lines: lines, photoIndex: 0)

        guard let rightReadings = result.rightEye?.readings else {
            return XCTFail("Missing right eye readings")
        }
        let lowConfRight = rightReadings.filter { $0.lowConfidence }
        XCTAssertEqual(lowConfRight.count, 1, "Standard fixture has exactly 1 E-quality reading per eye")
        XCTAssertEqual(lowConfRight.first?.ax, 83)
    }

    func testStarLineCapturesAverageAndConfidence() {
        let lines = OCRFixture.load("handheld_standard")
        let result = HandheldFormatParser.parse(lines: lines, photoIndex: 0)

        XCTAssertEqual(result.rightEye?.machineAvgSPH, -3.25)
        XCTAssertEqual(result.rightEye?.machineAvgCYL, -1.00)
        XCTAssertEqual(result.rightEye?.machineAvgAX, 83)
        XCTAssertEqual(result.handheldStarConfidenceRight, 5)
        XCTAssertEqual(result.handheldStarConfidenceLeft, 5)
    }

    func testLargeSPHFixtureParsesPlus21Values() {
        let lines = OCRFixture.load("handheld_large_sph")
        let result = HandheldFormatParser.parse(lines: lines, photoIndex: 0)

        guard let firstRight = result.rightEye?.readings.first else {
            return XCTFail("Missing right reading")
        }
        XCTAssertEqual(firstRight.sph, 21.00)
        XCTAssertEqual(firstRight.cyl, -1.00)
        XCTAssertEqual(result.handheldStarConfidenceRight, 6)
    }

    func testNegativeSPHReadingsParse() {
        let lines = OCRFixture.load("handheld_standard")
        let result = HandheldFormatParser.parse(lines: lines, photoIndex: 0)

        guard let firstRight = result.rightEye?.readings.first else {
            return XCTFail("Missing right reading")
        }
        XCTAssertEqual(firstRight.sph, -3.25)
        XCTAssertTrue(firstRight.sph < 0, "Negative SPH parsing must preserve sign")
    }

    func testNoPDOnHandheld() {
        let lines = OCRFixture.load("handheld_standard")
        let result = HandheldFormatParser.parse(lines: lines, photoIndex: 0)
        XCTAssertNil(result.pd, "Handheld printouts have no PD line")
    }
}
