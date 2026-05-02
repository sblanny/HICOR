import Foundation

// Cross-printout aggregation via Thibos M/J0/J45 medians + k×MAD outlier
// rejection + recomputed means of survivors. See MIKE_RX_PROCEDURE.md §1
// (agreement thresholds — different layer in ConsistencyValidator), §5
// (outlier rejection / Phase 5), and §10 (SPH-only readings).
//
// Algorithm:
//   1. Filter readings to the requested eye.
//   2. If fewer than outlierRejectionMinSurvivors readings, skip rejection
//      and average all readings (no clinical basis to identify an outlier
//      without a majority anchor — ConsistencyValidator gates 2-printout
//      disagreement at Layer 1).
//   3. Otherwise, compute medians on power-vector components: M (all
//      readings — sphOnly included), J0 / J45 (full readings only — sphOnly
//      excluded from cyl/axis math per §10).
//   4. Compute MAD per component (median of absolute deviations from median),
//      floored at outlierRejectionMadFloor so identical readings don't
//      collapse the tolerance window to zero.
//   5. Drop a reading when its M deviation exceeds k×MAD on M, OR exceeds the
//      ANSI 1.00 D hard floor on M, OR (when full) its J0 / J45 deviation
//      exceeds k×MAD on the respective component. Power-vector decomposition
//      handles axis circularity automatically (J0/J45 are continuous; near-180°
//      wrap is implicit).
//   6. Survivor-majority check: keep drops only if a strict majority of
//      input readings survived. Otherwise retain all readings and surface
//      the spread to the operator via a readingsVaryWidely flag (consumed
//      by PrescriptionCalculator).
//   7. Recompute MEAN M / J0 / J45 on survivors and reconstruct (sph, cyl, ax).
enum CrossPrintoutAggregator {

    struct AggregatedReading: Equatable {
        let sph: Double
        let cyl: Double
        let ax: Int
        let usedReadings: [RawReading]
        let droppedOutliers: [ConsistencyValidator.DroppedReading]
        // True when MAD rejection would have left less than a strict majority
        // of input readings surviving. Survivor-majority check retains all
        // readings and surfaces the spread via .readingsVaryWidely.
        let readingsVaryWidely: Bool
    }

