import SwiftUI
import SwiftData
import UIKit

@main
struct HICORApp: App {
    var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: PatientRefraction.self)
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
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
