import Foundation

final class SessionSettings {
    var lastDate: Date
    var lastLocation: String

    private static let lastDateKey = "session.lastDate"
    private static let lastLocationKey = "session.lastLocation"

    init(lastDate: Date, lastLocation: String) {
        self.lastDate = lastDate
        self.lastLocation = lastLocation
    }

    static func load(from defaults: UserDefaults = .standard) -> SessionSettings {
        let date = (defaults.object(forKey: lastDateKey) as? Date) ?? Date()
        let location = defaults.string(forKey: lastLocationKey) ?? ""
        return SessionSettings(lastDate: date, lastLocation: location)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(lastDate, forKey: SessionSettings.lastDateKey)
        defaults.set(lastLocation, forKey: SessionSettings.lastLocationKey)
    }
}
