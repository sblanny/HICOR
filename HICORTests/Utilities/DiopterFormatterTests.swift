import XCTest
@testable import HICOR

final class DiopterFormatterTests: XCTestCase {

    func testFormatsPositiveZeroAsLeadingSpacePlano() {
        XCTAssertEqual(DiopterFormatter.format(0.0), " 0.00")
    }

    func testFormatsNegativeZeroAsLeadingSpacePlano() {
        // The case that started this. `String(format: "%.2f", -0.0)` returns
        // "-0.00", and a `value >= 0 ? "+" : ""` prefix on top yields the
        // mangled "+-0.00" the user saw on screen. The formatter must
        // collapse -0.0 to plano " 0.00" with no sign.
        let negativeZero = Double(sign: .minus, exponent: 0, significand: 0)
        XCTAssertTrue(negativeZero.sign == .minus, "test setup: expected IEEE-754 -0.0")
        XCTAssertEqual(DiopterFormatter.format(negativeZero), " 0.00")
    }

    func testFormatsPositiveSphericalWithPlusPrefix() {
        XCTAssertEqual(DiopterFormatter.format(1.50), "+1.50")
        XCTAssertEqual(DiopterFormatter.format(0.25), "+0.25")
    }

    func testFormatsNegativeWithMinusPrefix() {
        XCTAssertEqual(DiopterFormatter.format(-1.50), "-1.50")
        XCTAssertEqual(DiopterFormatter.format(-0.25), "-0.25")
    }

    func testTwoDecimalPrecisionPreservedForLargeValues() {
        XCTAssertEqual(DiopterFormatter.format(12.25), "+12.25")
        XCTAssertEqual(DiopterFormatter.format(-12.25), "-12.25")
    }

    // MARK: - Axis formatting (column-aligned display)

    func testFormatAxisPadsThreeDigitsWithLeadingSpaces() {
        XCTAssertEqual(DiopterFormatter.formatAxis(1),    "  1°")
        XCTAssertEqual(DiopterFormatter.formatAxis(9),    "  9°")
        XCTAssertEqual(DiopterFormatter.formatAxis(99),   " 99°")
        XCTAssertEqual(DiopterFormatter.formatAxis(108),  "108°")
        XCTAssertEqual(DiopterFormatter.formatAxis(180),  "180°")
    }

    // MARK: - CYL display with Tier 2 dispense annotation
    //
    // MIKE_RX_PROCEDURE.md §7 Tier 2 stretch fit (CYL between -2.00 and -3.00):
    // Highlands inventory caps CYL at -2.00. Volunteer must see both the
    // calculated value (clinical truth) AND the dispense value (-2.00) so the
    // FileMaker entry uses the inventory cap, not the calculated.

    func testCylDisplay_tier1_noAnnotation() {
        XCTAssertEqual(DiopterFormatter.cylDisplayString(calculated: -1.50), "-1.50")
    }

    func testCylDisplay_atTier2LowerBoundary_noAnnotation() {
        // -2.00 exactly is the cap itself — calculated == dispense, no annotation.
        XCTAssertEqual(DiopterFormatter.cylDisplayString(calculated: -2.00), "-2.00")
    }

    func testCylDisplay_tier2_midRange_annotated() {
        XCTAssertEqual(
            DiopterFormatter.cylDisplayString(calculated: -2.50),
            "-2.50 (dispense -2.00)"
        )
    }

    func testCylDisplay_tier2_quarterStep_annotated() {
        XCTAssertEqual(
            DiopterFormatter.cylDisplayString(calculated: -2.75),
            "-2.75 (dispense -2.00)"
        )
    }

    func testCylDisplay_tier2_atUpperBoundary_annotated() {
        // -3.00 is still Tier 2 (boundary inclusive per Constants.cylTier2Max).
        XCTAssertEqual(
            DiopterFormatter.cylDisplayString(calculated: -3.00),
            "-3.00 (dispense -2.00)"
        )
    }

    func testCylDisplay_tier3_noAutoCapAnnotation() {
        // > -3.00 is Tier 3; clinical decision is operator's, not auto-cappable.
        XCTAssertEqual(DiopterFormatter.cylDisplayString(calculated: -3.25), "-3.25")
    }

    func testCylDisplay_plano_noAnnotation() {
        // Tier 0/1 zero CYL must render as the existing " 0.00" plano form.
        XCTAssertEqual(DiopterFormatter.cylDisplayString(calculated: 0.0), " 0.00")
    }
}
