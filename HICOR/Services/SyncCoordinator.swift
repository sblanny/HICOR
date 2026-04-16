import Foundation
import Observation

@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private let persistence: PersistenceService
    private let cloudKit: CloudKitService

    init(
        persistence: PersistenceService = .shared,
        cloudKit: CloudKitService = .shared
    ) {
        self.persistence = persistence
        self.cloudKit = cloudKit
    }

    func save(_ refraction: PatientRefraction) async {
        persistence.insert(refraction)
        do {
            try await cloudKit.saveRecord(refraction)
            try? persistence.save()
        } catch {
            print("CloudKit save failed, will retry in Phase 3: \(error)")
        }
    }
}
