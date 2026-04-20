import XCTest
@testable import HICOR

final class ClinicalFlagInstructionTests: XCTestCase {

    // MARK: - insufficientReadings — operator-actionable per §3 gate

    func test_insufficientReadings_antimetropia_tellsOperatorToAddPhoto() {
        let flag = ClinicalFlag.insufficientReadings(
            eye: .right,
            count: 2,
            reason: .antimetropiaNeedsFour
        )
        let inst = ClinicalFlagInstruction.make(for: flag)
        XCTAssertEqual(inst.severity, .blocking)
        XCTAssertTrue(inst.title.lowercased().contains("more printouts needed"))
        // Must name the clinical reason + minimum count (4) + action verb.
        XCTAssertTrue(inst.body.lowercased().contains("antimetropia"),
                      "body=\(inst.body)")
        XCTAssertTrue(inst.body.contains("4"), "body=\(inst.body)")
        XCTAssertTrue(inst.body.lowercased().contains("capture")
                      || inst.body.lowercased().contains("add"),
                      "body=\(inst.body)")
    }

    func test_insufficientReadings_rlSphDiff_showsDiopterDifference() {
        let flag = ClinicalFlag.insufficientReadings(
            eye: .right,
            count: 2,
            reason: .rlSphDifferenceExceedsThree(diff: 3.75)
        )
        let inst = ClinicalFlagInstruction.make(for: flag)
        XCTAssertEqual(inst.severity, .blocking)
        // Must show the observed difference so the operator sees why.
        XCTAssertTrue(inst.body.contains("3.75"), "body=\(inst.body)")
        // Must reference the minimum-printout gate (3).
        XCTAssertTrue(inst.body.contains("3"), "body=\(inst.body)")
    }

    func test_insufficientReadings_onePlanoOtherHigh_explainsCondition() {
        let flag = ClinicalFlag.insufficientReadings(
            eye: .left,
            count: 2,
            reason: .onePlanoOtherHighSph
        )
        let inst = ClinicalFlagInstruction.make(for: flag)
        XCTAssertEqual(inst.severity, .blocking)
        XCTAssertTrue(inst.body.lowercased().contains("plano"),
                      "body=\(inst.body)")
    }

    func test_insufficientReadings_highSphOverTen_mentionsHighSph() {
        let flag = ClinicalFlag.insufficientReadings(
            eye: .right,
            count: 2,
            reason: .highSphOverTen
        )
        let inst = ClinicalFlagInstruction.make(for: flag)
        XCTAssertEqual(inst.severity, .blocking)
        // Must reference the 10 D trigger so operator understands why.
        XCTAssertTrue(inst.body.contains("10"), "body=\(inst.body)")
    }

    // MARK: - Anisometropia / antimetropia

    func test_anisometropiaAdvisory_isWarning_not_blocking() {
        let inst = ClinicalFlagInstruction.make(
            for: .anisometropiaAdvisory(diffDiopters: 2.50)
        )
        XCTAssertEqual(inst.severity, .warning)
        XCTAssertTrue(inst.body.contains("2.50"), "body=\(inst.body)")
    }

    func test_anisometropiaReferOut_isBlocking_namesReferral() {
        let inst = ClinicalFlagInstruction.make(
            for: .anisometropiaReferOut(diffDiopters: 3.25)
        )
        XCTAssertEqual(inst.severity, .blocking)
        XCTAssertTrue(inst.body.lowercased().contains("refer"),
                      "body=\(inst.body)")
    }

    func test_antimetropiaDispense_identifiesEye() {
        let inst = ClinicalFlagInstruction.make(
            for: .antimetropiaDispense(lowestAbsEye: .left)
        )
        XCTAssertEqual(inst.severity, .warning)
        XCTAssertTrue(inst.body.lowercased().contains("left"),
                      "body=\(inst.body)")
    }

    func test_antimetropiaReferOut_isBlocking() {
        let inst = ClinicalFlagInstruction.make(for: .antimetropiaReferOut)
        XCTAssertEqual(inst.severity, .blocking)
        XCTAssertTrue(inst.body.lowercased().contains("refer"),
                      "body=\(inst.body)")
    }

    // MARK: - Medical concern + inventory

    func test_medicalConcern_isBlocking_showsValueAndEye() {
        let inst = ClinicalFlagInstruction.make(
            for: .medicalConcern(eye: .right, value: -11.25)
        )
        XCTAssertEqual(inst.severity, .blocking)
        XCTAssertTrue(inst.body.contains("-11.25") || inst.body.contains("11.25"),
                      "body=\(inst.body)")
    }

    func test_sphExceedsInventory_labelsEyeAndTier() {
        let inst = ClinicalFlagInstruction.make(
            for: .sphExceedsInventory(
                eye: .left,
                value: -7.50,
                tier: .tier3DoNotDispense
            )
        )
        // Tier 3 == refer out, so this should be blocking.
        XCTAssertEqual(inst.severity, .blocking)
        XCTAssertTrue(inst.body.lowercased().contains("left"),
                      "body=\(inst.body)")
    }

    // MARK: - PD / SPH-only / manual review

    func test_pdMeasurementRequired_mentionsSpread_mm() {
        let inst = ClinicalFlagInstruction.make(
            for: .pdMeasurementRequired(spreadMm: 7.0)
        )
        XCTAssertEqual(inst.severity, .warning)
        XCTAssertTrue(inst.body.contains("7"), "body=\(inst.body)")
        XCTAssertTrue(inst.body.lowercased().contains("mm"),
                      "body=\(inst.body)")
    }

    func test_sphOnlyReadings_isInfo_countShown() {
        let inst = ClinicalFlagInstruction.make(
            for: .sphOnlyReadings(eye: .right, count: 3)
        )
        XCTAssertEqual(inst.severity, .info)
        XCTAssertTrue(inst.body.contains("3"), "body=\(inst.body)")
    }

    func test_manualReviewRequired_isBlocking() {
        let inst = ClinicalFlagInstruction.make(
            for: .manualReviewRequired(reason: "CYL spread exceeded")
        )
        XCTAssertEqual(inst.severity, .blocking)
        // The underlying reason should be surfaced verbatim.
        XCTAssertTrue(inst.body.contains("CYL spread exceeded"),
                      "body=\(inst.body)")
    }

    // MARK: - Tier 0 symptom check flag

    func test_tier0SymptomCheckRequired_isInfo_notBlocking() {
        // Tier 0 is not an error; it just prompts the symptom screen.
        let inst = ClinicalFlagInstruction.make(
            for: .tier0SymptomCheckRequired(eye: .right)
        )
        XCTAssertEqual(inst.severity, .info)
    }
}
