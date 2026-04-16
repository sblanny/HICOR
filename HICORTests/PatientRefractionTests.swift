import XCTest
import SwiftData
@testable import HICOR

final class PatientRefractionTests: XCTestCase {
    func testInitAndDefaults() {
        let p = PatientRefraction(
            patientNumber: "001",
            sessionDate: Date(),
            sessionLocation: "San Quintin"
        )
        XCTAssertEqual(p.patientNumber, "001")
        XCTAssertEqual(p.sessionLocation, "San Quintin")
        XCTAssertEqual(p.odSPH, 0)
        XCTAssertEqual(p.osSPH, 0)
        XCTAssertEqual(p.pd, 0)
        XCTAssertFalse(p.pdManualEntry)
        XCTAssertFalse(p.consistencyWarningOverridden)
        XCTAssertFalse(p.syncedToCloud)
        XCTAssertEqual(p.photoData, [])
        XCTAssertNil(p.cloudKitRecordID)
    }

    func testInsertAndFetchInMemoryContainer() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        let context = ModelContext(container)

        let p = PatientRefraction(
            patientNumber: "042",
            sessionDate: Date(),
            sessionLocation: "Test"
        )
        context.insert(p)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PatientRefraction>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.patientNumber, "042")
    }
}
