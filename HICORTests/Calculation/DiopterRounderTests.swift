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

    // MARK: - CYL rounding (0.50 D step, SPH-driven tie direction per §6)
    // Rule (Mike, April 26): nearest 0.50 D; on a tie (e.g. -1.75 between -1.50 and -2.00),
    // use the eye's own |SPH| — < 3.00 D rounds weaker, ≥ 3.00 D rounds stronger.

    func testCylRoundsToNearestHalfStep_clearWeaker() {
        // -1.30 is closer to -1.50 than to -1.00? No — |-1.30| = 1.30, lower step 1.00,
        // upper step 1.50. Dist to lower 0.30, to upper 0.20 → upper (-1.50).
        XCTAssertEqual(DiopterRounder.roundCyl(-1.30, eyeSphMagnitude: 2.00), -1.50, accuracy: 1e-9)
    }

    func testCylRoundsToNearestHalfStep_clearStronger() {
        XCTAssertEqual(DiopterRounder.roundCyl(-1.85, eyeSphMagnitude: 2.00), -2.00, accuracy: 1e-9)
    }

    func testCylTieRoundsWeakerWhenSphLow() {
        // -1.75 ties between -1.50 and -2.00. |SPH| 2.50 < 3.00 → weaker.
        XCTAssertEqual(DiopterRounder.roundCyl(-1.75, eyeSphMagnitude: 2.50), -1.50, accuracy: 1e-9)
    }

    func testCylTieRoundsStrongerWhenSphHigh() {
        // -1.75 ties. |SPH| 3.00 is the boundary (≥) → stronger.
        XCTAssertEqual(DiopterRounder.roundCyl(-1.75, eyeSphMagnitude: 3.00), -2.00, accuracy: 1e-9)
    }

    func testCylTieRoundsStrongerWhenSphVeryHigh() {
        // -2.25 ties between -2.00 and -2.50. |SPH| 5.00 ≥ 3.00 → stronger.
        XCTAssertEqual(DiopterRounder.roundCyl(-2.25, eyeSphMagnitude: 5.00), -2.50, accuracy: 1e-9)
    }

    func testCylTieRoundsWeakerWhenSphVeryLow() {
        // -1.25 ties between -1.00 and -1.50. |SPH| 0.50 < 3.00 → weaker.
        XCTAssertEqual(DiopterRounder.roundCyl(-1.25, eyeSphMagnitude: 0.50), -1.00, accuracy: 1e-9)
    }

    func testCylAlreadyOnStep_unchanged_lowSph() {
        XCTAssertEqual(DiopterRounder.roundCyl(-1.50, eyeSphMagnitude: 2.00), -1.50, accuracy: 1e-9)
    }

    func testCylAlreadyOnStep_unchanged_highSph() {
        XCTAssertEqual(DiopterRounder.roundCyl(-2.00, eyeSphMagnitude: 5.00), -2.00, accuracy: 1e-9)
    }

    func testPlanoStaysPlano() {
        XCTAssertEqual(DiopterRounder.roundCyl(0.00, eyeSphMagnitude: 5.00), 0.00, accuracy: 1e-9)
    }

    func testCylBoundaryAt300Sph() {
        // |SPH| 3.00 uses ≥ comparison, so it falls into the stronger branch.
        XCTAssertEqual(DiopterRounder.roundCyl(-1.75, eyeSphMagnitude: 3.00), -2.00, accuracy: 1e-9)
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
