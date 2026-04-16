import Foundation
import SwiftData
import UIKit

@Model
final class PatientRefraction {
    var id: UUID
    var patientNumber: String
    var sessionDate: Date
    var sessionLocation: String
    var odSPH: Double
    var odCYL: Double
    var odAX: Int
    var osSPH: Double
    var osCYL: Double
    var osAX: Int
    var pd: Double
    var pdManualEntry: Bool
    var matchedLensOD: String
    var matchedLensOS: String
    var rawReadingsData: Data
    @Attribute(.externalStorage) var photoData: [Data]
    var consistencyWarningOverridden: Bool
    var createdAt: Date
    var deviceID: String
    var cloudKitRecordID: String?
    var syncedToCloud: Bool

    init(
        id: UUID = UUID(),
        patientNumber: String,
        sessionDate: Date,
        sessionLocation: String,
        odSPH: Double = 0,
        odCYL: Double = 0,
        odAX: Int = 0,
        osSPH: Double = 0,
        osCYL: Double = 0,
        osAX: Int = 0,
        pd: Double = 0,
        pdManualEntry: Bool = false,
        matchedLensOD: String = "",
        matchedLensOS: String = "",
        rawReadingsData: Data = Data(),
        photoData: [Data] = [],
        consistencyWarningOverridden: Bool = false,
        createdAt: Date = Date(),
        deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
        cloudKitRecordID: String? = nil,
        syncedToCloud: Bool = false
    ) {
        self.id = id
        self.patientNumber = patientNumber
        self.sessionDate = sessionDate
        self.sessionLocation = sessionLocation
        self.odSPH = odSPH
        self.odCYL = odCYL
        self.odAX = odAX
        self.osSPH = osSPH
        self.osCYL = osCYL
        self.osAX = osAX
        self.pd = pd
        self.pdManualEntry = pdManualEntry
        self.matchedLensOD = matchedLensOD
        self.matchedLensOS = matchedLensOS
        self.rawReadingsData = rawReadingsData
        self.photoData = photoData
        self.consistencyWarningOverridden = consistencyWarningOverridden
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.cloudKitRecordID = cloudKitRecordID
        self.syncedToCloud = syncedToCloud
    }
}
