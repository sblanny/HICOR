import XCTest
import SwiftData
@testable import HICOR

final class PersistenceServiceTests: XCTestCase {
    var service: PersistenceService!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        service = PersistenceService(container: container)
    }

    func testInsertAndFetchByID() throws {
        let p = PatientRefraction(patientNumber: "001", sessionDate: Date(), sessionLocation: "Loc")
        service.insert(p)
        let fetched = service.fetch(byID: p.id)
        XCTAssertEqual(fetched?.patientNumber, "001")
    }

    func testFetchToday() throws {
        let today = PatientRefraction(patientNumber: "001", sessionDate: Date(), sessionLocation: "L")
        let yesterday = PatientRefraction(
            patientNumber: "002",
            sessionDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            sessionLocation: "L"
        )
        service.insert(today)
        service.insert(yesterday)

        let results = service.fetchToday()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "001")
    }

    func testFetchForSpecificDate() throws {
        let target = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let p = PatientRefraction(patientNumber: "777", sessionDate: target, sessionLocation: "L")
        service.insert(p)

        let results = service.fetch(for: target)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "777")
    }

    func testFetchUnsyncedReturnsOnlyUnsyncedRecords() throws {
        let synced = PatientRefraction(patientNumber: "S", sessionDate: Date(), sessionLocation: "L")
        let unsynced = PatientRefraction(patientNumber: "U", sessionDate: Date(), sessionLocation: "L")
        service.insert(synced)
        service.insert(unsynced)

        synced.syncedToCloud = true
        synced.cloudKitRecordID = "rec-synced"
        try service.save()

        let results = service.fetchUnsynced()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "U")
    }
}
