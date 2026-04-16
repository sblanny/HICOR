import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var sessionContext = SessionContext()
    @State private var rootID = UUID()

    var body: some View {
        NavigationStack {
            SessionSetupView(sessionContext: sessionContext)
        }
        .id(rootID)
        .onReceive(NotificationCenter.default.publisher(for: .hicorReturnToRoot)) { _ in
            rootID = UUID()
        }
    }
}

private struct ContentViewPreview: View {
    let container: ModelContainer
    let sync: SyncCoordinator

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: PatientRefraction.self, configurations: config)
        let persistence = PersistenceService(modelContainer: container)
        let cloudKit = CloudKitService()
        self.container = container
        self.sync = SyncCoordinator(persistence: persistence, cloudKit: cloudKit)
    }

    var body: some View {
        ContentView()
            .environment(sync)
            .modelContainer(container)
    }
}

#Preview {
    ContentViewPreview()
}
