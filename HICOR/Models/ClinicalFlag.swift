import Foundation

enum InsufficientReadingsReason: Equatable, Codable {
    case antimetropiaNeedsFour
    case rlSphDifferenceExceedsThree(diff: Double)
    case onePlanoOtherHighSph
    case highSphOverTen
    case sameSignAnisometropiaNeedsThird
}

enum ClinicalFlag: Equatable, Codable {
    case tier0SymptomCheckRequired
    case anisometropiaAdvisory(diffDiopters: Double)
    case anisometropiaReferOut(diffDiopters: Double)
    case antimetropiaDispense(lowestAbsEye: Eye)
    case antimetropiaReferOut
    case sphExceedsInventory(eye: Eye, value: Double, tier: DispensingTier)
    case cylExceedsInventory(eye: Eye, value: Double, tier: DispensingTier)
    case medicalConcern(eye: Eye, value: Double)
    case sphOnlyReadings(eye: Eye, count: Int)
    case insufficientReadings(eye: Eye, count: Int, reason: InsufficientReadingsReason)
    case pdMeasurementRequired(spreadMm: Double)
    case axisAgreementExceeded(eye: Eye, spread: Double, tolerance: Double)
    case readingsVaryWidely(eye: Eye, count: Int)
    case manualReviewRequired(reason: String)
}
