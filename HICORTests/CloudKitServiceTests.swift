import XCTest
import CloudKit
@testable import HICOR

final class CloudKitServiceTests: XCTestCase {
    func testCKRecordRoundTrip() throws {
        let original = PatientRefraction(
            patientNumber: "123",
            sessionDate: Date(timeIntervalSince1970: 1_700_000_000),
            sessionLocation: "San Quintin",
            odSPH: 1.5, odCYL: -0.5, odAX: 108,
            osSPH: 1.25, osCYL: -0.5, osAX: 55,
            pd: 59,
            pdManualEntry: true,
            matchedLensOD: "+1.50 / -0.50",
            matchedLensOS: "+1.25 / -0.50",
            rawReadingsData: Data("[]".utf8),
            photoData: [Data([0x01, 0x02, 0x03])],
            consistencyWarningOverridden: true,
            deviceID: "device-xyz"
        )

        let record = CloudKitService.makeRecord(from: original)
        XCTAssertEqual(record["patientNumber"] as? String, "123")
        XCTAssertEqual(record["odSPH"] as? Double, 1.5)
        XCTAssertEqual(record["pdManualEntry"] as? Int, 1)
        XCTAssertEqual(record["consistencyWarningOverridden"] as? Int, 1)
        XCTAssertEqual(record["matchedLensOD"] as? String, "+1.50 / -0.50")

        let restored = CloudKitService.makeRefraction(from: record)
        XCTAssertEqual(restored.patientNumber, "123")
        XCTAssertEqual(restored.odSPH, 1.5)
        XCTAssertEqual(restored.osAX, 55)
        XCTAssertEqual(restored.pd, 59)
        XCTAssertTrue(restored.pdManualEntry)
        XCTAssertTrue(restored.consistencyWarningOverridden)
        XCTAssertEqual(restored.deviceID, "device-xyz")
    }

    func testSaveRecordSetsCloudKitRecordID() async throws {
        let mock = MockCKDatabase()
        let returnedRecord = CKRecord(
            recordType: CloudKitService.recordType,
            recordID: CKRecord.ID(recordName: "rec-abc")
        )
        mock.saveBehavior = .returnRecord(returnedRecord)
        let service = CloudKitService(database: mock)

        let p = PatientRefraction(patientNumber: "1", sessionDate: Date(), sessionLocation: "L")
        XCTAssertFalse(p.syncedToCloud)
        XCTAssertNil(p.cloudKitRecordID)

        try await service.saveRecord(p)

        XCTAssertEqual(p.cloudKitRecordID, "rec-abc")
        XCTAssertTrue(p.syncedToCloud)
        XCTAssertEqual(mock.savedRecords.count, 1)
    }

    func testSaveRecordPropagatesError() async {
        let mock = MockCKDatabase()
        mock.saveBehavior = .throwError(CKError(.networkUnavailable))
        let service = CloudKitService(database: mock)

        let p = PatientRefraction(patientNumber: "1", sessionDate: Date(), sessionLocation: "L")

        do {
            try await service.saveRecord(p)
            XCTFail("Expected CKError to propagate")
        } catch let error as CKError {
            XCTAssertEqual(error.code, .networkUnavailable)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        XCTAssertFalse(p.syncedToCloud)
        XCTAssertNil(p.cloudKitRecordID)
    }

    func testFetchRecordsReturnsConvertedRefractions() async throws {
        let mock = MockCKDatabase()
        let pA = PatientRefraction(patientNumber: "A", sessionDate: Date(), sessionLocation: "L")
        let pB = PatientRefraction(patientNumber: "B", sessionDate: Date(), sessionLocation: "L")
        mock.queryRecords = [
            CloudKitService.makeRecord(from: pA),
            CloudKitService.makeRecord(from: pB)
        ]
        let service = CloudKitService(database: mock)

        let results = try await service.fetchRecords(for: Date())

        XCTAssertEqual(results.count, 2)
        let numbers = Set(results.map { $0.patientNumber })
        XCTAssertEqual(numbers, ["A", "B"])
        XCTAssertEqual(mock.queryCount, 1)
    }

    func testSyncPendingIsNoOp() async {
        let service = CloudKitService(database: MockCKDatabase())
        await service.syncPending()
    }
}
