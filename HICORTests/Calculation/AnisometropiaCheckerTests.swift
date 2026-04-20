import XCTest
@testable import HICOR

final class AnisometropiaCheckerTests: XCTestCase {

    // MARK: - Same-sign cases (§8 first block)

    func testSameSign_smallDifference_returnsNormal() {
        let d = AnisometropiaChecker.check(rightSph: -3.00, leftSph: -2.00)
        XCTAssertEqual(d, .normal)
    }

    func testSameSign_differenceAtTwoDiopters_returnsNormal_inclusive() {
        // §8: |R−L| ≤ 2.00 dispenses normally. Exactly 2.00 is in the "normal" bucket.
        let d = AnisometropiaChecker.check(rightSph: -4.00, leftSph: -2.00)
        XCTAssertEqual(d, .normal)
    }

    func testSameSign_differenceJustOverTwo_returnsAdvisory() {
        let d = AnisometropiaChecker.check(rightSph: -4.00, leftSph: -1.75)
        XCTAssertEqual(d, .sameSignAdvisory(diff: 2.25))
    }

    func testSameSign_differenceAtThreeDiopters_returnsAdvisory_inclusive() {
        // §8: > 3.00 triggers refer-out. Exactly 3.00 is still advisory.
        let d = AnisometropiaChecker.check(rightSph: -4.50, leftSph: -1.50)
        XCTAssertEqual(d, .sameSignAdvisory(diff: 3.00))
    }

    func testSameSign_differenceOverThree_returnsReferOut() {
        let d = AnisometropiaChecker.check(rightSph: -5.00, leftSph: -1.00)
        XCTAssertEqual(d, .sameSignReferOut(diff: 4.00))
    }

    func testSameSign_positiveValues_sameRulesApply() {
        let d1 = AnisometropiaChecker.check(rightSph: 4.50, leftSph: 1.50)
        XCTAssertEqual(d1, .sameSignAdvisory(diff: 3.00))
        let d2 = AnisometropiaChecker.check(rightSph: 5.00, leftSph: 1.00)
        XCTAssertEqual(d2, .sameSignReferOut(diff: 4.00))
    }

    // MARK: - Zero handling (plano counts as same-sign with either)

    func testZeroAndNegative_treatedAsSameSign_noAntimetropia() {
        let d = AnisometropiaChecker.check(rightSph: 0.0, leftSph: -2.00)
        XCTAssertEqual(d, .normal)
    }

    func testBothZero_returnsNormal() {
        let d = AnisometropiaChecker.check(rightSph: 0.0, leftSph: 0.0)
        XCTAssertEqual(d, .normal)
    }

    // MARK: - Antimetropia (mixed-sign, §8 second block)

    func testAntimetropia_bothWithinOneFifty_dispense() {
        // R=+1.00, L=-1.00 → dispense (§8 fixture)
        let d = AnisometropiaChecker.check(rightSph: 1.00, leftSph: -1.00)
        // Lowest-abs tie → deterministic pick: right eye
        XCTAssertEqual(d, .antimetropiaDispense(lowestAbsEye: .right))
    }

    func testAntimetropia_lowestAbsIsLeftEye() {
        let d = AnisometropiaChecker.check(rightSph: 1.25, leftSph: -0.50)
        XCTAssertEqual(d, .antimetropiaDispense(lowestAbsEye: .left))
    }

    func testAntimetropia_atOneFiftyBoundary_dispense_inclusive() {
        // §8: "Both eyes within −1.50 to +1.50 D" — edge is inclusive.
        let d = AnisometropiaChecker.check(rightSph: 1.50, leftSph: -1.50)
        XCTAssertEqual(d, .antimetropiaDispense(lowestAbsEye: .right))
    }

    func testAntimetropia_oneEyeBeyondOneFifty_referOut() {
        // §8 fixture: R=+2.00, L=-1.00 → refer out.
        let d = AnisometropiaChecker.check(rightSph: 2.00, leftSph: -1.00)
        XCTAssertEqual(d, .antimetropiaReferOut)
    }

    func testAntimetropia_reversedSigns_referOut() {
        let d = AnisometropiaChecker.check(rightSph: -1.00, leftSph: 2.00)
        XCTAssertEqual(d, .antimetropiaReferOut)
    }

    func testAntimetropia_bothEyesOutside_referOut() {
        let d = AnisometropiaChecker.check(rightSph: 2.50, leftSph: -2.00)
        XCTAssertEqual(d, .antimetropiaReferOut)
    }
}
