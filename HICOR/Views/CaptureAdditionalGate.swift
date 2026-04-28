import Foundation

/// Whether to show the "Capture additional printout" affordance on
/// PrescriptionAnalysisView. The volunteer is the final clinical judge —
/// they can request more printouts even on a "successful" Phase 5 result,
/// regardless of tier — but two conditions must hold:
///
/// 1. A callback to wire it to (nil during previews/tests).
/// 2. Headroom under the maxPrintoutsAllowed (5) ceiling.
///
/// Mirrors the SaveGate pattern so the rule is testable without driving
/// the full SwiftUI view.
enum CaptureAdditionalGate {
    static func isAvailable(printoutCount: Int, callbackProvided: Bool) -> Bool {
        callbackProvided && printoutCount < Constants.maxPrintoutsAllowed
    }
}
