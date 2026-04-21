import SwiftUI

struct SessionSetupView: View {
    let sessionContext: SessionContext
    @State private var date: Date = Date()
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

                Form {
                    Section {
                        DatePicker("Session date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        TextField("e.g. San Quintin, Baja California", text: $location)
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 200)

                Button {
                    sessionContext.date = date
                    sessionContext.location = location
                    let settings = SessionSettings(lastDate: date, lastLocation: location)
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
            date = settings.lastDate
            location = settings.lastLocation
        }
        .navigationDestination(isPresented: $navigate) {
            PatientEntryView(sessionContext: sessionContext)
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryListView(
                    location: sessionContext.location.isEmpty ? location : sessionContext.location,
                    date: sessionContext.location.isEmpty ? date : sessionContext.date
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
