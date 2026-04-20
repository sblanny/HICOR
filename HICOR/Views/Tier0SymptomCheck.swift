import Foundation

// Pure decision logic for the Tier 0 "no glasses may be needed" symptom check
// per MIKE_RX_PROCEDURE.md §7 Tier 0 rules. Three yes/no questions; any "yes"
// flips to dispense as Tier 1. Unanswered → indeterminate (save blocked).
enum Tier0SymptomCheck {

    enum Answer: Equatable {
        case unanswered
        case no
        case yes
    }

    enum Decision: Equatable {
        case indeterminate
        case noGlassesNeeded
        case dispenseTier1
    }

    static func decide(
        blurryVision: Answer,
        headachesReading: Answer,
        squinting: Answer
    ) -> Decision {
        let all = [blurryVision, headachesReading, squinting]
        if all.contains(.unanswered) { return .indeterminate }
        if all.contains(.yes) { return .dispenseTier1 }
        return .noGlassesNeeded
    }
}
