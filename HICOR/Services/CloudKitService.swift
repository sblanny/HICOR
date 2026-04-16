import Foundation
import CloudKit

final class CloudKitService {
    static let shared = CloudKitService()

    enum ServiceError: Error {
        case notImplementedInPhase1
    }

    static let recordType = "PatientRefraction"

    static func makeRecord(from p: PatientRefraction) -> CKRecord {
        let record = CKRecord(recordType: recordType)
        record["patientNumber"] = p.patientNumber as CKRecordValue
        record["sessionDate"] = p.sessionDate as CKRecordValue
        record["sessionLocation"] = p.sessionLocation as CKRecordValue
        record["odSPH"] = p.odSPH as CKRecordValue
        record["odCYL"] = p.odCYL as CKRecordValue
        record["odAX"] = p.odAX as CKRecordValue
        record["osSPH"] = p.osSPH as CKRecordValue
        record["osCYL"] = p.osCYL as CKRecordValue
        record["osAX"] = p.osAX as CKRecordValue
        record["pd"] = p.pd as CKRecordValue
        record["pdManualEntry"] = (p.pdManualEntry ? 1 : 0) as CKRecordValue
        record["matchedLensOD"] = p.matchedLensOD as CKRecordValue
        record["matchedLensOS"] = p.matchedLensOS as CKRecordValue
        record["rawReadingsJSON"] = (String(data: p.rawReadingsData, encoding: .utf8) ?? "") as CKRecordValue
        record["consistencyWarningOverridden"] = (p.consistencyWarningOverridden ? 1 : 0) as CKRecordValue
        record["createdAt"] = p.createdAt as CKRecordValue
        record["deviceID"] = p.deviceID as CKRecordValue
        record["uuid"] = p.id.uuidString as CKRecordValue
        return record
    }

    static func makeRefraction(from record: CKRecord) -> PatientRefraction {
        let rawJSON = (record["rawReadingsJSON"] as? String) ?? ""
        let uuidString = (record["uuid"] as? String) ?? ""
        return PatientRefraction(
            id: UUID(uuidString: uuidString) ?? UUID(),
            patientNumber: (record["patientNumber"] as? String) ?? "",
            sessionDate: (record["sessionDate"] as? Date) ?? Date(),
            sessionLocation: (record["sessionLocation"] as? String) ?? "",
            odSPH: (record["odSPH"] as? Double) ?? 0,
            odCYL: (record["odCYL"] as? Double) ?? 0,
            odAX: (record["odAX"] as? Int) ?? 0,
            osSPH: (record["osSPH"] as? Double) ?? 0,
            osCYL: (record["osCYL"] as? Double) ?? 0,
            osAX: (record["osAX"] as? Int) ?? 0,
            pd: (record["pd"] as? Double) ?? 0,
            pdManualEntry: ((record["pdManualEntry"] as? Int) ?? 0) == 1,
            matchedLensOD: (record["matchedLensOD"] as? String) ?? "",
            matchedLensOS: (record["matchedLensOS"] as? String) ?? "",
            rawReadingsData: Data(rawJSON.utf8),
            photoData: [],
            consistencyWarningOverridden: ((record["consistencyWarningOverridden"] as? Int) ?? 0) == 1,
            createdAt: (record["createdAt"] as? Date) ?? Date(),
            deviceID: (record["deviceID"] as? String) ?? "",
            cloudKitRecordID: record.recordID.recordName,
            syncedToCloud: true
        )
    }

    func saveRecord(_ refraction: PatientRefraction) async throws {
        throw ServiceError.notImplementedInPhase1
    }

    func fetchRecords(for date: Date) async throws -> [PatientRefraction] {
        throw ServiceError.notImplementedInPhase1
    }

    func syncPending() async {
        // No-op in Phase 1.
    }
}
