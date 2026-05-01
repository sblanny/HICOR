import Foundation

// Phase 5 orchestrator per MIKE_RX_PROCEDURE.md §Phase 5 Priority Order.
//
// Composes the per-step services (CrossPrintoutAggregator, MachineAvgValidator,
// DiopterRounder, AnisometropiaChecker, TierAssigner, PDAggregator) into a
// single PrescriptionCalculationOutcome. Clinical gates from §3 that weren't
// enforced upstream by ConsistencyValidator are emitted here as
// insufficientReadings flags — the UI (Task 11) reads the reason to tell the
// volunteer which additional captures are needed.
//
// Upstream ConsistencyValidator drops stay on the outcome as a distinct field
// from Phase 5's own drops so the UI can label each category (operator
// transparency principle, CLAUDE.md).
struct PrescriptionCalculationOutcome: Equatable {
    let rightEye: FinalPrescription?
    let leftEye: FinalPrescription?
    let overallTier: DispensingTier
    let clinicalFlags: [ClinicalFlag]
    let pd: PDAggregator.Aggregate
    let upstreamDroppedOutliers: [ConsistencyValidator.DroppedReading]
}

enum PrescriptionCalculator {

    static func calculate(
        printouts: [PrintoutResult],
        upstreamDroppedOutliers: [ConsistencyValidator.DroppedReading]
    ) -> PrescriptionCalculationOutcome {
        let allRawReadings = printouts.flatMap { printout -> [RawReading] in
            var out: [RawReading] = []
            if let r = printout.rightEye { out.append(contentsOf: r.readings) }
            if let l = printout.leftEye  { out.append(contentsOf: l.readings) }
            return out
        }

        var flags: [ClinicalFlag] = []

        let rightResult = computeEye(
            .right,
            allRaw: allRawReadings,
            printouts: printouts,
            flags: &flags
        )
        let leftResult = computeEye(
            .left,
            allRaw: allRawReadings,
            printouts: printouts,
            flags: &flags
        )

        // §8 Anisometropia. Only evaluated when both eyes produced a value.
        if let r = rightResult, let l = leftResult {
            let decision = AnisometropiaChecker.check(
                rightSph: r.sph,
                leftSph: l.sph,
                printoutCount: printouts.count
            )
            switch decision {
            case .normal:
                break
            case .sameSignAdvisory(let diff):
                flags.append(.anisometropiaAdvisory(diffDiopters: diff))
            case .sameSignReferOut(let diff):
                flags.append(.anisometropiaReferOut(diffDiopters: diff))
            case .antimetropiaDispense(let lowestAbs):
                flags.append(.antimetropiaDispense(lowestAbsEye: lowestAbs))
            case .antimetropiaReferOut:
                flags.append(.antimetropiaReferOut)
            }
        }

        // §3 Clinical gates — minimum-printouts requirements not enforced upstream.
        appendClinicalGateFlags(
            rightSph: rightResult?.sph,
            leftSph:  leftResult?.sph,
            printoutCount: printouts.count,
            flags: &flags
        )

        // §7 Overall tier — max severity across per-eye tiers. A nil eye means
        // we couldn't compute anything for that eye; fall back to the other
        // eye's tier rather than adding another ad-hoc state.
        let overall: DispensingTier = {
            switch (rightResult?.tier, leftResult?.tier) {
            case let (.some(r), .some(l)):
                return TierAssigner.assignOverallTier(right: r, left: l)
            case let (.some(r), nil):
                return r
            case let (nil, .some(l)):
                return l
            case (nil, nil):
                return .tier1Normal
            }
        }()

        // Tier-0 symptom-check flag only fires when BOTH eyes individually
        // qualify — matching §7's "asymmetric Tier 0 dispenses" rule. Emitted
        // once per patient because the symptom check itself is patient-level
        // (three questions asked once, not per eye).
        if rightResult?.tier == .tier0NoGlassesNeeded && leftResult?.tier == .tier0NoGlassesNeeded {
            flags.append(.tier0SymptomCheckRequired)
        }

        // §9 PD aggregation.
        let pds = printouts.compactMap { $0.pd }
        let pdAggregate = PDAggregator.aggregate(pds: pds)
        if pdAggregate.requiresManualMeasurement {
            flags.append(.pdMeasurementRequired(spreadMm: pdAggregate.spreadMm))
        }

        let rightFinal = rightResult.map {
            finalize(eye: .right, computed: $0, overallTier: overall)
        }
        let leftFinal = leftResult.map {
            finalize(eye: .left, computed: $0, overallTier: overall)
        }

        return PrescriptionCalculationOutcome(
            rightEye: rightFinal,
            leftEye: leftFinal,
            overallTier: overall,
            clinicalFlags: flags,
            pd: pdAggregate,
            upstreamDroppedOutliers: upstreamDroppedOutliers
        )
    }

