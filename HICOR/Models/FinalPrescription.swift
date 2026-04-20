import Foundation

struct FinalPrescription: Equatable, Codable {
    let eye: Eye
    let sph: Double
    let cyl: Double
    let ax: Int
    let source: PrescriptionSource
    let acceptedReadings: [RawReading]
    let phase5DroppedOutliers: [ConsistencyValidator.DroppedReading]
    let machineAvgUsed: Bool
    let dispensingTier: DispensingTier
    let tierMessage: String?
}
