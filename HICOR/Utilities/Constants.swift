import Foundation

enum Constants {
    static let appName = "HICOR"
    static let bundleID = "com.creativearchives.hicor"
    static let cloudKitContainerID = "iCloud.com.creativearchives.hicor"
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

enum ConsistencyResult: Equatable {
    case ok
    case warningOverridable
    case hardBlock
}
