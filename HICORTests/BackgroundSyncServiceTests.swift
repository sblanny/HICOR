import XCTest
import CloudKit
import SwiftData
@testable import HICOR

final class BackgroundSyncServiceTests: XCTestCase {
    var persistence: PersistenceService!
    var mock: MockCKDatabase!
    var cloudKit: CloudKitService!
    var service: BackgroundSyncService!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        persistence = PersistenceService(container: container)
        mock = MockCKDatabase()
        cloudKit = CloudKitService(database: mock)
        service = BackgroundSyncService(persistence: persistence, cloudKit: cloudKit)
    }

    func testSyncIfNeededSkipsWhenNothingUnsynced() async throws {
        let p = PatientRefraction(
            patientNumber: "A",
            sessionDate: Date(),
            sessionLocation: "L",
            cloudKitRecordID: "already",
            syncedToCloud: true
        )
        persistence.insert(p)

        await service.syncIfNeeded()

        XCTAssertEqual(mock.savedRecords.count, 0)
    }

    func testSyncIfNeededAttemptsEachUnsyncedRecord() async throws {
        for name in ["A", "B", "C"] {
            persistence.insert(PatientRefraction(
                patientNumber: name,
                sessionDate: Date(),
                sessionLocation: "L"
            ))
        }

        await service.syncIfNeeded()

        XCTAssertEqual(mock.savedRecords.count, 3)
        XCTAssertEqual(persistence.fetchUnsynced().count, 0)
    }

    func testSyncIfNeededContinuesAfterPartialFailure() async throws {
        let a = PatientRefraction(patientNumber: "A", sessionDate: Date(), sessionLocation: "L")
        let b = PatientRefraction(patientNumber: "B", sessionDate: Date(), sessionLocation: "L")
        let c = PatientRefraction(patientNumber: "C", sessionDate: Date(), sessionLocation: "L")
        persistence.insert(a)
        persistence.insert(b)
        persistence.insert(c)

        let unsynced = persistence.fetchUnsynced()
        XCTAssertEqual(unsynced.count, 3)
        mock.perCallBehaviors = unsynced.map { record -> MockCKDatabase.SaveBehavior in
            record.patientNumber == "B"
                ? .throwError(CKError(.networkUnavailable))
                : .echo
        }

        await service.syncIfNeeded()

        XCTAssertEqual(mock.savedRecords.count, 3)
        let remaining = persistence.fetchUnsynced().map { $0.patientNumber }
        XCTAssertEqual(Set(remaining), ["B"])
    }
}
