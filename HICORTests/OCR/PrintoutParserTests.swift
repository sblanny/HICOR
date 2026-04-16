import XCTest
@testable import HICOR

final class PrintoutParserTests: XCTestCase {

    func testDetectsDesktopFromAVGOrHighlandsHeader() {
        let lines = OCRFixture.load("desktop_standard")
        XCTAssertEqual(PrintoutParser.detect(lines: lines), .desktop)
    }

    func testDetectsHandheldFromREFMarker() {
        let lines = OCRFixture.load("handheld_standard")
        XCTAssertEqual(PrintoutParser.detect(lines: lines), .handheld)
    }

    func testFallbackHandheldDetectionFromStarAndBrackets() {
        let lines = ["Some header", "[R]", "* - 1.00 - 0.50  90  5", "[L]", "* - 1.00 - 0.50  90  5"]
        XCTAssertEqual(PrintoutParser.detect(lines: lines), .handheld)
    }

    func testUnrecognizedFormatThrows() {
        let lines = ["Random text", "no markers here", "1234"]
        XCTAssertThrowsError(try PrintoutParser.parse(lines: lines, photoIndex: 0)) { error in
            XCTAssertEqual(error as? OCRService.OCRError, OCRService.OCRError.unrecognizedFormat)
        }
    }
}
