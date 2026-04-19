import Foundation

struct ConsistencyValidator {

    enum Result: Equatable {
        case consistent(droppedOutliers: [DroppedReading])
        case inconsistentAddPhoto(reason: String, currentCount: Int)
        case inconsistentEscalate(reason: String)
    }

    struct DroppedReading: Equatable {
        let reading: RawReading
        let photoIndex: Int
        let eye: Eye
        let reason: String
    }

    static let sphSpreadThreshold = 0.75
    static let cylSpreadThreshold = 0.75
    static let outlierDeviationThreshold = 1.00

    func validate(_ results: [PrintoutResult]) -> Result {
        let count = results.count

        if let mismatch = crossEyeSignMismatch(results) {
            return inconsistent(reason: mismatch, count: count)
        }

        for eye: Eye in [.right, .left] {
            if let message = perEyeSignDisagreement(results: results, eye: eye) {
                return inconsistent(reason: message, count: count)
            }
        }

        var droppedOutliers: [DroppedReading] = []
        var filteredResults = results
        if count >= 3 {
            let (filtered, dropped) = removeMajorityOutliers(from: results)
            filteredResults = filtered
            droppedOutliers = dropped
        }

        if let spread = spreadWarning(results: filteredResults) {
            return inconsistent(reason: spread, count: count)
        }

        for dropped in droppedOutliers {
            OCRLog.logger.info("Consistency dropped outlier eye=\(dropped.eye.rawValue, privacy: .public) photo=\(dropped.photoIndex) sph=\(dropped.reading.sph, format: .fixed(precision: 2)) reason=\(dropped.reason, privacy: .public)")
        }

        return .consistent(droppedOutliers: droppedOutliers)
    }

    private func inconsistent(reason: String, count: Int) -> Result {
        if count >= Constants.maxPhotosAllowed {
            return .inconsistentEscalate(reason: reason)
        }
        return .inconsistentAddPhoto(reason: reason, currentCount: count)
    }

    private func crossEyeSignMismatch(_ results: [PrintoutResult]) -> String? {
        let rightSPHs = allSPHs(results: results, eye: .right)
        let leftSPHs  = allSPHs(results: results, eye: .left)
        guard !rightSPHs.isEmpty, !leftSPHs.isEmpty else { return nil }
        let rAvg = rightSPHs.reduce(0, +) / Double(rightSPHs.count)
        let lAvg = leftSPHs.reduce(0, +) / Double(leftSPHs.count)
        OCRLog.logger.debug("Consistency avg sph r=\(rAvg, format: .fixed(precision: 2)) n=\(rightSPHs.count) l=\(lAvg, format: .fixed(precision: 2)) n=\(leftSPHs.count)")
        if rAvg > 0.25 && lAvg < -0.25 {
            return "Right eye plus, left eye minus — verify both printouts match the correct patient"
        }
        if rAvg < -0.25 && lAvg > 0.25 {
            return "Right eye minus, left eye plus — verify both printouts match the correct patient"
        }
        return nil
    }

    private func perEyeSignDisagreement(results: [PrintoutResult], eye: Eye) -> String? {
        guard results.count >= 2 else { return nil }
        var sawPlus = false
        var sawMinus = false
        for result in results {
            guard let section = (eye == .right ? result.rightEye : result.leftEye) else { continue }
            let plausibles = section.readings.map(\.sph).filter { ReadingPlausibility.isPlausibleSPH($0) }
            guard !plausibles.isEmpty else { continue }
            let avg = plausibles.reduce(0, +) / Double(plausibles.count)
            if avg > 0.25 { sawPlus = true }
            if avg < -0.25 { sawMinus = true }
        }
        if sawPlus && sawMinus {
            return "\(eye == .right ? "Right" : "Left") eye sign disagreement across printouts"
        }
        return nil
    }

