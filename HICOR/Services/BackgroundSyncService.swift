import Foundation
import Observation

@MainActor
@Observable
final class BackgroundSyncService {
    private let persistence: PersistenceService
    private let cloudKit: CloudKitService

    init(persistence: PersistenceService, cloudKit: CloudKitService) {
        self.persistence = persistence
        self.cloudKit = cloudKit
    }

    func syncIfNeeded() async {
        let unsynced: [PatientRefraction]
        do {
            unsynced = try await persistence.fetchUnsynced()
        } catch {
            print("Background sync: fetchUnsynced failed: \(error)")
            return
        }
        guard !unsynced.isEmpty else { return }
        for record in unsynced {
            do {
                let recordID = try await cloudKit.saveRecord(record)
                try await persistence.markSynced(id: record.id, cloudKitRecordID: recordID)
            } catch {
                // Record stays unsynced; retry next foreground.
            }
        }
    }
}
