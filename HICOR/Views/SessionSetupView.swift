import SwiftUI

struct SessionSetupView: View {
    let sessionContext: SessionContext
    @State private var location: String = ""
    @State private var navigate = false
    @State private var showHistory = false
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(
                onShowHistory: { showHistory = true },
                onShowAbout: { showAbout = true }
            )
            VStack(spacing: 24) {
                Spacer()

                CLEARLogo(size: 120)

                VStack(spacing: 4) {
                    Text("CLEAR")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("Christ's Love Expressed through Restored Sight")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 12) {
                    HStack {
                        Text("Today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Date(), style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

                    TextField("e.g. San Quintin, Baja California", text: $location)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                Button {
                    let trimmed = location.trimmingCharacters(in: .whitespaces)
                    location = trimmed
                    sessionContext.location = trimmed
                    let settings = SessionSettings(lastLocation: trimmed)
                    settings.save()
                    navigate = true
                } label: {
                    Text("Start Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(location.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal)

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let settings = SessionSettings.load()
            location = settings.lastLocation.trimmingCharacters(in: .whitespaces)
        }
        .navigationDestination(isPresented: $navigate) {
            PatientEntryView(sessionContext: sessionContext)
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryListView(
                    location: sessionContext.location.isEmpty ? location : sessionContext.location,
                    date: Date()
                )
            }
        }
        .alert("CLEAR Ministry", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Highlands Church Optical Refraction\nVersion 1.0")
        }
    }
}
