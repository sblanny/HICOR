import Foundation

struct ConsistencyValidator {

    struct Outcome: Equatable {
        let result: ConsistencyResult
        let message: String?
    }

    static let sphSpreadThreshold = 0.75
    static let cylSpreadThreshold = 0.75

    // v1 scope reduction (2026-04-17): validate operates on a single printout.
    // The photoCount-driven hardBlock/warningOverridable split was meaningful
    // only when multi-photo capture provided extra signal to demand before
    // hard-blocking; with one photo there is no "ask for more" path, so any
    // sign mismatch is always overridable.
    func validate(_ results: [PrintoutResult]) -> Outcome {
        let rightSPHs = results.compactMap { $0.rightEye }.flatMap { $0.readings.map(\.sph) }
        let leftSPHs  = results.compactMap { $0.leftEye  }.flatMap { $0.readings.map(\.sph) }

        if let mismatch = signMismatch(right: rightSPHs, left: leftSPHs) {
            return Outcome(
                result: .warningOverridable,
                message: "Right and left eyes have opposite corrections (\(mismatch)). Verify before continuing."
            )
        }

        if let spreadMessage = spreadWarning(results: results) {
            return Outcome(result: .warningOverridable, message: spreadMessage)
        }

        return Outcome(result: .ok, message: nil)
    }

    private func signMismatch(right: [Double], left: [Double]) -> String? {
        // Defense-in-depth: even though parsers now reject implausible SPH values,
        // filter again here so any future parser regression cannot produce
        // nonsense averages and false sign-mismatch alerts.
        let plausibleRight = right.filter { ReadingPlausibility.isPlausibleSPH($0) }
        let plausibleLeft  = left.filter  { ReadingPlausibility.isPlausibleSPH($0) }
        if plausibleRight.count != right.count {
            print("ConsistencyValidator: dropped \(right.count - plausibleRight.count) implausible right-eye SPH values before averaging")
        }
        if plausibleLeft.count != left.count {
            print("ConsistencyValidator: dropped \(left.count - plausibleLeft.count) implausible left-eye SPH values before averaging")
        }
        guard !plausibleRight.isEmpty, !plausibleLeft.isEmpty else { return nil }
        let rAvg = plausibleRight.reduce(0, +) / Double(plausibleRight.count)
        let lAvg = plausibleLeft.reduce(0, +)  / Double(plausibleLeft.count)
        print("ConsistencyValidator: R_avgSPH=\(rAvg) (n=\(plausibleRight.count)), L_avgSPH=\(lAvg) (n=\(plausibleLeft.count))")
        if rAvg > 0.25 && lAvg < -0.25 {
            return "right eye plus, left eye minus"
        }
        if rAvg < -0.25 && lAvg > 0.25 {
            return "right eye minus, left eye plus"
        }
        return nil
    }

    private func spreadWarning(results: [PrintoutResult]) -> String? {
        for eye: Eye in [.right, .left] {
            let readings = results.compactMap { result in
                eye == .right ? result.rightEye : result.leftEye
            }.flatMap { $0.readings }
            // Filter implausible spheres so a stray sph=+90 garbage value cannot
            // produce a 92 D fake spread. Same defense-in-depth as signMismatch.
            let sphReadings = readings.map(\.sph).filter { ReadingPlausibility.isPlausibleSPH($0) }
            guard sphReadings.count >= 2 else { continue }
            let sphSpread = (sphReadings.max()! - sphReadings.min()!)
            if sphSpread > ConsistencyValidator.sphSpreadThreshold {
                return "\(eye == .right ? "Right" : "Left") eye sphere readings vary by \(String(format: "%.2f", sphSpread)) D. Verify the printout."
            }
            // SPH-only readings carry cyl = 0.0 as a placeholder; excluding them
            // prevents false-positive spread warnings against the real cyl values.
            let cylReadings = readings.filter { !$0.isSphOnly }.map(\.cyl).filter { ReadingPlausibility.isPlausibleCYL($0) }
            guard cylReadings.count >= 2 else { continue }
            let cylSpread = (cylReadings.max()! - cylReadings.min()!)
            if cylSpread > ConsistencyValidator.cylSpreadThreshold {
                return "\(eye == .right ? "Right" : "Left") eye cylinder readings vary by \(String(format: "%.2f", cylSpread)) D. Verify the printout."
            }
        }
        return nil
    }
}
