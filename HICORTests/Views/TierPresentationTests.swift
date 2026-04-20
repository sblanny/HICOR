import XCTest
@testable import HICOR

final class TierPresentationTests: XCTestCase {

    func test_tier0_noGlassesNeeded_isInformational() {
        let p = TierPresentation.make(for: .tier0NoGlassesNeeded)
        XCTAssertEqual(p.severity, .info)
        XCTAssertTrue(p.title.lowercased().contains("no glasses")
                      || p.title.lowercased().contains("tier 0"),
                      "title=\(p.title)")
    }

    func test_tier1_normal_isSuccess_allowsDispense() {
        let p = TierPresentation.make(for: .tier1Normal)
        XCTAssertEqual(p.severity, .success)
        XCTAssertTrue(p.allowsDispense)
    }

    func test_tier2_stretchWithNotification_isWarning_requiresAcknowledgement() {
        let p = TierPresentation.make(for: .tier2StretchWithNotification)
        XCTAssertEqual(p.severity, .warning)
        XCTAssertTrue(p.allowsDispense)
        XCTAssertTrue(p.requiresPatientNotifiedAcknowledgement)
    }

    func test_tier3_doNotDispense_blocksDispense() {
        let p = TierPresentation.make(for: .tier3DoNotDispense)
        XCTAssertEqual(p.severity, .blocking)
        XCTAssertFalse(p.allowsDispense)
    }

    func test_tier4_medicalConcern_blocksDispense_isMedical() {
        let p = TierPresentation.make(for: .tier4MedicalConcern)
        XCTAssertEqual(p.severity, .blocking)
        XCTAssertFalse(p.allowsDispense)
        XCTAssertTrue(p.title.lowercased().contains("medical"),
                      "title=\(p.title)")
    }
}
