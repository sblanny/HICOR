import SwiftUI
import SwiftData
import UIKit

@main
struct HICORApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PatientRefraction.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
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
    }()

    init() {
        LensInventoryService.shared.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SyncCoordinator.shared)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    Task { await BackgroundSyncService.shared.syncIfNeeded() }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
