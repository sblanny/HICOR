import XCTest
@testable import HICOR

final class DiopterRounderTests: XCTestCase {

    // MARK: - SPH rounding (CYL-dependent per §6)
    // Rule: |CYL| > 1.00 → round to stronger (more magnitude).
    //       |CYL| ≤ 1.00 → round to weaker (less magnitude).

    func testRoundSph_negative_lowCyl_roundsWeaker() {
        // Fixture from §6: -2.37 with CYL -0.50 → -2.25 (weaker)
        XCTAssertEqual(DiopterRounder.roundSph(-2.37, forCyl: -0.50), -2.25, accuracy: 1e-9)
    }

    func testRoundSph_negative_highCyl_roundsStronger() {
        // Fixture from §6: -2.37 with CYL -1.50 → -2.50 (stronger)
        XCTAssertEqual(DiopterRounder.roundSph(-2.37, forCyl: -1.50), -2.50, accuracy: 1e-9)
    }

    func testRoundSph_positive_lowCyl_roundsWeaker() {
        // Fixture from §6: +2.37 with CYL -0.50 → +2.25
        XCTAssertEqual(DiopterRounder.roundSph(2.37, forCyl: -0.50), 2.25, accuracy: 1e-9)
    }

    func testRoundSph_positive_highCyl_roundsStronger() {
        // Fixture from §6: +2.37 with CYL -1.50 → +2.50
        XCTAssertEqual(DiopterRounder.roundSph(2.37, forCyl: -1.50), 2.50, accuracy: 1e-9)
    }

    func testRoundSph_cylExactlyAtBreakpoint_roundsWeaker_dueTo_strictGreaterThan() {
        // |CYL| = 1.00 is the boundary. §6 says "> 1.00" triggers stronger,
        // so exactly 1.00 still rounds weaker.
        XCTAssertEqual(DiopterRounder.roundSph(-2.37, forCyl: -1.00), -2.25, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(2.37, forCyl: -1.00), 2.25, accuracy: 1e-9)
    }

    func testRoundSph_alreadyOnQuarterStep_returnsUnchanged_bothDirections() {
        XCTAssertEqual(DiopterRounder.roundSph(-2.25, forCyl: -0.50), -2.25, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(-2.25, forCyl: -1.50), -2.25, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(2.50, forCyl: -0.50), 2.50, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(2.50, forCyl: -1.50), 2.50, accuracy: 1e-9)
    }

    func testRoundSph_zero_returnsZero_regardlessOfCyl() {
        XCTAssertEqual(DiopterRounder.roundSph(0.0, forCyl: -0.25), 0.0, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(0.0, forCyl: -1.75), 0.0, accuracy: 1e-9)
    }

    func testRoundSph_exactlyHalfwayBetweenSteps_weakerVsStronger() {
        // -2.125 is exactly between -2.00 and -2.25.
        // Weaker (toward zero) → -2.00. Stronger (away) → -2.25.
        XCTAssertEqual(DiopterRounder.roundSph(-2.125, forCyl: -0.50), -2.00, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(-2.125, forCyl: -1.50), -2.25, accuracy: 1e-9)
    }

    func testRoundSph_positiveCylSign_stillUsesMagnitudeForBreakpoint() {
        // CYL sign shouldn't matter; only |CYL| is compared to breakpoint.
        // (Clinical convention uses negative CYL, but the rule is magnitude-based.)
        XCTAssertEqual(DiopterRounder.roundSph(-2.37, forCyl: 1.50), -2.50, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundSph(-2.37, forCyl: 0.50), -2.25, accuracy: 1e-9)
    }

    // MARK: - CYL rounding (nearest 0.25)

    func testRoundCyl_nearestQuarterStep() {
        XCTAssertEqual(DiopterRounder.roundCyl(-1.37), -1.25, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundCyl(-1.38), -1.50, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundCyl(-0.12), 0.0, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundCyl(-0.13), -0.25, accuracy: 1e-9)
    }

    func testRoundCyl_alreadyOnQuarterStep_returnsUnchanged() {
        XCTAssertEqual(DiopterRounder.roundCyl(-1.25), -1.25, accuracy: 1e-9)
        XCTAssertEqual(DiopterRounder.roundCyl(0.0), 0.0, accuracy: 1e-9)
    }

    // MARK: - AX rounding (nearest integer, 1-180 clamp)

    func testRoundAx_nearestInteger() {
        XCTAssertEqual(DiopterRounder.roundAx(89.4), 89)
        XCTAssertEqual(DiopterRounder.roundAx(89.6), 90)
        XCTAssertEqual(DiopterRounder.roundAx(180.0), 180)
    }

    func testRoundAx_clampsBelowOne_toOne() {
        XCTAssertEqual(DiopterRounder.roundAx(0.0), 1)
        XCTAssertEqual(DiopterRounder.roundAx(-5.0), 1)
    }

    func testRoundAx_clampsAboveOneEighty_toOneEighty() {
        XCTAssertEqual(DiopterRounder.roundAx(181.0), 180)
        XCTAssertEqual(DiopterRounder.roundAx(359.7), 180)
    }
}