    // MARK: - Per-eye pipeline

    private struct ComputedEye {
        let eye: Eye
        let sph: Double
        let cyl: Double
        let ax: Int
        let source: PrescriptionSource
        let acceptedReadings: [RawReading]
        let phase5Dropped: [ConsistencyValidator.DroppedReading]
        let machineAvgUsed: Bool
        let tier: DispensingTier
        let allSphOnly: Bool
        let allRawSphs: [Double]
    }

    private static func computeEye(
        _ eye: Eye,
        allRaw: [RawReading],
        printouts: [PrintoutResult],
        flags: inout [ClinicalFlag]
    ) -> ComputedEye? {
        let eyeRaw = allRaw.filter { $0.eye == eye }
        guard !eyeRaw.isEmpty else { return nil }

        // §4: trust the machine AVG by default and validate it against the
        // UNFILTERED raw spherical equivalent. Outlier rejection runs only when
        // that comparison fails — running it first would let a bad in-printout
        // reading be silently dropped and a contaminated machine AVG accepted
        // because it matches the cleaned M.
        let rawM = rawMeanM(eyeRaw)

        let machineAvg = aggregateMachineAvgs(printouts: printouts, eye: eye)
        let useMachineAvg: Bool
        if let avg = machineAvg {
            let synthetic = EyeReading(
                id: UUID(),
                eye: eye,
                readings: [],
                machineAvgSPH: avg.sph,
                machineAvgCYL: avg.cyl,
                machineAvgAX: avg.ax,
                sourcePhotoIndex: 0,
                machineType: .desktop
            )
            useMachineAvg = MachineAvgValidator.validate(
                eyeReading: synthetic,
                computedM: rawM
            ) == .useMachineAvg
        } else {
            useMachineAvg = false
        }

        let rawSph: Double
        let rawCyl: Double
        let rawAx: Int
        let source: PrescriptionSource
        let acceptedReadings: [RawReading]
        let phase5Dropped: [ConsistencyValidator.DroppedReading]

        if useMachineAvg, let avg = machineAvg {
            rawSph = avg.sph
            rawCyl = avg.cyl
            rawAx = avg.ax
            source = .machineAvgValidated
            acceptedReadings = eyeRaw
            phase5Dropped = []
        } else {
            // AVG rejected (or absent). Now drop outliers and recompute.
            let aggregate = CrossPrintoutAggregator.aggregate(readings: eyeRaw, for: eye)

            // §4.5 CYL caveat. When |computed CYL| > 1.00, prefer the
            // most-negative raw SPH reading — aggregated SPH is gentler than
            // what Mike's clinical experience says is correct at this CYL.
            let preferMostNegative = MachineAvgValidator
                .shouldPreferMostNegativeSph(forComputedCyl: aggregate.cyl)
            let chosenSph: Double
            if preferMostNegative, let mostNeg = eyeRaw.map(\.sph).min() {
                chosenSph = mostNeg
            } else {
                chosenSph = aggregate.sph
            }
            rawSph = chosenSph
            rawCyl = aggregate.cyl
            rawAx = aggregate.ax
            source = aggregate.droppedOutliers.isEmpty
                ? .recomputedViaPowerVector
                : .recomputedWithOutliersDropped
            acceptedReadings = aggregate.usedReadings
            phase5Dropped = aggregate.droppedOutliers
        }

        let roundedSph = DiopterRounder.roundSph(rawSph, forCyl: rawCyl)
        // §6: CYL tie direction is per-eye, driven by this eye's own rounded SPH magnitude.
        let roundedCyl = DiopterRounder.roundCyl(rawCyl, eyeSphMagnitude: abs(roundedSph))
        let roundedAx = DiopterRounder.roundAx(Double(rawAx))

        let perEyeTier = TierAssigner.assignPerEyeTier(sph: roundedSph, cyl: roundedCyl)

        // Per-eye inventory / medical flags — attach to the flag list here so
        // the caller's flag ordering mirrors pipeline order.
        if abs(roundedSph) > Constants.sphMedicalConcernMin {
            flags.append(.medicalConcern(eye: eye, value: roundedSph))
        } else if perEyeTier == .tier3DoNotDispense || perEyeTier == .tier2StretchWithNotification {
            if abs(roundedSph) > Constants.sphTier1Max {
                flags.append(.sphExceedsInventory(eye: eye, value: roundedSph, tier: perEyeTier))
            }
            if abs(roundedCyl) > Constants.cylTier1Max {
                flags.append(.cylExceedsInventory(eye: eye, value: roundedCyl, tier: perEyeTier))
            }
        }

        let allSphOnly = eyeRaw.allSatisfy(\.isSphOnly)
        if allSphOnly {
            flags.append(.sphOnlyReadings(eye: eye, count: eyeRaw.count))
        }

        return ComputedEye(
            eye: eye,
            sph: roundedSph,
            cyl: allSphOnly ? 0.0 : roundedCyl,
            ax: allSphOnly ? 180 : roundedAx,
            source: source,
            acceptedReadings: acceptedReadings,
            phase5Dropped: phase5Dropped,
            machineAvgUsed: useMachineAvg,
            tier: perEyeTier,
            allSphOnly: allSphOnly,
            allRawSphs: eyeRaw.map(\.sph)
        )
    }

