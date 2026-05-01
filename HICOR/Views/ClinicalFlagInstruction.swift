import Foundation

// Maps a ClinicalFlag to an operator-facing title + actionable body.
// Phase 5 principle: flags must be operator-actionable, not silent badges
// (see MIKE_RX_PROCEDURE.md §3 and the Phase 5 plan's clinical-flag rendering
// contract). The view consumes this directly — no copy lives in the view body.
struct ClinicalFlagInstruction: Equatable {

    enum Severity: Equatable {
        case info       // no action required, but worth surfacing
        case warning    // action recommended, does not block dispense
        case blocking   // operator must act (add photos, refer out, etc.)
    }

    let severity: Severity
    let title: String
    let body: String

    static func make(for flag: ClinicalFlag) -> ClinicalFlagInstruction {
        switch flag {

        case .tier0SymptomCheckRequired:
            return ClinicalFlagInstruction(
                severity: .info,
                title: "Symptom check required",
                body: "Readings are near plano. Ask the three symptom questions before finalizing."
            )

        case .anisometropiaAdvisory(let diff):
            return ClinicalFlagInstruction(
                severity: .warning,
                title: "Large difference between eyes",
                body: String(
                    format: "R/L SPH difference is %.2f D. Patient may experience depth-perception issues — advise accordingly.",
                    diff
                )
            )

        case .anisometropiaReferOut(let diff):
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "Refer out — eye difference too large",
                body: String(
                    format: "R/L SPH difference is %.2f D, which exceeds the 3.00 D dispense limit. Refer to a local provider.",
                    diff
                )
            )

        case .antimetropiaDispense(let lowestAbs):
            let eyeLabel = (lowestAbs == .right) ? "right" : "left"
            return ClinicalFlagInstruction(
                severity: .warning,
                title: "Mixed-sign prescription",
                body: "Patient has one positive and one negative eye. Dispensing using the \(eyeLabel) eye (lowest absolute SPH) per Mike's procedure."
            )

        case .antimetropiaReferOut:
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "Refer out — mixed-sign with high SPH",
                body: "Patient has mixed signs (antimetropia) with at least one eye over 1.50 D. Refer to a local provider."
            )

        case .sphExceedsInventory(let eye, let value, let tier):
            let eyeLabel = (eye == .right) ? "right" : "left"
            let tierSeverity: Severity = (tier == .tier2StretchWithNotification) ? .warning : .blocking
            return ClinicalFlagInstruction(
                severity: tierSeverity,
                title: "SPH outside inventory",
                body: String(
                    format: "%@ eye SPH of %+.2f D is outside our typical stock range.",
                    eyeLabel.capitalized,
                    value
                )
            )

        case .cylExceedsInventory(let eye, let value, let tier):
            let eyeLabel = (eye == .right) ? "right" : "left"
            let tierSeverity: Severity = (tier == .tier2StretchWithNotification) ? .warning : .blocking
            return ClinicalFlagInstruction(
                severity: tierSeverity,
                title: "CYL outside inventory",
                body: String(
                    format: "%@ eye CYL of %+.2f D is outside our typical stock range.",
                    eyeLabel.capitalized,
                    value
                )
            )

        case .medicalConcern(let eye, let value):
            let eyeLabel = (eye == .right) ? "Right" : "Left"
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "Possible medical concern",
                body: String(
                    format: "%@ eye SPH of %+.2f D exceeds our medical-referral threshold. Escalate to the lead clinician.",
                    eyeLabel,
                    value
                )
            )

        case .sphOnlyReadings(let eye, let count):
            let eyeLabel = (eye == .right) ? "right" : "left"
            let s = count == 1 ? "" : "s"
            return ClinicalFlagInstruction(
                severity: .info,
                title: "SPH-only reading\(s) noted",
                body: "\(count) reading\(s) on the \(eyeLabel) eye recorded SPH only (no astigmatism detected on those samples)."
            )

        case .insufficientReadings(_, _, let reason):
            return insufficientReadingsInstruction(reason: reason)

        case .pdMeasurementRequired(let spread):
            return ClinicalFlagInstruction(
                severity: .warning,
                title: "Manual PD measurement required",
                body: String(
                    format: "Printout PDs disagree by %.1f mm. Measure the patient's PD manually with the ruler and overwrite the value shown.",
                    spread
                )
            )

        case .axisAgreementExceeded(let eye, let spread, let tolerance):
            let eyeLabel = (eye == .right) ? "right" : "left"
            return ClinicalFlagInstruction(
                severity: .warning,
                title: "Axis readings disagree",
                body: String(
                    format: "%@ eye axis spread of %.0f° exceeds the %.0f° tolerance for this CYL. Recheck the printouts before dispensing.",
                    eyeLabel.capitalized,
                    spread,
                    tolerance
                )
            )

        case .manualReviewRequired(let reason):
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "Manual review required",
                body: reason
            )
        }
    }

    // MARK: - insufficientReadings — §3 clinical gates

    private static func insufficientReadingsInstruction(
        reason: InsufficientReadingsReason
    ) -> ClinicalFlagInstruction {
        switch reason {
        case .antimetropiaNeedsFour:
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "More printouts needed",
                body: "Mixed-sign prescription detected — one eye plus, one eye minus (antimetropia). This unusual pattern requires 4 printouts to verify, more than the usual 2–3. Capture one more printout on the autorefractor."
            )
        case .rlSphDifferenceExceedsThree(let diff):
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "More printouts needed",
                body: String(
                    format: "Large difference between eyes detected (%.2f D). At least 3 printouts are required for this case. Please capture another photo.",
                    diff
                )
            )
        case .onePlanoOtherHighSph:
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "More printouts needed",
                body: "One eye is plano while the other is high. Mike's procedure requires at least 3 printouts for this case. Please capture another photo."
            )
        case .highSphOverTen:
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "More printouts needed",
                body: "SPH exceeds 10 D on at least one eye. Mike's procedure requires at least 3 printouts for high-SPH cases. Please capture another photo."
            )
        case .sameSignAnisometropiaNeedsThird:
            return ClinicalFlagInstruction(
                severity: .blocking,
                title: "More printouts needed",
                body: "Same-sign anisometropia >3.00 D detected. Take a 3rd printout to verify before referring out."
            )
        }
    }
}
