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

    // MARK: - Plano (signless 0.00) CYL parsing
    //
    // The GRK-6000 prints plano CYL as "0.00" with no sign. Forcing it
    // negative makes Double parse as IEEE-754 -0.0, whose sign bit
    // poisoned `value >= 0 ? "+" : ""` display formatters into rendering
    // "+-0.00" (which then wrapped on screen as "+-0.0\n0").

    func testParsesUnsignedZeroCYLAsPositiveZero() {
        let lines = [
            "Highlands Optical",
            "<R>",
            "+ 1.50  0.00  90",
            "AVG + 1.50  0.00  90",
            "PD: 64 mm"
        ]
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)
        guard let reading = result.rightEye?.readings.first else {
            return XCTFail("Expected a parsed reading")
        }
        XCTAssertEqual(reading.cyl, 0.0)
        XCTAssertEqual(reading.cyl.sign, .plus,
                       "Plano CYL must be positive zero; -0.0 leaks through display formatters as \"+-0.00\".")
    }

    func testParsesUnsignedZeroCYLAlongsideSignedCYL() {
        let lines = [
            "<R>",
            "+ 1.50  0.00  90",
            "+ 1.25  - 0.25  85",
            "AVG + 1.25  - 0.25  88"
        ]
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)
        let readings = result.rightEye?.readings ?? []
        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings[0].cyl, 0.0)
        XCTAssertEqual(readings[0].cyl.sign, .plus)
        XCTAssertEqual(readings[1].cyl, -0.25)
    }

    func testHandlesMultipleZeroCYLInSameEye() {
        // Mirrors the real-device capture in the bug report: left eye has
        // 0.00 / -0.25 / 0.00 across r1/r2/r3.
        let lines = [
            "<L>",
            "- 2.50  0.00  1",
            "- 2.50  - 0.25  175",
            "- 2.50  0.00  1",
            "AVG - 2.50  0.00  1"
        ]
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)
        let readings = result.leftEye?.readings ?? []
        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings[0].cyl, 0.0)
        XCTAssertEqual(readings[0].cyl.sign, .plus)
        XCTAssertEqual(readings[1].cyl, -0.25)
        XCTAssertEqual(readings[2].cyl, 0.0)
        XCTAssertEqual(readings[2].cyl.sign, .plus)
        XCTAssertEqual(result.leftEye?.machineAvgCYL, 0.0)
        XCTAssertEqual(result.leftEye?.machineAvgCYL?.sign, .plus)
    }

    func testRejectsRowWithMalformedSignToken() {
        // "+-0.00" is the literal pre-fix mangled token. The shape gate
        // and Double() coercion both reject it; pin the behavior so a
        // future "be helpful, try both signs" parser can't reintroduce
        // the rendering bug.
        let lines = [
            "<R>",
            "+ 1.50  +-0.00  90"
        ]
        let result = DesktopFormatParser.parse(lines: lines, photoIndex: 0)
        XCTAssertTrue(result.rightEye?.readings.isEmpty ?? true,
                      "Row with malformed +- sign token must not produce a reading")
    }
}
