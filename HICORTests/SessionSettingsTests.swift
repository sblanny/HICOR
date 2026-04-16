import XCTest
@testable import HICOR

final class SessionSettingsTests: XCTestCase {
    var defaults: UserDefaults!
    let suiteName = "HICOR.SessionSettingsTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadReturnsDefaultsWhenEmpty() {
        let settings = SessionSettings.load(from: defaults)
        XCTAssertEqual(settings.lastLocation, "")
        XCTAssertLessThan(abs(settings.lastDate.timeIntervalSinceNow), 5)
    }

    func testSaveAndLoadRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = SessionSettings(lastDate: date, lastLocation: "San Quintin")
        settings.save(to: defaults)

        let loaded = SessionSettings.load(from: defaults)
        XCTAssertEqual(loaded.lastDate, date)
        XCTAssertEqual(loaded.lastLocation, "San Quintin")
    }
}
