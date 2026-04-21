import XCTest
@testable import HICOR

final class SplashSettingsTests: XCTestCase {
    var defaults: UserDefaults!
    let suiteName = "HICOR.SplashSettingsTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFirstLaunchShowsSplash() {
        let settings = SplashSettings(defaults: defaults)
        XCTAssertTrue(settings.shouldShowSplash(), "First launch ever should show splash")
    }

    func testMarkingShownSameDayHidesSplash() {
        let settings = SplashSettings(defaults: defaults)
        let now = Date()
        settings.markShown(on: now)
        XCTAssertFalse(settings.shouldShowSplash(today: now),
                       "Splash marked shown today should not re-show same day")
    }

    func testMarkingShownYesterdayShowsSplashToday() {
        let settings = SplashSettings(defaults: defaults)
        let today = Date()
        let yesterday = today.addingTimeInterval(-24 * 60 * 60)
        settings.markShown(on: yesterday)
        XCTAssertTrue(settings.shouldShowSplash(today: today),
                      "Splash shown yesterday should re-show today")
    }

    func testPersistenceAcrossInstances() {
        let a = SplashSettings(defaults: defaults)
        let now = Date()
        a.markShown(on: now)
        let b = SplashSettings(defaults: defaults)
        XCTAssertFalse(b.shouldShowSplash(today: now),
                       "New instance must read persisted state, not reset to first-launch")
    }
}
