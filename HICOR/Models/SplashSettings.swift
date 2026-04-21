import Foundation

final class SplashSettings {
    private static let lastShownKey = "splash.lastShownDate"

    private let defaults: UserDefaults
    private let dateFormatter: DateFormatter

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = fmt
    }

    func shouldShowSplash(today: Date = Date()) -> Bool {
        let todayString = dateFormatter.string(from: today)
        guard let stored = defaults.string(forKey: Self.lastShownKey) else { return true }
        return stored != todayString
    }

    func markShown(on date: Date = Date()) {
        defaults.set(dateFormatter.string(from: date), forKey: Self.lastShownKey)
    }
}
