import SwiftUI
import SwiftData
import UIKit

@main
struct HICORApp: App {
    private let modelContainer: ModelContainer
    private let persistence: PersistenceService
    private let cloudKit: CloudKitService
    private let syncCoordinator: SyncCoordinator
    private let backgroundSync: BackgroundSyncService

    init() {
        let container = HICORApp.makeModelContainer()
        let persistence = PersistenceService(modelContainer: container)
        let cloudKit = CloudKitService()
        self.modelContainer = container
        self.persistence = persistence
        self.cloudKit = cloudKit
        self.syncCoordinator = SyncCoordinator(persistence: persistence, cloudKit: cloudKit)
        self.backgroundSync = BackgroundSyncService(persistence: persistence, cloudKit: cloudKit)

        LensInventoryService.shared.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(syncCoordinator)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    Task { await backgroundSync.syncIfNeeded() }
                }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([PatientRefraction.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            try? FileManager.default.removeItem(at: config.url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer after retry: \(error)")
            }
        }
    }
}
