import Foundation

struct LensOption: Codable, Identifiable, Equatable {
    var id: UUID
    var sph: Double
    var cyl: Double
    var available: Bool
}

struct LensInventory: Codable, Equatable {
    var version: String
    var lastUpdated: Date
    var supportedCylinders: [Double]
    var lenses: [LensOption]
}
