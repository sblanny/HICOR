import XCTest
@testable import HICOR

final class SaveGatingTests: XCTestCase {

    // Save-button gating per tier outcome. Unit-tests the pure decision;
    // SwiftUI binding lives in the view.

    private func outcome(
        tier: DispensingTier
    ) -> PrescriptionCalculationOutcome {
        PrescriptionCalculationOutcome(
            rightEye: nil,
            leftEye: nil,
            overallTier: tier,
            clinicalFlags: [],
            pd: PDAggregator.aggregate(pds: []),
            upstreamDroppedOutliers: []
        )
    }

    // MARK: - Tier 1: always enabled

    func test_tier1_enabled() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier1Normal),
            patientNotifiedTier2: false,
            tier0Decision: .indeterminate
        )
        XCTAssertTrue(state.enabled)
    }

    // MARK: - Tier 2: requires patient notified

    func test_tier2_disabled_whenNotNotified() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier2StretchWithNotification),
            patientNotifiedTier2: false,
            tier0Decision: .indeterminate
        )
        XCTAssertFalse(state.enabled)
    }

    func test_tier2_enabled_whenNotified() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier2StretchWithNotification),
            patientNotifiedTier2: true,
            tier0Decision: .indeterminate
        )
        XCTAssertTrue(state.enabled)
    }

    // MARK: - Tier 3 / 4: always enabled (save records the referral)

    func test_tier3_enabled_recordsReferral() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier3DoNotDispense),
            patientNotifiedTier2: false,
            tier0Decision: .indeterminate
        )
        XCTAssertTrue(state.enabled)
    }

    func test_tier4_enabled_recordsMedicalReferral() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier4MedicalConcern),
            patientNotifiedTier2: false,
            tier0Decision: .indeterminate
        )
        XCTAssertTrue(state.enabled)
    }

    // MARK: - Tier 0: blocked until symptom check complete

    func test_tier0_disabled_whenIndeterminate() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier0NoGlassesNeeded),
            patientNotifiedTier2: false,
            tier0Decision: .indeterminate
        )
        XCTAssertFalse(state.enabled)
    }

    func test_tier0_enabled_whenNoSymptoms() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier0NoGlassesNeeded),
            patientNotifiedTier2: false,
            tier0Decision: .noGlassesNeeded
        )
        XCTAssertTrue(state.enabled)
    }

    func test_tier0_enabled_whenSymptomsDispenseInstead() {
        let state = SaveGate.evaluate(
            outcome: outcome(tier: .tier0NoGlassesNeeded),
            patientNotifiedTier2: false,
            tier0Decision: .dispenseTier1
        )
        XCTAssertTrue(state.enabled)
    }

}