    // Mean spherical equivalent across all unfiltered readings. SPH-only
    // readings contribute SPH as M (CYL placeholder excluded), matching
    // CrossPrintoutAggregator.effectiveM.
    private static func rawMeanM(_ readings: [RawReading]) -> Double {
        guard !readings.isEmpty else { return 0 }
        let sum = readings.reduce(0.0) { acc, r in
            acc + PowerVector.toM(sph: r.sph, cyl: r.isSphOnly ? 0 : r.cyl)
        }
        return sum / Double(readings.count)
    }

    // MARK: - Machine AVG aggregation

    private static func aggregateMachineAvgs(
        printouts: [PrintoutResult],
        eye: Eye
    ) -> (sph: Double, cyl: Double, ax: Int)? {
        let readings: [EyeReading] = printouts.compactMap { eye == .right ? $0.rightEye : $0.leftEye }
        let sphs = readings.compactMap(\.machineAvgSPH)
        let cyls = readings.compactMap(\.machineAvgCYL)
        let axes = readings.compactMap(\.machineAvgAX)
        guard !sphs.isEmpty, !cyls.isEmpty else { return nil }
        let meanSph = sphs.reduce(0, +) / Double(sphs.count)
        let meanCyl = cyls.reduce(0, +) / Double(cyls.count)
        let meanM = PowerVector.toM(sph: meanSph, cyl: meanCyl)
        // Average axis through Thibos vectors to respect circularity.
        let ax: Int
        if axes.isEmpty {
            ax = 180
        } else {
            let j0s = zip(cyls, axes).map { PowerVector.toJ0(cyl: $0.0, axDegrees: $0.1) }
            let j45s = zip(cyls, axes).map { PowerVector.toJ45(cyl: $0.0, axDegrees: $0.1) }
            let mJ0 = j0s.reduce(0, +) / Double(j0s.count)
            let mJ45 = j45s.reduce(0, +) / Double(j45s.count)
            let reconstructed = PowerVector.reconstruct(m: meanM, j0: mJ0, j45: mJ45)
            ax = reconstructed.ax
        }
        return (meanSph, meanCyl, ax)
    }

