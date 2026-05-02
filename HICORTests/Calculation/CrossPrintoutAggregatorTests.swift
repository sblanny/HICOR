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
        // M values clustered within MAD threshold (0.15 D) so no rejection
        // fires — the assertions below test the *aggregation* path, not
        // rejection. The original test data had 0.50 D SPH spread, which was
        // fine under the old fixed-threshold algorithm (1.00 D agreement) but
        // now exceeds 3×MAD when 2 of 3 readings are identical.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),       // M = -2.50
            makeReading(sph: -2.10, cyl: -1.00, ax: 90, photo: 1),       // M = -2.60
            makeReading(sph: -2.50, cyl: 0, ax: 0, photo: 2, sphOnly: true)  // M = -2.50
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

    // MARK: - k=3 MAD scenarios

    func testAggregate_axisOutlierAmidTightCluster_dropsViaJ45MAD() {
        // Day-1 field scenario: 3 printouts × 3 readings each. Eight readings
        // cluster around axis 60°; one reading at axis 120° is an outlier on
        // J45. The old fixed-tolerance algorithm got stuck here because the
        // median pulled toward 78° and sliding-scale tolerance was wide enough
        // to keep the bad reading in.
        let axisData: [(sph: Double, cyl: Double, ax: Int, photo: Int)] = [
            (-2.00, -1.00, 58, 0), (-2.00, -1.00, 64, 0), (-2.00, -1.00, 59, 0),
            (-2.00, -1.00, 65, 1), (-2.00, -1.00, 69, 1), (-2.00, -1.00, 64, 1),
            (-2.00, -1.00, 57, 2), (-2.00, -1.00, 58, 2), (-2.00, -1.00, 120, 2)
        ]
        let readings = axisData.map { makeReading(sph: $0.sph, cyl: $0.cyl, ax: $0.ax, photo: $0.photo) }
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertEqual(result.droppedOutliers.count, 1, "axis-120 outlier should be dropped on J45 MAD")
        XCTAssertEqual(result.droppedOutliers.first?.reading.ax, 120)
        XCTAssertEqual(result.droppedOutliers.first?.photoIndex, 2)
        XCTAssertEqual(result.usedReadings.count, 8)
        // Survivors cluster around 62°; allow ±4° for averaging across the cluster.
        XCTAssertEqual(result.ax, 62, accuracy: 4)
        XCTAssertFalse(result.readingsVaryWidely)
    }

    func testAggregate_sphSignOutlier_droppedByMadOrAnsiFloor() {
        // 12 readings, one is +2.50 amid a -1.25/-1.50/-1.75 cluster. Either
        // M-MAD or the ANSI hard floor should catch it — assertion is
        // path-agnostic.
        let cluster: [(Double, Double, Int)] = [
            (-1.50, -0.50, 90), (-1.75, -0.50, 90), (-1.50, -0.50, 90),
            (-1.75, -0.50, 90), (-1.50, -0.50, 90), (-1.25, -0.50, 90),
            (-1.50, -0.50, 90), (-1.50, -0.50, 90), (-1.75, -0.50, 90),
            (+2.50, -0.50, 90), (-1.25, -0.50, 90), (-1.50, -0.50, 90)
        ]
        let readings = cluster.enumerated().map { (i, t) in
            makeReading(sph: t.0, cyl: t.1, ax: t.2, photo: i / 3)
        }
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertEqual(result.droppedOutliers.count, 1)
        XCTAssertEqual(result.droppedOutliers.first?.reading.sph, +2.50)
        XCTAssertEqual(result.usedReadings.count, 11)
        XCTAssertFalse(result.readingsVaryWidely)
    }

    func testAggregate_nearPlanoWithBadAxisReading_dropsOutlier_doesNotBlockTier0Path() {
        // Left eye near-plano cluster (cyl ~0); one reading has a bad axis.
        // Power-vector J0/J45 magnitudes are tiny but the bad axis still
        // produces a measurable deviation against the cluster's near-zero
        // J0/J45 — confirming Tier 0 path is no longer blocked by single bad
        // axis on a near-plano eye.
        let readings: [RawReading] = [
            makeReading(sph: 0.25, cyl: 0,      ax: 0,   photo: 0, eye: .left, sphOnly: true),
            makeReading(sph: 0.25, cyl: 0,      ax: 0,   photo: 1, eye: .left, sphOnly: true),
            makeReading(sph: 0.25, cyl: 0,      ax: 0,   photo: 2, eye: .left, sphOnly: true),
            makeReading(sph: 0.25, cyl: -0.25,  ax: 10,  photo: 3, eye: .left),
            makeReading(sph: 0.25, cyl: -0.25,  ax: 12,  photo: 4, eye: .left),
            makeReading(sph: 0.25, cyl: -0.25,  ax: 87,  photo: 5, eye: .left)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .left)

        XCTAssertEqual(result.droppedOutliers.count, 1)
        XCTAssertEqual(result.droppedOutliers.first?.photoIndex, 5)
        XCTAssertFalse(result.readingsVaryWidely)
        // After dropping the bad axis, mean M = 0.20 (3 sphOnly @ 0.25 + 2 cyl
        // @ 0.125), and the surviving cyl readings reconstruct to cyl ≈ -0.25,
        // so sph = M - cyl/2 ≈ 0.325. Still near-plano — the tier-0 path is
        // reachable after rounding (sph rounds to 0.25, cyl to -0.25).
        XCTAssertEqual(result.sph, 0.30, accuracy: 0.10)
    }

    func testAggregate_naturallyVariedReadings_dropsNothing() {
        // Genuine spread, not outlier-driven. Algorithm must not over-reject.
        let readings = [
            makeReading(sph: -2.00, cyl: -0.75, ax: 80,  photo: 0),
            makeReading(sph: -2.50, cyl: -1.25, ax: 95,  photo: 1),
            makeReading(sph: -1.75, cyl: -1.00, ax: 85,  photo: 2),
            makeReading(sph: -2.25, cyl: -1.50, ax: 90,  photo: 3)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertTrue(result.droppedOutliers.isEmpty, "natural variation must not trigger rejection")
        XCTAssertEqual(result.usedReadings.count, 4)
        XCTAssertFalse(result.readingsVaryWidely)
    }

    func testAggregate_tightClusterWithObviousOutlier_madFloorPreventsZeroTolerance() {
        // 4 readings identical at -2.00, plus one at -3.50.
        // Without MAD floor: median deviation = 0 → threshold = 0 → would
        // reject any noise. With MAD floor (0.05): threshold = 0.15 → only
        // -3.50 (deviates 1.50) is dropped.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 2),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 3),
            makeReading(sph: -3.50, cyl: -1.00, ax: 90, photo: 4)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertEqual(result.droppedOutliers.count, 1)
        XCTAssertEqual(result.droppedOutliers.first?.reading.sph, -3.50)
        XCTAssertEqual(result.usedReadings.count, 4)
        XCTAssertFalse(result.readingsVaryWidely)
    }

    func testAggregate_rejectionWouldLeaveTooFew_retainsAllAndFlagsWideVariance() {
        // 4 readings, 3 wildly different. ANSI floor would drop +5.00 and
        // -8.00, leaving 2 survivors — below minSurvivors (3). Algorithm
        // should retain all 4 and set readingsVaryWidely=true.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: +5.00, cyl: -1.00, ax: 90, photo: 2),
            makeReading(sph: -8.00, cyl: -1.00, ax: 90, photo: 3)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertTrue(result.droppedOutliers.isEmpty, "sample-size floor blocks rejection")
        XCTAssertEqual(result.usedReadings.count, 4)
        XCTAssertTrue(result.readingsVaryWidely, "wide variance must be flagged for operator")
    }

    func testAggregate_ansiHardFloorCatchesOutlierWhenMadIsLarge() {
        // High natural variance inflates MAD; the ANSI hard floor independently
        // catches the +0.50 reading that deviates >1.00 D from median M.
        let readings = [
            makeReading(sph: -1.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 1),
            makeReading(sph: -3.00, cyl: -1.00, ax: 90, photo: 2),
            makeReading(sph: -1.00, cyl: -1.00, ax: 90, photo: 3),
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 4),
            makeReading(sph: +0.50, cyl: -1.00, ax: 90, photo: 5)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertTrue(
            result.droppedOutliers.contains { $0.reading.sph == +0.50 },
            "rejection must fire on the +0.50 outlier (via M-MAD or ANSI floor)"
        )
        XCTAssertFalse(result.readingsVaryWidely)
    }

    // MARK: - Count < 3: skip rejection, average passthrough

    func testAggregate_twoReadingsDisagree_averagesThemNoRejection() {
        // Two readings 1.50 D apart. Without the count-<3 guard, ANSI floor
        // would drop both, leaving zero survivors and producing NaN. Now we
        // skip rejection entirely and just average — ConsistencyValidator
        // owns the decision of whether 2-printout disagreement was acceptable.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -0.50, cyl: -1.00, ax: 90, photo: 1)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertTrue(result.droppedOutliers.isEmpty, "no rejection at count < 3")
        XCTAssertEqual(result.usedReadings.count, 2)
        XCTAssertFalse(result.readingsVaryWidely, "wide-variance flag is for the >=3 path")
        XCTAssertEqual(result.sph, -1.25, accuracy: 0.05, "average of -2.00 and -0.50")
        XCTAssertFalse(result.sph.isNaN)
        XCTAssertFalse(result.cyl.isNaN)
    }

    func testAggregate_twoReadingsAgree_averagesThemCleanly() {
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 90, photo: 0),
            makeReading(sph: -2.25, cyl: -1.00, ax: 90, photo: 1)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertTrue(result.droppedOutliers.isEmpty)
        XCTAssertEqual(result.usedReadings.count, 2)
        XCTAssertEqual(result.sph, -2.125, accuracy: 0.05)
    }

    func testAggregate_threeReadings_axisOutlier_stillDropsViaJ45MAD() {
        // Regression: rejection still runs at count >= 3.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 60, photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 65, photo: 1),
            makeReading(sph: -2.00, cyl: -1.00, ax: 120, photo: 2)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertEqual(result.droppedOutliers.count, 1, "rejection still runs at count >= 3")
        XCTAssertEqual(result.droppedOutliers.first?.reading.ax, 120)
    }

    func testAggregate_resultNeverContainsNaN_acrossSmallNScenarios() {
        let scenarios: [[(Double, Double, Int)]] = [
            [(-2.00, -1.00, 90), (+1.00, -1.00, 90)],   // 2-reading wide spread (would be NaN before fix)
            [(0.00, 0.00, 0), (0.00, 0.00, 0)],          // 2-reading identical plano
            [(-5.00, -1.00, 90)]                         // 1-reading
        ]
        for scenario in scenarios {
            let readings = scenario.enumerated().map { (i, t) in
                makeReading(sph: t.0, cyl: t.1, ax: t.2, photo: i)
            }
            let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)
            XCTAssertFalse(result.sph.isNaN, "sph NaN for scenario: \(scenario)")
            XCTAssertFalse(result.cyl.isNaN, "cyl NaN for scenario: \(scenario)")
        }
    }

    func testAggregate_axisWrapAroundZero180_noFalseRejection() {
        // Readings on either side of the 0/180 boundary represent the same
        // axis clinically. Power-vector J0/J45 makes them numerically close,
        // so MAD must not trigger.
        let readings = [
            makeReading(sph: -2.00, cyl: -1.00, ax: 5,   photo: 0),
            makeReading(sph: -2.00, cyl: -1.00, ax: 175, photo: 1),
            makeReading(sph: -2.00, cyl: -1.00, ax: 178, photo: 2)
        ]
        let result = CrossPrintoutAggregator.aggregate(readings: readings, for: .right)

        XCTAssertTrue(result.droppedOutliers.isEmpty, "axis wrap must not trigger rejection")
        let distFrom0Or180 = min(abs(result.ax - 180), abs(result.ax))
        XCTAssertLessThanOrEqual(distFrom0Or180, 5)
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
