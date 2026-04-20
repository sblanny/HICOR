import Foundation

// Thibos M/J0/J45 power-vector decomposition. Axis is circular (179° ≡ -1°),
// so arithmetic averaging of axes is mathematically wrong. Decomposing into
// orthogonal J0/J45 components allows correct averaging across printouts.
// Reference: Thibos, Wheeler, Horner 1997, "Power Vectors: An Application of
// Fourier Analysis to the Description and Statistical Analysis of Refractive
// Error." See MIKE_RX_PROCEDURE.md §2 (axis sliding scale) and §Phase 5
// Priority step 2 (cross-printout aggregation via Thibos vectors).
enum PowerVector {

    static func toM(sph: Double, cyl: Double) -> Double {
        sph + cyl / 2.0
    }

    static func toJ0(cyl: Double, axDegrees: Int) -> Double {
        let axRadians = Double(axDegrees) * .pi / 180.0
        return -cyl / 2.0 * cos(2.0 * axRadians)
    }

    static func toJ45(cyl: Double, axDegrees: Int) -> Double {
        let axRadians = Double(axDegrees) * .pi / 180.0
        return -cyl / 2.0 * sin(2.0 * axRadians)
    }

    static func reconstruct(
        m: Double,
        j0: Double,
        j45: Double
    ) -> (sph: Double, cyl: Double, ax: Int) {
        let magnitude = sqrt(j0 * j0 + j45 * j45)
        let cyl = -2.0 * magnitude
        let sph = m - cyl / 2.0

        // When there is no cylinder, axis is undefined; atan2(0, 0) returns 0.
        // Clamp to the HICOR (0, 180] convention so RawReading's 1-180 range
        // holds downstream. Axis value is clinically meaningless in that case.
        let ax: Int
        if magnitude < 1e-9 {
            ax = 180
        } else {
            let axRadians = atan2(j45, j0) / 2.0
            var axDegrees = Int((axRadians * 180.0 / .pi).rounded())
            while axDegrees <= 0 { axDegrees += 180 }
            while axDegrees > 180 { axDegrees -= 180 }
            ax = axDegrees
        }
        return (sph, cyl, ax)
    }
}
