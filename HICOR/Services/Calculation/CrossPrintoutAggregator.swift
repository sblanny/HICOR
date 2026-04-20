import Foundation

// Cross-printout aggregation via Thibos M/J0/J45 medians + outlier rejection +
// recomputed means of survivors. See MIKE_RX_PROCEDURE.md §1 (agreement
// thresholds), §2 (axis sliding scale), §10 (SPH-only readings), and Phase 5
// Priority step 2 (cross-printout aggregation).
//
// Algorithm:
//   1. Filter readings to the requested eye.
//   2. Compute median M (all readings — sphOnly included), median J0/J45
//      (full readings only — sphOnly excluded from cyl/axis math per §10).
//   3. Flag outliers:
//      - M deviates from median M by > sphAgreementThreshold (1.00 D)
//      - cyl deviates from median cyl-from-vectors by > cylAgreementThreshold (0.50 D)
//      - axis deviates (circularly) from median axis by > sliding-scale tolerance
//   4. Drop outliers, recompute MEAN M/J0/J45 on survivors.
//   5. Reconstruct final (sph, cyl, ax).
enum CrossPrintoutAggregator {

    struct AggregatedReading: Equatable {
        let sph: Double
        let cyl: Double
        let ax: Int
        let usedReadings: [RawReading]
        let droppedOutliers: [ConsistencyValidator.DroppedReading]
    }

    static func aggregate(readings: [RawReading], for eye: Eye) -> AggregatedReading {
        let eyeReadings = readings.filter { $0.eye == eye }
        guard !eyeReadings.isEmpty else {
            return AggregatedReading(sph: 0, cyl: 0, ax: 180, usedReadings: [], droppedOutliers: [])
        }

        // Single reading: no averaging, no outlier detection.
        if eyeReadings.count == 1 {
            let r = eyeReadings[0]
            return AggregatedReading(
                sph: r.sph,
                cyl: r.isSphOnly ? 0 : r.cyl,
                ax: r.isSphOnly ? 180 : r.ax,
                usedReadings: eyeReadings,
                droppedOutliers: []
            )
        }

        let fullReadings = eyeReadings.filter { !$0.isSphOnly }

        // Medians (pre-drop baseline for outlier detection).
        let allMs = eyeReadings.map { effectiveM($0) }
        let medianM = median(allMs)
        let (medianCylFromVectors, medianAxis): (Double, Int)
        if fullReadings.isEmpty {
            medianCylFromVectors = 0
            medianAxis = 180
        } else {
            let j0s = fullReadings.map { PowerVector.toJ0(cyl: $0.cyl, axDegrees: $0.ax) }
            let j45s = fullReadings.map { PowerVector.toJ45(cyl: $0.cyl, axDegrees: $0.ax) }
            let mJ0 = median(j0s)
            let mJ45 = median(j45s)
            medianCylFromVectors = -2.0 * sqrt(mJ0 * mJ0 + mJ45 * mJ45)
            medianAxis = axisFromVectors(j0: mJ0, j45: mJ45)
        }

        let axisTolerance = axisToleranceForCyl(medianCylFromVectors)

        // Outlier detection.
        var survivors: [RawReading] = []
        var dropped: [ConsistencyValidator.DroppedReading] = []
        for r in eyeReadings {
            let m = effectiveM(r)
            if abs(m - medianM) > Constants.sphAgreementThreshold {
                dropped.append(.init(
                    reading: r,
                    photoIndex: r.sourcePhotoIndex,
                    eye: eye,
                    reason: String(
                        format: "Phase 5: spherical equivalent %.2f D differs from median %.2f D by more than %.2f D",
                        m, medianM, Constants.sphAgreementThreshold
                    )
                ))
                continue
            }
            if !r.isSphOnly && abs(r.cyl - medianCylFromVectors) > Constants.cylAgreementThreshold {
                dropped.append(.init(
                    reading: r,
                    photoIndex: r.sourcePhotoIndex,
                    eye: eye,
                    reason: String(
                        format: "Phase 5: cylinder %.2f D differs from median %.2f D by more than %.2f D",
                        r.cyl, medianCylFromVectors, Constants.cylAgreementThreshold
                    )
                ))
                continue
            }
            if !r.isSphOnly && !fullReadings.isEmpty {
                let axDiff = circularAxisDiff(r.ax, medianAxis)
                if Double(axDiff) > axisTolerance {
                    dropped.append(.init(
                        reading: r,
                        photoIndex: r.sourcePhotoIndex,
                        eye: eye,
                        reason: String(
                            format: "Phase 5: axis %d° differs from median %d° by %d° (tolerance %.0f°)",
                            r.ax, medianAxis, axDiff, axisTolerance
                        )
                    ))
                    continue
                }
            }
            survivors.append(r)
        }

        // Degenerate edge case: all readings flagged. Fall back to the original
        // set (ConsistencyValidator already gated the session; refusing to
        // output anything would lose information the operator still needs to
        // see).
        let working = survivors.isEmpty ? eyeReadings : survivors
        let reportedDropped = survivors.isEmpty ? [] : dropped

        // Recompute means on survivors.
        let meanM = working.map { effectiveM($0) }.reduce(0, +) / Double(working.count)
        let fullSurvivors = working.filter { !$0.isSphOnly }

        if fullSurvivors.isEmpty {
            return AggregatedReading(
                sph: meanM,
                cyl: 0,
                ax: 180,
                usedReadings: working,
                droppedOutliers: reportedDropped
            )
        }

        let meanJ0 = fullSurvivors.map { PowerVector.toJ0(cyl: $0.cyl, axDegrees: $0.ax) }
            .reduce(0, +) / Double(fullSurvivors.count)
        let meanJ45 = fullSurvivors.map { PowerVector.toJ45(cyl: $0.cyl, axDegrees: $0.ax) }
            .reduce(0, +) / Double(fullSurvivors.count)
        let final = PowerVector.reconstruct(m: meanM, j0: meanJ0, j45: meanJ45)
        return AggregatedReading(
            sph: final.sph,
            cyl: final.cyl,
            ax: final.ax,
            usedReadings: working,
            droppedOutliers: reportedDropped
        )
    }

    // MARK: - Helpers

    // M for a reading; sphOnly contributes sph as M (CYL=0 placeholder
    // excluded from cyl math per §10 but SPH still averages).
    private static func effectiveM(_ r: RawReading) -> Double {
        PowerVector.toM(sph: r.sph, cyl: r.isSphOnly ? 0.0 : r.cyl)
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    private static func axisFromVectors(j0: Double, j45: Double) -> Int {
        let mag = sqrt(j0 * j0 + j45 * j45)
        if mag < 1e-9 { return 180 }
        let rad = atan2(j45, j0) / 2.0
        var deg = Int((rad * 180.0 / .pi).rounded())
        while deg <= 0 { deg += 180 }
        while deg > 180 { deg -= 180 }
        return deg
    }

    private static func circularAxisDiff(_ a: Int, _ b: Int) -> Int {
        let raw = abs(a - b) % 180
        return min(raw, 180 - raw)
    }

    // §2 sliding scale by |CYL|.
    private static func axisToleranceForCyl(_ cyl: Double) -> Double {
        let mag = abs(cyl)
        if mag <= 0.25 { return Constants.axisToleranceCylUnder025 }
        if mag <= 0.50 { return Constants.axisToleranceCyl025To050 }
        if mag <= 1.00 { return Constants.axisToleranceCyl050To100 }
        if mag <= 2.00 { return Constants.axisToleranceCyl100To200 }
        return Constants.axisToleranceCylOver200
    }
}
