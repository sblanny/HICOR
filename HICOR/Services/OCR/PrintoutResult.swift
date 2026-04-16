import Foundation

struct PrintoutResult: Codable, Equatable {
    var rightEye: EyeReading?
    var leftEye: EyeReading?
    var pd: Double?
    var machineType: MachineType
    var sourcePhotoIndex: Int
    var rawText: String
    var handheldStarConfidenceRight: Int?
    var handheldStarConfidenceLeft: Int?
}
