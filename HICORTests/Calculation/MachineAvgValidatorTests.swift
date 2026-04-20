import XCTest
@testable import HICOR

final class MachineAvgValidatorTests: XCTestCase {

    // MARK: - validate(eyeReading:computedM:)

    func testValidate_agreementWithinQuarterDiopter_useMachineAvg() {
        let eyeReading = makeEyeReading(machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90)
        // machine M = -2.00 + -1.00/2 = -2.50
        // computed M = -2.25 → |diff| = 0.25 D → within 0.50 threshold
        let result = MachineAvgValidator.validate(eyeReading: eyeReading, computedM: -2.25)
        XCTAssertEqual(result, .useMachineAvg)
    }

    func testValidate_disagreementByThreeQuarters_recomputeRequired() {
        let eyeReading = makeEyeReading(machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90)
        // machine M = -2.50; computed M = -3.25 → 0.75 D diff → recompute
        let result = MachineAvgValidator.validate(eyeReading: eyeReading, computedM: -3.25)
        XCTAssertEqual(result, .recomputeRequired)
    }

    func testValidate_disagreementExactlyHalf_useMachineAvg_dueTo_lessEqual() {
        // §4 rule: |diff| ≤ 0.50 → use. Exactly 0.50 falls in the "use" bucket.
        let eyeReading = makeEyeReading(machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90)
        let result = MachineAvgValidator.validate(eyeReading: eyeReading, computedM: -3.00)
        XCTAssertEqual(result, .useMachineAvg)
    }

    func testValidate_missingMachineAvgSPH_recomputeRequired() {
        let eyeReading = makeEyeReading(machineAvgSPH: nil, machineAvgCYL: -1.00, machineAvgAX: 90)
        let result = MachineAvgValidator.validate(eyeReading: eyeReading, computedM: -2.50)
        XCTAssertEqual(result, .recomputeRequired)
    }

    func testValidate_missingMachineAvgCYL_recomputeRequired() {
        let eyeReading = makeEyeReading(machineAvgSPH: -2.00, machineAvgCYL: nil, machineAvgAX: 90)
        let result = MachineAvgValidator.validate(eyeReading: eyeReading, computedM: -2.50)
        XCTAssertEqual(result, .recomputeRequired)
    }

    func testValidate_completelyMissingMachineAvg_recomputeRequired() {
        let eyeReading = makeEyeReading(machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil)
        let result = MachineAvgValidator.validate(eyeReading: eyeReading, computedM: -2.50)
        XCTAssertEqual(result, .recomputeRequired)
    }

    // MARK: - Mike's §4.5 CYL caveat

    func testShouldPreferMostNegativeSph_highCyl_returnsTrue() {
        // |CYL| = 1.50 > 1.00 breakpoint → prefer most-negative SPH.
        XCTAssertTrue(MachineAvgValidator.shouldPreferMostNegativeSph(forComputedCyl: -1.50))
    }

    func testShouldPreferMostNegativeSph_lowCyl_returnsFalse() {
        XCTAssertFalse(MachineAvgValidator.shouldPreferMostNegativeSph(forComputedCyl: -0.50))
    }

    func testShouldPreferMostNegativeSph_exactBreakpoint_returnsFalse_dueTo_strictGreaterThan() {
        // §4.5 uses strict > 1.00, matching §6 rounding breakpoint.
        XCTAssertFalse(MachineAvgValidator.shouldPreferMostNegativeSph(forComputedCyl: -1.00))
    }

    func testShouldPreferMostNegativeSph_zeroCyl_returnsFalse() {
        XCTAssertFalse(MachineAvgValidator.shouldPreferMostNegativeSph(forComputedCyl: 0.0))
    }
}

// MARK: - Helpers

private func makeEyeReading(
    machineAvgSPH: Double?,
    machineAvgCYL: Double?,
    machineAvgAX: Int?
) -> EyeReading {
    EyeReading(
        id: UUID(),
        eye: .right,
        readings: [],
        machineAvgSPH: machineAvgSPH,
        machineAvgCYL: machineAvgCYL,
        machineAvgAX: machineAvgAX,
        sourcePhotoIndex: 0,
        machineType: .desktop
    )
}
