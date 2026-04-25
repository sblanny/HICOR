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
}
