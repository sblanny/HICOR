import Foundation

enum DispensingTier: String, Codable, Equatable, CaseIterable {
    case tier0NoGlassesNeeded
    case tier1Normal
    case tier2StretchWithNotification
    case tier3DoNotDispense
    case tier4MedicalConcern
}
