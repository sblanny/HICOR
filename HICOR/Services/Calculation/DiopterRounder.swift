import Foundation

// Final-value rounding per MIKE_RX_PROCEDURE.md §6.
//
// SPH rounding is CYL-dependent:
//   |CYL| > 1.00 D → round SPH to STRONGER correction (more magnitude)
//   |CYL| ≤ 1.00 D → round SPH to WEAKER correction (less magnitude)
// Rationale (Mike, April 20): when cylinder is significant, extra spherical
// magnitude compensates for its effect on overall vision; at low cylinder,
// slight under-correction is more comfortable.
//
// CYL: nearest 0.25 D step.
// AX : nearest integer degree, clamped to the HICOR 1-180 convention.
enum DiopterRounder {

    private static let step: Double = 0.25

    static func roundSph(_ sph: Double, forCyl cyl: Double) -> Double {
        let absSph = abs(sph)
        let q = absSph / step
        let lowerQ = q.rounded(.down)
        let upperQ = q.rounded(.up)
        if lowerQ == upperQ {
            // already on a 0.25 step — no rounding needed either direction
            return sph
        }
        let stronger = abs(cyl) > Constants.cylBreakpointForSphRounding
        let chosenAbs = (stronger ? upperQ : lowerQ) * step
        return sph < 0 ? -chosenAbs : chosenAbs
    }

    static func roundCyl(_ cyl: Double) -> Double {
        (cyl / step).rounded() * step
    }

    static func roundAx(_ ax: Double) -> Int {
        let rounded = Int(ax.rounded())
        if rounded < 1 { return 1 }
        if rounded > 180 { return 180 }
        return rounded
    }
}
