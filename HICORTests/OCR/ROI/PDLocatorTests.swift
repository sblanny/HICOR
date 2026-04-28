import XCTest
import UIKit
@testable import HICOR

final class PDLocatorTests: XCTestCase {

    // Single-line case: ML Kit emits "PD: 64 mm" as one element. Existing
    // DesktopFormatParser regex already covered this, but the locator owns
    // the contract end-to-end now.
    func testReturnsValueWhenLabelAndDigitsAreOnTheSameLine() {
        let lines = [
            OCRLine(text: "PD: 64 mm", frame: CGRect(x: 580, y: 2520, width: 360, height: 60))
        ]
        XCTAssertEqual(PDLocator.locate(in: lines), 64.0)
    }

    // Real-capture failure mode (ROI debug log fragment from device):
    //   line "PD:" x=579 y=2518 w=106 h=60
    //   line "59"  x=770 y=2520 w=81  h=63
    //   line "mm"  x=894 y=2532 w=83  h=48
    // Three separate ML Kit elements on the same printed row. The locator
    // must stitch them positionally — without this, every real device
    // capture's PD field renders "—" on the analysis screen.
    func testReturnsValueWhenLabelValueAndUnitAreSeparateElementsOnSameRow() {
        let lines = [
            OCRLine(text: "PD:", frame: CGRect(x: 579, y: 2518, width: 106, height: 60)),
            OCRLine(text: "59",  frame: CGRect(x: 770, y: 2520, width: 81,  height: 63)),
            OCRLine(text: "mm",  frame: CGRect(x: 894, y: 2532, width: 83,  height: 48)),
        ]
        XCTAssertEqual(PDLocator.locate(in: lines), 59.0)
    }

    // ML Kit sometimes drops the colon entirely on faded thermal paper, so
    // a bare "PD" label must still anchor the lookup.
    func testAcceptsLabelWithoutColonOrEqualsSeparator() {
        let lines = [
            OCRLine(text: "PD", frame: CGRect(x: 579, y: 2518, width: 80, height: 60)),
            OCRLine(text: "62", frame: CGRect(x: 720, y: 2520, width: 80, height: 60)),
        ]
        XCTAssertEqual(PDLocator.locate(in: lines), 62.0)
    }

    // The numeric must live on the same printed row as the label. A "59"
    // floating in a totally different y band must NOT be claimed as PD —
    // axis values like "59" appear constantly in reading rows above the
    // PD line and would otherwise poison the result.
    func testIgnoresNumericInDifferentYBand() {
        let lines = [
            OCRLine(text: "PD:", frame: CGRect(x: 579, y: 2518, width: 106, height: 60)),
            OCRLine(text: "59",  frame: CGRect(x: 770, y: 1200, width: 81,  height: 63)), // axis value, far above
            OCRLine(text: "mm",  frame: CGRect(x: 894, y: 2532, width: 83,  height: 48)),
        ]
        XCTAssertNil(PDLocator.locate(in: lines))
    }

    // Physiological PD bounds: 40-90 mm covers children through extreme
    // adults. Anything outside is OCR garbage (a 4-digit AX value, a year,
    // a serial number) and must not be reported as PD.
    func testRejectsValueOutsidePhysiologicalRange() {
        let lines = [
            OCRLine(text: "PD: 999", frame: CGRect(x: 580, y: 2520, width: 250, height: 60))
        ]
        XCTAssertNil(PDLocator.locate(in: lines))
    }

    func testReturnsNilWhenNoLabelPresent() {
        let lines = [
            OCRLine(text: "AVG", frame: CGRect(x: 100, y: 600, width: 60, height: 50)),
            OCRLine(text: "59",  frame: CGRect(x: 770, y: 2520, width: 81, height: 63)),
        ]
        XCTAssertNil(PDLocator.locate(in: lines))
    }

    // The numeric must be to the RIGHT of the label, not the left. ML Kit
    // sometimes recognizes a stray "59" (e.g. an axis value bleeding from
    // the reading column) at a y close to the PD label but on the wrong
    // side. Pinning direction prevents the locator from picking that up.
    func testIgnoresNumericToTheLeftOfTheLabel() {
        let lines = [
            OCRLine(text: "59",  frame: CGRect(x: 200, y: 2520, width: 80,  height: 60)),
            OCRLine(text: "PD:", frame: CGRect(x: 580, y: 2520, width: 106, height: 60)),
        ]
        XCTAssertNil(PDLocator.locate(in: lines))
    }

    // When multiple plausible numerics live in the same y band to the
    // right of the label (rare but possible — the right margin sometimes
    // carries a separator artifact ML Kit reads as "00"), the closest
    // candidate horizontally wins.
    func testPicksClosestNumericWhenMultipleCandidates() {
        let lines = [
            OCRLine(text: "PD:", frame: CGRect(x: 580, y: 2520, width: 106, height: 60)),
            OCRLine(text: "58",  frame: CGRect(x: 770, y: 2520, width: 80,  height: 60)),
            OCRLine(text: "00",  frame: CGRect(x: 1400, y: 2520, width: 80, height: 60)),
        ]
        XCTAssertEqual(PDLocator.locate(in: lines), 58.0)
    }
}
