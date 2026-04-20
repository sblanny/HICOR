import XCTest
@testable import HICOR

final class PDAggregatorTests: XCTestCase {

    // MARK: - Empty / single input

    func testAggregate_noPDs_returnsNilPD_noManualFlag() {
        let a = PDAggregator.aggregate(pds: [])
        XCTAssertNil(a.pd)
        XCTAssertEqual(a.sourceCount, 0)
        XCTAssertEqual(a.spreadMm, 0.0, accuracy: 1e-9)
        XCTAssertFalse(a.requiresManualMeasurement)
    }

    func testAggregate_singlePD_returnsThatValue() {
        let a = PDAggregator.aggregate(pds: [62.0])
        XCTAssertEqual(a.pd, 62.0)
        XCTAssertEqual(a.sourceCount, 1)
        XCTAssertEqual(a.spreadMm, 0.0, accuracy: 1e-9)
        XCTAssertFalse(a.requiresManualMeasurement)
    }

    // MARK: - Multiple PDs — mean + spread

    func testAggregate_multiplePDs_returnsMean() {
        let a = PDAggregator.aggregate(pds: [60.0, 62.0, 64.0])
        XCTAssertEqual(a.pd ?? 0, 62.0, accuracy: 1e-9)
        XCTAssertEqual(a.sourceCount, 3)
        XCTAssertEqual(a.spreadMm, 4.0, accuracy: 1e-9)
        XCTAssertFalse(a.requiresManualMeasurement)
    }

    func testAggregate_identicalPDs_spreadZero() {
        let a = PDAggregator.aggregate(pds: [62.0, 62.0, 62.0])
        XCTAssertEqual(a.pd ?? 0, 62.0, accuracy: 1e-9)
        XCTAssertEqual(a.spreadMm, 0.0, accuracy: 1e-9)
        XCTAssertFalse(a.requiresManualMeasurement)
    }

    // MARK: - Manual-measurement gate (§9 rule 4: spread > 5 mm)

    func testAggregate_spreadExactlyFive_doesNotFlag_dueTo_strictGreaterThan() {
        // §9: spread > 5 mm triggers the manual flag. Exactly 5.00 is not yet
        // flagged — matches Mike's "varies significantly" phrasing.
        let a = PDAggregator.aggregate(pds: [58.0, 63.0])
        XCTAssertEqual(a.spreadMm, 5.0, accuracy: 1e-9)
        XCTAssertFalse(a.requiresManualMeasurement)
    }

    func testAggregate_spreadJustOverFive_flagsManualMeasurement() {
        let a = PDAggregator.aggregate(pds: [58.0, 63.5])
        XCTAssertEqual(a.spreadMm, 5.5, accuracy: 1e-9)
        XCTAssertTrue(a.requiresManualMeasurement)
    }

    func testAggregate_largeSpread_stillReturnsMean_butFlagsManual() {
        // Mean is still computed for display; the flag tells the UI to warn.
        let a = PDAggregator.aggregate(pds: [55.0, 70.0])
        XCTAssertEqual(a.pd ?? 0, 62.5, accuracy: 1e-9)
        XCTAssertEqual(a.spreadMm, 15.0, accuracy: 1e-9)
        XCTAssertTrue(a.requiresManualMeasurement)
    }
}
