import Foundation

struct EyeReading: Codable, Identifiable, Equatable {
    var id: UUID
    var eye: Eye
    var readings: [RawReading]
    var machineAvgSPH: Double?
    var machineAvgCYL: Double?
    var machineAvgAX: Int?
    var sourcePhotoIndex: Int
    var machineType: MachineType
}