    private func spreadWarning(results: [PrintoutResult]) -> String? {
        for eye: Eye in [.right, .left] {
            let readings = results.compactMap { result in
                eye == .right ? result.rightEye : result.leftEye
            }.flatMap { $0.readings }

            let sphReadings = readings.map(\.sph).filter { ReadingPlausibility.isPlausibleSPH($0) }
            if sphReadings.count >= 2 {
                let sphSpread = sphReadings.max()! - sphReadings.min()!
                if sphSpread > ConsistencyValidator.sphSpreadThreshold {
                    return "\(eye == .right ? "Right" : "Left") eye sphere readings vary by \(String(format: "%.2f", sphSpread)) D across printouts"
                }
            }

            let cylReadings = readings.filter { !$0.isSphOnly }.map(\.cyl).filter { ReadingPlausibility.isPlausibleCYL($0) }
            if cylReadings.count >= 2 {
                let cylSpread = cylReadings.max()! - cylReadings.min()!
                if cylSpread > ConsistencyValidator.cylSpreadThreshold {
                    return "\(eye == .right ? "Right" : "Left") eye cylinder readings vary by \(String(format: "%.2f", cylSpread)) D across printouts"
                }
            }
        }
        return nil
    }

    // When 3+ photos exist and a single photo's SPH reading clearly disagrees
    // with the majority, drop that reading but surface it so the operator can
    // see what was excluded (clinical principle: app makes decisions, never
    // hides them).
    private func removeMajorityOutliers(from results: [PrintoutResult]) -> (filtered: [PrintoutResult], dropped: [DroppedReading]) {
        var dropped: [DroppedReading] = []
        var filtered = results

        for eye: Eye in [.right, .left] {
            let perPhoto: [(photoIndex: Int, avg: Double, readings: [RawReading])] = results.compactMap { result in
                guard let section = eye == .right ? result.rightEye : result.leftEye else { return nil }
                let plausibles = section.readings.filter { ReadingPlausibility.isPlausibleSPH($0.sph) }
                guard !plausibles.isEmpty else { return nil }
                let avg = plausibles.map(\.sph).reduce(0, +) / Double(plausibles.count)
                return (result.sourcePhotoIndex, avg, plausibles)
            }
            guard perPhoto.count >= 3 else { continue }

            for candidate in perPhoto {
                let others = perPhoto.filter { $0.photoIndex != candidate.photoIndex }
                let othersAvgs = others.map(\.avg)
                let majorityAvg = othersAvgs.reduce(0, +) / Double(othersAvgs.count)
                let othersSpread = (othersAvgs.max() ?? 0) - (othersAvgs.min() ?? 0)
                let deviation = abs(candidate.avg - majorityAvg)

                guard othersSpread <= ConsistencyValidator.sphSpreadThreshold,
                      deviation > ConsistencyValidator.outlierDeviationThreshold else {
                    continue
                }

                for reading in candidate.readings {
                    let reason = "SPH \(formatSigned(reading.sph)) differs from majority \(formatSigned(majorityAvg)) by \(String(format: "%.2f", abs(reading.sph - majorityAvg))) D"
                    dropped.append(DroppedReading(
                        reading: reading,
                        photoIndex: candidate.photoIndex,
                        eye: eye,
                        reason: reason
                    ))
                }
                filtered = stripEyeReadings(from: filtered, photoIndex: candidate.photoIndex, eye: eye)
            }
        }

        return (filtered, dropped)
    }

    private func stripEyeReadings(from results: [PrintoutResult], photoIndex: Int, eye: Eye) -> [PrintoutResult] {
        results.map { result in
            guard result.sourcePhotoIndex == photoIndex else { return result }
            return PrintoutResult(
                rightEye: eye == .right ? nil : result.rightEye,
                leftEye:  eye == .left  ? nil : result.leftEye,
                pd: result.pd,
                machineType: result.machineType,
                sourcePhotoIndex: result.sourcePhotoIndex,
                rawText: result.rawText,
                handheldStarConfidenceRight: result.handheldStarConfidenceRight,
                handheldStarConfidenceLeft: result.handheldStarConfidenceLeft
            )
        }
    }

    private func allSPHs(results: [PrintoutResult], eye: Eye) -> [Double] {
        results.compactMap { eye == .right ? $0.rightEye : $0.leftEye }
            .flatMap { $0.readings.map(\.sph) }
            .filter { ReadingPlausibility.isPlausibleSPH($0) }
    }

    private func formatSigned(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))"
    }
}
