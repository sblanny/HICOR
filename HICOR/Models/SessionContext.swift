import Foundation
import Observation

@Observable
final class SessionContext {
    var date: Date
    var location: String

    init(date: Date = Date(), location: String = "") {
        self.date = date
        self.location = location
    }
}
