import SwiftUI

struct PatientEntryView: View {
    let sessionContext: SessionContext
    @State private var patientNumber: String = ""
    @FocusState private var focused: Bool
    @State private var navigate = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(sessionContext.location)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(sessionContext.date, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top)

            Spacer()

            VStack(spacing: 8) {
                Text("Patient Number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("000", text: $patientNumber)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .focused($focused)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }

            Spacer()

            Button {
                navigate = true
            } label: {
                Text("Begin Refraction")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(patientNumber.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .navigationTitle("New Patient")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .navigationDestination(isPresented: $navigate) {
            PhotoCaptureView(
                patientNumber: patientNumber,
                sessionContext: sessionContext
            )
        }
    }
}
