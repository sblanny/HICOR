import Foundation

// Gates the "Save & Return" button on PrescriptionAnalysisView per
// MIKE_RX_PROCEDURE.md §7. Pure function so the gating is unit-testable
// independent of the SwiftUI binding.
enum SaveGate {

    struct State: Equatable {
        let enabled: Bool
        let disabledReason: String?
    }

    static func evaluate(
        outcome: PrescriptionCalculationOutcome,
        patientNotifiedTier2: Bool,
        tier0Decision: Tier0SymptomCheck.Decision
    ) -> State {
        switch outcome.overallTier {
        case .tier0NoGlassesNeeded:
            if tier0Decision == .indeterminate {
                return State(
                    enabled: false,
                    disabledReason: "Answer the three symptom questions first."
                )
            }
            return State(enabled: true, disabledReason: nil)

        case .tier2StretchWithNotification:
            if !patientNotifiedTier2 {
                return State(
                    enabled: false,
                    disabledReason: "Confirm you told the patient this is a stretch fit."
                )
            }
            return State(enabled: true, disabledReason: nil)

        case .tier1Normal, .tier3DoNotDispense, .tier4MedicalConcern:
            // Tier 3/4 still save — the save records the referral for the audit
            // trail. Dispensing is gated at the lens-handout step, not here.
            return State(enabled: true, disabledReason: nil)
        }
    }
}
