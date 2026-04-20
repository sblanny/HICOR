import Foundation

// Five-tier dispensing assignment per MIKE_RX_PROCEDURE.md §7.
//
//   Tier 0 — Both eyes |SPH| ≤ 0.25 AND |CYL| ≤ 0.50. Triggers the no-glasses
//            symptom check; only fires when BOTH eyes qualify.
//   Tier 1 — Normal range: |SPH| ≤ 6.00 and |CYL| ≤ 2.00.
//   Tier 2 — Stretch: 6.00 < |SPH| ≤ 8.00, or 2.00 < |CYL| ≤ 3.00. Patient
//            notification required.
//   Tier 3 — Hard ceiling: |SPH| > 8.00 or |CYL| > 3.00. Do not dispense.
//   Tier 4 — Medical concern: |SPH| > 12.00. Overrides Tier 3.
//
// Overall tier for the patient is the max severity of the two per-eye tiers.
// Tier 0 only wins overall when both eyes are Tier 0; any asymmetric case
// falls to the non-Tier-0 eye's classification.
enum TierAssigner {

    static func assignPerEyeTier(sph: Double, cyl: Double) -> DispensingTier {
        let absSph = abs(sph)
        let absCyl = abs(cyl)

        if absSph > Constants.sphMedicalConcernMin {
            return .tier4MedicalConcern
        }
        if absSph > Constants.sphTier2Max || absCyl > Constants.cylTier2Max {
            return .tier3DoNotDispense
        }
        if absSph > Constants.sphTier1Max || absCyl > Constants.cylTier1Max {
            return .tier2StretchWithNotification
        }
        if absSph <= Constants.tier0SphMax && absCyl <= Constants.tier0CylMax {
            return .tier0NoGlassesNeeded
        }
        return .tier1Normal
    }

    static func assignOverallTier(right: DispensingTier, left: DispensingTier) -> DispensingTier {
        severity(right) >= severity(left) ? right : left
    }

    // Higher number = higher severity. Tier 0 is the lowest so asymmetric
    // cases (one eye Tier 0, other Tier 1+) surface the non-Tier-0 eye.
    private static func severity(_ tier: DispensingTier) -> Int {
        switch tier {
        case .tier0NoGlassesNeeded: return 0
        case .tier1Normal: return 1
        case .tier2StretchWithNotification: return 2
        case .tier3DoNotDispense: return 3
        case .tier4MedicalConcern: return 4
        }
    }
}
