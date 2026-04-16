import SwiftUI
import SwiftData

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
        }
        .modelContainer(sharedModelContainer)
    }
}
