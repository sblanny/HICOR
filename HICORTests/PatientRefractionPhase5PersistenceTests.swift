import XCTest
import SwiftData
@testable import HICOR

// Roundtrips Phase 5 audit fields through SwiftData for each tier outcome
// per MIKE_RX_PROCEDURE.md + the Phase 5 plan Task 12 spec.
final class PatientRefractionPhase5PersistenceTests: XCTestCase {

    // MARK: - Fixtures

    private func rightPrescription(
        tier: DispensingTier,
        source: PrescriptionSource = .machineAvgValidated
    ) -> FinalPrescription {
        FinalPrescription(
            eye: .right,
            sph: -1.25,
            cyl: -0.50,
            ax: 90,
            source: source,
            acceptedReadings: [
                RawReading(id: UUID(), sph: -1.25, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0)
            ],
            phase5DroppedOutliers: [],
            machineAvgUsed: source == .machineAvgValidated,
            dispensingTier: tier,
            tierMessage: nil
        )
    }

    private func leftPrescription(
        tier: DispensingTier,
        source: PrescriptionSource = .recomputedViaPowerVector
    ) -> FinalPrescription {
        FinalPrescription(
            eye: .left,
            sph: -1.00,
            cyl: -0.25,
            ax: 85,
            source: source,
            acceptedReadings: [
                RawReading(id: UUID(), sph: -1.00, cyl: -0.25, ax: 85, eye: .left, sourcePhotoIndex: 0)
            ],
            phase5DroppedOutliers: [],
            machineAvgUsed: false,
            dispensingTier: tier,
            tierMessage: nil
        )
    }

    private func outcome(
        tier: DispensingTier,
        clinicalFlags: [ClinicalFlag] = [],
        manualReview: Bool = false,
        pdValues: [Double] = [62.0, 62.0]
    ) -> PrescriptionCalculationOutcome {
        PrescriptionCalculationOutcome(
            rightEye: rightPrescription(tier: tier),
            leftEye: leftPrescription(tier: tier),
            overallTier: tier,
            clinicalFlags: clinicalFlags,
            pd: PDAggregator.aggregate(pds: pdValues),
            upstreamDroppedOutliers: [],
            requiresManualReview: manualReview
        )
    }

