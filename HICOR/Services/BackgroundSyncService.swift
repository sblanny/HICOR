import Foundation
import Observation

@Observable
final class BackgroundSyncService {
    static let shared = BackgroundSyncService()

    private let persistence: PersistenceService
    private let cloudKit: CloudKitService

    init(
        persistence: PersistenceService = .shared,
        cloudKit: CloudKitService = .shared
    ) {
        self.persistence = persistence
        self.cloudKit = cloudKit
    }

    func syncIfNeeded() async {
        let unsynced = persistence.fetchUnsynced()
        guard !unsynced.isEmpty else { return }
        for record in unsynced {
            do {
                try await cloudKit.saveRecord(record)
                try? persistence.save()
            } catch {
                // Record stays unsynced; retry next foreground.
            }
        }
    }
}
