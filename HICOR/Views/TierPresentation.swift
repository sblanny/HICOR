import Foundation

// Pure presentation model for a DispensingTier per MIKE_RX_PROCEDURE.md §7.
// Maps each tier to (headline, subtitle, severity, dispense/acknowledge flags)
// so PrescriptionAnalysisView can render the banner without embedding copy
// decisions in the view body.
struct TierPresentation: Equatable {

    enum Severity: Equatable {
        case info        // Tier 0 — informational (symptom check follows)
        case success     // Tier 1 — normal dispense
        case warning     // Tier 2 — dispense with patient notification
        case blocking    // Tier 3 / Tier 4 — do not dispense
    }

    let tier: DispensingTier
    let title: String
    let subtitle: String
    let severity: Severity
    let allowsDispense: Bool
    let requiresPatientNotifiedAcknowledgement: Bool

    static func make(for tier: DispensingTier) -> TierPresentation {
        switch tier {
        case .tier0NoGlassesNeeded:
            return TierPresentation(
                tier: tier,
                title: "Tier 0 — No glasses may be needed",
                subtitle: "Readings are near plano. Ask the three symptom questions before skipping glasses.",
                severity: .info,
                allowsDispense: true,
                requiresPatientNotifiedAcknowledgement: false
            )
        case .tier1Normal:
            return TierPresentation(
                tier: tier,
                title: "Tier 1 — Normal dispense",
                subtitle: "Prescription is within our in-inventory range.",
                severity: .success,
                allowsDispense: true,
                requiresPatientNotifiedAcknowledgement: false
            )
        case .tier2StretchWithNotification:
            return TierPresentation(
                tier: tier,
                title: "Tier 2 — Dispense with patient notification",
                subtitle: "Prescription is outside our typical range. Tell the patient this is a stretch fit and confirm below before saving.",
                severity: .warning,
                allowsDispense: true,
                requiresPatientNotifiedAcknowledgement: true
            )
        case .tier3DoNotDispense:
            return TierPresentation(
                tier: tier,
                title: "Tier 3 — Do not dispense",
                subtitle: "Prescription exceeds our inventory. Refer this patient to a local provider.",
                severity: .blocking,
                allowsDispense: false,
                requiresPatientNotifiedAcknowledgement: false
            )
        case .tier4MedicalConcern:
            return TierPresentation(
                tier: tier,
                title: "Tier 4 — Medical concern",
                subtitle: "Prescription indicates a possible medical issue. Escalate to the lead clinician.",
                severity: .blocking,
                allowsDispense: false,
                requiresPatientNotifiedAcknowledgement: false
            )
        }
    }
}
