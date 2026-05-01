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
    private let ocrService: OCRService

    init() {
        let container = HICORApp.makeModelContainer()
        let persistence = PersistenceService(modelContainer: container)
        let cloudKit = CloudKitService()
        self.modelContainer = container
        self.persistence = persistence
        self.cloudKit = cloudKit
        self.syncCoordinator = SyncCoordinator(persistence: persistence, cloudKit: cloudKit)
        self.backgroundSync = BackgroundSyncService(persistence: persistence, cloudKit: cloudKit)
        self.ocrService = OCRService()

        LensInventoryService.shared.load()

        Task {
            do {
                let count = try await persistence.migrateNormalizeLocations()
                if count > 0 {
                    print("[migration] Trimmed sessionLocation whitespace on \(count) record(s)")
                }
            } catch {
                print("[migration] sessionLocation normalization failed: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(syncCoordinator)
                .environment(ocrService)
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
