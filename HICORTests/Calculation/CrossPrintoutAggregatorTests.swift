import XCTest
@testable import HICOR

final class CrossPrintoutAggregatorTests: XCTestCase {

    // MARK: - Happy paths

    func testAggregate_twoReadingsWithinHalfDiopter_producesClosestFinal_noOutliers() {
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.25, cyl: -1.00, ax: 92, photo: 1)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertTrue(result.droppedOutliers.isEmpty, "within-threshold readings should not be dropped")
        XCTAssertEqual(result.usedReadings.count, 2)
        XCTAssertEqual(result.sph, -2.125, accuracy: 0.01)
        XCTAssertEqual(result.cyl, -1.00, accuracy: 0.01)
        XCTAssertEqual(result.ax, 91, accuracy: 1)
    }

    func testAggregate_singleReading_returnsItAsFinal() {
        let r = makeReading(sph: -3.50, cyl: -1.25, ax: 180, photo: 0)
        let result = CrossPrintoutAggregator.aggregate(readings: [r], for: .right)
        XCTAssertTrue(result.droppedOutliers.isEmpty)
        XCTAssertEqual(result.usedReadings.count, 1)
        XCTAssertEqual(result.sph, -3.50, accuracy: 0.01)
        XCTAssertEqual(result.cyl, -1.25, accuracy: 0.01)
        XCTAssertEqual(result.ax, 180)
    }

    // MARK: - Outlier drops

    func testAggregate_threeReadings_oneFarOutlier_dropsOutlier() {
        // Mike's example: -2.00, -2.25, -4.50 → -4.50 is the outlier.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.25, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: -4.50, cyl: -1.00, ax: 90, photo: 2)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertEqual(result.droppedOutliers.count, 1)
        XCTAssertEqual(result.droppedOutliers.first?.reading.sph, -4.50)
        XCTAssertEqual(result.usedReadings.count, 2)
        // Final SPH should be near -2.125, NOT pulled toward -4.50.
        XCTAssertEqual(result.sph, -2.125, accuracy: 0.1)
    }

    func testAggregate_threeReadings_cylDifferenceExceedsThreshold_dropsOutlier() {
        // CYL agreement threshold is 0.50 D.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: -2.00, cyl: -2.25, ax: 90, photo: 2)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertEqual(result.droppedOutliers.count, 1)
        XCTAssertEqual(result.droppedOutliers.first?.reading.cyl, -2.25)
    }

    // MARK: - Axis circularity

    func testAggregate_axesStraddling179And1_reconstructsNear180_notNear90() {
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 179, photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 1, photo: 1)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        // Axis should land near 180° (or equivalently 0°), not 90°.
        let distFrom180 = min(abs(result.ax - 180), abs(result.ax - 0))
        XCTAssertLessThanOrEqual(distFrom180, 3, "axis circularity broken: got \(result.ax)")
        XCTAssertGreaterThan(abs(result.ax - 90), 85)
    }

    // MARK: - Axis sliding-scale tolerance

    func testAggregate_highCyl_tightAxisTolerance_dropsModerateAxisOutlier() {
        // CYL = -1.50 falls into the 10° tolerance bucket (1.00–2.00 D).
        // An axis differing by 15° from the median should be dropped.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.50, ax: 90, photo: 0),
            makeReading(sph: -2.00, cyl: -1.50, ax: 92, photo: 1),
            makeReading(sph: -2.00, cyl: -1.50, ax: 110, photo: 2)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertEqual(result.droppedOutliers.count, 1)
        XCTAssertEqual(result.droppedOutliers.first?.reading.ax, 110)
    }

    func testAggregate_lowCyl_wideAxisTolerance_keepsSameSpread() {
        // CYL = -0.25 falls into the 30° tolerance bucket.
        // A 20° axis difference should be tolerated, not dropped.
        let readings = [
            makeReading(sph: -2.00, cyl: -0.25, ax: 90, photo: 0),
            makeReading(sph: -2.00, cyl: -0.25, ax: 110, photo: 1)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertTrue(result.droppedOutliers.isEmpty, "20° spread at low CYL is within 30° tolerance")
    }

    // MARK: - isSphOnly handling (CLAUDE.md rule)

    func testAggregate_allSphOnlyReadings_returnsSphMean_withZeroCylAndAxis180() {
        let readings = [
            makeReading(sph: -2.00, cyl: 0, ax: 0, photo: 0, sphOnly: true),
            makeReading(sph: -2.25, cyl: 0, ax: 0, photo: 1, sphOnly: true),
            makeReading(sph: -2.50, cyl: 0, ax: 0, photo: 2, sphOnly: true)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertEqual(result.sph, -2.25, accuracy: 0.01)
        XCTAssertEqual(result.cyl, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.ax, 180, "convention: no-cyl reconstruct yields 180°")
        XCTAssertTrue(result.droppedOutliers.isEmpty)
    }

    func testAggregate_mixedSphOnlyAndFull_sphOnlyContributesOnlyToSph() {
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.25, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: -2.50, cyl: 0, ax: 0, photo: 2, sphOnly: true)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        // sphOnly contributes to M (and therefore to reconstructed SPH) but
        // NOT to J0/J45. CYL should remain ~-1.00 (from the two full readings).
        XCTAssertEqual(result.cyl, -1.00, accuracy: 0.01)
        XCTAssertEqual(result.ax, 90, accuracy: 1)
        XCTAssertEqual(result.usedReadings.count, 3)
    }

    // MARK: - Eye filter

    func testAggregate_mixedEyes_onlyConsidersSelectedEye() {
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0, eye: .right),
            makeReading(sph: +1.00, cyl: -0.50, ax: 180, photo: 0, eye: .left)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        XCTAssertEqual(result.usedReadings.count, 1)
        XCTAssertEqual(result.usedReadings.first?.eye, .right)
        XCTAssertEqual(result.sph, -2.00, accuracy: 0.01)
    }

    // MARK: - Drop metadata

    func testAggregate_droppedReading_carriesPhotoIndexAndReason() {
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.25, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: -5.00, cyl: -1.00, ax: 90, photo: 2)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
        let dropped = result.droppedOutliers.first
        XCTAssertEqual(dropped?.photoIndex, 2)
        XCTAssertEqual(dropped?.eye, .right)
        XCTAssertFalse(dropped?.reason.isEmpty ?? true, "drop reason must be populated for operator display")
    }
}

// MARK: - Helpers

private func makeReading(
    sph: Double,
    cyl: Double,
    ax: Int,
    photo: Int,
    eye: Eye = .right,
    sphOnly: Bool = false
) -> RawReading {
    RawReading(
        id: UUID(),
        sph: sph,
        cyl: cyl,
        ax: ax,
        eye: eye,
        sourcePhotoIndex: photo,
        lowConfidence: false,
        isSphOnly: sphOnly
    )
}
