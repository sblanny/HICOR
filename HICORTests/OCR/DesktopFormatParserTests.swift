import XCTest
@testable import HICOR

final class DesktopFormatParserTests: XCTestCase {

    func testStandardFixtureParsesThreeReadingsPerEye() {
        let lines = OCRFixture.load("desktop_standard")
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)

        XCTAssertEqual(result.machineType, .desktop)
        XCTAssertEqual(result.sourcePhotoIndex, 0)

        guard let right = result.rightEye, let left = result.leftEye else {
            return XCTFail("Expected both eyes to be parsed")
        }
        XCTAssertEqual(right.readings.count, 3)
        XCTAssertEqual(left.readings.count, 3)
        XCTAssertEqual(right.machineType, .desktop)
    }

    func testStandardFixtureExtractsCorrectFirstReadingValues() {
        let lines = OCRFixture.load("desktop_standard")
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)

        guard let firstRight = result.rightEye?.readings.first,
              let firstLeft = result.leftEye?.readings.first else {
            return XCTFail("Missing readings")
        }
        XCTAssertEqual(firstRight.sph, 1.50)
        XCTAssertEqual(firstRight.cyl, -0.25)
        XCTAssertEqual(firstRight.ax, 108)
        XCTAssertEqual(firstLeft.sph, -2.25)
        XCTAssertEqual(firstLeft.cyl, -0.75)
        XCTAssertEqual(firstLeft.ax, 92)
    }

    func testStandardFixtureCapturesAVGLine() {
        let lines = OCRFixture.load("desktop_standard")
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)

        XCTAssertEqual(result.rightEye?.machineAvgSPH, 1.50)
        XCTAssertEqual(result.rightEye?.machineAvgCYL, -0.50)
        XCTAssertEqual(result.rightEye?.machineAvgAX, 108)
        XCTAssertEqual(result.leftEye?.machineAvgSPH, -2.50)
        XCTAssertEqual(result.leftEye?.machineAvgCYL, -0.75)
        XCTAssertEqual(result.leftEye?.machineAvgAX, 90)
    }

    func testStandardFixtureExtractsPDValue() {
        let lines = OCRFixture.load("desktop_standard")
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)
        XCTAssertEqual(result.pd, 64.0)
    }

    func testMinimalFixtureWithTwoReadingsParses() {
        let lines = OCRFixture.load("desktop_minimal")
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 1)

        XCTAssertEqual(result.rightEye?.readings.count, 2)
        XCTAssertEqual(result.leftEye?.readings.count, 2)
        XCTAssertEqual(result.pd, 62.0)
    }

    func testAngleBracketMarkerVariantParses() {
        let lines = [
            "Highlands Optical",
            "<R>",
            "+ 1.00  - 0.50  90",
            "AVG + 1.00  - 0.50  90",
            "<L>",
            "- 1.00  - 0.50  90",
            "AVG - 1.00  - 0.50  90",
            "PD: 60 mm"
        ]
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)
        XCTAssertNotNil(result.rightEye)
        XCTAssertNotNil(result.leftEye)
        XCTAssertEqual(result.rightEye?.readings.first?.sph, 1.00)
        XCTAssertEqual(result.leftEye?.readings.first?.sph, -1.00)
        XCTAssertEqual(result.pd, 60.0)
    }
}
