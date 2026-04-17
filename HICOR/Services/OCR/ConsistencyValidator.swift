import Foundation

struct ConsistencyValidator {

    struct Outcome: Equatable {
        let result: ConsistencyResult
        let message: String?
    }

    static let signMismatchPhotoCountThresholdForOverride = 3
    static let sphSpreadThreshold = 0.75
    static let cylSpreadThreshold = 0.75

    func validate(_ results: [PrintoutResult], photoCount: Int) -> Outcome {
        let rightSPHs = results.compactMap { $0.rightEye }.flatMap { $0.readings.map(\.sph) }
        let leftSPHs  = results.compactMap { $0.leftEye  }.flatMap { $0.readings.map(\.sph) }

        if let mismatch = signMismatch(right: rightSPHs, left: leftSPHs) {
            if photoCount < ConsistencyValidator.signMismatchPhotoCountThresholdForOverride {
                return Outcome(
                    result: .hardBlock,
                    message: "Right and left eyes have opposite corrections (\(mismatch)). Please capture additional printouts."
                )
            }
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
        guard !right.isEmpty, !left.isEmpty else { return nil }
        let rAvg = right.reduce(0, +) / Double(right.count)
        let lAvg = left.reduce(0, +)  / Double(left.count)
        print("ConsistencyValidator: R_avgSPH=\(rAvg) (n=\(right.count)), L_avgSPH=\(lAvg) (n=\(left.count))")
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
            guard readings.count >= 2 else { continue }
            let sphSpread = (readings.map(\.sph).max()! - readings.map(\.sph).min()!)
            if sphSpread > ConsistencyValidator.sphSpreadThreshold {
                return "\(eye == .right ? "Right" : "Left") eye sphere readings vary by \(String(format: "%.2f", sphSpread)) D. Verify the printout."
            }
            // SPH-only readings carry cyl = 0.0 as a placeholder; excluding them
            // prevents false-positive spread warnings against the real cyl values.
            let cylReadings = readings.filter { !$0.isSphOnly }.map(\.cyl)
            guard cylReadings.count >= 2 else { continue }
            let cylSpread = (cylReadings.max()! - cylReadings.min()!)
            if cylSpread > ConsistencyValidator.cylSpreadThreshold {
                return "\(eye == .right ? "Right" : "Left") eye cylinder readings vary by \(String(format: "%.2f", cylSpread)) D. Verify the printout."
            }
        }
        return nil
    }
}
