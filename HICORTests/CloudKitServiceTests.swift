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

    func testSaveThrowsNotImplemented() async {
        let service = CloudKitService()
        let p = PatientRefraction(patientNumber: "1", sessionDate: Date(), sessionLocation: "L")
        do {
            try await service.saveRecord(p)
            XCTFail("Expected notImplementedInPhase1 error")
        } catch CloudKitService.ServiceError.notImplementedInPhase1 {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchThrowsNotImplemented() async {
        let service = CloudKitService()
        do {
            _ = try await service.fetchRecords(for: Date())
            XCTFail("Expected notImplementedInPhase1 error")
        } catch CloudKitService.ServiceError.notImplementedInPhase1 {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
