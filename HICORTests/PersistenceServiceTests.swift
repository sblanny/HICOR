import XCTest
import SwiftData
@testable import HICOR

final class PersistenceServiceTests: XCTestCase {
    var service: PersistenceService!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        service = PersistenceService(modelContainer: container)
    }

    func testInsertAndFetchByID() async throws {
        let p = PatientRefraction(patientNumber: "001", sessionDate: Date(), sessionLocation: "Loc")
        try await service.insert(p)
        let fetched = try await service.fetch(byID: p.id)
        XCTAssertEqual(fetched?.patientNumber, "001")
    }

    func testFetchToday() async throws {
        let today = PatientRefraction(patientNumber: "001", sessionDate: Date(), sessionLocation: "L")
        let yesterday = PatientRefraction(
            patientNumber: "002",
            sessionDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            sessionLocation: "L"
        )
        try await service.insert(today)
        try await service.insert(yesterday)

        let results = try await service.fetchToday()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "001")
    }

    func testFetchForSpecificDate() async throws {
        let target = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let p = PatientRefraction(patientNumber: "777", sessionDate: target, sessionLocation: "L")
        try await service.insert(p)

        let results = try await service.fetch(for: target)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "777")
    }

    func testFetchUnsyncedReturnsOnlyUnsyncedRecords() async throws {
        let synced = PatientRefraction(patientNumber: "S", sessionDate: Date(), sessionLocation: "L")
        let unsynced = PatientRefraction(patientNumber: "U", sessionDate: Date(), sessionLocation: "L")
        try await service.insert(synced)
        try await service.insert(unsynced)

        try await service.markSynced(id: synced.id, cloudKitRecordID: "rec-synced")

        let results = try await service.fetchUnsynced()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "U")
    }

    func testMarkSyncedUpdatesRecord() async throws {
        let p = PatientRefraction(patientNumber: "M", sessionDate: Date(), sessionLocation: "L")
        try await service.insert(p)

        try await service.markSynced(id: p.id, cloudKitRecordID: "rec-abc")

        let fetched = try await service.fetch(byID: p.id)
        XCTAssertEqual(fetched?.cloudKitRecordID, "rec-abc")
        XCTAssertEqual(fetched?.syncedToCloud, true)
    }
}
