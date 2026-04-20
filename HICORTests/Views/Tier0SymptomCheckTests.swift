import XCTest
@testable import HICOR

final class Tier0SymptomCheckTests: XCTestCase {

    // MARK: - "No symptoms" short-circuit

    func test_noSymptoms_shortCircuits_noGlassesNeeded() {
        let decision = Tier0SymptomCheck.decide(
            blurryVision: .no,
            headachesReading: .no,
            squinting: .no
        )
        XCTAssertEqual(decision, .noGlassesNeeded)
    }

    // MARK: - Any symptom flips to "dispense as normal"

    func test_anyBlurryVision_triggersDispense() {
        let decision = Tier0SymptomCheck.decide(
            blurryVision: .yes,
            headachesReading: .no,
            squinting: .no
        )
        XCTAssertEqual(decision, .dispenseTier1)
    }

    func test_anyHeadaches_triggersDispense() {
        let decision = Tier0SymptomCheck.decide(
            blurryVision: .no,
            headachesReading: .yes,
            squinting: .no
        )
        XCTAssertEqual(decision, .dispenseTier1)
    }

    func test_anySquinting_triggersDispense() {
        let decision = Tier0SymptomCheck.decide(
            blurryVision: .no,
            headachesReading: .no,
            squinting: .yes
        )
        XCTAssertEqual(decision, .dispenseTier1)
    }

    // MARK: - Incomplete entry stays indeterminate

    func test_unanswered_questions_returnIndeterminate() {
        let decision = Tier0SymptomCheck.decide(
            blurryVision: .unanswered,
            headachesReading: .no,
            squinting: .no
        )
        XCTAssertEqual(decision, .indeterminate)
    }

    func test_allUnanswered_returnIndeterminate() {
        let decision = Tier0SymptomCheck.decide(
            blurryVision: .unanswered,
            headachesReading: .unanswered,
            squinting: .unanswered
        )
        XCTAssertEqual(decision, .indeterminate)
    }
}
