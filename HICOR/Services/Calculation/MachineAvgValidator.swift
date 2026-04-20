import Foundation

// Machine AVG validation per MIKE_RX_PROCEDURE.md §4. Mike trusts the
// autorefractor's printed AVG line by default but defers to recomputation
// when it disagrees with our Thibos M calculation by more than 0.50 D —
// that gap implies an outlier reading skewed the machine's average.
//
// §4.5 CYL caveat: when aggregated cylinder magnitude exceeds 1.00 D,
// the orchestrator (Task 9) should prefer the most-negative raw SPH
// reading over the aggregated mean; this module exposes that gate
// separately since SPH selection depends on raw readings the validator
// does not own.
enum MachineAvgValidator {

    enum Validation: Equatable {
        case useMachineAvg
        case recomputeRequired
    }

    static func validate(eyeReading: EyeReading, computedM: Double) -> Validation {
        guard
            let mSph = eyeReading.machineAvgSPH,
            let mCyl = eyeReading.machineAvgCYL
        else {
            return .recomputeRequired
        }
        let machineM = PowerVector.toM(sph: mSph, cyl: mCyl)
        if abs(machineM - computedM) <= Constants.machineAvgValidationThreshold {
            return .useMachineAvg
        }
        return .recomputeRequired
    }

    // §4.5 — strict >, matching §6 SPH-rounding breakpoint.
    static func shouldPreferMostNegativeSph(forComputedCyl cyl: Double) -> Bool {
        abs(cyl) > Constants.cylBreakpointForSphRounding
    }
}
