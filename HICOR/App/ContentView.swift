import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("HICOR")
                    .font(.largeTitle.bold())
                Text("Highlands Church Optical Refraction")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Phase 1 skeleton — UI in later phases")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 32)
            }
            .padding()
            .navigationTitle("HICOR")
        }
    }
}

#Preview {
    ContentView()
}