    private func container() throws -> ModelContainer {
        // Disable CloudKit integration in tests — the production container
        // requires every attribute to be Optional or have a default *at the
        // schema level*, which is a production-container concern unrelated to
        // the roundtrip behavior we're verifying here.
        let config = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: PatientRefraction.self, configurations: config)
    }

    private func newRefraction() -> PatientRefraction {
        PatientRefraction(
            patientNumber: "001",
            sessionDate: Date(timeIntervalSince1970: 1_700_000_000),
            sessionLocation: "Test"
        )
    }

    private func roundtrip(_ refraction: PatientRefraction) throws -> PatientRefraction {
        let c = try container()
        let ctx = ModelContext(c)
        ctx.insert(refraction)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<PatientRefraction>())
        XCTAssertEqual(fetched.count, 1)
        return fetched[0]
    }

    // MARK: - Tier 1: normal dispense, no acknowledgement needed

    func test_tier1_roundtrip_storesFinalValues_and_nilPatientNotified() throws {
        let o = outcome(tier: .tier1Normal)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)

        XCTAssertEqual(r.dispensingTier, DispensingTier.tier1Normal.rawValue)
        XCTAssertEqual(r.odSPH, -1.25, accuracy: 1e-9)
        XCTAssertEqual(r.odCYL, -0.50, accuracy: 1e-9)
        XCTAssertEqual(r.odAX, 90)
        XCTAssertEqual(r.osSPH, -1.00, accuracy: 1e-9)
        XCTAssertEqual(r.osCYL, -0.25, accuracy: 1e-9)
        XCTAssertEqual(r.osAX, 85)
        XCTAssertEqual(r.pd, 62.0, accuracy: 1e-9)
        XCTAssertEqual(r.pdSpread, 0.0, accuracy: 1e-9)
        XCTAssertEqual(r.finalRightSource, PrescriptionSource.machineAvgValidated.rawValue)
        XCTAssertEqual(r.finalLeftSource, PrescriptionSource.recomputedViaPowerVector.rawValue)
        XCTAssertFalse(r.manualReviewRequired)
        XCTAssertNil(r.noGlassesReason)
        // Not Tier 2 — acknowledgement field stays nil.
        XCTAssertNil(r.patientNotifiedTier2)
    }

    // MARK: - Tier 2: acknowledgement audit trail

    func test_tier2_confirmed_persistsPatientNotifiedTrue() throws {
        let o = outcome(tier: .tier2StretchWithNotification)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: true, tier0Decision: nil)

        let r = try roundtrip(refraction)

        XCTAssertEqual(r.dispensingTier, DispensingTier.tier2StretchWithNotification.rawValue)
        XCTAssertEqual(r.patientNotifiedTier2, true)
    }

    func test_tier2_savedWithoutConfirm_persistsPatientNotifiedFalse() throws {
        // Edge case: UI should normally block save, but if it reached persistence
        // without confirmation, the audit trail must show that distinction.
        let o = outcome(tier: .tier2StretchWithNotification)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: false, tier0Decision: nil)

        let r = try roundtrip(refraction)

        XCTAssertEqual(r.patientNotifiedTier2, false)
    }

    func test_nonTier2_patientNotifiedStaysNil_evenIfValuePassed() throws {
        // Nil for non-Tier-2 cases so audit readers can tell
        // "not applicable" apart from "applicable but not confirmed."
        let o = outcome(tier: .tier1Normal)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: true, tier0Decision: nil)

        let r = try roundtrip(refraction)

        XCTAssertNil(r.patientNotifiedTier2)
    }

    // MARK: - Tier 0 — no-glasses reason

    func test_tier0_noSymptoms_persistsNoGlassesReason() throws {
        let o = outcome(tier: .tier0NoGlassesNeeded)
        let refraction = newRefraction()
        refraction.apply(
            outcome: o,
            patientNotifiedTier2: nil,
            tier0Decision: .noGlassesNeeded
        )

        let r = try roundtrip(refraction)

        XCTAssertEqual(r.dispensingTier, DispensingTier.tier0NoGlassesNeeded.rawValue)
        XCTAssertEqual(r.noGlassesReason, "no symptoms")
    }

    func test_tier0_symptomsPresent_doesNotSetNoGlassesReason() throws {
        let o = outcome(tier: .tier0NoGlassesNeeded)
        let refraction = newRefraction()
        refraction.apply(
            outcome: o,
            patientNotifiedTier2: nil,
            tier0Decision: .dispenseTier1
        )

        let r = try roundtrip(refraction)

        XCTAssertNil(r.noGlassesReason)
    }

    // MARK: - Tier 3 / Tier 4: referral records

    func test_tier3_referOut_persistsTier() throws {
        let o = outcome(tier: .tier3DoNotDispense)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)
        XCTAssertEqual(r.dispensingTier, DispensingTier.tier3DoNotDispense.rawValue)
    }

    func test_tier4_medicalConcern_persistsTier() throws {
        let o = outcome(tier: .tier4MedicalConcern)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)
        XCTAssertEqual(r.dispensingTier, DispensingTier.tier4MedicalConcern.rawValue)
    }

    // MARK: - Manual review

    func test_manualReview_persistsFlag() throws {
        let o = outcome(tier: .tier1Normal, manualReview: true)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)
        XCTAssertTrue(r.manualReviewRequired)
    }

    // MARK: - Clinical flags JSON

    func test_clinicalFlags_roundtripThroughJson() throws {
        let flags: [ClinicalFlag] = [
            .anisometropiaAdvisory(diffDiopters: 2.50),
            .pdMeasurementRequired(spreadMm: 7.0),
            .insufficientReadings(eye: .right, count: 2, reason: .antimetropiaNeedsFour)
        ]
        let o = outcome(tier: .tier1Normal, clinicalFlags: flags)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)

        let decoded = try JSONDecoder().decode([ClinicalFlag].self, from: r.clinicalFlagsJSON)
        XCTAssertEqual(decoded, flags)
    }

    // MARK: - Combined dropped outliers (upstream + Phase 5)

    func test_droppedOutliers_combinesUpstreamAndPhase5() throws {
        let upstream = ConsistencyValidator.DroppedReading(
            reading: RawReading(id: UUID(), sph: -0.25, cyl: 0, ax: 0, eye: .right, sourcePhotoIndex: 1),
            photoIndex: 1,
            eye: .right,
            reason: "upstream outlier"
        )
        let phase5 = ConsistencyValidator.DroppedReading(
            reading: RawReading(id: UUID(), sph: -1.75, cyl: 0, ax: 0, eye: .left, sourcePhotoIndex: 2),
            photoIndex: 2,
            eye: .left,
            reason: "phase5 outlier"
        )
        let right = FinalPrescription(
            eye: .right, sph: -1.25, cyl: -0.50, ax: 90,
            source: .machineAvgValidated, acceptedReadings: [],
            phase5DroppedOutliers: [phase5], machineAvgUsed: true,
            dispensingTier: .tier1Normal, tierMessage: nil
        )
        let o = PrescriptionCalculationOutcome(
            rightEye: right,
            leftEye: leftPrescription(tier: .tier1Normal),
            overallTier: .tier1Normal,
            clinicalFlags: [],
            pd: PDAggregator.aggregate(pds: [62.0]),
            upstreamDroppedOutliers: [upstream],
            requiresManualReview: false
        )

        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)
        let r = try roundtrip(refraction)

        let decoded = try JSONDecoder().decode(
            [ConsistencyValidator.DroppedReading].self,
            from: r.droppedOutliersJSON
        )
        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded.contains(where: { $0.reason == "upstream outlier" }))
        XCTAssertTrue(decoded.contains(where: { $0.reason == "phase5 outlier" }))
    }

    // MARK: - PD source + spread

    func test_pd_spreadAndSourcePersisted() throws {
        // Spread under the 5 mm manual-measurement threshold — source stays
        // "aggregate" with no manual-recommended suffix.
        let o = outcome(tier: .tier1Normal, pdValues: [60.0, 62.0, 64.0])
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)

        XCTAssertEqual(r.pd, 62.0, accuracy: 1e-9)
        XCTAssertEqual(r.pdSpread, 4.0, accuracy: 1e-9)
        XCTAssertEqual(r.pdSource, "aggregate")
    }

    func test_pd_largeSpread_marksManualRequired() throws {
        // >5 mm spread per §9 should flag manual measurement.
        let o = outcome(tier: .tier1Normal, pdValues: [58.0, 66.0])
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)

        XCTAssertEqual(r.pdSpread, 8.0, accuracy: 1e-9)
        XCTAssertEqual(r.pdSource, "aggregate-manual-recommended")
    }

    // MARK: - Accepted readings JSON

    func test_acceptedReadings_jsonIncludesBothEyes() throws {
        let o = outcome(tier: .tier1Normal)
        let refraction = newRefraction()
        refraction.apply(outcome: o, patientNotifiedTier2: nil, tier0Decision: nil)

        let r = try roundtrip(refraction)
        let decoded = try JSONDecoder().decode([RawReading].self, from: r.acceptedReadingsJSON)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded.contains(where: { $0.eye == .right }))
        XCTAssertTrue(decoded.contains(where: { $0.eye == .left }))
    }
}
