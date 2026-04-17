import Foundation

enum Constants {
    static let appName = "HICOR"
    static let bundleID = "com.creativearchives.hicor"
    static let cloudKitContainerID = "iCloud.com.creativearchives.hicor"
    // v1 scope reduction (2026-04-17): capture requires exactly one photo while
    // we prove single-photo OCR end-to-end. Multi-photo aggregation, cross-photo
    // averaging, and photo-count-driven hard-block consistency will return in a
    // future phase once single-photo extraction is validated on-device.
    static let minPhotosRequired = 1
    static let maxPhotosAllowed = 1
}

enum Eye: String, Codable, Equatable, CaseIterable {
    case right
    case left
}

enum MachineType: String, Codable, Equatable, CaseIterable {
    case desktop
    case handheld
}

enum ConsistencyResult: Equatable {
    case ok
    case warningOverridable
    case hardBlock
}
