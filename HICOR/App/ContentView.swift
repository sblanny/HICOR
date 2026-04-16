import SwiftUI

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

#Preview {
    ContentView()
        .environment(SyncCoordinator.shared)
}
