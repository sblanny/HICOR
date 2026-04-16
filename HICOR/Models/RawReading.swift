import Foundation

struct RawReading: Codable, Identifiable, Equatable {
    var id: UUID
    var sph: Double
    var cyl: Double
    var ax: Int
    var eye: Eye
    var sourcePhotoIndex: Int
}
