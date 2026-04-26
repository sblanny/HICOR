import Foundation

// Final-value rounding per MIKE_RX_PROCEDURE.md §6.
//
// SPH rounding is CYL-dependent (0.25 D steps):
//   |CYL| > 1.00 D → round SPH to STRONGER correction (more magnitude)
//   |CYL| ≤ 1.00 D → round SPH to WEAKER correction (less magnitude)
// Rationale (Mike, April 20): when cylinder is significant, extra spherical
// magnitude compensates for its effect on overall vision; at low cylinder,
// slight under-correction is more comfortable.
//
// CYL rounding is SPH-dependent (0.50 D steps; Highlands Optical inventory
// does not stock 0.25 D CYL increments). On a tie between two 0.50 steps:
//   |SPH| ≥ 3.00 D → round CYL STRONGER (away from zero)
//   |SPH| < 3.00 D → round CYL WEAKER (toward zero)
//
// AX: nearest integer degree, clamped to the HICOR 1-180 convention.
enum DiopterRounder {

    private static let sphStep: Double = 0.25

    static func roundSph(_ sph: Double, forCyl cyl: Double) -> Double {
        let absSph = abs(sph)
        let q = absSph / sphStep
        let lowerQ = q.rounded(.down)
        let upperQ = q.rounded(.up)
        if lowerQ == upperQ {
            // already on a 0.25 step — no rounding needed either direction
            return sph
        }
        let stronger = abs(cyl) > Constants.cylBreakpointForSphRounding
        let chosenAbs = (stronger ? upperQ : lowerQ) * sphStep
        return sph < 0 ? -chosenAbs : chosenAbs
    }

    static func roundCyl(_ value: Double, eyeSphMagnitude: Double) -> Double {
        if value == 0 { return 0 }

        // CYL is conventionally negative; work in magnitude space and re-sign.
        let absValue = abs(value)
        let step = Constants.cylRoundingStep
        let lowerStep = (absValue / step).rounded(.down) * step  // weaker (toward zero)
        let upperStep = lowerStep + step                          // stronger (away from zero)

        let distToLower = absValue - lowerStep
        let distToUpper = upperStep - absValue
        let epsilon = 1e-9

        let chosenAbs: Double
        if distToLower < distToUpper - epsilon {
            chosenAbs = lowerStep
        } else if distToUpper < distToLower - epsilon {
            chosenAbs = upperStep
        } else if eyeSphMagnitude >= Constants.sphMagnitudeThresholdForCylRounding {
            chosenAbs = upperStep
        } else {
            chosenAbs = lowerStep
        }
        return value < 0 ? -chosenAbs : chosenAbs
    }

    static func roundAx(_ ax: Double) -> Int {
        let rounded = Int(ax.rounded())
        if rounded < 1 { return 1 }
        if rounded > 180 { return 180 }
        return rounded
    }
}
