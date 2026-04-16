import Foundation
import Observation

@MainActor
@Observable
final class SyncCoordinator {
    private let persistence: PersistenceService
    private let cloudKit: CloudKitService

    init(persistence: PersistenceService, cloudKit: CloudKitService) {
        self.persistence = persistence
        self.cloudKit = cloudKit
    }

    func save(_ refraction: PatientRefraction) async {
        do {
            try await persistence.insert(refraction)
        } catch {
            print("Local insert failed: \(error)")
            return
        }
        do {
            let recordID = try await cloudKit.saveRecord(refraction)
            try await persistence.markSynced(id: refraction.id, cloudKitRecordID: recordID)
        } catch {
            print("CloudKit save failed, will retry on next foreground: \(error)")
        }
    }
}