    // MARK: - Clinical gates (§3)

    private static func appendClinicalGateFlags(
        rightSph: Double?,
        leftSph: Double?,
        printoutCount: Int,
        flags: inout [ClinicalFlag]
    ) {
        // (a) antimetropia needs 4 printouts
        if let r = rightSph, let l = leftSph {
            let isAntimetropia = (r > 0 && l < 0) || (r < 0 && l > 0)
            if isAntimetropia && printoutCount < Constants.antimetropiaMinimumPrintouts {
                flags.append(.insufficientReadings(eye: .right, count: printoutCount, reason: .antimetropiaNeedsFour))
            }

            // (b) R/L SPH diff > 3.00 needs ≥3 printouts. Same-sign gets a
            // sign-specific reason — §8 says "take 3 readings, look for <3 D
            // option, otherwise refer out", so the operator's next step is
            // capture-then-recheck rather than the generic large-diff banner
            // that mixed-sign cases use.
            let diff = abs(r - l)
            if diff > Constants.rlDiffTriggersMin3 && printoutCount < 3 {
                let mixedSign = (r > 0 && l < 0) || (r < 0 && l > 0)
                let reason: InsufficientReadingsReason = mixedSign
                    ? .rlSphDifferenceExceedsThree(diff: diff)
                    : .sameSignAnisometropiaNeedsThird
                flags.append(.insufficientReadings(
                    eye: .right,
                    count: printoutCount,
                    reason: reason
                ))
            }

            // (c) one eye near plano (±1.00) AND other over ±5.00 → needs ≥3
            let rPlanoLHigh = abs(r) <= 1.00 && abs(l) > Constants.onePlanoOtherHighTrigger
            let lPlanoRHigh = abs(l) <= 1.00 && abs(r) > Constants.onePlanoOtherHighTrigger
            if (rPlanoLHigh || lPlanoRHigh) && printoutCount < 3 {
                let eye: Eye = rPlanoLHigh ? .left : .right
                flags.append(.insufficientReadings(eye: eye, count: printoutCount, reason: .onePlanoOtherHighSph))
            }
        }

        // (d) R or L SPH over ±10.00 → needs ≥3
        for (eye, sph) in [(Eye.right, rightSph), (Eye.left, leftSph)] {
            guard let s = sph else { continue }
            if abs(s) > Constants.highSphTrigger && printoutCount < 3 {
                flags.append(.insufficientReadings(eye: eye, count: printoutCount, reason: .highSphOverTen))
            }
        }
    }

    // MARK: - Finalize

    private static func finalize(
        eye: Eye,
        computed: ComputedEye,
        overallTier: DispensingTier
    ) -> FinalPrescription {
        FinalPrescription(
            eye: eye,
            sph: computed.sph,
            cyl: computed.cyl,
            ax: computed.ax,
            source: computed.source,
            acceptedReadings: computed.acceptedReadings,
            phase5DroppedOutliers: computed.phase5Dropped,
            machineAvgUsed: computed.machineAvgUsed,
            dispensingTier: computed.tier,
            tierMessage: tierMessage(for: computed.tier)
        )
    }

    private static func tierMessage(for tier: DispensingTier) -> String? {
        switch tier {
        case .tier0NoGlassesNeeded, .tier1Normal:
            return nil
        case .tier2StretchWithNotification:
            return "Patient notification required: This prescription is at the edge of our available lens range. Inform the patient their glasses may not fully correct their vision."
        case .tier3DoNotDispense:
            return "Prescription exceeds dispensable range. Do not issue glasses. Refer to professional care."
        case .tier4MedicalConcern:
            return "Medical concern: Prescription over ±12.00 D may indicate cataracts or other eye conditions requiring professional evaluation. Do not dispense. Refer to medical care."
        }
    }
}
