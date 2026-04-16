import SwiftUI

struct AnalysisPlaceholderView: View {
    let patientNumber: String
    let sessionContext: SessionContext
    let photos: [Data]
    let pd: Double
    let pdManualEntry: Bool

    @Environment(SyncCoordinator.self) private var sync
    @State private var advance = false

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.extraLarge)
            Text("Analyzing prescription…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .task {
            let refraction = PatientRefraction(
                patientNumber: patientNumber,
                sessionDate: sessionContext.date,
                sessionLocation: sessionContext.location,
                pd: pd,
                pdManualEntry: pdManualEntry,
                photoData: photos
            )
            await sync.save(refraction)

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            advance = true
        }
        .navigationDestination(isPresented: $advance) {
            ResultPlaceholderView(
                patientNumber: patientNumber,
                photoCount: photos.count
            )
        }
    }
}
