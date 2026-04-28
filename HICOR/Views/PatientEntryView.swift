import SwiftUI

struct PatientEntryView: View {
    let sessionContext: SessionContext
    @State private var patientNumber: String = ""
    @FocusState private var focused: Bool
    @State private var navigate = false
    @State private var showHistory = false
    @State private var showAbout = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(
                onShowHistory: { showHistory = true },
                onChangeLocation: { changeLocationTapped() },
                onShowAbout: { showAbout = true }
            )
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(sessionContext.location)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(Date(), style: .date)
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
            }
            .padding()
        }
        // Pin Begin Refraction above the keyboard. Without safeAreaInset the
        // button gets clipped by the numeric pad on return-to-PatientEntry —
        // SwiftUI's default keyboard avoidance leaves the Spacer-bracketed
        // button stack reaching below the keyboard's top edge with no way
        // for the operator to scroll or dismiss. Mirrors the pattern in
        // PrescriptionAnalysisView for the Save button.
        .safeAreaInset(edge: .bottom) {
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
            .padding(.horizontal)
            .padding(.bottom, 12)
            .background(.background)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .hicorReturnToPatientEntry)) { _ in
            patientNumber = ""
            navigate = false
            focused = true
        }
        .navigationDestination(isPresented: $navigate) {
            PhotoCaptureView(
                patientNumber: patientNumber,
                sessionContext: sessionContext
            )
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryListView(sessionContext: sessionContext)
            }
        }
        .alert("CLEAR Ministry", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Highlands Church Optical Refraction\nVersion 1.0")
        }
        .alert("Discard current patient?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard and Continue", role: .destructive) { postReturnToRoot() }
        } message: {
            Text("Going back to Location/Date setup will discard the current patient's data. This cannot be undone.")
        }
    }

    private func changeLocationTapped() {
        if patientNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            postReturnToRoot()
        } else {
            confirmDiscard = true
        }
    }

    private func postReturnToRoot() {
        NotificationCenter.default.post(name: .hicorReturnToRoot, object: nil)
    }
}
