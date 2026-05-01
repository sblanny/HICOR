import XCTest
@testable import HICOR

final class PrescriptionCalculatorTests: XCTestCase {

    // MARK: - Happy path

    func testCalculate_twoMatchingPrintouts_bothEyesInNormalRange_tier1NoFlags() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.50, cyl: -0.75, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.50, cyl: -0.75, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])

        XCTAssertNotNil(outcome.rightEye)
        XCTAssertNotNil(outcome.leftEye)
        XCTAssertEqual(outcome.overallTier, .tier1Normal)
        XCTAssertEqual(outcome.rightEye?.sph ?? 0, -2.00, accuracy: 0.01)
        XCTAssertEqual(outcome.leftEye?.sph ?? 0, -1.50, accuracy: 0.01)
        XCTAssertTrue(
            outcome.clinicalFlags.allSatisfy {
                if case .pdMeasurementRequired = $0 { return false }
                return true
            }
        )
        XCTAssertEqual(outcome.pd.pd, 62.0)
    }

    // MARK: - Machine AVG trust path (§4)

    func testCalculate_machineAvgAgrees_sourcedFromMachineAvg() {
        // Machine AVG M = -2.50, computed M ≈ -2.50 — agreement within 0.50 D.
        let printouts = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 0)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 1)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: nil, pd: nil
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.rightEye?.source, .machineAvgValidated)
        XCTAssertTrue(outcome.rightEye?.machineAvgUsed ?? false)
    }

    func testCalculate_machineAvgDisagrees_sourcedFromRecomputed() {
        // Machine AVG M = -5.00, computed M ≈ -2.50 — disagreement > 0.50 D.
        let printouts = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 0)
                    ],
                    machineAvgSPH: -4.50, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 1)
                    ],
                    machineAvgSPH: -4.50, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: nil, pd: nil
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.rightEye?.source, .recomputedViaPowerVector)
        XCTAssertFalse(outcome.rightEye?.machineAvgUsed ?? true)
        XCTAssertEqual(outcome.rightEye?.sph ?? 0, -2.00, accuracy: 0.01)
    }

    func testCalculate_machineAvgRejected_outliersDroppedSourcedAccordingly() {
        // Three printouts. Raw readings: -2.00, -2.00, -5.00 (last is an
        // outlier). Synthetic machine AVG SPH ≈ -2.07 → machineM ≈ -2.07.
        // Unfiltered raw M = (-2.5 + -2.5 + -5.5) / 3 ≈ -3.50.
        // |machineM − rawM| ≈ 1.43 > 0.50 → recompute. Aggregator drops the
        // -5.00 outlier, source becomes recomputedWithOutliersDropped.
        let printouts = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 0)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 1)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 2,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -5.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 2)
                    ],
                    machineAvgSPH: -2.20, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 2, machineType: .desktop
                ),
                left: nil, pd: nil
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.rightEye?.source, .recomputedWithOutliersDropped)
        XCTAssertFalse(outcome.rightEye?.machineAvgUsed ?? true)
        let dropCount = outcome.rightEye?.phase5DroppedOutliers.count ?? 0
        XCTAssertGreaterThanOrEqual(dropCount, 1)
    }

    func testCalculate_rawOutlierInsidePrintout_machineAvgNoLongerSilentlyAccepted() {
        // Regression for the inverted-order bug. Raw: -2.00, -2.00, -5.00.
        // Per-printout machine AVGs cluster near -2.00 (one slightly pulled
        // by its outlier reading). Old order: aggregator dropped the -5.00
        // first, filtered M ≈ -2.50 matched synthetic AVG → AVG silently
        // accepted. New order: unfiltered raw M ≈ -3.50 is far from the
        // synthetic AVG → AVG rejected, fallback recomputes WITHOUT the
        // outlier, and the operator sees the dropped reading.
        let printouts = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 0)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 1)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 2,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -5.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 2)
                    ],
                    machineAvgSPH: -2.20, machineAvgCYL: -1.00, machineAvgAX: 90,
                    sourcePhotoIndex: 2, machineType: .desktop
                ),
                left: nil, pd: nil
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertNotEqual(outcome.rightEye?.source, .machineAvgValidated,
                          "AVG should have been rejected against unfiltered raw M, not silently accepted")
        XCTAssertEqual(outcome.rightEye?.source, .recomputedWithOutliersDropped)
    }

    func testCalculate_cylCaveatOnlyAppliesWhenAvgRejected() {
        // (a) AVG accepted, |CYL| > 1.00 → SPH from synthetic AVG, NO swap.
        let avgAccepted = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -1.50, cyl: -1.50, ax: 90, eye: .right, sourcePhotoIndex: 0)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.50, machineAvgAX: 90,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.50, cyl: -1.50, ax: 90, eye: .right, sourcePhotoIndex: 1)
                    ],
                    machineAvgSPH: -2.00, machineAvgCYL: -1.50, machineAvgAX: 90,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: nil, pd: nil
            )
        ]
        let acceptedOutcome = PrescriptionCalculator.calculate(printouts: avgAccepted, upstreamDroppedOutliers: [])
        XCTAssertEqual(acceptedOutcome.rightEye?.source, .machineAvgValidated)
        // SPH should come from synthetic AVG (-2.00), NOT swapped to most-negative raw (-2.50).
        XCTAssertEqual(acceptedOutcome.rightEye?.sph ?? 0, -2.00, accuracy: 0.01)

        // (b) AVG rejected, |CYL| > 1.00 → SPH swapped to most-negative raw.
        let avgRejected = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -1.50, cyl: -1.50, ax: 90, eye: .right, sourcePhotoIndex: 0)
                    ],
                    machineAvgSPH: -5.00, machineAvgCYL: -1.50, machineAvgAX: 90,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: nil, pd: nil
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.50, cyl: -1.50, ax: 90, eye: .right, sourcePhotoIndex: 1)
                    ],
                    machineAvgSPH: -5.00, machineAvgCYL: -1.50, machineAvgAX: 90,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: nil, pd: nil
            )
        ]
        let rejectedOutcome = PrescriptionCalculator.calculate(printouts: avgRejected, upstreamDroppedOutliers: [])
        XCTAssertNotEqual(rejectedOutcome.rightEye?.source, .machineAvgValidated)
        // |aggregate.cyl| = 1.50 > 1.00 → SPH swapped to min(-1.50, -2.50) = -2.50.
        XCTAssertEqual(rejectedOutcome.rightEye?.sph ?? 0, -2.50, accuracy: 0.01)
    }

    // MARK: - Tier assignment (§7)

    func testCalculate_bothEyesPlano_overallTier0_symptomCheckFlagOnce() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: 0.0, cyl: 0.0, ax: 180),
                left:  makeEyeReading(.left,  sph: 0.0, cyl: 0.0, ax: 180),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: 0.0, cyl: 0.0, ax: 180),
                left:  makeEyeReading(.left,  sph: 0.0, cyl: 0.0, ax: 180),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.overallTier, .tier0NoGlassesNeeded)
        let symptomFlags = outcome.clinicalFlags.filter {
            if case .tier0SymptomCheckRequired = $0 { return true }
            return false
        }
        XCTAssertEqual(symptomFlags.count, 1)
    }

    func testCalculate_asymmetricTier0_overallNotTier0_noSymptomFlag() {
        // R plano (would be Tier 0), L myope -3.00 (Tier 1). Overall Tier 1.
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: 0.0, cyl: 0.0, ax: 180),
                left:  makeEyeReading(.left,  sph: -3.00, cyl: -1.00, ax: 90),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: 0.0, cyl: 0.0, ax: 180),
                left:  makeEyeReading(.left,  sph: -3.00, cyl: -1.00, ax: 90),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.overallTier, .tier1Normal)
        XCTAssertTrue(outcome.clinicalFlags.allSatisfy {
            if case .tier0SymptomCheckRequired = $0 { return false }
            return true
        }, "asymmetric Tier 0 must not emit symptom-check flag")
    }

    func testCalculate_tier3_emitsReferOutTierAndFlag() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -9.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -9.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 2,
                right: makeEyeReading(.right, sph: -9.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.overallTier, .tier3DoNotDispense)
        let hasInventoryFlag = outcome.clinicalFlags.contains {
            if case .sphExceedsInventory(_, _, let tier) = $0, tier == .tier3DoNotDispense { return true }
            return false
        }
        XCTAssertTrue(hasInventoryFlag)
    }

    func testCalculate_tier4_emitsMedicalConcernFlag() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -13.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -13.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 2,
                right: makeEyeReading(.right, sph: -13.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.overallTier, .tier4MedicalConcern)
        let hasMedical = outcome.clinicalFlags.contains {
            if case .medicalConcern = $0 { return true }
            return false
        }
        XCTAssertTrue(hasMedical)
    }

    // MARK: - Anisometropia and clinical gates (§8, §3)

    func testCalculate_sameSignAdvisory_emitsAdvisoryFlag() {
        // R -2.00, L -4.50 → diff 2.50 → advisory
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -4.50, cyl: -1.00, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -4.50, cyl: -1.00, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasAdvisory = outcome.clinicalFlags.contains {
            if case .anisometropiaAdvisory(let diff) = $0 { return abs(diff - 2.50) < 0.01 }
            return false
        }
        XCTAssertTrue(hasAdvisory)
    }

    func testCalculate_antimetropiaWithThreePrintouts_emitsInsufficientReadingsFlag() {
        // Antimetropia (§3a) requires ≥4 printouts. Only 3 here.
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: 1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: 1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 2,
                right: makeEyeReading(.right, sph: 1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.00, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasInsufficient = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .antimetropiaNeedsFour = reason { return true }
            }
            return false
        }
        XCTAssertTrue(hasInsufficient, "<4 printouts with antimetropia must emit antimetropiaNeedsFour")
    }

    func testCalculate_antimetropiaWithFourPrintouts_noInsufficientFlag_dispenseFlag() {
        let printouts = (0..<4).map { i in
            makePrintout(
                photo: i,
                right: makeEyeReading(.right, sph: 1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -0.75, cyl: -0.50, ax: 85),
                pd: 62
            )
        }
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasInsufficient = outcome.clinicalFlags.contains {
            if case .insufficientReadings = $0 { return true }
            return false
        }
        XCTAssertFalse(hasInsufficient)
        let hasDispense = outcome.clinicalFlags.contains {
            if case .antimetropiaDispense = $0 { return true }
            return false
        }
        XCTAssertTrue(hasDispense)
    }

    func testCalculate_sameSignSphDiffOverThree_withTwoPrintouts_emitsSameSignNeedsThirdFlag_notReferOut() {
        // R -1.00, L -5.00 → diff 4.00 D, same sign. §8 with <3 printouts:
        // emit advisory + sameSignAnisometropiaNeedsThird; do NOT refer out.
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -5.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -5.00, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasNeedsThird = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .sameSignAnisometropiaNeedsThird = reason { return true }
            }
            return false
        }
        XCTAssertTrue(hasNeedsThird, "<3 printouts with same-sign diff > 3.00 must emit sameSignAnisometropiaNeedsThird")

        let hasAdvisory = outcome.clinicalFlags.contains {
            if case .anisometropiaAdvisory = $0 { return true }
            return false
        }
        XCTAssertTrue(hasAdvisory, "advisory should still fire alongside the needs-third flag")

        let hasReferOut = outcome.clinicalFlags.contains {
            if case .anisometropiaReferOut = $0 { return true }
            return false
        }
        XCTAssertFalse(hasReferOut, "<3 printouts must not refer out yet")
    }

    func testCalculate_sameSignSphDiffOverThree_withThreePrintouts_emitsReferOut_noNeedsThirdFlag() {
        // Three identical printouts, diff still > 3.00 → refer out, no
        // needs-third advisory.
        let printouts = (0..<3).map { i in
            makePrintout(
                photo: i,
                right: makeEyeReading(.right, sph: -1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -5.00, cyl: -0.50, ax: 85),
                pd: 62
            )
        }
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasReferOut = outcome.clinicalFlags.contains {
            if case .anisometropiaReferOut = $0 { return true }
            return false
        }
        XCTAssertTrue(hasReferOut)

        let hasNeedsThird = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .sameSignAnisometropiaNeedsThird = reason { return true }
            }
            return false
        }
        XCTAssertFalse(hasNeedsThird, "≥3 printouts must not emit the needs-third flag")
    }

    func testCalculate_sameSignSphDiffUnderThree_neverEmitsNeedsThirdFlag() {
        // Diff = 2.5 D → same-sign advisory but no needs-third flag.
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -3.50, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -1.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -3.50, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasNeedsThird = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .sameSignAnisometropiaNeedsThird = reason { return true }
            }
            return false
        }
        XCTAssertFalse(hasNeedsThird)
    }

    func testCalculate_mixedSignSphDiffOverThree_withTwoPrintouts_emitsRlSphDiffReason() {
        // R +2.00, L -2.50 → diff 4.5 D, mixed sign. §3b mixed-sign retains
        // the generic rlSphDifferenceExceedsThree reason; the §3a
        // antimetropiaNeedsFour reason fires too.
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: 2.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.50, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: 2.00, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.50, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasRlDiff = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .rlSphDifferenceExceedsThree = reason { return true }
            }
            return false
        }
        XCTAssertTrue(hasRlDiff, "mixed-sign diff > 3.00 with <3 printouts must still emit rlSphDifferenceExceedsThree")

        let hasSameSignNeedsThird = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .sameSignAnisometropiaNeedsThird = reason { return true }
            }
            return false
        }
        XCTAssertFalse(hasSameSignNeedsThird, "mixed-sign must not emit the same-sign-specific reason")
    }

    func testCalculate_highSphOverTen_withTwoPrintouts_emitsInsufficientFlag() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -10.50, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -10.00, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -10.50, cyl: -0.50, ax: 90),
                left:  makeEyeReading(.left,  sph: -10.00, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasInsufficient = outcome.clinicalFlags.contains {
            if case .insufficientReadings(_, _, let reason) = $0 {
                if case .highSphOverTen = reason { return true }
            }
            return false
        }
        XCTAssertTrue(hasInsufficient)
    }

    // MARK: - PD aggregation and flags (§9)

    func testCalculate_pdSpreadOverFive_emitsPdMeasurementRequiredFlag() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -1.00, ax: 85),
                pd: 58
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -2.00, cyl: -1.00, ax: 85),
                pd: 66
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        let hasPdFlag = outcome.clinicalFlags.contains {
            if case .pdMeasurementRequired = $0 { return true }
            return false
        }
        XCTAssertTrue(hasPdFlag)
    }

    // MARK: - SPH-only handling (§10)

    func testCalculate_allSphOnlyForOneEye_emitsSphOnlyFlagAndZeroCyl() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.00, cyl: 0, ax: 0, eye: .right, sourcePhotoIndex: 0, isSphOnly: true)
                    ],
                    machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil,
                    sourcePhotoIndex: 0, machineType: .desktop
                ),
                left: makeEyeReading(.left, sph: -1.50, cyl: -0.50, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: EyeReading(
                    id: UUID(),
                    eye: .right,
                    readings: [
                        RawReading(id: UUID(), sph: -2.25, cyl: 0, ax: 0, eye: .right, sourcePhotoIndex: 1, isSphOnly: true)
                    ],
                    machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil,
                    sourcePhotoIndex: 1, machineType: .desktop
                ),
                left: makeEyeReading(.left, sph: -1.50, cyl: -0.50, ax: 85),
                pd: 62
            )
        ]
        let outcome = PrescriptionCalculator.calculate(printouts: printouts, upstreamDroppedOutliers: [])
        XCTAssertEqual(outcome.rightEye?.cyl ?? -1, 0.0, accuracy: 0.01)
        let hasSphOnly = outcome.clinicalFlags.contains {
            if case .sphOnlyReadings(let eye, _) = $0, eye == .right { return true }
            return false
        }
        XCTAssertTrue(hasSphOnly)
    }

    // MARK: - Upstream drops passthrough

    func testCalculate_upstreamDroppedOutliers_propagateToOutcome() {
        let printouts = [
            makePrintout(
                photo: 0,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.50, cyl: -0.75, ax: 85),
                pd: 62
            ),
            makePrintout(
                photo: 1,
                right: makeEyeReading(.right, sph: -2.00, cyl: -1.00, ax: 90),
                left:  makeEyeReading(.left,  sph: -1.50, cyl: -0.75, ax: 85),
                pd: 62
            )
        ]
        let fakeDrop = ConsistencyValidator.DroppedReading(
            reading: RawReading(id: UUID(), sph: -10.0, cyl: -1.0, ax: 90, eye: .right, sourcePhotoIndex: 99),
            photoIndex: 99,
            eye: .right,
            reason: "upstream: disagreed with majority"
        )
        let outcome = PrescriptionCalculator.calculate(
            printouts: printouts,
            upstreamDroppedOutliers: [fakeDrop]
        )
        XCTAssertEqual(outcome.upstreamDroppedOutliers.count, 1)
        XCTAssertEqual(outcome.upstreamDroppedOutliers.first?.reason, "upstream: disagreed with majority")
    }
}

// MARK: - Helpers

private func makePrintout(
    photo: Int,
    right: EyeReading?,
    left: EyeReading?,
    pd: Double?
) -> PrintoutResult {
    PrintoutResult(
        rightEye: right,
        leftEye: left,
        pd: pd,
        machineType: .desktop,
        sourcePhotoIndex: photo,
        rawText: "",
        handheldStarConfidenceRight: nil,
        handheldStarConfidenceLeft: nil
    )
}

private func makeEyeReading(
    _ eye: Eye,
    sph: Double,
    cyl: Double,
    ax: Int
) -> EyeReading {
    let photoIndex = 0
    return EyeReading(
        id: UUID(),
        eye: eye,
        readings: [
            RawReading(id: UUID(), sph: sph, cyl: cyl, ax: ax, eye: eye, sourcePhotoIndex: photoIndex)
        ],
        machineAvgSPH: sph, machineAvgCYL: cyl, machineAvgAX: ax,
        sourcePhotoIndex: photoIndex,
        machineType: .desktop
    )
}
