import Foundation

final class SessionSettings {
    var lastLocation: String

    private static let lastLocationKey = "session.lastLocation"

    init(lastLocation: String) {
        self.lastLocation = lastLocation
    }

    static func load(from defaults: UserDefaults = .standard) -> SessionSettings {
        let location = defaults.string(forKey: lastLocationKey) ?? ""
        return SessionSettings(lastLocation: location)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(lastLocation, forKey: SessionSettings.lastLocationKey)
    }
}
