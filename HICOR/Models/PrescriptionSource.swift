import Foundation

enum PrescriptionSource: String, Codable, Equatable, CaseIterable {
    case machineAvgValidated
    case recomputedViaPowerVector
    case recomputedWithOutliersDropped
    case manualReviewRequired
}
