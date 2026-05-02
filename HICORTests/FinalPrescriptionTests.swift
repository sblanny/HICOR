import XCTest
@testable import HICOR

final class FinalPrescriptionTests: XCTestCase {

    // MARK: - PrescriptionSource

    func testPrescriptionSource_codableRoundtrip_allCases() throws {
        for source in PrescriptionSource.allCases {
            let encoded = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(PrescriptionSource.self, from: encoded)
            XCTAssertEqual(decoded, source)
        }
    }

    // MARK: - DispensingTier

    func testDispensingTier_codableRoundtrip_allCases() throws {
        for tier in DispensingTier.allCases {
            let encoded = try JSONEncoder().encode(tier)
            let decoded = try JSONDecoder().decode(DispensingTier.self, from: encoded)
            XCTAssertEqual(decoded, tier)
        }
    }

    // MARK: - InsufficientReadingsReason

    func testInsufficientReadingsReason_codableRoundtrip_antimetropia() throws {
        let reason: InsufficientReadingsReason = .antimetropiaNeedsFour
        let encoded = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(InsufficientReadingsReason.self, from: encoded)
        XCTAssertEqual(decoded, reason)
    }

    func testInsufficientReadingsReason_codableRoundtrip_rlSphDiff() throws {
        let reason: InsufficientReadingsReason = .rlSphDifferenceExceedsThree(diff: 3.5)
        let encoded = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(InsufficientReadingsReason.self, from: encoded)
        XCTAssertEqual(decoded, reason)
    }

    func testInsufficientReadingsReason_codableRoundtrip_onePlano() throws {
        let reason: InsufficientReadingsReason = .onePlanoOtherHighSph
        let encoded = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(InsufficientReadingsReason.self, from: encoded)
        XCTAssertEqual(decoded, reason)
    }

    func testInsufficientReadingsReason_codableRoundtrip_highSph() throws {
        let reason: InsufficientReadingsReason = .highSphOverTen
        let encoded = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(InsufficientReadingsReason.self, from: encoded)
        XCTAssertEqual(decoded, reason)
    }

    func testInsufficientReadingsReason_codableRoundtrip_sameSignAnisometropiaNeedsThird() throws {
        let reason: InsufficientReadingsReason = .sameSignAnisometropiaNeedsThird
        let encoded = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(InsufficientReadingsReason.self, from: encoded)
        XCTAssertEqual(decoded, reason)
    }

    // MARK: - ClinicalFlag

    func testClinicalFlag_insufficientReadings_carriesTypedReason() throws {
        let flag: ClinicalFlag = .insufficientReadings(
            eye: .right,
            count: 2,
            reason: .antimetropiaNeedsFour
        )
        let encoded = try JSONEncoder().encode(flag)
        let decoded = try JSONDecoder().decode(ClinicalFlag.self, from: encoded)
        XCTAssertEqual(decoded, flag)
    }

    func testClinicalFlag_sphExceedsInventory_carriesTierAndValue() throws {
        let flag: ClinicalFlag = .sphExceedsInventory(
            eye: .left,
            value: -9.50,
            tier: .tier3DoNotDispense
        )
        let encoded = try JSONEncoder().encode(flag)
        let decoded = try JSONDecoder().decode(ClinicalFlag.self, from: encoded)
        XCTAssertEqual(decoded, flag)
    }

    func testClinicalFlag_antimetropiaReferOut_noAssociatedValues() throws {
        let flag: ClinicalFlag = .antimetropiaReferOut
        let encoded = try JSONEncoder().encode(flag)
        let decoded = try JSONDecoder().decode(ClinicalFlag.self, from: encoded)
        XCTAssertEqual(decoded, flag)
    }

    func testClinicalFlag_axisAgreementExceeded_carriesSpreadAndTolerance() throws {
        let flag: ClinicalFlag = .axisAgreementExceeded(eye: .right, spread: 14.0, tolerance: 10.0)
        let encoded = try JSONEncoder().encode(flag)
        let decoded = try JSONDecoder().decode(ClinicalFlag.self, from: encoded)
        XCTAssertEqual(decoded, flag)
    }

    // MARK: - FinalPrescription

    func testFinalPrescription_codableRoundtrip_fullPayload() throws {
        let reading = RawReading(
            id: UUID(),
            sph: -2.50,
            cyl: -1.00,
            ax: 90,
            eye: .right,
            sourcePhotoIndex: 0
        )
        let dropped = ConsistencyValidator.DroppedReading(
            reading: reading,
            photoIndex: 2,
            eye: .right,
            reason: "Phase 5 outlier: M exceeds 1.00 D from median"
        )
        let rx = FinalPrescription(
            eye: .right,
            sph: -2.50,
            cyl: -1.00,
            ax: 90,
            source: .machineAvgValidated,
            acceptedReadings: [reading],
            phase5DroppedOutliers: [dropped],
            machineAvgUsed: true,
            dispensingTier: .tier1Normal,
            tierMessage: nil
        )
        let encoded = try JSONEncoder().encode(rx)
        let decoded = try JSONDecoder().decode(FinalPrescription.self, from: encoded)
        XCTAssertEqual(decoded, rx)
    }

    func testFinalPrescription_equatable_distinguishesBySph() {
        let base = FinalPrescription(
            eye: .right, sph: -2.50, cyl: -1.00, ax: 90,
            source: .machineAvgValidated,
            acceptedReadings: [], phase5DroppedOutliers: [],
            machineAvgUsed: true,
            dispensingTier: .tier1Normal,
            tierMessage: nil
        )
        let mutated = FinalPrescription(
            eye: .right, sph: -2.25, cyl: -1.00, ax: 90,
            source: .machineAvgValidated,
            acceptedReadings: [], phase5DroppedOutliers: [],
            machineAvgUsed: true,
            dispensingTier: .tier1Normal,
            tierMessage: nil
        )
        XCTAssertNotEqual(base, mutated)
    }

    func testFinalPrescription_tierMessageOptional_persistsWhenProvided() throws {
        let rx = FinalPrescription(
            eye: .left, sph: -7.50, cyl: -1.25, ax: 180,
            source: .recomputedViaPowerVector,
            acceptedReadings: [], phase5DroppedOutliers: [],
            machineAvgUsed: false,
            dispensingTier: .tier2StretchWithNotification,
            tierMessage: "Patient notification required…"
        )
        let encoded = try JSONEncoder().encode(rx)
        let decoded = try JSONDecoder().decode(FinalPrescription.self, from: encoded)
        XCTAssertEqual(decoded.tierMessage, "Patient notification required…")
    }

    // MARK: - Phase 5 Constants canaries

    func testPhase5Constants_sphAgreementThreshold_isOneDiopter() {
        XCTAssertEqual(Constants.sphAgreementThreshold, 1.00)
    }

    func testPhase5Constants_cylAgreementThreshold_isOneDiopter() {
        // Calibrated 2026-05-02 mid-trip: bumped from 0.50 D (industry
        // standard) to 1.00 D (inventory CYL step size). See
        // MIKE_RX_PROCEDURE.md §1.
        XCTAssertEqual(Constants.cylAgreementThreshold, 1.00)
    }

    func testPhase5Constants_tier0SphMax_matchesMike() {
        XCTAssertEqual(Constants.tier0SphMax, 0.25)
    }

    func testPhase5Constants_sphMedicalConcernMin_isTwelveDiopters() {
        XCTAssertEqual(Constants.sphMedicalConcernMin, 12.00)
    }
}
