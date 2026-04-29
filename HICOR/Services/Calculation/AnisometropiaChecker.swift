import Foundation

// R/L anisometropia classification per MIKE_RX_PROCEDURE.md §8.
//
// Same-sign (both eyes positive, both negative, or either zero):
//   |R − L| ≤ 2.00  → normal, dispense
//   |R − L| > 2.00  → advisory banner (depth-perception warning)
//   |R − L| > 3.00 with ≥3 printouts → refer out
//   |R − L| > 3.00 with <3 printouts → advisory; the orchestrator emits a
//     separate insufficientReadings flag asking for a 3rd printout before
//     refer-out fires (§8: "take 3 readings, look for <3 D option, otherwise
//     refer out")
//
// Mixed-sign (antimetropia — one eye strictly positive, the other strictly
// negative):
//   Both eyes |SPH| ≤ 1.50  → dispense using the lowest-absolute-SPH eye
//   Either eye |SPH| > 1.50 → refer out
//
// The ≥4-printout gate for antimetropia is enforced upstream by the
// orchestrator (via the ConsistencyValidator input count), not here.
enum AnisometropiaChecker {

    enum Decision: Equatable {
        case normal
        case sameSignAdvisory(diff: Double)
        case sameSignReferOut(diff: Double)
        case antimetropiaDispense(lowestAbsEye: Eye)
        case antimetropiaReferOut
    }

    static func check(rightSph: Double, leftSph: Double, printoutCount: Int) -> Decision {
        if isAntimetropia(rightSph: rightSph, leftSph: leftSph) {
            if abs(rightSph) > Constants.antimetropiaBothEyesMaxAbs ||
               abs(leftSph) > Constants.antimetropiaBothEyesMaxAbs {
                return .antimetropiaReferOut
            }
            let lowest: Eye = abs(leftSph) < abs(rightSph) ? .left : .right
            return .antimetropiaDispense(lowestAbsEye: lowest)
        }

        let diff = abs(rightSph - leftSph)
        if diff > Constants.anisometropiaReferOutThreshold {
            // §8: with fewer than 3 printouts, hold off on refer-out and let
            // the operator capture a 3rd printout to verify the difference.
            if printoutCount < 3 {
                return .sameSignAdvisory(diff: diff)
            }
            return .sameSignReferOut(diff: diff)
        }
        if diff > Constants.anisometropiaAdvisoryThreshold {
            return .sameSignAdvisory(diff: diff)
        }
        return .normal
    }

    // Plano (0.0) is not a sign — pairs with either positive or negative
    // without triggering antimetropia. Strict inequalities match that.
    private static func isAntimetropia(rightSph: Double, leftSph: Double) -> Bool {
        (rightSph > 0 && leftSph < 0) || (rightSph < 0 && leftSph > 0)
    }
}
