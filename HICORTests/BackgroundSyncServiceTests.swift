import XCTest
import CloudKit
import SwiftData
@testable import HICOR

@MainActor
final class BackgroundSyncServiceTests: XCTestCase {
    var persistence: PersistenceService!
    var mock: MockCKDatabase!
    var cloudKit: CloudKitService!
    var service: BackgroundSyncService!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        persistence = PersistenceService(modelContainer: container)
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
        try await persistence.insert(p)

        await service.syncIfNeeded()

        XCTAssertEqual(mock.savedRecords.count, 0)
    }

    func testSyncIfNeededAttemptsEachUnsyncedRecord() async throws {
        for name in ["A", "B", "C"] {
            try await persistence.insert(PatientRefraction(
                patientNumber: name,
                sessionDate: Date(),
                sessionLocation: "L"
            ))
        }

        await service.syncIfNeeded()

        XCTAssertEqual(mock.savedRecords.count, 3)
        let remaining = try await persistence.fetchUnsynced()
        XCTAssertEqual(remaining.count, 0)
    }

    func testSyncIfNeededContinuesAfterPartialFailure() async throws {
        let a = PatientRefraction(patientNumber: "A", sessionDate: Date(), sessionLocation: "L")
        let b = PatientRefraction(patientNumber: "B", sessionDate: Date(), sessionLocation: "L")
        let c = PatientRefraction(patientNumber: "C", sessionDate: Date(), sessionLocation: "L")
        try await persistence.insert(a)
        try await persistence.insert(b)
        try await persistence.insert(c)

        let unsynced = try await persistence.fetchUnsynced()
        XCTAssertEqual(unsynced.count, 3)
        let behaviors: [MockCKDatabase.SaveBehavior] = unsynced.map { record in
            record.patientNumber == "B"
                ? .throwError(CKError(.networkUnavailable))
                : .echo
        }
        mock.perCallBehaviors = behaviors

        await service.syncIfNeeded()

        XCTAssertEqual(mock.savedRecords.count, 3)
        let remaining = try await persistence.fetchUnsynced().map(\.patientNumber)
        XCTAssertEqual(Set(remaining), ["B"])
    }
}
