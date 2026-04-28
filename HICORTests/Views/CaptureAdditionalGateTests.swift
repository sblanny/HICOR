import XCTest
@testable import HICOR

final class CaptureAdditionalGateTests: XCTestCase {

    // The volunteer is the final clinical judge — they can request more
    // printouts even on a "successful" Phase 5 result, regardless of tier.
    // Gate is open whenever there's both a callback to fire AND headroom
    // under the 5-printout ceiling.

    func testHiddenWhenNoCallbackProvided() {
        // Previews / tests pass nil for the callback. Don't render a
        // dead-end button.
        XCTAssertFalse(
            CaptureAdditionalGate.isAvailable(printoutCount: 2, callbackProvided: false)
        )
    }

    func testAvailableWithRoomBelowCeiling() {
        for count in 1..<Constants.maxPrintoutsAllowed {
            XCTAssertTrue(
                CaptureAdditionalGate.isAvailable(printoutCount: count, callbackProvided: true),
                "Should be available at count=\(count)"
            )
        }
    }

    func testHiddenAtCeiling() {
        XCTAssertFalse(
            CaptureAdditionalGate.isAvailable(
                printoutCount: Constants.maxPrintoutsAllowed,
                callbackProvided: true
            ),
            "5/5 printouts → no more capacity, hide the affordance"
        )
    }

    func testHiddenAboveCeiling() {
        // Defensive: the count should never exceed the ceiling, but if it
        // somehow does the gate must still close rather than enable a
        // tap that would push past the limit.
        XCTAssertFalse(
            CaptureAdditionalGate.isAvailable(
                printoutCount: Constants.maxPrintoutsAllowed + 1,
                callbackProvided: true
            )
        )
    }
}
