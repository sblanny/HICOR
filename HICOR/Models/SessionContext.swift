import Foundation
import Observation

@Observable
final class SessionContext {
    let sessionStartDate: Date
    var location: String

    init(sessionStartDate: Date = Date(), location: String = "") {
        self.sessionStartDate = sessionStartDate
        self.location = location
    }
}