    static func aggregate(readings: [RawReading], for eye: Eye) -> AggregatedReading {
        let eyeReadings = readings.filter { $0.eye == eye }
        guard !eyeReadings.isEmpty else {
            return AggregatedReading(
                sph: 0, cyl: 0, ax: 180,
                usedReadings: [], droppedOutliers: [], readingsVaryWidely: false
            )
        }

        // Single reading: no averaging, no outlier detection.
        if eyeReadings.count == 1 {
            let r = eyeReadings[0]
            return AggregatedReading(
                sph: r.sph,
                cyl: r.isSphOnly ? 0 : r.cyl,
                ax: r.isSphOnly ? 180 : r.ax,
                usedReadings: eyeReadings,
                droppedOutliers: [],
                readingsVaryWidely: false
            )
        }

        // Below the rejection floor (count < 3): no clinical basis to identify
        // an outlier without a majority anchor. ConsistencyValidator already
        // gated 2-printout disagreement at Layer 1, so trust its decision and
        // just compute the mean. This also avoids divide-by-zero / NaN if
        // ANSI floor would otherwise drop all readings.
        let working: [RawReading]
        let reportedDropped: [ConsistencyValidator.DroppedReading]
        let readingsVaryWidely: Bool
        if eyeReadings.count < Constants.outlierRejectionMinSurvivors {
            working = eyeReadings
            reportedDropped = []
            readingsVaryWidely = false
        } else {
            let fullReadings = eyeReadings.filter { !$0.isSphOnly }

            // Medians on power-vector components (pre-drop baseline).
            let allMs = eyeReadings.map { effectiveM($0) }
            let medianM = median(allMs)
            let medianJ0: Double
            let medianJ45: Double
            if fullReadings.isEmpty {
                medianJ0 = 0
                medianJ45 = 0
            } else {
                let j0s = fullReadings.map { PowerVector.toJ0(cyl: $0.cyl, axDegrees: $0.ax) }
                let j45s = fullReadings.map { PowerVector.toJ45(cyl: $0.cyl, axDegrees: $0.ax) }
                medianJ0 = median(j0s)
                medianJ45 = median(j45s)
            }

            // MAD per component, floored. Empty fullReadings → infinite
            // J-thresholds (those checks are unreachable for sphOnly anyway).
            let madM: Double = max(
                median(eyeReadings.map { abs(effectiveM($0) - medianM) }),
                Constants.outlierRejectionMadFloor
            )
            let madJ0: Double
            let madJ45: Double
            if fullReadings.isEmpty {
                madJ0 = .infinity
                madJ45 = .infinity
            } else {
                let j0Devs = fullReadings.map { abs(PowerVector.toJ0(cyl: $0.cyl, axDegrees: $0.ax) - medianJ0) }
                let j45Devs = fullReadings.map { abs(PowerVector.toJ45(cyl: $0.cyl, axDegrees: $0.ax) - medianJ45) }
                madJ0 = max(median(j0Devs), Constants.outlierRejectionMadFloor)
                madJ45 = max(median(j45Devs), Constants.outlierRejectionMadFloor)
            }

            let k = Constants.outlierRejectionK
            let thresholdM = k * madM
            let thresholdJ0 = k * madJ0
            let thresholdJ45 = k * madJ45
            let ansiFloor = Constants.outlierRejectionAnsiHardFloorM

            var survivors: [RawReading] = []
            var dropped: [ConsistencyValidator.DroppedReading] = []
            for r in eyeReadings {
                let m = effectiveM(r)
                let devM = abs(m - medianM)

                // 1. M-MAD check (adaptive)
                if devM > thresholdM {
                    dropped.append(.init(
                        reading: r, photoIndex: r.sourcePhotoIndex, eye: eye,
                        reason: String(
                            format: "Phase 5: spherical equivalent %.2f D differs from median %.2f D by %.2f D (3×MAD threshold %.2f D)",
                            m, medianM, devM, thresholdM
                        )
                    ))
                    continue
                }
                // 2. ANSI hard floor on M (independent safety net for sign-flip outliers)
                if devM > ansiFloor {
                    dropped.append(.init(
                        reading: r, photoIndex: r.sourcePhotoIndex, eye: eye,
                        reason: String(
                            format: "Phase 5: spherical equivalent %.2f D differs from median %.2f D by more than %.2f D (ANSI hard floor)",
                            m, medianM, ansiFloor
                        )
                    ))
                    continue
                }
                // 3. J0 / J45 MAD checks (full readings only)
                if !r.isSphOnly && !fullReadings.isEmpty {
                    let j0 = PowerVector.toJ0(cyl: r.cyl, axDegrees: r.ax)
                    let j45 = PowerVector.toJ45(cyl: r.cyl, axDegrees: r.ax)
                    let devJ0 = abs(j0 - medianJ0)
                    let devJ45 = abs(j45 - medianJ45)
                    if devJ0 > thresholdJ0 {
                        dropped.append(.init(
                            reading: r, photoIndex: r.sourcePhotoIndex, eye: eye,
                            reason: String(
                                format: "Phase 5: power-vector J0 %.3f differs from median %.3f by %.3f (3×MAD threshold %.3f) — likely cyl/axis outlier",
                                j0, medianJ0, devJ0, thresholdJ0
                            )
                        ))
                        continue
                    }
                    if devJ45 > thresholdJ45 {
                        dropped.append(.init(
                            reading: r, photoIndex: r.sourcePhotoIndex, eye: eye,
                            reason: String(
                                format: "Phase 5: power-vector J45 %.3f differs from median %.3f by %.3f (3×MAD threshold %.3f) — likely cyl/axis outlier",
                                j45, medianJ45, devJ45, thresholdJ45
                            )
                        ))
                        continue
                    }
                }
                survivors.append(r)
            }

            // Survivor-majority check: keep drops only if a strict majority of
            // input readings survived. With at-or-below half surviving, the
            // rejection set is too aggressive — retain all and surface the
            // spread to the operator via readingsVaryWidely.
            //
            // Examples:
            //   3 in, 1 drop → 2 of 3 (majority) → drops accepted
            //   4 in, 2 drops → 2 of 4 (not majority) → all retained + warn
            //   9 in, 1 drop → 8 of 9 (majority) → drops accepted
            //
            // A fixed floor (e.g., "≥3 survivors") would prevent any drop from
            // a 3-reading input, contradicting the clinical intent of the
            // Day-1 axis-120 fix.
            if survivors.count * 2 > eyeReadings.count {
                working = survivors
                reportedDropped = dropped
                readingsVaryWidely = false
            } else {
                working = eyeReadings
                reportedDropped = []
                readingsVaryWidely = true
            }
        }

        // Recompute means on the working set.
        let meanM = working.map { effectiveM($0) }.reduce(0, +) / Double(working.count)
        let fullSurvivors = working.filter { !$0.isSphOnly }

        if fullSurvivors.isEmpty {
            return AggregatedReading(
                sph: meanM, cyl: 0, ax: 180,
                usedReadings: working,
                droppedOutliers: reportedDropped,
                readingsVaryWidely: readingsVaryWidely
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
            droppedOutliers: reportedDropped,
            readingsVaryWidely: readingsVaryWidely
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
}
