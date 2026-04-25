import Foundation

struct ConsistencyValidator {

    enum Result: Equatable {
        case consistent(droppedOutliers: [DroppedReading])
        case inconsistentAddPhoto(reason: String, currentCount: Int)
        case inconsistentEscalate(reason: String)
    }

    struct DroppedReading: Equatable, Codable {
        let reading: RawReading
        let photoIndex: Int
        let eye: Eye
        let reason: String
    }

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

        if let disagreement = pairwiseAgreementCheck(results: filteredResults) {
            return inconsistent(reason: disagreement, count: count)
        }

        for dropped in droppedOutliers {
            OCRLog.logger.info("Consistency dropped outlier eye=\(dropped.eye.rawValue, privacy: .public) photo=\(dropped.photoIndex) sph=\(dropped.reading.sph, format: .fixed(precision: 2)) reason=\(dropped.reason, privacy: .public)")
        }

        return .consistent(droppedOutliers: droppedOutliers)
    }

    private func inconsistent(reason: String, count: Int) -> Result {
        if count >= Constants.maxPrintoutsAllowed {
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

    // Per-printout AVG signal used for cross-printout agreement. Compares
    // each printout's representation of the eye (machine-printed AVG when
    // present, else mean of plausible raw readings). See MIKE_RX_PROCEDURE.md
    // §1 (SPH/CYL agreement thresholds), §2 (axis sliding scale), §4
    // (machine AVG line).
    private struct PerEyeAvg {
        let photoIndex: Int
        let sph: Double
        let cyl: Double?
        let ax: Int?
    }

    private func perEyeAvg(eye: Eye, in result: PrintoutResult) -> PerEyeAvg? {
        guard let section = eye == .right ? result.rightEye : result.leftEye else { return nil }

        let plausibleSphs = section.readings.map(\.sph).filter { ReadingPlausibility.isPlausibleSPH($0) }
        let sph: Double
        if let machineAvg = section.machineAvgSPH, ReadingPlausibility.isPlausibleSPH(machineAvg) {
            sph = machineAvg
        } else if !plausibleSphs.isEmpty {
            sph = plausibleSphs.reduce(0, +) / Double(plausibleSphs.count)
        } else {
            return nil
        }

        let plausibleCyls = section.readings
            .filter { !$0.isSphOnly }
            .map(\.cyl)
            .filter { ReadingPlausibility.isPlausibleCYL($0) }
        let cyl: Double?
        if let machineAvg = section.machineAvgCYL, ReadingPlausibility.isPlausibleCYL(machineAvg) {
            cyl = machineAvg
        } else if !plausibleCyls.isEmpty {
            cyl = plausibleCyls.reduce(0, +) / Double(plausibleCyls.count)
        } else {
            cyl = nil
        }

        // Axis is circular; arithmetic mean of raw axes is mathematically
        // wrong. Only trust the machine-printed AVG axis here. Phase 5's
        // CrossPrintoutAggregator handles axis math via Thibos vectors.
        let ax: Int? = section.machineAvgAX

        return PerEyeAvg(photoIndex: result.sourcePhotoIndex, sph: sph, cyl: cyl, ax: ax)
    }

    private func pairwiseAgreementCheck(results: [PrintoutResult]) -> String? {
        for eye: Eye in [.right, .left] {
            let avgs = results.compactMap { perEyeAvg(eye: eye, in: $0) }
            guard avgs.count >= 2 else { continue }

            for i in 0..<avgs.count {
                for j in (i + 1)..<avgs.count {
                    if let reason = compare(avgs[i], avgs[j], eye: eye) {
                        return reason
                    }
                }
            }
        }
        return nil
    }

    private func compare(_ a: PerEyeAvg, _ b: PerEyeAvg, eye: Eye) -> String? {
        let eyeLabel = eye == .right ? "Right" : "Left"

        let sphDiff = abs(a.sph - b.sph)
        if sphDiff > Constants.sphAgreementThreshold {
            return "\(eyeLabel) eye AVG sphere differs by \(String(format: "%.2f", sphDiff)) D between printouts"
        }

        if let aCyl = a.cyl, let bCyl = b.cyl {
            let cylDiff = abs(aCyl - bCyl)
            if cylDiff > Constants.cylAgreementThreshold {
                return "\(eyeLabel) eye AVG cylinder differs by \(String(format: "%.2f", cylDiff)) D between printouts"
            }
        }

        if let aAx = a.ax, let bAx = b.ax {
            // Plano CYL has no meaningful axis — when there's no astigmatism
            // to align, autorefractors emit a placeholder axis (typically
            // 180°) that varies arbitrarily between printouts of the same
            // eye. Comparing it triggers spurious disagreement banners. The
            // CYL agreement check above already pinned both printouts to 0;
            // skip the axis check when either side is plano.
            let aCyl = a.cyl ?? 0
            let bCyl = b.cyl ?? 0
            if aCyl != 0 && bCyl != 0 {
                let cylForTolerance = max(abs(aCyl), abs(bCyl))
                let tolerance = AxisMath.toleranceForCyl(cylForTolerance)
                let axDiff = AxisMath.circularDiff(aAx, bAx)
                if Double(axDiff) > tolerance {
                    return "\(eyeLabel) eye AVG axis differs by \(axDiff)° between printouts (tolerance \(Int(tolerance))°)"
                }
            }
        }

        return nil
    }

    // When 3+ photos exist and one printout's AVG signal clearly disagrees
    // with the majority, drop that printout's eye section but surface the
    // dropped readings so the operator can see what was excluded (clinical
    // principle: the app makes decisions, never hides them).
    private func removeMajorityOutliers(from results: [PrintoutResult]) -> (filtered: [PrintoutResult], dropped: [DroppedReading]) {
        var dropped: [DroppedReading] = []
        var filtered = results

        for eye: Eye in [.right, .left] {
            let avgs: [(avg: PerEyeAvg, readings: [RawReading])] = results.compactMap { result in
                guard let avg = perEyeAvg(eye: eye, in: result),
                      let section = eye == .right ? result.rightEye : result.leftEye else { return nil }
                return (avg, section.readings)
            }
            guard avgs.count >= 3 else { continue }

            for candidate in avgs {
                let others = avgs.filter { $0.avg.photoIndex != candidate.avg.photoIndex }

                if let reason = sphOutlierReason(candidate: candidate.avg, others: others.map(\.avg)) {
                    for reading in candidate.readings {
                        dropped.append(DroppedReading(
                            reading: reading,
                            photoIndex: candidate.avg.photoIndex,
                            eye: eye,
                            reason: reason
                        ))
                    }
                    filtered = stripEyeReadings(from: filtered, photoIndex: candidate.avg.photoIndex, eye: eye)
                    continue
                }

                if let reason = cylOutlierReason(candidate: candidate.avg, others: others.map(\.avg)) {
                    for reading in candidate.readings {
                        dropped.append(DroppedReading(
                            reading: reading,
                            photoIndex: candidate.avg.photoIndex,
                            eye: eye,
                            reason: reason
                        ))
                    }
                    filtered = stripEyeReadings(from: filtered, photoIndex: candidate.avg.photoIndex, eye: eye)
                }
            }
        }

        return (filtered, dropped)
    }

    private func sphOutlierReason(candidate: PerEyeAvg, others: [PerEyeAvg]) -> String? {
        let othersSphs = others.map(\.sph)
        guard !othersSphs.isEmpty else { return nil }
        let majoritySph = othersSphs.reduce(0, +) / Double(othersSphs.count)
        let othersSpread = (othersSphs.max() ?? 0) - (othersSphs.min() ?? 0)
        let deviation = abs(candidate.sph - majoritySph)
        guard othersSpread <= Constants.sphAgreementThreshold,
              deviation > Constants.sphAgreementThreshold else {
            return nil
        }
        return "SPH AVG \(DiopterFormatter.format(candidate.sph)) differs from majority \(DiopterFormatter.format(majoritySph)) by \(String(format: "%.2f", deviation)) D"
    }

    private func cylOutlierReason(candidate: PerEyeAvg, others: [PerEyeAvg]) -> String? {
        guard let candidateCyl = candidate.cyl else { return nil }
        let othersCyls = others.compactMap(\.cyl)
        guard othersCyls.count >= 2 else { return nil }
        let majorityCyl = othersCyls.reduce(0, +) / Double(othersCyls.count)
        let othersSpread = (othersCyls.max() ?? 0) - (othersCyls.min() ?? 0)
        let deviation = abs(candidateCyl - majorityCyl)
        guard othersSpread <= Constants.cylAgreementThreshold,
              deviation > Constants.cylAgreementThreshold else {
            return nil
        }
        return "CYL AVG \(DiopterFormatter.format(candidateCyl)) differs from majority \(DiopterFormatter.format(majorityCyl)) by \(String(format: "%.2f", deviation)) D"
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

}
