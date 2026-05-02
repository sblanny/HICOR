import Foundation

enum Constants {
    static let appName = "HICOR"
    static let bundleID = "com.creativearchives.hicor"
    static let cloudKitContainerID = "iCloud.com.creativearchives.hicor"
    // Clinical requirement per MIKE_RX_PROCEDURE.md: 2-5 autorefractor printouts
    // per patient. Operators may take multiple photos of the same printout so
    // OCR consensus can recover faint or clipped values. A printout is only
    // considered "finalized" (eligible for analysis) once it has at least
    // minPhotosPerPrintout samples; below that, deleting a photo drops the
    // ✓ until another capture brings it back to the floor.
    static let minPrintoutsRequired = 2
    static let maxPrintoutsAllowed = 5
    static let minPhotosPerPrintout = 2
    static let maxPhotosPerPrintout = 4

    // MARK: - Phase 5 (see HICOR/Documentation/MIKE_RX_PROCEDURE.md §Implementation Constants)

    // Cross-printout agreement thresholds
    static let sphAgreementThreshold: Double = 1.00   // Mike's clinical threshold (§1)
    static let cylAgreementThreshold: Double = 1.00   // Calibrated to inventory CYL step size (§1) — see MIKE_RX_PROCEDURE.md for 2026-05-02 Day 2 calibration

    // Phase 5 outlier rejection — k×MAD on power-vector components (§5).
    // Used by CrossPrintoutAggregator only; ConsistencyValidator's pairwise
    // AVG check (different layer, runs earlier) keeps the fixed thresholds
    // above.
    static let outlierRejectionK: Double = 3.0
    static let outlierRejectionMadFloor: Double = 0.05    // diopters / J units; prevents zero-tolerance when readings agree
    static let outlierRejectionAnsiHardFloorM: Double = 1.00   // diopters; sign-flip safety net independent of MAD
    static let outlierRejectionMinSurvivors: Int = 3

    // Axis agreement — sliding scale by CYL magnitude (§2)
    static let axisToleranceCylUnder025: Double = 30.0
    static let axisToleranceCyl025To050: Double = 20.0
    static let axisToleranceCyl050To100: Double = 15.0
    static let axisToleranceCyl100To200: Double = 10.0
    static let axisToleranceCylOver200: Double = 7.0

    // Machine AVG validation tolerance (§4)
    static let machineAvgValidationThreshold: Double = 0.50

    // Anisometropia thresholds (§8)
    static let anisometropiaAdvisoryThreshold: Double = 2.00
    static let anisometropiaReferOutThreshold: Double = 3.00
    static let antimetropiaBothEyesMaxAbs: Double = 1.50
    static let antimetropiaMinimumPrintouts: Int = 4

    // Clinical gates requiring 3+ readings (§3)
    static let rlDiffTriggersMin3: Double = 3.00
    static let onePlanoOtherHighTrigger: Double = 5.00
    static let highSphTrigger: Double = 10.00

    // Tier 0 (no glasses needed) thresholds (§7)
    static let tier0SphMax: Double = 0.25
    static let tier0CylMax: Double = 0.50

    // Tier boundaries (§7)
    static let sphTier1Max: Double = 6.00
    static let sphTier2Max: Double = 8.00        // HARD CEILING
    static let sphMedicalConcernMin: Double = 12.00
    static let cylTier1Max: Double = 2.00
    static let cylTier2Max: Double = 3.00

    // Rounding (§6)
    static let cylBreakpointForSphRounding: Double = 1.00
    static let cylRoundingStep: Double = 0.50
    static let sphMagnitudeThresholdForCylRounding: Double = 3.00

    // PD aggregation (§9)
    static let pdMaxSpreadBeforeManual: Double = 5.0  // mm
}

enum Eye: String, Codable, Equatable, CaseIterable {
    case right
    case left
}

enum MachineType: String, Codable, Equatable, CaseIterable {
    case desktop
    case handheld
}
