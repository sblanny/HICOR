import XCTest
@testable import HICOR

final class TierAssignerTests: XCTestCase {

    // MARK: - Per-eye classification (MIKE_RX_PROCEDURE.md §7)

    func testPerEye_plano_returnsTier0() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: 0.0, cyl: 0.0), .tier0NoGlassesNeeded)
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: 0.25, cyl: -0.50), .tier0NoGlassesNeeded)
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -0.25, cyl: -0.50), .tier0NoGlassesNeeded)
    }

    func testPerEye_justOutsideTier0SphBand_returnsTier1() {
        // |SPH| = 0.50 > 0.25 breakpoint → leaves Tier 0, lands in Tier 1.
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -0.50, cyl: -0.25), .tier1Normal)
    }

    func testPerEye_justOutsideTier0CylBand_returnsTier1() {
        // |CYL| = 0.75 > 0.50 breakpoint → leaves Tier 0.
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -0.25, cyl: -0.75), .tier1Normal)
    }

    func testPerEye_normalRange_returnsTier1() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -3.00, cyl: -1.00), .tier1Normal)
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: 4.50, cyl: -1.50), .tier1Normal)
    }

    func testPerEye_sphAtTier1UpperBound_returnsTier1() {
        // |SPH| = 6.00 is inclusive in Tier 1 per §7 ("within ±6.00 D").
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -6.00, cyl: -1.00), .tier1Normal)
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: 6.00, cyl: -1.00), .tier1Normal)
    }

    func testPerEye_sphJustBeyondSix_returnsTier2() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -6.25, cyl: -1.00), .tier2StretchWithNotification)
    }

    func testPerEye_cylAtTier1UpperBound_returnsTier1() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -3.00, cyl: -2.00), .tier1Normal)
    }

    func testPerEye_cylJustBeyondTwo_returnsTier2() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -3.00, cyl: -2.25), .tier2StretchWithNotification)
    }

    func testPerEye_sphAtTier2UpperBound_returnsTier2() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -8.00, cyl: -1.00), .tier2StretchWithNotification)
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: 8.00, cyl: -1.00), .tier2StretchWithNotification)
    }

    func testPerEye_sphJustBeyondEight_returnsTier3() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -8.25, cyl: -1.00), .tier3DoNotDispense)
    }

    func testPerEye_cylBeyondThree_returnsTier3() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -3.00, cyl: -3.25), .tier3DoNotDispense)
    }

    func testPerEye_sphAtTier3UpperBound_returnsTier3() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -12.00, cyl: -1.00), .tier3DoNotDispense)
    }

    func testPerEye_sphBeyondTwelve_returnsTier4() {
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: -12.25, cyl: -1.00), .tier4MedicalConcern)
        XCTAssertEqual(TierAssigner.assignPerEyeTier(sph: 13.50, cyl: -1.00), .tier4MedicalConcern)
    }

    // MARK: - Overall tier combination

    func testOverall_bothTier0_returnsTier0() {
        let overall = TierAssigner.assignOverallTier(
            right: .tier0NoGlassesNeeded,
            left: .tier0NoGlassesNeeded
        )
        XCTAssertEqual(overall, .tier0NoGlassesNeeded)
    }

    func testOverall_asymmetricTier0_returnsOtherEyeTier_notTier0() {
        // §7: Tier 0 only triggers when BOTH eyes qualify.
        let overall = TierAssigner.assignOverallTier(
            right: .tier0NoGlassesNeeded,
            left: .tier1Normal
        )
        XCTAssertEqual(overall, .tier1Normal)
    }

    func testOverall_picksHigherSeverityBetweenEyes() {
        XCTAssertEqual(
            TierAssigner.assignOverallTier(right: .tier1Normal, left: .tier2StretchWithNotification),
            .tier2StretchWithNotification
        )
        XCTAssertEqual(
            TierAssigner.assignOverallTier(right: .tier2StretchWithNotification, left: .tier1Normal),
            .tier2StretchWithNotification
        )
    }

    func testOverall_tier4_overridesTier3() {
        // Plan callout: Tier 4 (medical concern) overrides Tier 3 (do not dispense).
        let overall = TierAssigner.assignOverallTier(
            right: .tier3DoNotDispense,
            left: .tier4MedicalConcern
        )
        XCTAssertEqual(overall, .tier4MedicalConcern)
    }

    func testOverall_tier3_overridesTier2() {
        let overall = TierAssigner.assignOverallTier(
            right: .tier2StretchWithNotification,
            left: .tier3DoNotDispense
        )
        XCTAssertEqual(overall, .tier3DoNotDispense)
    }
}
