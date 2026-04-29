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
            // Stack content at the top so the numeric keypad at the bottom
            // never overlaps the action button — independent of SwiftUI's
            // keyboard avoidance behavior, which proved unreliable across
            // navigation re-entry on this layout.
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(sessionContext.location)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(Date(), style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

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

                Spacer()
            }
            .padding()
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
            Text("Going back to Location setup will discard the current patient's data. This cannot be undone.")
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
