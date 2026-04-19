import Foundation

enum Constants {
    static let appName = "HICOR"
    static let bundleID = "com.creativearchives.hicor"
    static let cloudKitContainerID = "iCloud.com.creativearchives.hicor"
    // Clinical requirement per MIKE_RX_PROCEDURE.md: 2-5 autorefractor printouts
    // per patient. Cross-printout consistency validation is a clinical safety
    // gate (not an OCR workaround) — non-negotiable.
    static let minPhotosRequired = 2
    static let maxPhotosAllowed = 5
}

enum Eye: String, Codable, Equatable, CaseIterable {
    case right
    case left
}

enum MachineType: String, Codable, Equatable, CaseIterable {
    case desktop
    case handheld
}
