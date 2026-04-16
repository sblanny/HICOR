import XCTest
import CloudKit
import SwiftData
@testable import HICOR

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    var persistence: PersistenceService!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        persistence = PersistenceService(modelContainer: container)
    }

    func testSaveInsertsLocallyEvenIfCloudKitFails() async throws {
        let mock = MockCKDatabase()
        mock.saveBehavior = .throwError(CKError(.networkUnavailable))
        let cloudKit = CloudKitService(database: mock)
        let coordinator = SyncCoordinator(persistence: persistence, cloudKit: cloudKit)

        let p = PatientRefraction(patientNumber: "OFFLINE", sessionDate: Date(), sessionLocation: "L")
        await coordinator.save(p)

        let fetched = try await persistence.fetch(byID: p.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.patientNumber, "OFFLINE")
        XCTAssertFalse(fetched?.syncedToCloud ?? true)
        XCTAssertNil(fetched?.cloudKitRecordID)
    }

    func testSaveSetsSyncedToCloudOnSuccess() async throws {
        let mock = MockCKDatabase()
        let returned = CKRecord(
            recordType: CloudKitService.recordType,
            recordID: CKRecord.ID(recordName: "rec-xyz")
        )
        mock.saveBehavior = .returnRecord(returned)
        let cloudKit = CloudKitService(database: mock)
        let coordinator = SyncCoordinator(persistence: persistence, cloudKit: cloudKit)

        let p = PatientRefraction(patientNumber: "ONLINE", sessionDate: Date(), sessionLocation: "L")
        await coordinator.save(p)

        let fetched = try await persistence.fetch(byID: p.id)
        XCTAssertNotNil(fetched)
        XCTAssertTrue(fetched?.syncedToCloud ?? false,
                      "Re-fetched record should reflect persisted syncedToCloud=true")
        XCTAssertEqual(fetched?.cloudKitRecordID, "rec-xyz",
                       "Re-fetched record should reflect persisted cloudKitRecordID")
    }
}
