import SwiftUI

struct PatientDetailView: View {
    let refraction: PatientRefraction

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(onBack: { dismiss() })
            Text("Patient #\(refraction.patientNumber)")
                .font(.title2)
                .padding()
            Spacer()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
